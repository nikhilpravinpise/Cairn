# Tester Handoff: Android Speed, MTP, And Structural Reliability

## Current State

Cairn now has Android-first inference speed work in place:

- `flutter_gemma` 0.15.0 official LiteRT-LM speculative decoding is wired
  behind `BENCH_MTP=true`.
- Legacy native LiteRT-LM bridge remains behind `INFERENCE_RUNTIME=native_mtp`
  for diagnostics.
- Pinned Android LiteRT-LM dependency instead of `latest.release`.
- Android GPU create with CPU fallback and native perf payloads.
- Capture-time inference sidecars so photo analysis can skip repeated app-side preprocessing.
- Android-native JPEG sidecars through `app.cairn/image_preprocess`, default enabled.
- Benchmark flag to compare native JPEG sidecars against the old Dart PNG resize path:
  `BENCH_NATIVE_IMAGE_PREPROCESS=true|false`.
- Dev model scenarios with real 4-photo packs under
  `apps/cairn_mobile/assets/images/dev_scenarios/`.

Latest local verification:

- `flutter analyze lib test tool/api_probe.dart` passed.
- `flutter test` passed: 634 tests.
- `flutter build apk --debug --no-pub` passed.

## What The Tester Must Use

Primary target:

- Samsung S23 FE Exynos tester phone.
- Real physical device, not emulator.
- Profile or release mode only for speed judgement.
- Same model file for every run.
- Same battery/thermal setup for every run.

Before timing:

- Charge above 60%.
- Disable battery saver.
- Close other heavy apps.
- Let the phone cool for 5 minutes before each full matrix.
- Keep screen brightness stable.
- Run the same scenario order every time.

## Build Sanity Commands

From `apps/cairn_mobile`:

```bash
flutter pub get
flutter analyze lib test tool/api_probe.dart
flutter test
flutter build apk --debug --no-pub
```

For profile testing:

```bash
flutter run --profile -d <DEVICE_ID> --dart-define=DEV_MODEL_TEST=true
```

## Critical Speed Matrix

Use the PowerShell benchmark helper from `apps/cairn_mobile`:

```powershell
.\tool\benchmark_android_speed.ps1 -DeviceId <DEVICE_ID> -OutDir .\bench_out -Variant matrix
```

If time is limited, run the highest-signal subset:

```powershell
.\tool\benchmark_android_speed.ps1 -DeviceId <DEVICE_ID> -OutDir .\bench_out -Variant flutter
.\tool\benchmark_android_speed.ps1 -DeviceId <DEVICE_ID> -OutDir .\bench_out -Variant image_preprocess_ab
.\tool\benchmark_android_speed.ps1 -DeviceId <DEVICE_ID> -OutDir .\bench_out -Variant native_mtp_gpu
.\tool\benchmark_android_speed.ps1 -DeviceId <DEVICE_ID> -OutDir .\bench_out -Variant native_mtp_batch
```

The important variants are:

- Baseline Flutter runtime:
  `INFERENCE_RUNTIME=flutter_gemma`, `BENCH_IMAGE_PX=640`
- Official Flutter MTP:
  `INFERENCE_RUNTIME=flutter_gemma`, `BENCH_MTP=true`, `BENCH_IMAGE_PX=640`
- Native MTP GPU:
  `INFERENCE_RUNTIME=native_mtp`, `BENCH_BACKEND=gpu`, `BENCH_IMAGE_PX=512/640/768`
- Native MTP CPU fallback comparison:
  `INFERENCE_RUNTIME=native_mtp`, `BENCH_BACKEND=cpu`, `BENCH_IMAGE_PX=640`
- Native batch experiment:
  `INFERENCE_RUNTIME=native_mtp`, `BENCH_BATCH=true`, `BENCH_IMAGE_PX=640`
- Image preprocessing A/B:
  `BENCH_NATIVE_IMAGE_PREPROCESS=false` vs `true` at `BENCH_IMAGE_PX=640`

## What To Record

For every run, capture:

- Device model and Android version.
- Model key and model file used.
- Dart defines.
- Total 4-photo wall time.
- `image_preprocess` `wall` and `img_bytes`.
- `describe_all total_wallclock_ms`.
- Native MTP `backendUsed`.
- GPU fallback true/false.
- `prefillTokenCount`.
- `prefillTokS`.
- decode `tokensPerSecond`.
- `schema_failure_count`.
- `vision_understanding_score`.
- `priority_band`.

Fail the run if:

- Any schema failure occurs.
- Any image ref is lost.
- The final deterministic priority band is wrong.
- The app crashes or hangs.
- Native JPEG sidecar produces obviously rotated/wrong images.

