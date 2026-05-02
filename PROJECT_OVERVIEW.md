# Cairn — Project Overview

_Generated: deep-dive snapshot of `c:\Dev\gemma_project` (HEAD `1851264`, 6 days old, clean working tree)._

This document is a 100% repo-grounded summary. Every claim below cites a file that exists in the tree right now. Anything not in the tree is called out as **not yet present**.

---

## 1. What the project actually is

**Cairn** is a hackathon submission for the **"Gemma 4 Good"** competition. It is a **post-earthquake building triage tool** that runs **Gemma 4 (E2B / E4B) on-device / in-browser**, walks a non-expert volunteer through a **FEMA P-154 Level 1 "Sidewalk Survey"**, and emits a structured `EvidencePacket` (JSON + photos + audio) plus a printable PDF placard.

Source of truth for the product:
- `@c:\Dev\gemma_project\README.md:1-56` — repo intro
- `@c:\Dev\gemma_project\cairn-implementation-plan-0b751e.md:1-416` — the locked 31-day plan (D0 = Apr 17, 2026, submit D30 = May 17)
- `@c:\Dev\gemma_project\docs\LEGAL.md:1-44` — what Cairn is and explicitly is **not** (not ATC-20, not a placard, not an engineering determination)

Prizes targeted: **Global Resilience + LiteRT + Unsloth** (`@c:\Dev\gemma_project\cairn-implementation-plan-0b751e.md:19`).

### Three deliverable artifacts in the plan
1. **Flutter app** (`apps/cairn_mobile/`) — Android + Web, offline, multimodal screening flow.
2. **Engineer console** (`apps/cairn_console/`) — Next.js static site reading `.cairn.json` packets, table + MapLibre map. **Not yet present in the repo.**
3. **Fine-tuning pipeline** (`finetune/` + `scripts/data/`) — Phase A text-only LoRA on Unsloth → MediaPipe flatbuffer → on-device load.

---

## 2. The Week-1 pivot (decisive context)

Per `@c:\Dev\gemma_project\docs\week1_pivot.md:1-79`, decided **Apr 20, 2026**: target Android device (Samsung S23 FE) **was not available**, only an iPhone 14. The team **pivoted Week-1 work to Flutter Web + WebGPU running Gemma E4B**. Android is restored when hardware arrives (Week 2+). The locked plan was **not rewritten** — every change is an explicit delta against it.

Pivot consequences encoded in the repo:
- `apps/cairn_mobile/` only generates the `web/` platform folder (`@c:\Dev\gemma_project\apps\cairn_mobile\README.md:20-29`).
- `pubspec.yaml` pins `flutter_gemma: ^0.13.0` and full mobile plugin set (`geolocator`, `record`, `printing`, `flutter_map`, …) — codebase is platform-agnostic, only the build target changed (`@c:\Dev\gemma_project\apps\cairn_mobile\pubspec.yaml:15-37`).
- `main.dart` initializes `FlutterGemma` with `WebStorageMode.streaming` because the E4B `.task` is ~4 GB and exceeds the browser ArrayBuffer cap (`@c:\Dev\gemma_project\apps\cairn_mobile\lib\main.dart:13-25`).
- S1 spike replaced: `scripts/spikes/s1_web_feasibility.md` supersedes `s1_device_feasibility.md` for Week-1 (`@c:\Dev\gemma_project\scripts\spikes\s1_web_feasibility.md:1-65`). adb harness stays in-tree (`scripts/spikes/s1_adb_harness.py`) for when the phone arrives.
- LoRA on-device load (S2 substep) is **deferred** — MediaPipe Web doesn't support `setLoraPath` today.

---

## 3. Repository layout (what's actually on disk)

