"""Inline the system prompt + split into train / eval.

Only place in the repo where the system prompt text is pasted into training
data. Everything upstream keeps `system_ref`.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
from pathlib import Path

from cairn.prompts import SYSTEM_REF, resolve_system_ref


def _assemble(rec: dict, system_text: str) -> dict:
    if rec.get("system_ref") != SYSTEM_REF:
        raise ValueError(f"{rec.get('seed_id')}: unexpected system_ref {rec.get('system_ref')!r}")
    convs = [{"from": "system", "value": system_text}] + rec["conversations"]
    rec_out = {k: v for k, v in rec.items() if k != "system_ref"}
    rec_out["conversations"] = convs
    return rec_out


def _stable_hash(rec: dict) -> int:
    s = json.dumps(rec.get("seed_id", ""), sort_keys=True)
    return int(hashlib.sha1(s.encode()).hexdigest(), 16)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True, type=Path)
    ap.add_argument("--train-out", required=True, type=Path)
    ap.add_argument("--eval-out", required=True, type=Path)
    ap.add_argument("--eval-n", type=int, default=100)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    rows = [json.loads(l) for l in args.src.read_text().splitlines() if l.strip()]
    # Deterministic split by stable hash of seed_id.
    rows.sort(key=_stable_hash)
    rng = random.Random(args.seed)
    rng.shuffle(rows)
    eval_rows = rows[: args.eval_n]
    train_rows = rows[args.eval_n:]

    system_text = resolve_system_ref(SYSTEM_REF)

    args.train_out.parent.mkdir(parents=True, exist_ok=True)
    with args.train_out.open("w", encoding="utf-8") as f:
        for r in train_rows:
            f.write(json.dumps(_assemble(r, system_text), ensure_ascii=False) + "\n")

    args.eval_out.parent.mkdir(parents=True, exist_ok=True)
    with args.eval_out.open("w", encoding="utf-8") as f:
        for r in eval_rows:
            f.write(json.dumps(_assemble(r, system_text), ensure_ascii=False) + "\n")

    print(f"train: {len(train_rows)} → {args.train_out}")
    print(f"eval : {len(eval_rows)} → {args.eval_out}")


if __name__ == "__main__":
    main()