## Manual Field UX Test

Run this outside the dev scenario screen:

1. Start app.
2. Start a new screening.
3. Capture required photos: front, ground floor, cracks, foundation.
4. Confirm capture returns quickly and does not wait for model analysis.
5. Retake one photo and confirm the new image is used.
6. Kill the app after capture, reopen, and confirm the draft restores.
7. Tap `Describe photos`.
8. Confirm the processing screen advances photo by photo.
9. Finish protocol and synthesis.
10. Confirm final report priority and rationale are present.
11. Save screening.
12. Open Saved Screenings.
13. Open the packet detail.
14. Open photo detail and check tags, confidence, dimensions, and bbox overlay.
15. Export/share PDF and bundle.

Regression checks:

- Original evidence images must remain high quality in saved packet/export.
- Inference sidecars must not replace original evidence bytes.
- App should still work if sidecar files disappear after process kill.
- If native preprocessing fails, Dart fallback should still let inference run.

## Structural Understanding Gate

Run all three dev scenarios:

- `low_no_visible_damage`
- `medium_cracks_spalling`
- `high_column_soft_story`

Acceptance gate:

- `schema_failure_count == 0`
- all 4 image refs preserved
- damage/no-damage classification correct
- severity within 1 bucket
- expected structural tags mostly present
- final deterministic `priority_band` correct
- `total_wallclock_ms` recorded

Do not trust a fast run if structural accuracy regresses. The model only extracts observations; the final priority score/band must stay deterministic in Dart.

## What To Change If Results Are Bad

If native MTP is not faster:

- Compare `tokensPerSecond`, not just wall time.
- If decode tokens/sec improves but wall time does not, the bottleneck is prefill/image/session overhead.
- Keep native MTP only if schema reliability is equal and total wall time improves.
- If `BENCH_MTP=true` produces empty output or no `phase=generate` rows, rerun
  with `INFERENCE_RUNTIME=flutter_gemma`; MTP is still experimental for vision.
- Prefer the `flutter_gemma` official `BENCH_MTP=true` path over the Kotlin
  bridge. The bridge is now diagnostic-only.

If image preprocessing is still slow:

- Prefer the fastest passing `BENCH_IMAGE_PX`: try `512`, `640`, `768`.
- If `512` loses small-crack accuracy, use `640`.
- If `640` loses severity/tag accuracy, fall back to `768`.
- If native JPEG sidecars regress orientation or accuracy, disable with:
  `--dart-define=BENCH_NATIVE_IMAGE_PREPROCESS=false`

If GPU is unstable on Exynos:

- Check native logs for GPU fallback.
- Compare `native_mtp_cpu` against `native_mtp_gpu`.
- Prefer CPU only if it is both faster or more reliable on the tester phone.

If batch mode fails:

- Keep batch disabled.
- Sequential mode is safer because one bad photo does not lose the entire batch.

If model output is buggy:

- Keep the strict JSON contract.
- Shorten `describe_photo` output further before changing scoring.
- Add failing examples to dev scenarios before tuning prompts.

## Current Best Guess For Production Candidate

Session 4 update (2026-05-14): `native_mtp` is blocked on Android 16 (SIGABRT).
`flutter_gemma` + MTP is now the confirmed stable path. MTP is now ON by default
(`BENCH_MTP` defaultValue flipped to `true`).

Start with:

```bash
--dart-define=BENCH_IMAGE_PX=640
--dart-define=BENCH_NATIVE_IMAGE_PREPROCESS=true
```

MTP is automatically active. No `INFERENCE_RUNTIME` or `BENCH_MTP` needed.
Opt out with `--dart-define=BENCH_MTP=false` if MTP causes issues.

Session 4 confirmed results on SM-S711B:

- S1/S2/S3 all pass (zero schema failures, correct priority bands)
- S2 `no_visible_damage` contradiction RESOLVED (system prompt Rule 12)
- S3 warm wall: 133,492ms (4 photos, +33% faster than Session 3 without MTP)
- `speculativeDecoding=true` and `mtp_requested=true` confirmed in logcat
- json_extract `repairOrphanEmptyStrings` working — `parse_contract wall=0ms` on all turns

Remaining benchmarks before final promotion:

- §6b CPU vs GPU backend comparison
- §7 Session config variants (esp. `vision_single_image` maxNumImages=1 and `vision_history_retained`)
- §8 History retention contamination hard gate
- §9 Manual UX flow
- §10 Regression checks

Only promote to release if the full §6–§10 matrix passes.