```
gemma_project/
├── apps/
│   └── cairn_mobile/              ← Flutter app (only target wired today: web)
│       ├── lib/
│       │   ├── main.dart                    ← FlutterGemma init + ProviderScope
│       │   ├── core/
│       │   │   ├── llm/                     ← gemma_session, orchestrator, json_extract, model_registry
│       │   │   ├── models/evidence_packet.dart  ← Dart mirror of EvidencePacket schema (15 KB)
│       │   │   ├── routing/app_router.dart  ← go_router 9-screen flow + /spike
│       │   │   ├── state/session_controller.dart ← SessionDraft Riverpod notifier
│       │   │   ├── storage/evidence_vault.dart   ← in-memory vault stub
│       │   │   ├── triage/priority.dart     ← deterministic Dart scorer (mirror of Python)
│       │   │   └── providers.dart           ← Riverpod wiring
│       │   ├── features/
│       │   │   ├── start/        ← Screen 1 ✅ implemented
│       │   │   ├── location/     ← Screen 2 ✅ implemented (GPS + typology chips)
│       │   │   ├── photos/       ← Screen 3 ✅ implemented (4 required + 1 extra slots)
│       │   │   ├── describe/     ← Screen 4 ✅ implemented (web-fallback text; audio is Android)
│       │   │   ├── protocol/     ← Screen 5 ✅ implemented (P-154 Q&A)
│       │   │   ├── humility/     ← Screen 6 ✅ implemented (lowest-confidence re-query)
│       │   │   ├── synthesize/   ← Screen 7 ⚠ STUB (PassPlaceholder — "Pass 3")
│       │   │   ├── report/       ← Screen 8 ⚠ STUB (PassPlaceholder — "Pass 3")
│       │   │   └── _pending.dart ← shared stub widget
│       │   └── spike/s2_spike_page.dart ← S2 10-prompt harness UI
│       ├── test/                ← 5 unit tests (priority, evidence_packet, json_extract, session_controller, web_bootstrap)
│       └── docs/s2_checklist.md
│
├── docs/
│   ├── prompts/system_prompt_v1.{md,txt} ← LOCKED D4, ~1.9k tokens
│   ├── schema/evidence_packet_v1.schema.json + README.md ← LOCKED D4
│   ├── LEGAL.md                          ← protocol framing + licenses
│   ├── week1_pivot.md                    ← web-first delta vs the plan
│   └── week1_decision.md                 ← D7 go/no-go scoreboard (all rows TBD)
│
├── finetune/                       ← Unsloth + MediaPipe LoRA conversion
│   ├── phase_a_text_lora.py        ← Phase A (P0) — Unsloth FastLanguageModel, attention-only LoRA
│   ├── convert_mediapipe_lora.py   ← PEFT adapter → MediaPipe .fb flatbuffer
│   ├── phase_b_vision_lora.py      ← STUB (sys.exit), ships W3 if gate passes
│   └── README.md
│
├── scripts/
│   ├── pyproject.toml              ← `cairn-scripts` pkg, Python ≥3.11
│   ├── cairn/                      ← shared library
│   │   ├── constants.py            ← MODELS dict, SCHEMA_PATH, SEED_JSONL_PATH (fail-loud)
│   │   ├── prompts.py              ← system_prompt() loader
│   │   ├── schema.py               ← jsonschema validator (Draft 2020-12)
│   │   ├── triage.py               ← priority_score Python mirror
│   │   ├── metrics.py              ← F1, top-k, Spearman, Jaccard, ECE
│   │   └── runners/                ← OllamaRunner, GeminiRunner, base
│   ├── data/                       ← D5 synthetic dialogue pipeline
│   │   ├── validate_seeds.py       ← CI validator for the 30 hand-authored seeds
│   │   ├── generate_dialogues.py   ← Gemini-2.5-Pro expansion to 2000
│   │   ├── sample_for_review.py    ← 200-row review sampler
│   │   └── assemble_dialogues.py   ← split + inline system prompt
│   ├── eval/                       ← S3 + tuned eval (shared metrics)
│   │   ├── eval_baseline.py        ← runner × strategy × N gold items
│   │   ├── prompt_strategies.py    ← strict_schema, cot_then_schema, schema_only
│   │   └── report.py
│   ├── spikes/
│   │   ├── s1_web_feasibility.md   ← Week-1 active S1 doc
│   │   ├── s1_device_feasibility.md + s1_adb_harness.py ← Android, deferred
│   │   ├── s3_bbox_probe.py        ← D4 bbox-format probe
│   │   ├── s4_audio_multilingual.py ← ASR-text mode against Ollama
│   │   └── s5_lora_round_trip.md   ← LoRA Colab procedure
│   └── tests/                      ← pytest: constants_parity, metrics, schema, seeds, triage
│
├── data/seeds/                     ← only `data/seeds/` is git-tracked; everything else gitignored
├── QUICKSTART.md
├── README.md
├── cairn-implementation-plan-0b751e.md
├── LICENSE                         ← Apache-2.0
└── .gitignore
```

