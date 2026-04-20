# `scripts/data/` — synthetic dialogue pipeline (D5)

Input:  `data/seeds/dialogues.seed.jsonl`  (30 hand-authored, CI-validated)
Output: `data/train/phase_a.jsonl`         (≤ 2000 expanded dialogues, train split)
        `data/eval/phase_a_holdout.jsonl`  (100 dialogues, never seen during train)

## Stages

1. **Validate seeds** — every seed passes the schema-ref + JSON-parse contract.
   ```bash
   PYTHONPATH=scripts python -m data.validate_seeds
   ```
2. **Expand with Gemini 2.5 Pro** — per-seed paraphrase + axis-variation, then
   axis-cross sampling to hit the coverage target.
   ```bash
   export GEMINI_API_KEY=…
   PYTHONPATH=scripts python -m data.generate_dialogues \
       --seeds data/seeds/dialogues.seed.jsonl \
       --out   data/train/phase_a.raw.jsonl \
       --n 2000 --per-seed-max 100 --concurrency 4
   ```
3. **Hand-review sample** — pull 200 random rows for human review:
   ```bash
   PYTHONPATH=scripts python -m data.sample_for_review --in data/train/phase_a.raw.jsonl \
       --out data/train/phase_a.review.jsonl --n 200
   ```
   Mark each row `accept: true|false` in place. Re-seed if < 90 % accepted.
4. **Assemble** — split into train / eval and inline the system prompt:
   ```bash
   PYTHONPATH=scripts python -m data.assemble_dialogues \
       --in  data/train/phase_a.raw.jsonl \
       --train-out data/train/phase_a.jsonl \
       --eval-out  data/eval/phase_a_holdout.jsonl \
       --eval-n 100
   ```

`assemble_dialogues.py` is the **only** script that inlines the full system prompt
into a training record. Everything upstream keeps `"system_ref": "cairn.system.v1"`.
