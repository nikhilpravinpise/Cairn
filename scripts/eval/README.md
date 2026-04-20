# Cairn eval harness

Shared between **S3 (zero-shot baseline)** and the **D17 tuned eval** (post Phase A
LoRA). Same metrics, same data format.

## Gold file

One JSON object per line in `data/eval/gold.jsonl`:

```json
{
  "item_id": "idea-000123",
  "image_path": "data/eval/images/idea-000123.jpg",
  "building_type": "concrete_moment_frame",
  "asked_in": "en",
  "prompt_id": "fema_p154_q02_exterior_walls",
  "gold": {
    "model_tags": ["concrete_spalling", "exposed_rebar", "column_base_damage"],
    "damage_presence": true,
    "severity_ordinal": 3,
    "notes": "from IDEA Pascal VOC annotation"
  }
}
```

## Run baseline

```bash
# E4B via Ollama on Mac (pre-start: `ollama serve`, `ollama pull gemma3n:e4b`)
# Run from `scripts/` with PYTHONPATH=. so the `eval` package resolves.
PYTHONPATH=. python -m eval.eval_baseline \
  --gold data/eval/gold.jsonl \
  --runner ollama:gemma3n:e4b \
  --strategy strict_schema \
  --out scripts/eval/reports/baseline_e4b_strict.json

# E2B on-device is evaluated by running the same `eval_baseline.py` with
# --runner device_adb (forwards to the spike app over adb). See `runners/adb.py`.
```

## Prompt strategies (S3)
- `strict_schema`  — system prompt + JSON-only instruction; temperature 0.2.
- `cot_then_schema` — two turns: CoT first, then "now emit JSON only".
- `schema_only`   — no system prompt, only schema example (ablation).

## Reports
`scripts/eval/reports/*.json` + a rendered `report.md` produced by
`PYTHONPATH=scripts python -m eval.report scripts/eval/reports/*.json`.
