"""Sample N rows for hand review, adding an 'accept' field defaulting to null."""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    rows = [json.loads(l) for l in args.src.read_text().splitlines() if l.strip()]
    rng.shuffle(rows)
    picked = rows[: args.n]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8") as f:
        for r in picked:
            r.setdefault("_review", {"accept": None, "notes": ""})
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"wrote {len(picked)} → {args.out}")


if __name__ == "__main__":
    main()