**Notably absent from disk** (mentioned by README/plan but not yet created):
- `apps/cairn_console/` (Next.js engineer console)
- `.github/workflows/` (CI was removed in commit `180301a Remove CI workflow`)
- `data/seeds/dialogues.seed.jsonl` is referenced by `cairn/constants.py` as required-on-import, so it must exist locally even though I cannot see inside `data/` due to `.gitignore` rules

---

## 4. Architecture & contracts

### 4.1 Locked artifacts (Day-4 freeze, must move together)
1. `@c:\Dev\gemma_project\docs\prompts\system_prompt_v1.txt` — the system prompt loaded by Flutter (`assets/prompts/`), the eval harness, and inlined into training data by `assemble_dialogues.py`. Hard rules visible in lines 1-60: strict JSON only, English keys + locale free-text, closed structural-vocabulary enum, `uncertain_*` tags + confidence ≤ 0.5 when unsure, **LLM never computes priority**, bbox uses `[y1,x1,y2,x2]` 0..1000.
2. `@c:\Dev\gemma_project\docs\schema\evidence_packet_v1.schema.json` — JSON Schema 2020-12 source of truth (referenced by `cairn/schema.py`).
3. `@c:\Dev\gemma_project\data\seeds\dialogues.seed.jsonl` — 30 hand-authored ShareGPT seeds (validated by `validate_seeds.py`).

CI parity test `scripts/tests/test_constants_parity.py` enforces `cairn/constants.py::MODELS` ↔ `apps/cairn_mobile/lib/core/llm/model_registry.dart::models`.

### 4.2 The four LLM task contracts
The orchestrator (`@c:\Dev\gemma_project\apps\cairn_mobile\lib\core\llm\orchestrator.dart:1-273`) is the only place the app constructs user-turn JSON. It implements:

| Task | Purpose | Result type |
|---|---|---|
| `describe_photo` | Per-photo `Observation` with tags, confidence, optional bbox | `DescribePhotoResult` |
| `ask_followup` | Humility check: re-query lowest-confidence observation | `AskFollowupResult` |
| `protocol_answer` | Map free-text reply onto exactly one `protocol_answers_delta` key | `ProtocolAnswerResult` |
| `synthesize` | Thinking-mode triage: rationale bullets + uncertainty notes | `SynthesizeResult` |

Each task **fails loud** with `GemmaContractError` on parse / contract violations (no silent fallbacks).

### 4.3 Deterministic triage (anti-hallucination)
The LLM **describes**; pure Dart **scores**. Implemented in `lib/core/triage/priority.dart` and mirrored byte-for-byte in `@c:\Dev\gemma_project\scripts\cairn\triage.py:13-42`:

- `visible_collapse` or `building_off_foundation` → 10
- `leaning == "severe"` → 9
- otherwise: hazard severity points + `ground_failure_adjacent`(+2) + `falling_hazards`(+2) + URM(+2) + `H01_soft_story`(+2), clamped to 1..10
- Bands (constants in both languages): LOW 1-3, MEDIUM 4-6, HIGH 7-8, CRITICAL 9-10

### 4.4 9-screen flow
Defined by `@c:\Dev\gemma_project\apps\cairn_mobile\lib\core\routing\app_router.dart:32-51`:

1. `/` Start — model picker (e2b/e4b), Load button, recent reports list ✅
2. `/location` — GPS + reverse-geocode + typology chips + stories ✅
3. `/photos` — 4 required FEMA slots (front, ground_floor, cracks, foundation) + 1 extra; per-photo `describe_photo` round-trip ✅
4. `/describe` — text fallback (web); on Android will be 30s mono 16kHz WAV ✅
5. `/protocol` — P-154 L1 six-question form, drives `applyProtocolDelta` ✅
6. `/humility` — picks lowest-confidence observation, fires `ask_followup`, records `user_override` at confidence 1.0 ✅
7. `/synthesize` — **STUB** (`PassPlaceholder`, "Pass 3") ⚠
8. `/report` — **STUB** (`PassPlaceholder`, "Pass 3") ⚠
9. PDF placard — not yet wired (`pdf` + `printing` + `qr_flutter` are in `pubspec.yaml` ready)
10. `/spike` — S2 stability harness (10 vision prompts, latency log, JSON download) ✅

