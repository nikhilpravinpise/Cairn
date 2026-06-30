# Cairn — Technical Interview Overview

> Everything factual you need to know to demo and discuss this project confidently.
> All information sourced directly from the codebase — no speculation.

---

## 1. What is Cairn?

**Cairn** is an offline-first Android app that helps trained volunteers perform post-earthquake building screenings. It runs **Google Gemma 4 entirely on-device** (no internet required), guides a volunteer through a **FEMA P-154 Level 1 Sidewalk Survey**, and produces an auditable **EvidencePacket** — a sealed JSON document plus binary assets (photos, audio, PDF report).

Key constraint: **Gemma describes structural evidence; it never computes the final triage score.** Dart code computes the priority score deterministically from protocol answers. This is an explicit safety design decision.

**Version**: `0.1.0` (initial public release, `2026-06-14`)

---

## 2. Tech Stack

### Flutter App (`apps/cairn_mobile/`)

| Layer | Technology |
|---|---|
| Language | Dart (SDK `>=3.6.0 <4.0.0`) |
| Framework | Flutter `>=3.27.0` |
| State management | Riverpod (`riverpod` + `flutter_riverpod` ^2.5.1) |
| Navigation | `go_router` ^14.2.0 |
| LLM runtime | `flutter_gemma` ^0.15.0 (wraps MediaPipe / LiteRT-LM) |
| PDF generation | `pdf` + `printing` + `qr_flutter` |
| Maps | `flutter_map` + `latlong2` |
| Location | `geolocator` + `geocoding` |
| Audio recording | `record` 5.2.1 |
| Camera / gallery | `image_picker` |
| Crypto | `crypto` (SHA for packet integrity) |
| UUID | `uuid` ^4.4.0 (UUIDv7 for time-ordered packet IDs) |
| Storage | `path_provider` + `shared_preferences` |
| Sharing | `share_plus` |
| Archiving | `archive` |

### Python Tooling (`scripts/`)

| Layer | Technology |
|---|---|
| Language | Python `>=3.11` |
| Schema validation | `jsonschema` (Draft 2020-12) |
| Data / eval | `numpy`, `scipy`, `scikit-learn`, `pandas`, `pillow` |
| CLI | `typer` |
| HTTP | `httpx` |
| Optional: LLM eval | `ollama` |
| Optional: data gen | `google-generativeai` (Gemini) |
| Optional: finetuning | `unsloth`, `transformers`, `peft`, `trl`, `accelerate`, `datasets` |
| Linting | `ruff` |
| Testing | `pytest` |

---

## 3. Model Details

Only **Gemma 4 LiteRT-LM** models are permitted. Any other model is rejected at runtime by the model registry guard.

| Key | Model | Params | Quant | Modalities | Context budget | Inference image size |
|---|---|---|---|---|---|---|
| `e2b` | `litert-community/gemma-4-E2B-it-litert-lm` | 2B | int4 | text + image | 8192 tokens | 640 px long edge |
| `e4b` | `litert-community/gemma-4-E4B-it-litert-lm` | 4B | int4 | text + image | 8192 tokens | 640 px long edge |

**File formats:**
- Android: `.litertlm` files (~2–4 GB)
- Web: `.task` files

**Model file is NOT bundled in the APK.** It must be pushed to the device:
```bash
adb push /path/to/gemma-4-*.litertlm /data/local/tmp/
```

**Inference runtime selection:**
- Primary: `flutter_gemma` (MediaPipe / LiteRT-LM)
- Diagnostic: `native_mtp` (legacy native bridge, selectable via `--dart-define=INFERENCE_RUNTIME=native_mtp`)

**Speculative decoding (MTP):** Enabled by default via `flutter_gemma` 0.15.0, delivering ~33% faster decode speed. Can be disabled with `--dart-define=BENCH_MTP=false`.

**Tested on:** Samsung S23 FE (Exynos). Requires ≥6 GB RAM.

---

## 4. App Screen Flow (9 Screens)

The app is a **linear FEMA P-154 triage workflow** using GoRouter:

```
Bootstrap → Start → Location → Photos → Audio → Describe → Protocol → Humility → Synthesize → Report
```

