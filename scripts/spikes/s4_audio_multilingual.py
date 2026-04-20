"""S4 — audio multilingual spike.

Run a 20-clip manifest (10 EN / 5 ES / 5 TR) through one runner and score
whether the stated damage tag appears in `model_tags`.

Audio path today: `flutter_gemma` native audio on device (not covered here) OR
Whisper-tiny ASR → text pipeline (covered by `--mode asr_text`). Ollama's vision
models don't take audio bytes directly, so the Mac side of S4 runs in
`asr_text` mode against E4B.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from dataclasses import asdict, dataclass
from pathlib import Path

from tqdm import tqdm

from cairn.constants import REPO_ROOT
from cairn.prompts import system_prompt
from cairn.runners import OllamaRunner


@dataclass
class ClipResult:
    clip_id: str
    locale: str
    expected_tag: str
    transcript_or_raw: str
    pred_tags: list[str]
    correct: bool


def _transcribe(path: Path) -> str:
    """Placeholder ASR. For now we require a paired `.txt` transcript next to
    the `.wav` so the operator can use whatever ASR they prefer (Whisper-tiny,
    macOS `speech`, etc.)."""
    txt = path.with_suffix(".txt")
    if not txt.is_file():
        raise FileNotFoundError(
            f"missing transcript for {path} at {txt} — write one by hand or run Whisper-tiny first"
        )
    return txt.read_text(encoding="utf-8").strip()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True, type=Path,
                    help="JSONL with fields: clip_id, audio_path, locale, expected_tag")
    ap.add_argument("--runner", default="ollama:gemma3n:e4b")
    ap.add_argument("--mode", choices=["asr_text"], default="asr_text")
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args()

    if not args.runner.startswith("ollama:"):
        raise ValueError("only ollama:<tag> supported in S4 asr_text mode")
    runner = OllamaRunner(model=args.runner.removeprefix("ollama:"))

    results: list[ClipResult] = []
    for line in tqdm(args.manifest.read_text().splitlines(), desc="clips"):
        if not line.strip():
            continue
        item = json.loads(line)
        clip_path = REPO_ROOT / item["audio_path"]
        transcript = _transcribe(clip_path)
        user_text = json.dumps(
            {
                "task": "describe_photo",  # reuse same schema contract; image_refs empty
                "asked_in": item["locale"],
                "prompt_id": "fema_p154_audio_probe",
                "image_refs": [],
                "user_text": transcript,
            },
            ensure_ascii=False,
        )
        resp = runner.run(system=system_prompt(), user_text=user_text, max_tokens=512)
        pred_tags: list[str] = []
        try:
            obj = json.loads(resp.text[resp.text.index("{"): resp.text.rindex("}") + 1])
            pred_tags = obj.get("model_tags", []) or []
        except Exception:
            pass
        results.append(
            ClipResult(
                clip_id=item["clip_id"],
                locale=item["locale"],
                expected_tag=item["expected_tag"],
                transcript_or_raw=transcript,
                pred_tags=pred_tags,
                correct=item["expected_tag"] in pred_tags,
            )
        )

    correct = sum(r.correct for r in results)
    summary = {
        "schema": "cairn.spike.s4.v1",
        "runner": runner.name,
        "mode": args.mode,
        "n": len(results),
        "correct": correct,
        "accuracy": correct / len(results) if results else 0.0,
        "by_locale": {
            loc: {
                "n": sum(1 for r in results if r.locale == loc),
                "correct": sum(1 for r in results if r.locale == loc and r.correct),
            }
            for loc in sorted({r.locale for r in results})
        },
        "generated_at_utc": dt.datetime.now(dt.UTC).isoformat(),
        "results": [asdict(r) for r in results],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(summary, indent=2, ensure_ascii=False))
    print(json.dumps(
        {k: v for k, v in summary.items() if k != "results"},
        indent=2, ensure_ascii=False,
    ))


if __name__ == "__main__":
    main()
