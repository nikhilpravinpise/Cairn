Tell the next developer this:

```md
# Next Developer Task: Make Cairn Field UX + Dev Model Test Actually Demo-Ready

## Current State
The app now has:
- Saved Screenings list/detail flow
- Photo evidence detail with metadata/tags/confidence/bbox overlay
- ZIP export bundle: PDF + packet.json + photos + turns.jsonl
- Low-storage warning on Android
- Developer Model Test route behind:
  `--dart-define=DEV_MODEL_TEST=true`
- Dev scenario runner that calls the real on-device Gemma 4 `describeAll`
- Unit/widget tests passing
- Android debug build passing

Verification already done:
- `flutter test` passed: 602 tests
- Dart analyze passed
- `flutter build apk --debug --no-pub` passed

## Critical Remaining Work
The dev scenario packs currently all point to:
`assets/images/s2_probe.jpg`

That is only a placeholder. Replace this with real curated 4-photo packs:
- `low_no_visible_damage`
- `medium_cracks_spalling`
- `high_column_soft_story`

Each pack needs 4 images:
- front
- ground_floor
- cracks
- foundation

Update the scenario manifest in:
`apps/cairn_mobile/lib/core/dev_model/dev_scenario.dart`

Prefer small compressed JPEGs under:
`apps/cairn_mobile/assets/images/dev_scenarios/<scenario_id>/`

Then add them to `pubspec.yaml` if needed.

## Build Commands
From:
`apps/cairn_mobile`

Run:

```bash
flutter pub get
flutter analyze lib test tool/api_probe.dart
flutter test
flutter build apk --debug --no-pub
```

## Device Test Command
Use a real Android device with the Gemma 4 `.litertlm` model installed.

Basic dev model test:

```bash
flutter run --profile -d <DEVICE_ID> --dart-define=DEV_MODEL_TEST=true
```

Native MTP path:

```bash
flutter run --profile -d <DEVICE_ID> \
  --dart-define=DEV_MODEL_TEST=true \
  --dart-define=INFERENCE_RUNTIME=native_mtp \
  --dart-define=BENCH_RUNTIME=native_mtp \
  --dart-define=BENCH_MTP=true \
  --dart-define=BENCH_BATCH=true
```

PowerShell helper:

```powershell
.\tool\run_dev_model_scenarios.ps1 -DeviceId <DEVICE_ID>
.\tool\run_dev_model_scenarios.ps1 -DeviceId <DEVICE_ID> -NativeMtp -CaptureLogcat
```

## What To Test Manually
1. Start app.
2. Confirm `Developer Model Test` appears on Start screen.
3. Open it.
4. Run each scenario.
5. Run all scenarios.
6. Export JSON.
7. Confirm result includes:
   - vision_understanding_score
   - understands_damage
   - severity_close
   - priority_band
   - schema_failure_count
   - total_wallclock_ms

## Field UX Test
1. Start screening.
2. Capture 4 photos quickly.
3. Confirm camera does not wait for model inference after each photo.
4. Tap `Describe photos`.
5. Confirm processing screen shows staged progress.
6. Finish protocol/synthesis/report.
7. Save/share PDF.
8. Share export bundle.
9. Go to Saved Screenings.
10. Open saved packet.
11. Open photo detail.
12. Confirm tags, confidence, metadata, and bbox overlay render.

## Acceptance Gate
Do not claim the model works until the real curated image packs pass:

- zero schema failures
- all 4 image refs preserved
- damage/no-damage classification correct
- severity within 1 bucket
- final deterministic priority band correct
- total 4-photo wall time recorded

Target:
- under 3 minutes for 4-photo processing
- stretch: under 90 seconds
```

The most important message: **the code infrastructure is ready, but the model test is only meaningful after replacing the placeholder `s2_probe.jpg` with real curated scenario images.**