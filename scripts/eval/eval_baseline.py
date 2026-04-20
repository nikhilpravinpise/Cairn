"""Zero-shot eval driver. Runs one strategy × one runner × N gold items.

Writes a per-item JSONL alongside a summary JSON. Both go under
`scripts/eval/reports/`.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path

from tqdm import tqdm

from cairn.constants import REPO_ROOT
from cairn.metrics import summarize
from cairn.runners import ImageInput, LlmRunner, OllamaRunner
from eval.prompt_strategies import STRATEGIES

_JSON_OBJ_RE = re.compile(r"\{(?:[^{}]|(?:\{[^{}]*\}))*\}", re.DOTALL)


def _extract_first_json(text: str) -> dict | None:
    m = _JSON_OBJ_RE.search(text)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except json.JSONDecodeError:
        return None


def _build_runner(spec: str) -> LlmRunner:
    if spec.startswith("ollama:"):
        return OllamaRunner(model=spec.removeprefix("ollama:"))
    raise ValueError(
        f"unknown runner {spec!r}. supported: ollama:<tag>. "
        "(device_adb runner ships alongside S2 spike in a later commit.)"
    )


def _load_gold(path: Path) -> list[dict]:
    items: list[dict] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        items.append(json.loads(line))
    return items


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gold", required=True, type=Path)
    ap.add_argument("--runner", required=True, help="e.g. ollama:gemma3n:e4b")
    ap.add_argument("--strategy", required=True, choices=list(STRATEGIES))
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--temperature", type=float, default=0.2)
    ap.add_argument("--max-tokens", type=int, default=512)
    args = ap.parse_args()

    gold = _load_gold(args.gold)
    if args.limit:
        gold = gold[: args.limit]

    runner = _build_runner(args.runner)
    strategy = STRATEGIES[args.strategy]

    preds: list[dict] = []
    golds: list[dict] = []
    per_item: list[dict] = []

    parse_fails = 0
    ttfts: list[float] = []

    for item in tqdm(gold, desc=f"{runner.name}/{strategy.name}"):
        img_path = REPO_ROOT / item["image_path"]
        if not img_path.is_file():
            sys.exit(f"missing image {img_path}")
        sys_prompt, user_text = strategy.build(item)
        resp = runner.run(
            system=sys_prompt,
            user_text=user_text,
            images=[ImageInput.from_path(img_path)],
            temperature=args.temperature,
            max_tokens=args.max_tokens,
        )
        parsed = _extract_first_json(resp.text) or {}
        if not parsed:
            parse_fails += 1
        if resp.ttft_s is not None:
            ttfts.append(resp.ttft_s)

        preds.append(parsed)
        golds.append(item["gold"])
        per_item.append(
            {
                "item_id": item["item_id"],
                "parsed": parsed,
                "raw_text": resp.text,
                "ttft_s": resp.ttft_s,
                "decode_tok_per_s": resp.decode_tok_per_s,
                "wallclock_s": resp.wallclock_s,
            }
        )

    summary = summarize(preds, golds) | {
        "runner": runner.name,
        "strategy": strategy.name,
        "parse_fail_rate": parse_fails / len(gold) if gold else 0.0,
        "median_ttft_s": (sorted(ttfts)[len(ttfts) // 2] if ttfts else None),
        "generated_at_utc": dt.datetime.now(dt.UTC).isoformat(),
        "gold_file": str(args.gold),
        "n_items": len(gold),
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(summary, indent=2))
    items_path = args.out.with_suffix(".items.jsonl")
    with items_path.open("w", encoding="utf-8") as f:
        for row in per_item:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(f"summary  → {args.out}")
    print(f"per-item → {items_path}")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
