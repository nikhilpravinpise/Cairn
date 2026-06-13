# Cairn

> Offline FEMA P-154 building triage powered by Gemma 4 on-device.

[![Flutter CI](https://github.com/N1KH1LT0X1N/cairn/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/N1KH1LT0X1N/cairn/actions/workflows/flutter-ci.yml)
[![Python CI](https://github.com/N1KH1LT0X1N/cairn/actions/workflows/python-ci.yml/badge.svg)](https://github.com/N1KH1LT0X1N/cairn/actions/workflows/python-ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.22-blue)](https://flutter.dev)

<!-- ## Screenshots

> Screenshots will be added in `docs/assets/screenshots/` before the first public release.
> Contributors: please open an issue if you have high-quality screenshots from a real device. -->

## What it does

After a major earthquake, the first shortage is not always concrete or trucks — it is trusted information. Streets fill with people asking the same urgent question: is this building safe enough to approach, avoid, or escalate?

**Cairn** is an offline-first Android app that helps trained volunteers collect post-earthquake building evidence, run Gemma 4 entirely on-device, and produce an auditable FEMA P-154-style triage packet without sending photos or notes to the cloud.

The app guides a volunteer through a fixed collection flow: location, building context, required exterior photos, optional audio notes, protocol answers, AI-assisted observations, deterministic triage, and a sealed evidence packet. Gemma 4 describes visible structural cues such as diagonal cracks, soft-story indicators, spalling, or foundation damage. Every model response must pass a strict JSON contract before it can enter app state. Gemma does not get to make the final call — Dart computes the final priority score and band deterministically. This separation keeps the model useful while preventing it from becoming an unbounded authority in a high-stakes situation.

> **Preliminary screening tool only.** Not an ATC-20 placard. Not a structural-engineering determination. See `docs/LEGAL.md`.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Volunteer (Android device)                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────────┐  │
│  │ Location   │  │ Photos     │  │ Audio notes │  │ Protocol Q&A   │  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └───────┬────────┘  │
│         │                │                │                   │          │
│         └────────────────┴────────────────┴───────────────────┘          │
│                                     │                                   │
│                              EvidencePacket                             │
│                                     │                                   │
│                    ┌────────────────┴────────────────┐                  │
│                    │  GemmaOrchestrator (on-device)  │                  │
│                    │  - describe_photo (per photo)   │                  │
│                    │  - describe_audio (optional)    │                  │
│                    │  - protocol_answer              │                  │
│                    │  - synthesize (rationale)       │                  │
│                    └────────────────┬────────────────┘                  │
│                                     │                                   │
│                    ┌────────────────┴────────────────┐                  │
│                    │ Contract validation               │                  │
│                    │ - tags, bboxes, confidence       │                  │
│                    │ - media refs, tool shape         │                  │
│                    │ - triage ownership               │                  │
│                    └────────────────┬────────────────┘                  │
│                                     │                                   │
│                    ┌────────────────┴────────────────┐                  │
│                    │ Deterministic scoring (Dart)    │                  │
│                    │ - priority score & band        │                  │
│                    └────────────────┬────────────────┘                  │
│                                     │                                   │
│                    ┌────────────────┴────────────────┐                  │
│                    │ Sealed EvidencePacket + PDF     │                  │
│                    │ Share locally (user-initiated)  │                  │
│                    └─────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Repository layout

```text
apps/
  cairn_mobile/        # Flutter Android app (production)
finetune/              # LoRA experiments and conversion utilities
scripts/
  cairn/               # Python mirrors for constants, schema, prompts, scoring
  data/                # Synthetic dialogue pipeline
  eval/                # Baseline and tuned evaluation harness
  spikes/              # Historical and current de-risk harnesses
docs/
  prompts/             # Locked system prompt
  schema/              # EvidencePacket JSON Schema v1
  LEGAL.md             # Protocol framing, liability, licenses
  submission/          # Prize-track writeups and plans
data/
  seeds/               # Hand-authored seed dialogues
```

## Prerequisites

- **Flutter** ≥3.22 (stable channel)
- **Android SDK** with command-line tools
- **Android device** with ≥6 GB RAM (tested on Samsung S23 FE-class devices)
- **Gemma 4 LiteRT-LM `.task` model file** (see Model download below)

## Model download

Cairn requires a Gemma 4 LiteRT-LM model file. The model is **not bundled** in the repo or APK due to size (~2–4 GB).

Download from HuggingFace:

- **E2B (2B params)**: [`litert-community/gemma-4-E2B-it-litert-lm`](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm)
- **E4B (4B params)**: [`litert-community/gemma-4-E4B-it-litert-lm`](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm)

Download the `.task` web file, then push it to your device:

```bash
adb push /path/to/gemma-4-*.task /data/local/tmp/
```

The app will detect the model file at runtime. See `QUICKSTART.md` for full setup.

## Quickstart

For local development setup, validation commands, and first-run instructions, see:

- [`QUICKSTART.md`](QUICKSTART.md) — project setup and device testing
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — branch workflow, commit style, and locked artifacts policy

## Tests

```bash
# Flutter (657+ tests)
cd apps/cairn_mobile
flutter test

# Python
cd scripts
PYTHONPATH=. pytest -q
```

## Legal

Licensed under the [Apache-2.0 License](LICENSE).

Upstream datasets retain their own licenses; see [`docs/LEGAL.md`](docs/LEGAL.md).

> **Disclaimer:** Cairn is a preliminary screening aid, not a structural-engineering determination, not an ATC-20 placard, and not a life-safety instruction. Every report includes an in-app disclaimer: "I am not a licensed engineer. This is preliminary screening only."

## Contributing

We welcome contributions. Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) for environment setup, the locked-artifacts policy, and the PR checklist.
