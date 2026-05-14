# Session 5 Handover — Cairn S23 FE Benchmark

**Date written:** 2026-05-14 (end of Session 4)
**Device:** SM-S711B (S23 FE), Exynos 2200, Android 16 / API 36
**Codebase:** `c:\Dev\gemma_project\apps\cairn_mobile`

---

## 1. What was confirmed in Session 4

### §3 Structural gate — ALL 3 PASS ✅

| Scenario | Total wall (warm) | Priority band | schema_failures |
|---|---|---|---|
| S1 low_no_visible | 428,240ms cold¹ / ~35,400ms/photo warm | LOW ✅ | 0 |
| S2 medium_cracks | 163,349ms | MEDIUM ✅ | 0 |
| S3 high_col_soft | **133,492ms** | CRITICAL ✅ | 0 |

¹ One-time GPU shader compile after APK reinstall. Not a regression.

### Key confirmed facts

- `speculativeDecoding=true` logged in session ✅
- `mtp_requested=true` in engine_create perf event ✅
- `parse_contract wall=0ms` on **every single turn** across all 3 scenarios ✅
- S2 `no_visible_damage` contradiction: **RESOLVED** by Rule 12 + SCAN ORDER ✅
- flutter_gemma 0.15.0 stable ✅
- json_extract `repairOrphanEmptyStrings` working — zero Gemma 4 stray-token failures ✅
- Second engine_create (GPU warm): **12,812ms** (fastest recorded) ✅

---

## 2. Changes made at end of Session 4 (new in this commit)

### 2a. MTP promoted to production default

`lib/core/providers.dart`:
```dart
// BEFORE:
const _kBenchMtp = bool.fromEnvironment('BENCH_MTP', defaultValue: false);

// AFTER — Sessions 3+4 confirmed +33% decode speedup, zero schema regressions:
const _kBenchMtp = bool.fromEnvironment('BENCH_MTP', defaultValue: true);
```

**Impact:** All builds (including `flutter build apk --release`) now have MTP active
by default. Opt out with `--dart-define=BENCH_MTP=false`.

### 2b. New SessionConfig: `visionSingleImage` (maxNumImages: 1)

`lib/core/llm/session_config.dart`:
```dart
static const visionSingleImage = SessionConfig(
  maxTokens: 4096, temperature: 0.1, topK: 40, topP: 0.95,
  preferredBackend: PreferredBackend.gpu,
  maxNumImages: 1,   // ← was 5 in production vision
);
```

Rationale: OPT-7 confirmed each `describe_photo` turn sends exactly 1 image
sequentially. The production `maxNumImages: 5` causes LiteRT-LM to allocate
a 5-image vision encoder buffer per turn unnecessarily.

Wired via `BENCH_CONFIG=vision_single_image`.

### 2c. `bench_out/RESULTS.md` updated with full Session 4 tables

---

## 3. The full MTP API chain (verified from flutter_gemma 0.15.0 source)

```
BENCH_MTP=true (dart-define)
  → _kBenchMtp = true (providers.dart)
    → enableSpeculativeDecoding: true (GemmaSession.openForVision)
      → FlutterGemma.getActiveModel(enableSpeculativeDecoding: true)
        → FlutterGemmaMobile.createModel(enableSpeculativeDecoding: true)
          → (fileType == .litertlm on Android) → LiteRtLmFfiClient.initialize()
            → litert_lm_engine_settings_set_enable_speculative_decoding(settings, true)
              → native C API → Gemma 4 MTP drafter in .litertlm model activated
```

**MTP is a binary toggle.** There are no additional tuning parameters exposed
at any layer of flutter_gemma 0.15.0:
- No draft token count
- No acceptance threshold
- No drafter temperature

The C binding `litert_lm_engine_settings_set_enable_speculative_decoding` takes
a single `bool`. This is the full extent of MTP configuration available.

---

## 4. Hidden C API levers — NOT yet wired in flutter_gemma 0.15.0

These functions exist in `lib/core/ffi/litert_lm_bindings.dart` (auto-generated
from engine.h) but are NOT called from `LiteRtLmFfiClient.initialize()`:

### 4a. `set_prefill_chunk_size(N)` — **#1 TTFT reduction lever**

