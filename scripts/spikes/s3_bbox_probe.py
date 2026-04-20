"""D4 bbox-format probe.

Send a single image + a prompt instructing the model to return a bounding box,
and inspect which convention (`[y1,x1,y2,x2]` in 0..1000 vs `[x,y,w,h]` in
pixels) the model actually uses. Gemma vision convention is the former; if a
given runtime diverges we update the system prompt or post-process.

Result is written as JSON to stdout / --out. Does not pass/fail — it's a
schema-confirmation probe.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

from cairn.runners import ImageInput, OllamaRunner

_PROMPT = (
    "Return one JSON object with a single key `box_2d` that is the tightest "
    "bounding box around the most visible crack or damage in the image. Use "
    "the Gemma vision convention: integer array [y1, x1, y2, x2], values 0..1000, "
    "normalized to the image. If there is no damage, return {\"box_2d\": null}. "
    "JSON only, no prose."
)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True, type=Path)
    ap.add_argument("--runner", default="ollama:gemma3n:e4b")
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()

    img = Image.open(args.image)
    w, h = img.size

    if not args.runner.startswith("ollama:"):
        sys.exit("only ollama:<tag> supported here")
    runner = OllamaRunner(model=args.runner.removeprefix("ollama:"))

    resp = runner.run(
        system="You are a compact vision assistant. Return JSON only.",
        user_text=_PROMPT,
        images=[ImageInput.from_path(args.image)],
        temperature=0.0,
        max_tokens=64,
    )
    text = resp.text.strip()
    parsed: dict | None = None
    try:
        parsed = json.loads(text[text.index("{"): text.rindex("}") + 1])
    except Exception:
        pass

    box = (parsed or {}).get("box_2d")
    verdict = "unknown"
    if box is None:
        verdict = "none_returned"
    elif isinstance(box, list) and len(box) == 4 and all(isinstance(v, int) for v in box):
        if all(0 <= v <= 1000 for v in box):
            verdict = "gemma_normalized_0_1000"
        elif all(0 <= v <= max(w, h) for v in box):
            verdict = "likely_pixels_xywh_or_yxyx"
        else:
            verdict = "out_of_range"
    else:
        verdict = "non_list_or_wrong_arity"

    out = {
        "schema": "cairn.spike.s3.bbox.v1",
        "image": str(args.image),
        "image_px": [w, h],
        "runner": runner.name,
        "raw_text": resp.text,
        "parsed_box": box,
        "verdict": verdict,
    }
    s = json.dumps(out, indent=2)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(s)
    print(s)


if __name__ == "__main__":
    main()
