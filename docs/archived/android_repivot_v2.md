# Android Repivot V2: Verified Execution Plan

Status date: 2026-04-30

Target platform: Android primary, web fallback.

Default Android package ID: `app.cairn.cairn_mobile`.

This document supersedes `docs/android_repivot.md` for execution planning. It does not prove Android feasibility yet. Android feasibility is gated until Flutter, Dart, ADB, Android project generation, target-device install, and device measurements are completed and recorded.

## Current Verified State

- `apps/cairn_mobile/android/` is absent. Android platform files must be restored before any Android build, manifest, Gradle, or package-ID work can be validated.
- `apps/cairn_mobile/.metadata` tracks only `root` and `web` platforms.
- Local PATH currently does not expose `flutter`, `dart`, or `adb`; all Flutter and Android checks are blocked until the toolchain is installed or PATH is corrected.
- Python checks are currently healthy:
  - `PYTHONPATH=scripts python -m pytest -q scripts\tests`
  - `PYTHONPATH=scripts python -m data.validate_seeds`
- `apps/cairn_mobile/pubspec.lock` resolves `flutter_gemma` to `0.13.6`. First Android pass must keep that lockfile behavior stable unless a separate dependency-upgrade change is planned.
- `path_provider` exists only transitively in the lockfile. A file-backed vault implementation must add it as a direct dependency.
- `assets/images/s2_probe.jpg` is absent. S2 image-burst validation requires an operator-provided probe image or a committed non-sensitive test image.

## Critical Corrections From `android_repivot.md`

### Android platform restoration

Restore Android using a stable package namespace:

```powershell
cd apps\cairn_mobile
flutter create --org app.cairn --platforms=android,web --project-name cairn_mobile .
```

After generation, verify:

- `android/app/build.gradle` or `android/app/build.gradle.kts` has `applicationId` set to `app.cairn.cairn_mobile`.
- Android `namespace` matches `app.cairn.cairn_mobile`.
- `MainActivity` package and file path match the package ID.
- Any `/sdcard/Android/data/.../files` references use the actual package ID.

Flutter's Android deployment docs treat `applicationId` as the unique device and Play Store identifier, and note that changing `applicationId` and `namespace` also requires matching `MainActivity` package structure.

### S1 harness command

The existing S1 harness does not accept `--model`. It requires `--pkg`.

Use this command shape:

```powershell
python scripts\spikes\s1_adb_harness.py `
  --device <serial> `
  --pkg app.cairn.cairn_mobile `
  --out scripts\spikes\out\s1_e2b_<UTC_TIMESTAMP>.json `
  --duration 120 `
  --hz 1