```c
litert_lm_engine_settings_set_prefill_chunk_size(settings, int N)
```

Controls the number of tokens processed per GPU dispatch during the prefill
(prompt encoding) phase. The system prompt is ~2,700 tokens. If the LiteRT-LM
default chunk size is 512, that's ≥5 sequential GPU dispatches just for the
system prompt, dominating TTFT.

Measured warm TTFT (Session 4, S3): 16,307–17,012ms.
If prefill chunk is the bottleneck, setting `N=2048` or `N=4096` could halve TTFT.

**To expose this:** fork flutter_gemma and add to `LiteRtLmFfiClient.initialize()`:
```dart
// In litert_lm_client.dart initialize():
int? prefillChunkSize,
...
if (prefillChunkSize != null && prefillChunkSize > 0) {
  b.litert_lm_engine_settings_set_prefill_chunk_size(settings, prefillChunkSize);
}
```
Then wire through `FlutterGemma.getActiveModel()`, `createModel()`, and our
`gemma_session.dart`. Use `dependency_overrides` in `pubspec.yaml` to point to
the local fork.

Benchmark matrix: `prefillChunkSize` = 512, 1024, 2048, 4096.

### 4b. `set_parallel_file_section_loading(true)` — faster engine_create

```c
litert_lm_engine_settings_set_parallel_file_section_loading(settings, true)
```

Loads model file sections in parallel. Could reduce engine_create from
~12,812ms (warm GPU, Session 4 Run 2) closer to 5,000–8,000ms. Lower priority
than prefill chunk since engine_create is a one-time cost.

### 4c. `enable_benchmark()` — SDK-native per-turn timing

```c
litert_lm_engine_settings_enable_benchmark(settings)
```

Enables `litert_lm_session_get_benchmark_info()` / 
`litert_lm_conversation_get_benchmark_info()` which return:
- `get_time_to_first_token` (native TTFT, more accurate than Dart stopwatch)
- `get_prefill_tokens_per_sec_at(index)`
- `get_decode_tokens_per_sec_at(index)`
- `get_prefill_token_count_at(index)`
- `get_decode_token_count_at(index)`

This would give us native-measured tokens/sec data without the Dart stream
overhead. Low priority but useful for regression reporting.

---

## 5. #1 accessible TTFT lever: history retention (OPT-5)

**This is the highest-impact change achievable without touching flutter_gemma.**

Current TTFT (warm, Session 4):
- S3 photos: 16,307–17,012ms
- S2 photos: 16,500–25,684ms (still warming from S1 GPU compile)

The system prompt is ~2,700 tokens. With `clearHistoryBetweenTurns: true`
(production default), the **full system prompt is re-prefilled on every photo
turn.** That re-prefill dominates TTFT.

With `clearHistoryBetweenTurns: false` (`visionHistoryRetained`):
- Turn 1: full prefill (~2,700 + image + user msg tokens) → TTFT unchanged
- Turns 2–4: only image + user message prefill (~200–400 tokens) → TTFT target **<5,000ms**

**Gate (zero cross-photo contamination is hard gate):**
- Run `BENCH_CONFIG=vision_history_retained` on all 3 dev scenarios
- Check each obs references only its own image (not prior photos)
- If TTFT turns 2–4 < 5,000ms AND zero contamination → **promote immediately**

Command:
```powershell
.\tool\run_dev_model_scenarios.ps1 -DeviceId RZCX920ARVA -CaptureLogcat `
  -BenchImagePx 640 -BenchConfig vision_history_retained
```

---

## 6. Session 5 benchmark queue (in priority order)

### Priority 1 (do first — fast)
```powershell
# §6b CPU vs GPU
.\tool\benchmark_backend.ps1 -DeviceId RZCX920ARVA -CaptureLogcat -BenchImagePx 640

# OPT-5 history retention (highest TTFT lever)
.\tool\run_dev_model_scenarios.ps1 -DeviceId RZCX920ARVA -CaptureLogcat `
  -BenchImagePx 640 -BenchConfig vision_history_retained
```

### Priority 2 (new variants)
```powershell
# vision_single_image (maxNumImages: 1 vs production 5)
.\tool\benchmark_session_config.ps1 -DeviceId RZCX920ARVA -Variant vision_single_image -CaptureLogcat

# vision_history_retained full session config run
.\tool\benchmark_session_config.ps1 -DeviceId RZCX920ARVA -Variant vision_history_retained -CaptureLogcat
```