| Screen | Route | Purpose |
|---|---|---|
| Bootstrap | `/` | Permission requests (camera, mic, location) |
| Start | `/start` | Session init, locale selection (en / es / tr) |
| Location | `/location` | GPS capture (skippable — sentinel `[GPS unavailable - location not recorded]`) |
| Photos | `/photos` | Capture 4 required slots: `front`, `ground_floor`, `cracks`, `foundation`. Extra slots allowed. |
| Audio | `/audio` | Optional voice notes. Captured as mono 16 kHz WAV. |
| Describe | `/describe` | Gemma runs `describe_photo` per image. Streams `DescribePhotoEvent` (started/succeeded/failed per photo). |
| Protocol | `/protocol` | Structured FEMA P-154 yes/no/slider questions. Gemma runs `protocol_answer`. |
| Humility | `/humility` | Model over-confidence screening. Picks lowest-confidence observation, Gemma runs `ask_followup`. Volunteer answers as `humility_override_v1`. |
| Synthesize | `/synthesize` | Gemma runs `synthesize` task to produce triage rationale bullets. Dart computes the final score. |
| Report | `/report` | PDF generation with QR code. Schema validation → atomic write to vault. EvidencePacket sealed. |

Plus supporting screens: `/saved` (saved screenings list), `/saved/:packetId` (packet detail), `/saved/:packetId/photo/:imageRef` (photo evidence).

---

## 5. LLM Orchestrator — The Core of the AI Layer

**File:** `apps/cairn_mobile/lib/core/llm/orchestrator.dart`

The `GemmaOrchestrator` is the **only place that builds user-turn JSON for Gemma**. It implements 4 task contracts defined in the locked system prompt:

| Task | Method | Input | Output |
|---|---|---|---|
| `describe_photo` | `describePhoto()` / `describeAll()` | One image (preprocessed to ≤640 px) | `DescribePhotoResult` with tags, bbox, confidence, description |
| `ask_followup` | Called in humility screen | Low-confidence observation text | Follow-up question text |
| `protocol_answer` | — | FEMA protocol question | Structured JSON answer |
| `synthesize` | — | All observations | `rationale_bullets`, `uncertainty_notes`, `recommend_engineer_followup` |

**`describeAll` stream** emits sealed events per photo:
- `DescribePhotoStarted` — before model call
- `DescribePhotoSucceeded` — after valid response
- `DescribePhotoFailed` — on any error

**Contract enforcement (fails loud on violations):**
- `model_tags` must be from the closed enum (19 values)
- `bbox_annotations`: `[y1, x1, y2, x2]` in 0–1000 (Gemma vision convention), `y1 < y2`, `x1 < x2`
- `model_confidence`: 0.0–1.0
- Synthesize task cannot contain `priority_score` / `priority_band` (model is forbidden from making the triage call)
- Media refs must match `img-N` / `aud-N` pattern

`GemmaContractError` is thrown on any violation.

---

## 6. Deterministic Triage Scoring

**Dart:** `apps/cairn_mobile/lib/core/triage/priority.dart`  
**Python mirror:** `scripts/cairn/triage.py`

These are byte-identical implementations. CI tests (`test_constants_parity.py`) enforce they never diverge.

**Score: 1–10 integer**

| Condition | Points |
|---|---|
| `visible_collapse = true` | → score = 10 (immediate) |
| `building_off_foundation = true` | → score = 10 (immediate) |
| `leaning = 'severe'` | → score = 9 (immediate) |
| Each hazard flagged | +1 (low) / +2 (moderate) / +3 (high) |
| `ground_failure_adjacent` | +2 |
| `falling_hazards` | +2 |
| Building type = `unreinforced_masonry` | +2 |
| Hazard code `H01_soft_story` present | +2 |

**Bands:**

| Score | Band |
|---|---|
| 1–3 | LOW |
| 4–6 | MEDIUM |
| 7–8 | HIGH |
| 9–10 | CRITICAL |

---

## 7. EvidencePacket Schema (v1)

**Source of truth:** `docs/schema/evidence_packet_v1.schema.json`  
**Schema ID:** `cairn.evidence.v1`  
**JSON Schema draft:** 2020-12

The packet is the single artifact produced by each session.

**Top-level required fields:**

