# S23 FE Benchmark Guide

Complete tester handoff for Android speed, structural reliability, and UX
validation on the Samsung Galaxy S23 FE (Exynos 2200, `SM-S711B`).
Device serial: `RZCX920ARVA`.

---

## Contents

1. [Prerequisites and pre-flight](#1-prerequisites-and-pre-flight)
2. [Build sanity check](#2-build-sanity-check)
3. [Structural understanding gate](#3-structural-understanding-gate)
4. [Speed matrix](#4-speed-matrix)
5. [Image preprocessing A/B](#5-image-preprocessing-ab)
6. [CPU vs GPU backend diagnostic](#6-cpu-vs-gpu-backend-diagnostic)
7. [Session config variants](#7-session-config-variants)
8. [History retention A/B](#8-history-retention-ab)
9. [Manual field UX flow](#9-manual-field-ux-flow)
10. [Regression checks](#10-regression-checks)
11. [Reading perf logs](#11-reading-perf-logs)
12. [Promotion decisions](#12-promotion-decisions)
13. [What to do when results are bad](#13-what-to-do-when-results-are-bad)
14. [Quick-run path (time-limited)](#14-quick-run-path-time-limited)
15. [Production candidate config](#15-production-candidate-config)

---

## 1. Prerequisites and pre-flight

**Device:**

- Samsung Galaxy S23 FE (model `SM-S711B`, Exynos 2200).
- Developer options enabled. USB debugging on.
- ADB-connected: `adb devices` must show `RZCX920ARVA device`.
- Profile or release mode for all speed judgement — never debug builds.
- Same `.litertlm` model file for every run (do not swap between runs).

**Thermal discipline (skip nothing — Exynos throttles):**

- Charge above 60% before any run.
- Disable battery saver mode.
- Close all background-heavy apps (YouTube, Maps, Chrome).
- Let phone cool 5 minutes before starting a full matrix.
- Keep screen brightness constant across runs.
- Run scenarios in the same order every time.

**Tools required in PATH:**

```powershell
adb version          # Android Platform Tools
flutter --version    # Flutter SDK at C:\Dev\flutter
```

If either is missing, the benchmark scripts fall back to hard-coded paths
(`C:\Dev\android-sdk\platform-tools\adb.exe` and
`C:\Dev\flutter\bin\flutter.bat`).

All commands below are run from `apps/cairn_mobile` unless stated otherwise.

---

## 2. Build sanity check

Run once before any device work:

```powershell
flutter pub get
flutter analyze lib test tool/api_probe.dart
flutter test
flutter build apk --debug --no-pub
```

Expected: `flutter test` passes all 634+ tests. Zero analyzer warnings.
Debug APK must build cleanly — if it does not, fix before benchmarking.

Profile run check (model load + cold start):

```powershell
flutter run --profile -d RZCX920ARVA --dart-define=DEV_MODEL_TEST=true
```

Verify: app launches, model loads within 90 s on first run (Wi-Fi), within
25 s on warm start (GPU kernel cache warm). If model load exceeds 60 s on
warm start, thermal throttle is likely — cool the device and retry.

---

## 3. Structural understanding gate

**Run this gate first, before any speed work.**
A fast run that regresses structural accuracy is a failed run.

### Dev scenarios

Three curated 4-photo packs live under
`apps/cairn_mobile/assets/images/dev_scenarios/`:

| Scenario key            | Expected priority band |
|-------------------------|------------------------|
| `low_no_visible_damage` | LOW                    |
| `medium_cracks_spalling`| MEDIUM                 |
| `high_column_soft_story`| HIGH (or CRITICAL)     |

### Command

```powershell
.\tool\run_dev_model_scenarios.ps1 -DeviceId RZCX920ARVA -CaptureLogcat
```

To run the official `flutter_gemma` MTP path, launch the app with:

```powershell
flutter run --profile -d RZCX920ARVA `
  --dart-define=DEV_MODEL_TEST=true `
  --dart-define=INFERENCE_RUNTIME=flutter_gemma `
  --dart-define=BENCH_MTP=true `
  --dart-define=BENCH_IMAGE_PX=640
```

To run with the legacy native MTP bridge:

```powershell
.\tool\run_dev_model_scenarios.ps1 -DeviceId RZCX920ARVA -NativeMtp -CaptureLogcat
```

This launches the app with `DEV_MODEL_TEST=true`. The dev scenario screen
appears automatically. Run all three scenarios in sequence.

### Acceptance gate — ALL must pass before promoting any config

| Check | Required value |
|-------|----------------|
| `schema_failure_count` | `0` for every scenario |
| All 4 image refs preserved | No `img-N` missing from packet |
| Damage / no-damage classification | Correct per scenario key |
| Severity band | Within 1 bucket of expected (e.g. HIGH acceptable for `high_column_soft_story`) |
| Expected structural tags present | `>=50%` of expected tags appear in observations |
| Final `priority_band` (deterministic Dart scorer) | Matches expected column exactly |
| `total_wallclock_ms` | Recorded — compare across runtime variants |

**Do not trust a fast run if any structural check fails.** The Dart priority
scorer is deterministic — if the band is wrong, the model output fed to it
is wrong.

---

## 4. Speed matrix

The primary benchmark. Covers the full runtime × backend × image-size space.

### Full matrix (preferred — run when time allows)

```powershell
.\tool\benchmark_android_speed.ps1 -DeviceId RZCX920ARVA -OutDir .\bench_out -Variant matrix
```

This runs all five variant groups in sequence:

| Group | Dart defines | Purpose |
|-------|-------------|---------|
| `flutter` | `INFERENCE_RUNTIME=flutter_gemma BENCH_IMAGE_PX=640` | Production baseline |
| `flutter_mtp` | `INFERENCE_RUNTIME=flutter_gemma BENCH_MTP=true BENCH_IMAGE_PX=640` | Official flutter_gemma MTP A/B |
| `native_mtp_gpu` | `INFERENCE_RUNTIME=native_mtp BENCH_MTP=true BENCH_BACKEND=gpu BENCH_IMAGE_PX=512/640/768` | Legacy native MTP at 3 image sizes |
| `native_mtp_cpu` | `INFERENCE_RUNTIME=native_mtp BENCH_MTP=true BENCH_BACKEND=cpu BENCH_IMAGE_PX=640` | CPU fallback comparison |
| `native_mtp_batch` | `INFERENCE_RUNTIME=native_mtp BENCH_MTP=true BENCH_BACKEND=gpu BENCH_BATCH=true BENCH_IMAGE_PX=640` | Batch experiment |
| `image_preprocess_ab` | `… BENCH_NATIVE_IMAGE_PREPROCESS=false` vs `true` | JPEG sidecar A/B |

The script pauses between variants and waits for ENTER. For each variant:
1. Wait for the app to launch and the model to load.
2. Navigate to the dev scenario screen (or start a new screening).
3. Run the same 4-photo scenario you used for every other variant.
4. Wait for all descriptions + synthesis to complete.
5. Press ENTER in the terminal to stop capture and move to the next variant.

### Individual variant runs

```powershell
.\tool\benchmark_android_speed.ps1 -DeviceId RZCX920ARVA -OutDir .\bench_out -Variant flutter
.\tool\benchmark_android_speed.ps1 -DeviceId RZCX920ARVA -OutDir .\bench_out -Variant native_mtp_gpu
.\tool\benchmark_android_speed.ps1 -DeviceId RZCX920ARVA -OutDir .\bench_out -Variant native_mtp_cpu
.\tool\benchmark_android_speed.ps1 -DeviceId RZCX920ARVA -OutDir .\bench_out -Variant native_mtp_batch
```

### What to record for every run

| Field | Log source |
|-------|-----------|
| Total 4-photo wall time | `total_wallclock_ms` in logcat |
| `image_preprocess` wall + `img_bytes` | `[Cairn/perf] phase=image_preprocess` |
| `describe_all total_wallclock_ms` | `[Cairn/perf] phase=generate` aggregate |
| `backendUsed` (native MTP) | `[Cairn/native_mtp]` lines |
| GPU fallback occurred | look for `backendUsed=cpu` when GPU requested |
| `prefillTokenCount` | `[FfiInferenceModelSession/perf]` |
| `prefillTokS` (tokens/sec prefill) | `[FfiInferenceModelSession/perf]` |
| decode `tokensPerSecond` | `[FfiInferenceModelSession/perf]` |
| `time_to_first_chunk_ms` (TTFT) | `[FfiInferenceModelSession/perf]` |
| `schema_failure_count` | logcat filter `schema_failure` |
| `vision_understanding_score` | logcat |
| `priority_band` | logcat |

### Speed matrix acceptance gates

| Comparison | Gate |
|-----------|------|
| `flutter_mtp` vs `flutter` | Decode tokens/sec **+35%** OR 4-photo total wall time **+20%** faster |
| `native_mtp_gpu` vs `flutter` | Decode tokens/sec **+35%** OR 4-photo total wall time **+20%** faster |
| `native_mtp_batch` vs sequential | 4-photo total wall time **+30%** faster, zero cross-photo contamination |
| Any variant vs baseline | `schema_failure_count == 0`, no priority band regression |

If native MTP is not faster, keep `flutter_gemma` as the production runtime.

> **Session 2 S23 FE finding:** `native_mtp` runtime loads the model
> (`engine_create` 31,071 ms, `mtp_available=true`) but produces **zero vision inference
> output** — `phase=generate` is absent from all runs, `vision_score=0.00`, schema
> failures on every photo, total_wallclock ≈600 ms (preprocessing only). Root cause:
> the legacy bridge likely failed before or during native generation. Use the
> official `flutter_gemma` 0.15.x MTP path for the next MTP A/B, and keep
> `flutter_gemma` without MTP as the production fallback.

---

## 5. Image preprocessing A/B

Tests native Android JPEG sidecars (`app.cairn/image_preprocess`) against
the legacy Dart PNG resize path.

```powershell
.\tool\benchmark_android_speed.ps1 -DeviceId RZCX920ARVA -OutDir .\bench_out -Variant image_preprocess_ab
```

This runs two builds back-to-back:

| Build | Dart defines | Path |
|-------|-------------|------|
| A | `… BENCH_NATIVE_IMAGE_PREPROCESS=false BENCH_IMAGE_PX=640` | Dart `BoundedImagePreprocessor` → PNG |
| B | `… BENCH_NATIVE_IMAGE_PREPROCESS=true BENCH_IMAGE_PX=640` | `AndroidJpegImagePreprocessor` → JPEG sidecar |

Also run the standalone image-size benchmark to compare raw vs 768px vs 512px vs 640px:

```powershell
.\tool\benchmark_image_px.ps1 -DeviceId RZCX920ARVA -Variant all -OutDir .\bench_out\image_px
```

| Variant | `BENCH_IMAGE_PX` | Preprocessor |
|---------|-----------------|--------------|
| `raw` | `-1` | `PassthroughImagePreprocessor` (no resize) |
| `768px` | `768` | `BoundedImagePreprocessor(768)` |
| `640px` | `0` → spec default 640 | `BoundedImagePreprocessor(640)` |
| `512px` | `512` | `BoundedImagePreprocessor(512)` |

> **Session 2 result (S23 FE):** 512px rejected — S3 (`high_column_soft_story`) vision_score 0.36
> (foundation sees `no_visible_damage`, severityDelta=3). 640px passes: S3 vision_score 0.54,
> `column_base_damage` correctly identified. **640px is the promoted image size for this device.**

### Key fields to compare

- `[Cairn/perf] phase=image_preprocess wall=...ms img_bytes=...`
  Lower `img_bytes` = less data sent to the model = faster prefill.
- `[FfiInferenceModelSession/perf] time_to_first_chunk_ms`
  This is the TTFT gate metric.

### Acceptance gate

Promote `BENCH_NATIVE_IMAGE_PREPROCESS=true` only if:
- JPEG sidecar `img_bytes` is materially lower than Dart PNG.
- No orientation or colour regression visible in saved packet images.
- `schema_failure_count == 0` on the 3-scenario structural gate.

Promote `BENCH_IMAGE_PX=512` only if:
- TTFT / prefill improves **≥15%** vs `raw` baseline.
- All 4 photo descriptions pass schema validation.
- No visible small-crack accuracy loss on real building photos.
- If `512` loses crack accuracy, use `640`. If `640` loses severity/tag accuracy, use `768`.

**S23 FE (Session 2) measured:** 512px rejected; **640px promoted** — see `bench_out/RESULTS.md §5`.

---

## 6. CPU vs GPU backend diagnostic

Tests Exynos 2200 GPU vs CPU for vision (describe_photo) and synthesis turns.

```powershell
.\tool\benchmark_backend.ps1 -DeviceId RZCX920ARVA -Variant all -OutDir .\bench_out\backend
```

Four variants run in sequence:

| Variant | Dart defines | Task |
|---------|-------------|------|
| `vision_gpu` | *(none — GPU default)* | `describe_photo` ×5 |
| `vision_cpu` | `BENCH_BACKEND=cpu` | `describe_photo` ×5 |
| `synthesis_gpu` | *(none — GPU default)* | `synthesize` |
| `synthesis_cpu` | `BENCH_BACKEND=cpu` | `synthesize` |

For each variant the script launches the app and prints the exact steps to
follow on device. Do not deviate.

### Key log lines to compare

```
[LiteRtLmFfi/perf] engine_create wall=...ms
[FfiInferenceModelSession/perf] time_to_first_chunk_ms=...
[FfiInferenceModelSession/perf] generation_time_ms=...
[Cairn/perf] phase=generate ttft=...ms wall=...ms
```

### Decision rule

| Condition | Action |
|-----------|--------|
| `vision_cpu` TTFT < `vision_gpu` TTFT | Set `SessionConfig.vision.preferredBackend = cpu` |
| `synthesis_cpu` wall < `synthesis_gpu` wall | Set `SessionConfig.synthesis.preferredBackend = cpu` |
| GPU wins or ties on all | No change — GPU confirmed optimal for Exynos 2200 |
| GPU produces OOM or fallback to CPU | Log it; prefer whichever is stable |

GPU is expected to be faster for multimodal (vision) on Exynos 2200.
CPU may be competitive for text-only synthesis. Confirm before changing
production `SessionConfig` defaults in `lib/core/llm/session_config.dart`.

---

## 7. Session config variants

Tests token budget and temperature variants from Sprints 2 and 4.

```powershell
.\tool\benchmark_session_config.ps1 -DeviceId RZCX920ARVA -Variant all -OutDir .\bench_out\session_config
```

Variants in the matrix:

| Variant | maxTokens | temperature | clearHistory | Purpose |
|---------|-----------|-------------|:------------:|---------|
| `baseline` | 4096 | 0.1 | true | Production reference |
| `vision_3072` | 3072 | 0.1 | true | KV-cache memory reduction |
| `vision_2048` | 2048 | 0.1 | true | Maximum memory reduction |
| `vision_temp01` | 4096 | 0.05 | true | Near-greedy — JSON determinism |
| `standard_temp01` | 4096 | 0.05 | true | Protocol/followup JSON |
| `vision_history_retained` | 4096 | 0.1 | **false** | History A/B (see §8) |

Each variant runs `BENCH_CONFIG=<key>` which maps to a named `SessionConfig`
constant in `lib/core/llm/session_config.dart` via `_benchConfigForKey()` in
`providers.dart`.

For each variant: run the full flow
`Start → Location → Photos (all 4) → Describe → Protocol → Humility → Synthesize → Report`.

### Reading the summary

The script writes `bench_results/benchmark_summary.tsv` with one row per
variant:

```
variant  maxTokens  temperature  engine_create_ms  ttft_ms_avg  wall_ms_avg  out_chars_avg
```

### Acceptance gate

Promote a variant only if:
- Zero `GemmaContractError` in `turns.jsonl` (no JSON truncation).
- No output truncation — JSON parse failures = 0.
- `engine_create_ms` and/or average TTFT/wall improve vs `baseline`.

Do not lower `maxTokens` below 2048 — it breaks the KV cache for vision
(system prompt ~500 + image tokens ~1800 at 768px + user JSON ~200 = ~2695
total, which exceeds 2048).

---

## 8. History retention A/B

Isolates OPT-5: does retaining chat history between sequential
`describe_photo` turns speed up prefill without introducing cross-photo
contamination?

```powershell
.\tool\benchmark_session_config.ps1 -DeviceId RZCX920ARVA -Variant vision_history_retained -OutDir .\bench_out\history
```

Dart define applied: `BENCH_CONFIG=vision_history_retained`
This sets `clearHistoryBetweenTurns: false` in `SessionConfig.visionHistoryRetained`.

### What to check

1. **Speed:** Is `ttft_ms_avg` materially lower than `baseline`? Record both
   and compute the delta.
2. **Contamination:** Read each `describe_photo` output in `turns.jsonl`.
   Does observation for photo N mention photo N−1? Any cross-photo reference
   is an automatic fail.
3. **Contract:** `GemmaContractError` rate must be equal to or better than
   `baseline`.

### Gate

| Check | Required |
|-------|----------|
| No cross-photo output contamination | **Hard gate — any fail = reject** |
| TTFT / prefill improvement | Materially better (>10%) vs baseline |
| `GemmaContractError` rate | ≤ baseline |

Only promote `clearHistoryBetweenTurns: false` to production if all three
pass. Production default is `clearHistoryBetweenTurns: true`.

---

## 9. Manual field UX flow

Run this outside the dev scenario screen, with a fresh install if possible.

1. Start app — verify Bootstrap screen requests camera, mic, location.
2. Grant all permissions.
3. Load model — verify progress bar advances through download → load phases.
   On warm start, model should appear ready within 25 s.
4. Start a new screening.
5. Acquire GPS — verify coordinates appear or a clear error/skip option.
6. Capture the 4 required photos: **front, ground floor, cracks, foundation**.
   Confirm capture returns immediately (no model wait during capture phase).
7. Retake one photo — confirm the new image replaces the old one.
8. Kill the app via recents.
9. Reopen the app — confirm the draft resume banner appears.
10. Resume the draft — confirm all 4 photos are still present.
11. Tap **Describe photos** — confirm the processing screen advances
    photo by photo and shows progress.
12. Complete the protocol questions — all 6 yes/no questions.
13. Complete humility check — one follow-up question with free text answer.
14. Tap **Synthesize** — verify the thinking-mode progress screen appears
    and the model produces a rationale.
15. Confirm the report screen shows:
    - Priority badge (score 1–10, band LOW/MEDIUM/HIGH/CRITICAL).
    - Rationale bullets.
    - Photo thumbnails.
    - Packet ID and QR code.
    - Disclaimer text.
16. Save screening.
17. Open Saved Screenings.
18. Open the packet detail.
19. Open photo detail — check tags, confidence, dimensions, bbox overlay.
20. Export / share PDF — confirm PDF opens and contains all pages.
21. Share JSON bundle — confirm file is produced and contains `cairn.evidence.v1`.

---

## 10. Regression checks

These must pass for every benchmark variant and after every UX flow run:

| Check | Pass criterion |
|-------|---------------|
| Original evidence images | Full-resolution bytes in saved packet/export — NOT replaced by inference sidecars |
| Inference sidecars | Do not appear in the exported packet assets |
| Native JPEG sidecar orientation | Saved images are not rotated or mirrored vs capture |
| Dart fallback path | If native preprocessing fails, Dart path still runs — disable with `BENCH_NATIVE_IMAGE_PREPROCESS=false` to verify |
| Sidecar disappearance | Kill app after capture; sidecar files deleted by OS; reopen — inference still runs (reads original bytes) |
| Schema validity | `schema_failure_count == 0` on every run |
| Priority band | Final band is deterministic — if it changes between identical runs, the Dart scorer has a bug |
| No crash / ANR | App must not crash or produce ANR at any step |

---

## 11. Reading perf logs

All `/perf` lines appear in `adb logcat` under the `flutter` tag. Filter:

```
adb -s RZCX920ARVA logcat -v time | Select-String '/perf|schema_failure|total_wallclock'
```

Or use the standalone capture script (streams to file + console):

```powershell
.\tool\capture_perf_log.ps1 -DeviceId RZCX920ARVA -DurationSeconds 600 -OutDir .\bench_out
```

### Line sources and formats

**Native flutter_gemma / LiteRT-LM lines (emitted by the SDK):**

```
[LiteRtLmFfi/perf] dylib_load wall=...ms
[LiteRtLmFfi/perf] settings_create wall=...ms
[LiteRtLmFfi/perf] engine_create wall=...ms
[FfiInferenceModel/perf] createConversation wall=...ms
[FfiInferenceModelSession/perf] time_to_first_chunk_ms=... generation_time_ms=...
```

**Cairn Dart lines (emitted by `PerfLogger` in `lib/core/llm/perf_log.dart`):**

```
[Cairn/perf] phase=install          wall=...ms
[Cairn/perf] phase=engine_create    wall=...ms
[Cairn/perf] phase=image_preprocess wall=...ms img_bytes=...
[Cairn/perf] phase=generate task=describe_photo  wall=...ms ttft=...ms out_chars=... img_bytes=...
[Cairn/perf] phase=generate task=synthesize      wall=...ms ttft=...ms out_chars=... thinking_chars=...
[Cairn/perf] phase=generate task=protocol_answer wall=...ms ttft=...ms out_chars=...
[Cairn/perf] phase=parse_contract   wall=...ms
```

**Field glossary:**

| Field | Meaning |
|-------|---------|
| `wall=...ms` | Total elapsed wall-clock time for the phase |
| `ttft=...ms` | Time to first token (prefill + first decode step) |
| `out_chars=...` | UTF-16 code units in generated text (excludes thinking) |
| `thinking_chars=...` | Code units in thinking/reasoning trace |
| `img_bytes=...` | Byte size of image sent to inference |
| `time_to_first_chunk_ms` | Native SDK TTFT (prefill) |
| `generation_time_ms` | Native SDK total decode time |

**What a complete single `describe_photo` turn looks like:**

```
[LiteRtLmFfi/perf] engine_create wall=8234ms         ← model init + KV alloc
[Cairn/perf] phase=image_preprocess wall=34ms img_bytes=98304
[FfiInferenceModelSession/perf] time_to_first_chunk_ms=1823 generation_time_ms=4512
[Cairn/perf] phase=generate task=describe_photo wall=4551ms ttft=1823ms out_chars=187 img_bytes=98304
[Cairn/perf] phase=parse_contract wall=2ms
```

**Minimal required phases** — a run is incomplete if any of these are missing:

- `phase=engine_create`
- `phase=generate`
- `phase=image_preprocess`
- `phase=parse_contract`

The `missingRequiredBenchmarkFields()` function in
`lib/core/llm/perf_log_parser.dart` checks exactly these four phases
programmatically.

---

## 12. Promotion decisions

### Runtime promotion (`INFERENCE_RUNTIME`)

Promote `native_mtp` if, vs `flutter_gemma` baseline:
- Decode tokens/sec improves ≥35%, **or**
- 4-photo total wall time improves ≥20%.

Keep `flutter_gemma` if native MTP is not faster or is less reliable.

> **S23 FE Session 2:** `native_mtp` **REJECTED** — vision inference non-functional
> (`phase=generate` absent, all schema failures, 0.00 score all scenarios).
> **Current production runtime: `flutter_gemma`.**

### Image size promotion (`BENCH_IMAGE_PX`)

| Result | Action |
|--------|--------|
| 512px TTFT ≥15% better vs raw, no accuracy loss | Set `inferenceMaxLongEdgePx: 512` in `model_registry.dart` |
| 512px loses small-crack accuracy | Use 640px |
| 640px loses severity/tag accuracy | Stay at 768px |

> **S23 FE Session 2:** 512px loses S3 structural accuracy (0.54→0.36). **640px promoted**
> (S3 recovers to 0.54, `column_base_damage` detected, all checks pass).
> Set `BENCH_IMAGE_PX=640` for this device.

### Native preprocessing promotion (`BENCH_NATIVE_IMAGE_PREPROCESS`)

Promote `true` (the current default) if:
- JPEG `img_bytes` is materially lower than Dart PNG.
- No orientation regression in saved images.
- `schema_failure_count == 0`.

### Backend promotion (`BENCH_BACKEND`)

Change `preferredBackend` in `SessionConfig` (in `session_config.dart`) only
after the backend diagnostic (§6) proves CPU is faster or more stable.
Expected: GPU wins for vision; uncertain for synthesis.

### Token budget promotion (`maxTokens`)

Lower `maxTokens` from 4096 only after a full `benchmark_session_config.ps1`
run shows zero truncation and acceptable TTFT delta. Do not lower below 2048.

### History retention promotion (`clearHistoryBetweenTurns`)

Set `clearHistoryBetweenTurns: false` in production `SessionConfig.vision`
only after the §8 gate passes with zero contamination.

---

## 13. What to do when results are bad

### Native MTP is not faster

- Compare `tokensPerSecond` (decode), not just wall time.
- If decode tokens/sec improves but wall time does not, the bottleneck is
  prefill or session overhead, not decode speed.
- Keep native MTP only if schema reliability is equal **and** total wall time
  improves.

**If native_mtp returns vision_score=0.00 with schema failures on ALL scenarios
and total_wallclock ≈600 ms** (preprocessing only, no `phase=generate` lines):
the legacy `NativeMtpGemmaSession.describeAll()` generate step is failing before
or during native generation. Keep the official `flutter_gemma` runtime as the
baseline, then compare `flutter_mtp` separately before spending more time on
the bridge.

### Image preprocessing is still slow

- Try 512px → 640px → 768px in order.
- If native JPEG sidecars regress orientation or accuracy:
  ```
  --dart-define=BENCH_NATIVE_IMAGE_PREPROCESS=false
  ```

### GPU is unstable on Exynos

- Check native logs for `backendUsed=cpu` (GPU fallback).
- Compare `native_mtp_cpu` against `native_mtp_gpu`.
- Prefer CPU only if it is both faster and more stable on this device.

### Batch mode fails

- Keep `BENCH_BATCH=true` disabled in production.
- Note: Cairn's production path intentionally keeps per-photo vision turns
  separate. Multi-image batch is a diagnostic experiment only.
  `describeAll()` sequential is the correct production path.

### Schema failures appear

- Check the raw LLM output in `turns.jsonl` (`cairn_vault/<packetId>/turns.jsonl`).
- Look for truncated JSON — indicates `maxTokens` is too low.
- Lower `temperature` (try `vision_temp01` at 0.05) if the model produces
  malformed JSON.
- Shorten `describe_photo` output further before changing scoring.
- Add failing examples to `assets/images/dev_scenarios/` before tuning prompts.

### Priority band is wrong

- The Dart scorer is byte-identical to the Python scorer in
  `scripts/cairn/metrics.py`. If the band is wrong, the model observations
  fed to it are wrong.
- Do not adjust the scorer — fix the model output or prompts.

### App crashes or ANRs

- Check logcat for `SIGSEGV`, `OutOfMemoryError`, or `ANR`.
- GPU SIGSEGV → try `BENCH_BACKEND=cpu`.
- OOM → lower `maxTokens` or reduce `BENCH_IMAGE_PX`.
- If crash is in the flutter_gemma LiteRT-LM path, compare to the last
  known-good commit; the integration was confirmed working in Phase 5
  (`docs/android_repivot_v5_runlog.md`).

---

## 14. Quick-run path (time-limited)

If you have limited time, run in this priority order:

**Step 1 — Structural gate (mandatory, ~20 min)**

```powershell
.\tool\run_dev_model_scenarios.ps1 -DeviceId RZCX920ARVA -CaptureLogcat
```

Do not skip this. A speed win with structural regression is a net loss.

**Step 2 — Highest-signal speed variants (~40 min)**

```powershell
.\tool\benchmark_android_speed.ps1 -DeviceId RZCX920ARVA -OutDir .\bench_out -Variant image_preprocess_ab
.\tool\benchmark_android_speed.ps1 -DeviceId RZCX920ARVA -OutDir .\bench_out -Variant native_mtp_gpu
.\tool\benchmark_android_speed.ps1 -DeviceId RZCX920ARVA -OutDir .\bench_out -Variant flutter
```

**Step 3 — UX smoke check (~15 min)**

Full flow once: start → 4 photos → describe → protocol → synthesize → report → export.
Verify no crash, no OOM, priority band present.

**If time allows after the above:**

```powershell
.\tool\benchmark_android_speed.ps1 -DeviceId RZCX920ARVA -OutDir .\bench_out -Variant native_mtp_cpu
.\tool\benchmark_android_speed.ps1 -DeviceId RZCX920ARVA -OutDir .\bench_out -Variant native_mtp_batch
.\tool\benchmark_backend.ps1      -DeviceId RZCX920ARVA -Variant all -OutDir .\bench_out\backend
.\tool\benchmark_image_px.ps1     -DeviceId RZCX920ARVA -Variant all -OutDir .\bench_out\image_px
.\tool\benchmark_session_config.ps1 -DeviceId RZCX920ARVA -Variant vision_history_retained -OutDir .\bench_out\history
```

---

## 15. Production candidate config

**Current best config (S23 FE, Session 2 measured):**

```powershell
flutter run --profile -d RZCX920ARVA \
  --dart-define=INFERENCE_RUNTIME=flutter_gemma \
  --dart-define=BENCH_IMAGE_PX=640 \
  --dart-define=BENCH_NATIVE_IMAGE_PREPROCESS=true
```

Rationale:
- `flutter_gemma`: native_mtp produces no vision output on this device (Session 2).
- `BENCH_IMAGE_PX=640`: 512px rejected (S3 regression 0.54→0.36); 640px restores S3
  to 0.54 with all structural checks passing.
- `BENCH_NATIVE_IMAGE_PREPROCESS=true`: default, not yet A/B tested (pending §5).

**Promotion checklist (Session 2 status):**

- [x] `schema_failure_count == 0` on all 3 dev scenarios — confirmed flutter_gemma.
- [x] Correct priority bands on all 3 dev scenarios — LOW/MEDIUM/CRITICAL all match.
- [x] S3 structural gate: vision_score 0.54 ≥ 0.50 at 640px ✅
- [ ] §6b CPU vs GPU backend decision — pending.
- [ ] §7 Session config variants (token budget gate) — pending.
- [ ] §8 History contamination hard gate — pending.
- [ ] §9 Manual UX flow 21-step pass — pending.
- [ ] §10 Regression checks (original images, sidecar safety) — pending.
- [ ] No image orientation problems in saved packets — pending §9/§10.

If any remaining gate fails, the confirmed fallback is:

```powershell
flutter run --profile -d RZCX920ARVA \
  --dart-define=INFERENCE_RUNTIME=flutter_gemma \
  --dart-define=BENCH_IMAGE_PX=640
```

The `flutter_gemma` + 640px config is the current production baseline.
Do not ship `native_mtp` with `BENCH_MTP=true` until `phase=generate` is
confirmed present on this device.