### Priority 3 (before shipping)
```powershell
# §9 Manual UX flow — follow 15-step procedure in docs/s23_fe_benchmark_guide.md §9
# §10 Regression checks — original images, sidecar safety, Dart fallback
```

### Priority 4 (medium-term — requires flutter_gemma fork)
- Expose `prefillChunkSize` in `LiteRtLmFfiClient.initialize()`
- Benchmark `prefillChunkSize` = 512 / 1024 / 2048 / 4096
- If this halves TTFT: it's the biggest win in the whole project

---

## 7. Perf baseline for comparison (Session 4 warm numbers)

| Metric | Value | Notes |
|---|---|---|
| engine_create (warm GPU) | **12,812ms** | Run 2, Session 4 |
| S3 per-photo wall (warm) | **31,951–34,048ms** | 4-photo average |
| S3 per-photo TTFT (warm) | **16,307–17,012ms** | System prompt re-prefill each turn |
| S3 describe_all total | **133,492ms** | 4 photos, MTP on, GPU warm |
| S2 describe_all total | **163,349ms** | Still GPU-warming from S1 |
| S1 photo 1 warm (Run 2) | **35,396ms** | GPU fully warm |

Target after OPT-5 (history retained):
- TTFT turns 2–4: **<5,000ms**
- describe_all 4 photos: **<80,000ms**

Target after prefillChunkSize patch:
- TTFT turn 1 (cold history): **<8,000ms**
- describe_all 4 photos with history retained + large chunk: **<50,000ms**

---

## 8. Production build command (current best)

```powershell
flutter build apk --profile `
  --dart-define=BENCH_IMAGE_PX=640 `
  --dart-define=BENCH_NATIVE_IMAGE_PREPROCESS=true
```

MTP is now the default (no `--dart-define=BENCH_MTP=true` needed).
`INFERENCE_RUNTIME` not set = `flutter_gemma` (correct, `native_mtp` is blocked).

---

## 9. Logcat analysis commands

```powershell
# All perf events
Select-String -Path "bench_out\<logfile>.txt" -Pattern "phase="

# TTFT per turn
Select-String -Path "bench_out\<logfile>.txt" -Pattern "phase=generate" |
  ForEach-Object { $_.Line }

# model_tags per observation
Select-String -Path "bench_out\<logfile>.txt" -Pattern "model_tags" |
  ForEach-Object { $_.Line }

# Schema failures
Select-String -Path "bench_out\<logfile>.txt" -Pattern "schema_failure|GemmaContractError"

# Engine create details
Select-String -Path "bench_out\<logfile>.txt" -Pattern "phase=engine_create"
```

---

## 10. What NOT to do

- **Do NOT enable `INFERENCE_RUNTIME=native_mtp`** — crashes with SIGABRT on Android 16 (every session).
- **Do NOT lower `maxTokens` below 2048** — system prompt + image tokens exceed 2048 at 640px.
- **Do NOT promote `visionHistoryRetained` without zero-contamination gate** — if any observation references a prior photo's content, this is a hard failure.
- **Do NOT assume MTP is off** — `_kBenchMtp` defaultValue is now `true`. Use `--dart-define=BENCH_MTP=false` explicitly if you need to measure without MTP.

---

## 11. Promotion checklist status

- [x] Zero schema failures (Sessions 1–4) ✅
- [x] Priority bands correct (LOW/MEDIUM/CRITICAL) ✅
- [x] 640px accuracy gate ✅
- [x] flutter_gemma 0.15.0 + MTP default ✅
- [x] native_mtp retired (blocked Android 16) ✅
- [x] S2 structural gate PASSED — no_visible_damage resolved ✅
- [x] json_extract repair working ✅
- [ ] §6b CPU vs GPU
- [ ] §7 Session config variants (esp. `vision_single_image`, `vision_history_retained`)
- [ ] §8 History contamination hard gate
- [ ] §9 Manual UX flow
- [ ] §10 Regression checks
- [ ] prefillChunkSize benchmark (requires flutter_gemma fork — optional but high value)