| Field | Type | Notes |
|---|---|---|
| `packet_id` | string (UUIDv7 pattern) | Time-ordered uniqueness |
| `created_at_utc` | date-time string | |
| `app_version` | semver string | |
| `protocol` | const `"FEMA-P-154-L1"` | |
| `model` | object (`name`, `quant`, `lora?`) | |
| `location` | object (lat, lng, accuracy_m, address_text?) | accuracy_m ≥ 0 |
| `building` | object (type, stories_above_grade, occupancy_hint?, year_built_est?) | type is closed enum |
| `observations` | array (0–16 items) | |
| `hazards_flagged` | array | H01–H08 codes, severity low/moderate/high |
| `protocol_answers` | object | visible_collapse, building_off_foundation, leaning, etc. |
| `triage` | object (priority_score 1–10, priority_band, rationale_bullets) | |
| `volunteer` | object | locale, attestation text |
| `assets` | object (images[], audio[]) | |

**Building types (closed enum):** `concrete_moment_frame`, `unreinforced_masonry`, `wood_light_frame`, `steel`, `mixed`, `unknown`

**Hazard codes (closed enum):** `H01_soft_story`, `H02_unreinforced_masonry`, `H03_pounding`, `H04_falling_hazard`, `H05_adjacent_leaning`, `H06_ground_failure`, `H07_chimney_parapet`, `H08_foundation_displacement`

**Damage tags (closed enum, 19 values):** `diagonal_crack`, `horizontal_crack`, `vertical_crack`, `x_pattern_crack`, `concrete_spalling`, `exposed_rebar`, `column_base_damage`, `beam_column_joint_damage`, `soft_story_condition`, `pounding_damage`, `infill_wall_crack`, `out_of_plane_failure`, `foundation_displacement`, `chimney_damage`, `parapet_damage`, `falling_hazard_unsecured`, `uncertain_structural`, `uncertain_cosmetic`, `no_visible_damage`

**Vault storage on-device** (per packet):
```
cairn_vault/<packetId>/
  packet.json      — atomic-write sealed EvidencePacket
  img-1.jpg        — original JPEG bytes (never modified)
  aud-1.wav        — mono 16 kHz WAV bytes
  turns.jsonl      — one JSON object per LLM inference turn (provenance log)
  report.pdf       — generated PDF
```

---

## 8. System Prompt (Locked)

**File:** `docs/prompts/system_prompt_v1.txt` (also at `apps/cairn_mobile/assets/prompts/system_prompt_v1.txt`)

This file is **locked** — do not edit without a schema/prompt migration. ~1.9k tokens under Gemma tokenizer.

**12 Hard Rules enforced by the prompt:**
1. Output is strict JSON only — no prose, no markdown, no code fences
2. Schema keys in English; free-text in `asked_in` locale (`en`/`es`/`tr`)
3. Only 19 permitted `model_tags` (structural vocabulary)
4. Uncertainty is required — blurry/ambiguous images MUST emit `uncertain_structural`/`uncertain_cosmetic` with confidence ≤ 0.5
5. Never invent facts not visible in the image
6. User speech overrides model inference
7. Bounding boxes use Gemma convention: `[y1, x1, y2, x2]` 0–1000 normalized
8. Model does NOT compute priority score (app does this in Dart)
9. Hazard codes are closed enum (H01–H08)
10. Protocol answers are strict boolean/enum types
11. `describe_photo` output limit: ≤3 sentences, ≤60 words, 1–4 tags, ≤1 bbox per finding
12. `no_visible_damage` discipline — only when scan finds zero candidates AND photo clearly shows building exterior

**`no_visible_damage` is placed last in the tag enum** in `cairn_tools.dart` to reduce model bias toward the "easy out" answer (small VLMs are biased toward first/last enum tokens).

---

## 9. Image Preprocessing

**File:** `apps/cairn_mobile/lib/core/images/image_preprocessor.dart`

**Production path:** `BoundedImagePreprocessor(maxLongEdgePx: 640)`  
- Downscales to longest edge ≤ 640 px, aspect-ratio preserving, via `dart:ui`
- Images already within bound are passed through unchanged (zero cost)
- **Original bytes in `SessionDraft` are NEVER modified** — inference uses a sidecar copy

**Why 640 px was chosen:** Benchmarked on Samsung S23 FE. 512 px caused structural accuracy regression (lost soft-story and column-base detail). 768 px was the conservative fallback. 640 px matched 768 px structural score while cutting image bytes heavily.

**Native Android JPEG sidecar preprocessing** also available via `app.cairn/image_preprocess` to offload resize from Dart to the Android native layer.

**Test path:** `PassthroughImagePreprocessor` — no-op, for raw-bytes benchmarks and unit tests.

---

## 10. Session Config (Inference Profiles)

