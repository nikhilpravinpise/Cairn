"""Render a comparison table across N summary JSONs."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

_COLS = (
    "runner",
    "strategy",
    "n_items",
    "f1_damage_presence",
    "top1_damage_type",
    "top3_damage_type",
    "severity_spearman",
    "tag_jaccard",
    "confidence_ece",
    "parse_fail_rate",
    "median_ttft_s",
)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("summaries", nargs="+", type=Path)
    ap.add_argument("--out", type=Path, default=Path("scripts/eval/reports/report.md"))
    args = ap.parse_args()

    rows = [json.loads(p.read_text()) for p in args.summaries]

    lines: list[str] = [
        "# Eval comparison",
        "",
        f"Compared {len(rows)} runs.",
        "",
        "| " + " | ".join(_COLS) + " |",
        "|" + "|".join("---" for _ in _COLS) + "|",
    ]
    for r in rows:
        cells = []
        for c in _COLS:
            v = r.get(c)
            if isinstance(v, float):
                cells.append(f"{v:.3f}")
            elif v is None:
                cells.append("—")
            else:
                cells.append(str(v))
        lines.append("| " + " | ".join(cells) + " |")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines) + "\n")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
