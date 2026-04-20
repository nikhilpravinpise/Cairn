# `data/seeds/` — hand-authored seed dialogues

30 hand-authored seed dialogues in **Unsloth ShareGPT JSONL** format, used as the
seed corpus for the D5 synthetic-dialogue expansion (→ 2000 dialogues).

## Format

Each line is one JSON object:

```json
{
  "seed_id": "seed-001",
  "task": "describe_photo | ask_followup | protocol_answer | synthesize",
  "locale": "en | es | tr",
  "building_type": "concrete_moment_frame | ... | unknown",
  "scenario": "none | cosmetic | moderate | severe",
  "system_ref": "cairn.system.v1",
  "conversations": [
    { "from": "human", "value": "..." },
    { "from": "gpt",   "value": "..." }
  ]
}
```

Notes
- `system_ref` is resolved at train time by
  `scripts/data/assemble_dialogues.py` — it inlines the current
  `docs/prompts/system_prompt_v1.txt` as the leading `{"from":"system"}` turn.
  Storing a ref (not the prompt text) keeps this file diffable and keeps seeds
  in lock-step with the live system prompt.
- The user turn `value` is valid JSON (the app never sends free-form text to
  the model; it sends a structured `{task, ...}` object).
- The assistant `value` MUST be valid JSON matching the schema described by
  the system prompt for that `task`. CI (`scripts/data/validate_seeds.py`)
  enforces this.

## Coverage
30 seeds × 4 tasks × 6 typologies × 4 scenarios × 3 locales — sampled for coverage,
not cross-product. See `scripts/data/coverage_report.py` for the live matrix.