**File:** `apps/cairn_mobile/lib/core/llm/session_config.dart`

| Profile | maxTokens | temperature | clearHistory | Use |
|---|---|---|---|---|
| `vision` | 4096 | 0.1 | true | `describe_photo` (per photo) |
| `audio` | 4096 | 0.1 | true | `describe_audio` |
| `standard` | 4096 | 0.1 | true | `protocol_answer`, `ask_followup` |
| `synthesis` | 4096 | 0.2 | true | `synthesize` |

`clearHistoryBetweenTurns: true` by default to prevent cross-photo contamination.

---

## 11. Identity Allocation (No Collision)

Three monotonic counters per session, never decrement:

| Space | Pattern | Allocated by |
|---|---|---|
| Observations | `obs-N` (starts at 1) | `SessionDraft.allocateObservationId()` |
| Images | `img-N` (starts at 1) | `SessionDraft.allocateImageRef()` |
| Audio | `aud-N` (starts at 1) | `SessionDraft.allocateAudioRef()` |

This was a deliberate fix: v4 used length-based allocation which caused collision bugs on retake/remove.

---

## 12. Observations: Two Kinds

**Model-authored** (from `describe_photo`, `protocol_answer`, `synthesize`):
- `model_description`: required
- `model_tags`: from closed enum
- `model_confidence`: 0.0–1.0 (model-supplied)
- `user_text`: null

**Volunteer-authored** (from `volunteer_note_v1`, `humility_override_v1`):
- `user_text`: required (volunteer-typed text)
- `model_description`: omitted
- `model_tags`: empty `[]`
- `model_confidence`: `1.0` (sentinel — "human ground truth", not actual confidence)

The combination of `1.0` confidence + distinct `prompt_id` + empty `model_tags` + absent `model_description` unambiguously signals volunteer authorship.

---

## 13. Performance Logging

**File:** `apps/cairn_mobile/lib/core/llm/perf_log.dart`

Emits `[Cairn/perf]` log lines via `adb logcat`, complementing native `[*/perf]` lines from `flutter_gemma`.

Tracked events: `install`, `engine_create`, `generate`

Per-`generate` turn: `task`, `wall_ms`, `ttft_ms`, `out_chars`, `img_bytes`, `thinking_chars`

**Each `TurnRecord`** is persisted to `turns.jsonl` for complete inference provenance:
- `ts` (UTC ISO 8601)
- `task` (e.g. `describe_photo`, `synthesize`)
- `observation_id` (links to the resulting observation)
- `ttft_ms`, `wallclock_ms`, `output_char_count`, `thinking_chars`

---

## 14. Python Tooling Structure

```
scripts/
  cairn/
    constants.py     — MODELS dict, HAZARD_SEVERITY_POINTS, file paths (fail-loud on missing locked files)
    schema.py        — JSON Schema Draft 2020-12 validator (lru_cache)
    triage.py        — Deterministic priority score (Python mirror of Dart)
    prompts.py       — Loads locked system prompt (lru_cache)
    metrics.py       — Eval metrics: damage-presence F1, damage-type top-k, severity Spearman, tag Jaccard
    runners/         — LlmRunner interface, OllamaRunner
  data/
    generate_dialogues.py   — Synthetic training dialogue generation (via Gemini API)
    assemble_dialogues.py   — Assembles JSONL training data
    validate_seeds.py       — Validates seed JSONL against the schema
  eval/
    eval_baseline.py        — Zero-shot eval: strategy × runner × N gold items → JSONL report
    prompt_strategies.py    — Three strategies: strict_schema, cot_then_schema, schema_only
    report.py               — Eval report generation
  tests/
    test_constants_parity.py  — Ensures Dart and Python model constants are identical
    test_metrics.py
    test_schema.py
    test_seeds.py
    test_triage.py
    test_prompt_sync.py       — Ensures system prompt is in sync across all copies
```

---

## 15. LoRA Fine-tuning (Experimental)

**Directory:** `finetune/`

- `phase_a_text_lora.py` — Text-only LoRA on E2B/E4B using **Unsloth FastLanguageModel** (Linux/CUDA only, Colab A100/L4)
  - LoRA targets attention layers only: `q_proj`, `k_proj`, `v_proj`, `o_proj`
  - Ranks: `r ∈ {4, 8, 16}` (MediaPipe converter constraint)
  - `finetune_vision_layers=False`, `finetune_mlp_modules=False`