```

The current harness samples process memory and CPU through ADB. It does not, by itself, prove TTFT, decode speed, or prompt quality. Those metrics need either manual markers in the S1 report or a dedicated device runner.

### Android model artifact

Do not use `gemma-4-E2B-it-web.task` as the Android primary artifact.

Use platform-specific model selection:

- Android primary: `litert-community/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it.litertlm`
- Web fallback: `litert-community/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it-web.task`
- E4B remains optional and secondary because its model file is larger and must be validated separately on target hardware.

The `flutter_gemma` docs list `.litertlm` as supported for Android and newer models, while `-web.task` is web-specific. Hugging Face lists `gemma-4-E2B-it.litertlm` at 2.58 GB and `gemma-4-E2B-it-web.task` separately.

### `flutter_gemma` API usage

Keep `flutter_gemma` pinned to the currently locked `0.13.6` for the first Android pass.

Required API corrections:

- Use `createChat(... supportImage: true, supportAudio: true, loraPath: ...)` when audio is active.
- Use `Message.withAudio(...)` for audio-only text prompts.
- Use `Message.withImage(...)` for image-only text prompts.
- For combined image and audio, use the base `Message(...)` constructor with both `imageBytes` and `audioBytes`, unless local API inspection after dependency resolution proves a better constructor exists.
- Do not reference `Message.withImageAndAudio`; that constructor is not documented in the `Message` API.

### Android audio requirements

Audio capture must produce mono `.wav` bytes before forwarding to Gemma.

Execution requirements:

- Request `RECORD_AUDIO` at runtime.
- Configure the `record` package for WAV output where supported.
- Verify mono channel output. If the package or device records stereo, add a conversion step before inference.
- Store captured audio as local session evidence only when the user explicitly records it.

The MediaPipe Android LLM guide states that audio input must be mono channel formatted as `.wav`.

### Android storage and permissions

Do not add `READ_EXTERNAL_STORAGE` for the Android 13+ target path.

Use:

- `INTERNET` for model download.
- `RECORD_AUDIO` for audio capture.
- `ACCESS_FINE_LOCATION` or related location permissions only for the current location screen behavior.
- Camera permission only if direct camera capture is implemented; picker-only image selection should use picker-scoped access when possible.
- App-specific internal or external storage for vault files, model artifacts, LoRA files, and S2 reports.

Android docs state that app-specific external storage on Android 4.4+ does not require storage permissions. Android 13+ requires granular media permissions only when accessing media created by other apps, and recommends the photo picker when only selected images/videos are needed.

### Schema contract blockers

The app must be made schema-safe before Android feature expansion.

Required fixes:

- Generate observation IDs as `obs-N`, matching the v1 schema pattern `^obs-[0-9]+$`.
- Stop emitting custom `model_tags` values such as `user_note` and `user_override`; the v1 schema has a closed enum.
- Ensure volunteer text and humility answers are represented with schema-valid fields and tags.
- Add a Dart-side packet validation path or a golden packet test that compares sealed output against `docs/schema/evidence_packet_v1.schema.json`.

Default policy: keep schema v1 unchanged and modify the app to comply. A schema v2 change requires a separate plan.

### `ask_followup` prompt contract

The locked prompt expects:

```json
{ "followup": { "target_observation_id": "...", "question": "..." } }
```

or:

```json
{ "followup": null }
```

The app must stop expecting `followup` to be a bare string. Update the result type and UI flow to handle a nullable follow-up object with `targetObservationId` and `question`.

### Synthesize thinking mode

Final synthesis must use a thinking-enabled session when the selected model supports it.

Required behavior:

- Load or recreate the session with `isThinking: true` or the `createSession` equivalent before synthesis.
- Keep non-thinking mode for low-latency photo description unless measurements show it is unnecessary.
- Record whether the final triage came from thinking-enabled synthesis in the run artifact.

### S2 Android validation

The current `/spike` page is web/E4B-oriented and does not prove Android LoRA behavior.

Before using S2 as an Android gate, add:

- E2B Android artifact selection.
- Android LoRA file path selection or controlled app-files lookup.
- Base-vs-LoRA prompt pair execution.
- `s2_report.json` persistence in app-specific external files.
- Clear UI copy that distinguishes web fallback from Android validation.

### Device eval runner

`scripts/eval/README.md` references `device_adb`, but the runner is absent and `eval_baseline.py` says it ships later.

Do one of the following before claiming D16 device eval:

- Implement `scripts/cairn/runners/adb.py` and wire `--runner device_adb`.
- Or remove device-eval claims from the timeline and keep S1/S2 as manual device gates.

## Execution Plan

### 1. Environment and toolchain gate

Record the following outputs before Android work starts:

```powershell
flutter --version
dart --version
adb version
java -version
flutter doctor -v
adb devices
adb shell getprop ro.hardware.egl
adb shell df -h /sdcard
```

Acceptance:

- Flutter and Dart are available.
- Android SDK and ADB are available.
- Exactly one intended device is attached or `--device <serial>` is documented.
- Target device has enough free space for model, LoRA, app data, and reports.

### 2. Restore Android platform

Run the Flutter platform restoration command from the repo app directory.

Then add Android-specific setup:

- Manifest permissions listed above.
- OpenCL native library declarations for GPU use, following `flutter_gemma` Android setup docs.
- Package ID verification.
- A debug build install path.

Acceptance:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter install -d <serial>
```

All must pass or produce documented blockers.

### 3. Split model registry by platform

Update model registry behavior so E2B resolves to:

- Web: `gemma-4-E2B-it-web.task`
- Android: `gemma-4-E2B-it.litertlm`

Keep `ModelType.gemmaIt`.

Keep `ModelFileType.task` only if local `flutter_gemma` behavior confirms it is correct for `.litertlm` under the pinned version; otherwise use the exact file-type API available after `flutter pub get`.

Acceptance:

- App logs show the Android URL ends in `.litertlm`.
- Web logs show the web URL ends in `-web.task`.
- E2B install completes on Android without changing the web path.

