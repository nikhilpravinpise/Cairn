"""D5 — expand 30 hand-authored seeds → 2000 synthetic dialogues via Gemini.

Keeps `system_ref`, never inlines the system prompt. Runs N paraphrase
variations per seed under controlled axes (locale swap, typology swap,
severity shift, light change, occlusion wording).
"""
from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import random
import re
import sys
from pathlib import Path

from tqdm.asyncio import tqdm_asyncio

from cairn.constants import SEED_JSONL_PATH
from cairn.prompts import SYSTEM_REF
from cairn.runners import GeminiRunner
from cairn.runners.base import Message

_AXES: dict[str, list[str]] = {
    "locale": ["en", "es", "tr"],
    "building": [
        "concrete_moment_frame", "unreinforced_masonry", "wood_light_frame",
        "steel", "mixed", "unknown",
    ],
    "scenario": ["none", "cosmetic", "moderate", "severe"],
}

_EXPANSION_META_PROMPT = """You are a data augmentation tool for a building-triage dataset.

Given ONE seed record below (JSON), produce {n_variants} NEW records that explore
the following axes while keeping the contract identical:
  - locale ∈ {{"en","es","tr"}}
  - building_type ∈ {buildings}
  - scenario ∈ {{"none","cosmetic","moderate","severe"}}

Rules:
  * Each new record MUST keep the same "task" as the seed.
  * Each new record MUST have "system_ref": "cairn.system.v1" and NOT embed the
    system prompt text.
  * conversations[0] is the human turn (a valid JSON string under .value); its
    "asked_in" must match the new "locale".
  * conversations[1] is the gpt turn (a valid JSON string under .value) that
    obeys the same schema contract as the seed for that task.
  * Paraphrase descriptions. DO NOT copy the seed verbatim.
  * model_confidence must reflect realistic certainty for the new scenario.
  * Avoid forbidden vocabulary ("unsafe","condemned","red-tagged", etc.).

Return a JSON ARRAY of {n_variants} records. No prose outside the array.

SEED:
{seed_json}
"""


def _axes_line(axes: dict[str, list[str]]) -> str:
    return json.dumps(axes)


def _seed_hash(rec: dict) -> str:
    s = json.dumps(rec, sort_keys=True, ensure_ascii=False)
    return hashlib.sha1(s.encode("utf-8")).hexdigest()[:10]


async def _expand_one(runner: GeminiRunner, seed: dict, n: int, sem: asyncio.Semaphore) -> list[dict]:
    prompt = _EXPANSION_META_PROMPT.format(
        n_variants=n,
        buildings=json.dumps(_AXES["building"]),
        seed_json=json.dumps(seed, ensure_ascii=False),
    )
    async with sem:
        resp = await asyncio.to_thread(
            runner.generate,
            messages=[Message("user", prompt)],
            temperature=0.9,
            max_tokens=8000,
        )
    text = resp.text.strip()
    m = re.search(r"\[.*\]", text, re.DOTALL)
    if not m:
        return []
    try:
        arr = json.loads(m.group(0))
    except json.JSONDecodeError:
        return []
    out: list[dict] = []
    for i, r in enumerate(arr):
        r.setdefault("system_ref", SYSTEM_REF)
        r.setdefault("task", seed["task"])
        r["seed_id"] = f"{seed['seed_id']}__{_seed_hash(seed)}__{i:03d}"
        out.append(r)
    return out


async def _amain(args: argparse.Namespace) -> None:
    seeds = [json.loads(l) for l in args.seeds.read_text().splitlines() if l.strip()]
    random.shuffle(seeds)

    per_seed = min(args.per_seed_max, max(1, args.n // len(seeds) + 1))
    runner = GeminiRunner(model=args.model)
    sem = asyncio.Semaphore(args.concurrency)

    tasks = [_expand_one(runner, s, per_seed, sem) for s in seeds]
    chunks = await tqdm_asyncio.gather(*tasks, desc="expand")

    all_rows = [r for c in chunks for r in c][: args.n]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8") as f:
        for r in all_rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"wrote {len(all_rows)} rows → {args.out}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=Path, default=SEED_JSONL_PATH)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--n", type=int, default=2000, help="target row count")
    ap.add_argument("--per-seed-max", type=int, default=100)
    ap.add_argument("--concurrency", type=int, default=4)
    ap.add_argument("--model", default="gemini-2.5-pro")
    args = ap.parse_args()
    asyncio.run(_amain(args))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