- `convert_mediapipe_lora.py` — Converts LoRA adapter to MediaPipe flatbuffer (`.fb`)
  - On-device load via `flutter_gemma`'s `InferenceChat(loraPath: ...)`
- `phase_b_vision_lora.py` — Stub for vision-conditioned LoRA (not yet implemented)

---

## 16. Test Coverage

### Flutter (657+ tests)

```bash
cd apps/cairn_mobile
flutter test
```

Key test files:
- `orchestrator_contract_test.dart` — LLM contract enforcement
- `evidence_packet_validator_test.dart` — Schema validator
- `priority_test.dart` — Triage scoring
- `model_registry_platform_test.dart` — Gemma 4 model guard
- `session_controller_test.dart` — Session state machine
- `image_preprocessor_test.dart` — Image bounds
- `photos_lost_data_test.dart` — Process-death recovery
- `perf_log_parser_test.dart` — Perf log parsing
- `vision_prompt_constraints_test.dart` — Output size limits
- `web_bootstrap_test.dart` — Web platform path

### Python

```bash
cd scripts
PYTHONPATH=. pytest -q
```

---

## 17. Privacy & Safety Design

- **Zero telemetry, zero analytics, zero crash reporting** — explicit design choice
- All data stays on device; sharing is user-initiated only
- The volunteer attestation text is embedded in every packet: *"I am not a licensed engineer. This is preliminary screening only."*
- Gemma is forbidden by system prompt from using safety-authority language: `"unsafe"`, `"condemned"`, `"do not enter"`, `"red-tagged"`, `"yellow-tagged"`, etc.
- The model is explicitly not a structural engineering determination and not an ATC-20 placard

---

## 18. Locked Artifacts (Do Not Edit Without Migration)

| File | Purpose |
|---|---|
| `docs/prompts/system_prompt_v1.txt` | Canonical system prompt |
| `apps/cairn_mobile/assets/prompts/system_prompt_v1.txt` | App-bundled copy |
| `docs/schema/evidence_packet_v1.schema.json` | Canonical JSON Schema |
| `apps/cairn_mobile/assets/schema/evidence_packet_v1.schema.json` | App-bundled copy |
| `data/seeds/dialogues.seed.jsonl` | Hand-authored gold dialogues |

---

## 19. Build & Run Commands

```bash
# Flutter tests
cd apps/cairn_mobile
flutter pub get
flutter test

# Run on Android device
flutter run -d <device-id>

# Run without speculative decoding (for benchmarking)
flutter run -d <device-id> --dart-define=BENCH_MTP=false

# Run on web (Chrome with WebGPU)
flutter config --enable-web
flutter run -d chrome --web-browser-flag=--enable-unsafe-webgpu

# Profile build with dev model test screen
flutter run --profile -d <device-id> --dart-define=DEV_MODEL_TEST=true

# Debug APK build
flutter build apk --debug --no-pub

# Python tests
cd scripts
python3 -m venv .venv
. .venv/bin/activate   # or .venv\Scripts\activate on Windows
pip install -e .
PYTHONPATH=. pytest -q
```

---

## 20. Key Design Decisions to Know

1. **Gemma never computes triage.** The model describes and tags observations; Dart computes the priority score deterministically. This prevents the model from being an unbounded authority in a high-stakes situation.

2. **Locked schema + locked prompt.** Both are versioned artifacts. Changing either requires a deliberate migration, not an edit.

3. **Constants parity between Dart and Python.** CI test (`test_constants_parity.py`) enforces that model IDs, hazard codes, tags, and scoring logic are identical on both sides.

4. **Fail loud on contract violations.** `GemmaContractError` is thrown immediately on any schema violation — the session controller decides whether to surface the error or re-ask, not the orchestrator.

5. **Original capture bytes are never modified.** Image preprocessing creates a sidecar for inference only; the vault stores originals.

6. **640 px inference image size chosen empirically.** 512 px caused structural accuracy regression in S23 FE benchmarks.

7. **Monotonic counters for IDs.** Prevents collision bugs on photo retake or remove operations.

8. **`no_visible_damage` is positioned last in the tag enum** to counteract small VLM bias toward "easy out" answers.

9. **Privacy-first.** No data leaves the device unless the user explicitly shares.

10. **Supports 3 locales:** English (`en`), Spanish (`es`), Turkish (`tr`) — all free-text in the `asked_in` locale, all JSON keys always in English.
