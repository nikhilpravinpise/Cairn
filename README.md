# Cairn

Cairn is an offline-first Flutter app for post-earthquake building triage. It
guides a volunteer through a FEMA P-154 Level 1 sidewalk screening flow, runs
Gemma 4 on-device or in-browser, and produces a structured `EvidencePacket`
with photos, audio observations, deterministic triage, and a PDF report.

> Preliminary screening tool only. Not an ATC-20 placard. Not a
> structural-engineering determination. See `docs/LEGAL.md`.

## Current architecture

- **Model policy:** Gemma 4 only.
- **Approved models:** `gemma-4-E2B-it` and `gemma-4-E4B-it` LiteRT-LM artifacts
  from `litert-community`.
- **Runtime:** `flutter_gemma` by default; Android `native_mtp` bridge is
  available for LiteRT-LM speculative decoding experiments.
- **Trust boundary:** `GemmaOrchestrator` is the only code path that parses
  model JSON. It validates tags, media refs, bounding boxes, confidence, tool
  shape, and triage ownership before app state can persist the output.
- **Scoring:** Gemma describes evidence; Dart computes final priority score and
  priority band deterministically.

The Gemma 4-only rule is enforced by
`apps/cairn_mobile/test/model_registry_platform_test.dart`.

## Repository layout

```text
apps/
  cairn_mobile/        # Flutter Android + Web app
finetune/              # LoRA experiments and conversion utilities
scripts/
  cairn/               # Python mirrors for constants, schema, prompts, scoring
  data/                # synthetic dialogue pipeline
  eval/                # baseline and tuned evaluation harness
  spikes/              # historical and current de-risk harnesses
docs/
  prompts/             # locked system prompt
  schema/              # EvidencePacket JSON Schema v1
  LEGAL.md             # protocol framing, liability, licenses
data/
  seeds/               # hand-authored seed dialogues
```

## Key files

- `apps/cairn_mobile/lib/core/llm/model_registry.dart` — approved Gemma 4 model
  registry and artifact names.
- `apps/cairn_mobile/lib/core/llm/orchestrator.dart` — model prompt/response
  boundary and contract enforcement.
- `apps/cairn_mobile/lib/core/models/evidence_packet.dart` — Dart packet model.
- `apps/cairn_mobile/lib/core/models/evidence_packet_validator.dart` — packet
  integrity checks before sealing.
- `docs/prompts/system_prompt_v1.txt` — locked model instruction prompt.
- `docs/schema/evidence_packet_v1.schema.json` — locked packet schema.
- `QUICKSTART.md` — local setup and validation commands.

## Validation baseline

Use the Flutter analyzer and test suite before changing app behavior:

```bash
cd apps/cairn_mobile
flutter analyze
flutter test
```

Use the Python checks when changing mirrored constants, schema, prompts, or
data tooling:

```bash
cd scripts
PYTHONPATH=. pytest -q
```

## Prize tracks

Global Resilience, LiteRT, and Unsloth.

## License

Apache-2.0 (see `LICENSE`). Datasets retain their upstream licenses; see
`docs/LEGAL.md`.