### 4.5 Models
`@c:\Dev\gemma_project\scripts\cairn\constants.py:39-60` and the Dart mirror `@c:\Dev\gemma_project\apps\cairn_mobile\lib\core\llm\model_registry.dart:30-49`:

| key | repo | task file | quant | modalities | ctx |
|---|---|---|---|---|---|
| `e2b` | `litert-community/gemma-4-E2B-it-litert-lm` | `gemma-4-E2B-it-web.task` | int4 | text + image | 8192 |
| `e4b` | `litert-community/gemma-4-E4B-it-litert-lm` | `gemma-4-E4B-it-web.task` | int4 | text + image | 8192 |

Loaded via `flutter_gemma 0.13.x` MediaPipe LLM Inf API; `preferredBackend: PreferredBackend.gpu`, `maxTokens: 4096`, `maxNumImages: 5`, temp 0.2, top-k 40, top-p 0.95 (`gemma_session.dart:108-125`). Chat history is cleared after every turn — each task contract is independent (`gemma_session.dart:177-181`).

---

## 5. Current implementation status

### ✅ Done
- Locked artifacts: system prompt v1, schema v1, 30 seeds
- Python `cairn` package: constants, schema validator, triage mirror, metrics (F1/top-k/Spearman/Jaccard/ECE), Ollama + Gemini runners
- Eval harness skeleton: `eval_baseline.py` with strict_schema / cot_then_schema / schema_only strategies
- Synthetic-data pipeline (D5): seed validator + Gemini-2.5-Pro expander + sampler + assembler
- `finetune/phase_a_text_lora.py` (full Unsloth config, attention-only target_modules, ranks 4/8/16) and `convert_mediapipe_lora.py` wrapper
- Flutter app foundations:
  - `FlutterGemma` web-streaming bootstrap, `GemmaSession` lifecycle (queued generations, timeout, ttft/wallclock metrics, thinking-trace capture)
  - `GemmaOrchestrator` with all 4 task contracts (fail-loud parsing)
  - `EvidencePacket` Dart model + sealed-draft builder + `cloneShallow` Riverpod-friendly mutators
  - 6/9 screens fully implemented (Start, Location, Photos, Describe, Protocol, Humility)
  - S2 spike page wired at `/spike`
  - 5 unit tests (priority, evidence_packet round-trip, json_extract, session_controller, web bootstrap)

### ⚠ Stubs / placeholders
- Screens 7 (Synthesize) and 8 (Report) — `PassPlaceholder` widgets labelled "Pass 3"
- `phase_b_vision_lora.py` — intentional `sys.exit` until W3 gate
- `evidence_vault.dart` is `InMemoryEvidenceVault`; OPFS-backed vault is "Pass 4"
- PDF placard generation not yet wired (deps present)
- Audio capture path (Screen 4 falls back to text on web)

### ❌ Not present yet
- `apps/cairn_console/` (Next.js engineer console — table + MapLibre map)
- `.github/workflows/ci.yml` (CI was deleted; QUICKSTART still refers to it)
- LoRA on-device load (deferred; MediaPipe Web limitation)
- USGS ShakeMap prefill, ES/TR locales (P1 stretch)
- Web demo deployment artefact, signed APK, HF model card uploads, Kaggle notebook, video, writeup

### Week-1 decision doc
`@c:\Dev\gemma_project\docs\week1_decision.md:6-14` — every "Measured" cell is **TBD**. The D7 GO/NO-GO has not been signed yet.

### Git state
- HEAD: `1851264 Test flutter_gemma web bootstrap` (6 days ago), clean working tree
- 13 commits on `main`, last several explicitly walking the "Pass 1 / Pass 2 web" implementation track
- `180301a Remove CI workflow` removed `.github/`

---

## 6. The 31-day plan (where we are on the timeline)

From `@c:\Dev\gemma_project\cairn-implementation-plan-0b751e.md:273-336`:

| Week | Days | Focus | Status vs repo |
|---|---|---|---|
| W1 | D1–D7 (Apr 17–24) | De-risk via 5 spikes; lock prompt + schema + seeds; start Phase A LoRA overnight D7 | **In progress** — prompt/schema/seeds locked, foundations + 6 screens shipped, but `week1_decision.md` rows are TBD and there's no Phase A run yet |
| W2 | D8–D14 (Apr 25–May 1) | Flutter scaffold, screens 1–8, encrypted vault, D14 airplane-mode E2E + record raw video | Screens 1–6 already done; screens 7–8 + vault + D14 E2E remaining |
| W3 | D15–D21 | PDF + share, Phase A LoRA load + eval, Next.js console + map, multilingual UI, usability test, start Phase B overnight | Console + PDF + LoRA load all not started |
| W4 | D22–D28 | Phase B ship/skip, Web demo deployment, video shoot + edit, 1500-word writeup, Kaggle notebook, HF uploads | — |
| W5 | D29–D31 (May 15–17) | Submit | — |

Today (Apr 30 per IDE timestamp) ≈ **D14**. Per the plan that means the **W1 decision doc should already be signed** and the team should be wrapping the W2 E2E test. Repo evidence says W1 spikes are still **un-measured** and the W2 work is **partially done ahead of decision**.

---

## 7. Risks & open assumptions still live

From `@c:\Dev\gemma_project\cairn-implementation-plan-0b751e.md:358-385`, none of these have a **resolved** mark in `week1_decision.md` yet:

- E4B WebGPU latency / OOM on judge laptops (S1 web pass criteria untested)
- `flutter_gemma` Web 10-prompt stability (S2 untested)
- Vision F1 ≥ 0.7 (E2B) / ≥ 0.8 (E4B) on 200 IDEA held-out (S3 untested; gold file not present)
- Audio multilingual ≥ 16/20 (S4 untested; manifest not present)
- MediaPipe LoRA conversion working end-to-end on Unsloth Gemma 4 (S5 in Colab; not run)
- IDEA exact CC variant verification (D1 task)
- `cairn.app` domain reservation (D1 task)

---

## 8. Recommended next steps (grounded in what's missing)

In priority order, anchored to the locked plan and the actual repo state:

1. **Run the Week-1 spikes and fill in `docs/week1_decision.md`** — S1 web (Chrome WebGPU on Mac), S2 (10-prompt burst against `/spike`), S3 (`eval_baseline.py` against Ollama E4B on a 200-row IDEA gold file you still need to assemble), S4 (20-clip ASR-text manifest), S5 (Colab notebook). This gates everything else by design.
2. **Implement Screens 7–8 + PDF placard** (the W2 D13 deliverables). All wiring already exists — `synthesize` orchestrator method, `computeAndStoreTriage`, `sealAndSave`, `pdf`/`printing`/`qr_flutter` deps.
3. **Stand up `apps/cairn_console/`** (Next.js static + MapLibre + ajv schema validator). Plan §6 + `docs/schema/README.md:30` describe the contract.
4. **Persist packets to OPFS** — replace `InMemoryEvidenceVault` (the "Pass 4" TODO note in `core/providers.dart`).
5. **Re-add CI** — `test_constants_parity.py` is meant to enforce Python↔Dart drift but no workflow is currently running it.
6. **Phase A LoRA Colab run** — feed the assembled `data/train/phase_a.jsonl` through `phase_a_text_lora.py`, then `convert_mediapipe_lora.py`. On-device load is parked until Android hardware arrives.
7. **Submission artefacts** (W4): web demo deployment URL, HF Hub LoRA + dataset cards, Kaggle notebook, 3-min video, 1500-word writeup, cover image + 4 gallery assets.

---

## 9. TL;DR

You are building **Cairn**, an offline FEMA P-154 rapid-screening Flutter app powered by **Gemma 4 E4B (web, Week-1) / E2B (Android, Week-2+)** plus a small **Phase A text-only LoRA** (Unsloth → MediaPipe flatbuffer) and a static **Next.js engineer console**. The critical design choice is **LLM describes, Dart scores** — priority is computed deterministically, never by the model, and the system prompt + JSON Schema are locked across Python/Dart/TypeScript readers.

You're ~D14 on a 31-day timeline. The locked artifacts and Python pipeline are solid; the Flutter app has 6/9 screens implemented and ready to drive Gemma; the **Week-1 spike measurements are not yet recorded** and the **Next.js console + Synthesize/Report screens + PDF + LoRA-on-device** are the largest remaining blocks before submission on **D30 (May 17)**.