### 4. Make packet generation schema-safe

Centralize observation ID allocation and remove closed-enum violations.

Acceptance:

- Dart tests cover sequential `obs-N`.
- Dart tests cover user text/humility answer serialization.
- A generated session packet validates against the canonical v1 JSON schema.
- Python schema tests still pass.

### 5. Fix follow-up flow

Update orchestration, result types, and humility UI to consume the locked prompt output shape.

Acceptance:

- Valid follow-up object is displayed.
- `followup: null` skips the question cleanly.
- Malformed follow-up JSON is handled as a non-fatal model error.
- Existing JSON extraction tests still pass.

### 6. Add Android audio flow

Replace the current text-only Screen 4 fallback with Android audio capture while preserving web fallback.

Acceptance:

- Android records mono WAV or converts to mono WAV before inference.
- Gemma chat is created with audio support.
- Audio prompt uses the documented `Message` API.
- Session evidence records the audio asset metadata without schema violations.
- Web still offers text fallback without attempting native audio inference.

### 7. Add file-backed vault and report export

Add direct `path_provider` dependency and implement app-support/app-files persistence.

Acceptance:

- Draft session survives app restart.
- Sealed packet is written to app-specific storage.
- Report screen exports PDF and JSON from the sealed packet.
- Android report artifact can be pulled through ADB from the package-specific files directory.

### 8. Add Android LoRA and S2 validation

Make `/spike` useful for Android E2B and LoRA validation.

Acceptance:

- Base E2B run completes.
- LoRA path run completes or fails with a captured native error.
- S2 report includes model artifact, LoRA path, load time, per-prompt timings, failures, and memory notes.
- Report is saved as `s2_report.json`.

### 9. Final device measurement gate

Only after the above passes, run S1/S2 and final workflow on target hardware.

Acceptance:

- `s1_e2b_<timestamp>.json` exists.
- `s2_report.json` exists.
- Final packet JSON exists and validates.
- Final PDF exists.
- Device metrics include load time, TTFT or equivalent manual marker, decode speed if available, RSS/CPU samples, and thermal/crash notes.

## Acceptance Checklist

Do not mark any item complete without command output, artifact path, or device report.

- [ ] Flutter/Dart/ADB/JDK versions recorded.
- [ ] Target device serial and EGL/OpenCL facts recorded.
- [ ] Android platform restored.
- [ ] Package ID verified as `app.cairn.cairn_mobile`.
- [ ] Android manifest permissions reviewed and legacy storage permission excluded.
- [ ] `flutter_gemma` remains pinned to lockfile version for first pass.
- [ ] Android model URL resolves to `.litertlm`.
- [ ] Web model URL remains `-web.task`.
- [ ] S1 command uses `--pkg`, not `--model`.
- [ ] Observation IDs comply with `obs-N`.
- [ ] Closed schema tags are respected.
- [ ] `ask_followup` nullable object contract is implemented.
- [ ] Audio capture produces mono WAV.
- [ ] Gemma audio request uses documented API.
- [ ] File-backed vault persists draft and sealed sessions.
- [ ] S2 Android E2B base run recorded.
- [ ] S2 LoRA run recorded.
- [ ] Final packet validates against schema v1.
- [ ] Final PDF/JSON export works on Android.
- [ ] README/QUICKSTART are updated later to point to this v2 plan after implementation starts.

## References

- [`flutter_gemma` 0.13.6 package docs](https://pub.dev/packages/flutter_gemma/versions/0.13.6)
- [`flutter_gemma` `Message` API](https://pub.dev/documentation/flutter_gemma/latest/core_message/Message-class.html)
- [`flutter_gemma` `InferenceModel` API](https://pub.dev/documentation/flutter_gemma/latest/flutter_gemma_interface/InferenceModel-class.html)
- [Google LiteRT-LM overview](https://ai.google.dev/edge/litert-lm/overview)
- [MediaPipe Android LLM guide](https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference/android)
- [E2B LiteRT-LM model files](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/tree/main)
- [Android app-specific storage](https://developer.android.com/training/data-storage/app-specific)
- [Android 13 media permission changes](https://developer.android.com/about/versions/13/behavior-changes-13)
- [Flutter Android application ID guidance](https://docs.flutter.dev/deployment/android)

