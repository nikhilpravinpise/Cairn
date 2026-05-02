# Android Repivot v4 - verified execution plan

Status date: 2026-04-30

Supersedes: `docs/android_repivot.md`, `docs/android_repivot_v2.md`, `docs/android_repivot_v3.md`.

Scope: move Cairn from the current web-first Flutter app to an installable Android app that can create a schema-valid `EvidencePacket` on a real device, while keeping web as a degraded fallback.

This v4 plan is intentionally stricter than v3. A statement is either:

- a repo fact verified in this workspace,
- an external fact linked to current upstream documentation,
- or a gate that must be proven before the next phase starts.

No Android build, install, Flutter analysis, or Dart test result is claimed unless the command has actually run on a machine with Flutter and ADB available.

## 0. Audit scope and local constraints

Audited workspace: `c:\Dev\gemma_project`

Audited file set: every non-generated file returned by:

```powershell
rg --files -g '!**/.git/**' -g '!**/.pytest_cache/**' -g '!**/__pycache__/**' -g '!**/*.png'
```

Before this v4 file was added, that command returned 99 files. With `docs/android_repivot_v4.md` present, it returns 100. Generated caches and binary PNG assets were excluded from semantic review.

Current repo state observed during this audit:

- `apps/cairn_mobile/android/` is absent.
- `.github/workflows/` is absent.
- `apps/cairn_console/` is absent.
- `apps/cairn_mobile/assets/images/s2_probe.jpg` is absent.
- `data/eval/gold.jsonl` is absent.
- Flutter, Dart, and ADB are not on PATH in this shell.
- `java -version` reports OpenJDK 24.0.2.
- Python verification did run:
  - `PYTHONPATH=scripts python -m pytest -q scripts\tests` -> 19 passed.
  - `PYTHONPATH=scripts python -m data.validate_seeds` -> ok.

Git state was already dirty before this v4 file was added. Existing untracked and modified files are not part of this plan unless listed explicitly.

## 1. Critical corrections to v3

These are the v3 statements that must not be carried forward unchanged.

1. `flutter_gemma` is not pinned in `pubspec.yaml`.
   - Actual `apps/cairn_mobile/pubspec.yaml`: `flutter_gemma: ^0.13.0`.
   - Actual `apps/cairn_mobile/pubspec.lock`: resolved `flutter_gemma` version is `0.13.6`.
   - v4 changes the dependency phase to "pin an exact version after verification", not "bump from a pinned 0.13.6".

2. `record`, `pdf`, and `printing` are already direct dependencies.
   - `record: ^5.1.2`, locked `5.2.1`.
   - `pdf: ^3.11.1`, locked `3.12.0`.
   - `printing: ^5.13.0`, locked `5.14.3`.
   - v4 says to verify or intentionally upgrade them, not add them.

3. `path_provider` is transitive only.
   - Locked `path_provider` is present as a transitive dependency.
   - It must be promoted to a direct dependency before file-backed storage work.

4. `docs/prompts/system_prompt_v1.txt:20-27` is not an exact `model_tags` enum.
   - The exact closed enum is in `docs/schema/evidence_packet_v1.schema.json`.
   - The prompt is currently compatible in spirit, but not precise enough for "no assumptions".
   - v4 adds a prompt/schema alignment phase before Android feature work.

5. `ModelFileType.litertlm` must not be assumed.
   - `flutter_gemma` 0.14.0 README says use `ModelFileType.task` for both `.task` and `.litertlm` files.
   - The changelog mentions `ModelFileType.litertlm` in 0.13.0, but the current public README/API surface emphasizes `task` and `binary`.
   - v4 requires a compile/API gate before referring to any distinct `litertlm` enum value. The default implementation should use the documented `ModelFileType.task` for `.litertlm` unless local API inspection proves otherwise.

6. Android camera permission is not currently justified.
   - The app uses `image_picker` with `ImageSource.camera`.
   - Current `image_picker` Android docs say no Android configuration is required and the plugin uses system intents/scoped storage.
   - Do not add `CAMERA` unless the app switches to a direct camera plugin or direct Camera2/CameraX integration.

7. Android storage permissions are not justified.
   - App-specific internal and external directories do not require storage permissions on Android 4.4+.
   - Android 13 media permissions are for accessing other apps' media. The current plan uses `image_picker`/photo picker and app-specific storage.
   - Do not add `READ_EXTERNAL_STORAGE`, `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, or `MANAGE_EXTERNAL_STORAGE`.

8. Android location permissions are required before the location screen can work.
   - `LocationScreen` calls `Geolocator.checkPermission`, `requestPermission`, and `getCurrentPosition`.
   - Add `ACCESS_FINE_LOCATION` and/or `ACCESS_COARSE_LOCATION` when the Android scaffold is restored.
   - Do not add background location permissions unless background tracking is implemented.

9. The synthesize screen is still a stub.
   - `orchestrator.synthesize()` exists, but `/synthesize` is currently `PassPlaceholder`.
   - v4 must not imply a user-facing thinking-mode synthesize flow already exists.

10. S2 docs are stale relative to S2 UI.
    - `apps/cairn_mobile/docs/s2_checklist.md` mentions Toggle LoRA and reboot/resume paths not implemented in the current spike page.
    - `s2_spike_page.dart` references missing `assets/images/s2_probe.jpg`.

11. Several repo docs are stale.
    - `README.md`, `QUICKSTART.md`, `PROJECT_OVERVIEW.md`, `apps/cairn_mobile/README.md`, `docs/schema/README.md`, and `scripts/eval/README.md` mention missing or future pieces as if they exist.
    - v4 includes a docs-correction phase so future operators do not trust stale instructions.

12. `minSdk = 26` is not a verified requirement from current docs.
    - Current checked docs: `record` latest says Android min SDK 23; `image_picker` latest page says support SDK 24+; `flutter_gemma` README does not state an Android minSdk in the visible setup section.
    - v4 requires using the maximum of Flutter defaults, plugin manifest requirements, and actual Gradle errors after `flutter pub get`. Do not cite "Gemma 4 requires 26" unless a source or build error proves it.

## 2. Verified current codebase facts

### 2.1 Platform and app scaffold

- `apps/cairn_mobile/.metadata` lists only `root` and `web` platforms.
- There is no Android project directory.
- `apps/cairn_mobile/web/index.html` currently imports `@mediapipe/tasks-genai@0.10.27`.
- `apps/cairn_mobile/web/index.html` currently loads `cache_api.js` from `DenisovAV/flutter_gemma@0.11.14`, which may be stale once `flutter_gemma` is upgraded.
- `apps/cairn_mobile/test/web_bootstrap_test.dart` asserts the MediaPipe import and cache helper are present, but does not assert the helper version matches the Dart package.

### 2.2 Dependencies

- Direct Flutter deps already include `flutter_gemma`, `geolocator`, `geocoding`, `permission_handler`, `image_picker`, `record`, `printing`, `pdf`, and `qr_flutter`.
- `path_provider` is transitive only.
- `uuid` is direct and currently used for schema-invalid observation IDs in three UI paths.

### 2.3 Model registry

- Dart registry:
  - `apps/cairn_mobile/lib/core/llm/model_registry.dart` has one `taskFilename` per model.
  - E2B and E4B both point to `*-web.task`.
- Python mirror:
  - `scripts/cairn/constants.py` mirrors the same `task_filename`.
- This hardcodes the web artifact for all platforms.

### 2.4 LLM session and orchestrator

- `GemmaSession.ensureReady()` installs from `_spec.hfDownloadUrl` and does not pass `fileType`.
- `GemmaSession._create()` passes `supportImage` but not `supportAudio` to `FlutterGemma.getActiveModel()` or `createChat()`.
- `GemmaSession.generate()` supports text plus optional image only. It does not support audio messages.
- `AskFollowupResult.followup` is a required `String`.
- `orchestrator.askFollowup()` rejects the prompt's documented nullable object shape.
- `orchestrator.synthesize()` uses the existing session through `_session.generate(...)`.

### 2.5 Schema and prompt

- `docs/schema/evidence_packet_v1.schema.json` is the canonical schema.
- `observation_id` pattern is `^obs-[0-9]+$`.
- `assets.images[].ref` pattern is `^img-[0-9]+$`.
- `assets.audio[].ref` pattern is `^aud-[0-9]+$`.
- `assets.audio[].sample_rate_hz` must be 16000.
- `assets.audio[].channels` must be 1.
- `assets.audio[].duration_s` must be <= 30.
- `model_tags` is a closed enum in the schema. Current app-only tags `user_note` and `user_override` are invalid.
- `bbox_annotations[].box_2d` is `[y1,x1,y2,x2]` with integer values 0..1000. The schema does not enforce y1 < y2 or x1 < x2, but the prompt does.
- `ask_followup` prompt contract is `{ "followup": { "target_observation_id": "...", "question": "..." } }` or `{ "followup": null }`.
- The prompt and app asset copy are currently identical.

### 2.6 Current contract violations in app code

- `photos_screen.dart` creates `obs-${uuid.v7()}`.
- `describe_screen.dart` creates `obs-${uuid.v7()}` and `modelTags: ['user_note']`.
- `humility_screen.dart` creates `obs-${uuid.v7()}` and `modelTags: ['user_override']`.
- `describe_screen.dart` filters volunteer notes by `modelTags.contains('user_note')`.
- `SessionDraft` has no observation sequence counter.
- `SessionDraft.cloneShallow()` must preserve any new sequence counter when added.
- `SessionController.addAudio()` defaults to 16000 Hz mono but does not reject invalid duration, sample rate, or channel count.
- The comment in `evidence_packet.dart` references `evidence_packet_validator.dart`, but that file does not exist.

### 2.7 Feature completeness

- Start, location, photos, describe, protocol, and humility screens exist.
- Synthesize and report screens are placeholders.
- `EvidenceVault` is in-memory only.
- There is no file-backed draft restore.
- There is no PDF report implementation despite `pdf`, `printing`, and `qr_flutter` being present.
- There is no `device_adb` runner, and `eval_baseline.py` explicitly says non-Ollama runners ship later.
- `data/eval/gold.jsonl` is absent.

### 2.8 Seeds and Python tooling

- `data/seeds/dialogues.seed.jsonl` currently validates with `scripts/data/validate_seeds.py`.
- Seeds include `describe_photo`, `ask_followup`, `protocol_answer`, and `synthesize`.
- Seed `model_tags` are inside the schema enum.
- Ask-followup seeds already use the object/null contract, so training data is ahead of app code.
- `scripts/data/validate_seeds.py` does not enforce the schema enum or the ask-followup object/null shape strongly enough. It should.
- `scripts/eval/README.md` references `device_adb`, but no runner exists.
- `scripts/data/README.md` references `scripts/data/coverage_report.py`, which is absent.

## 3. External facts used by this plan

Use these references again at implementation time because package docs can drift.

- `flutter_gemma` latest checked during this audit: 0.14.0.
  - Package page: https://pub.dev/packages/flutter_gemma
  - Changelog: https://pub.dev/packages/flutter_gemma/changelog
  - Latest `Message` API: https://pub.dev/documentation/flutter_gemma/latest/core_message/Message-class.html
  - Latest `getActiveModel`: https://pub.dev/documentation/flutter_gemma/latest/core_api_flutter_gemma/FlutterGemma/getActiveModel.html
  - Latest `createChat`: https://pub.dev/documentation/flutter_gemma/latest/flutter_gemma_interface/InferenceModel/createChat.html
  - Latest `installModel`: https://pub.dev/documentation/flutter_gemma/latest/core_api_flutter_gemma/FlutterGemma/installModel.html
- `flutter_gemma` package docs say:
  - `.litertlm` is supported on Android for newer models.
  - `-web.task` is web-specific.
  - Use `ModelFileType.task` for `.task` and `.litertlm`.
  - `getActiveModel` has `supportAudio`.
  - `createChat` has `supportAudio` and `isThinking`.
  - Android GPU support needs optional OpenCL `uses-native-library` entries.
- Hugging Face E2B repo checked during audit:
  - https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/tree/main
  - It lists `gemma-4-E2B-it-web.task`, `gemma-4-E2B-it.litertlm`, and Qualcomm-specific `.litertlm` variants.
- Flutter Android deployment docs:
  - https://docs.flutter.dev/deployment/android
  - `applicationId` is the unique app identifier and changing it with `namespace` requires matching `MainActivity` package structure.
- Android app-specific storage docs:
  - https://developer.android.com/training/data-storage/app-specific
  - App-specific internal storage needs no storage permission.
  - App-specific external storage needs no storage permission on Android 4.4+.
- Android 13 media permission docs:
  - https://developer.android.com/about/versions/13/behavior-changes-13
  - If the app only needs images/photos/videos, Android recommends using photo picker instead of declaring `READ_MEDIA_IMAGES` or `READ_MEDIA_VIDEO`.
- `geolocator` docs:
  - https://pub.dev/packages/geolocator
  - Android requires `ACCESS_COARSE_LOCATION` or `ACCESS_FINE_LOCATION`.
- `image_picker` docs:
  - https://pub.dev/packages/image_picker
  - Android says no configuration is required, uses scoped storage, uses Android Photo Picker on Android 13+, and camera/gallery results must be moved from cache if needed permanently.
- `record` docs:
  - https://pub.dev/packages/record
  - Latest version supports WAV on Android and permission checks.
  - `RecordConfig` exposes `encoder`, `sampleRate`, and `numChannels`: https://pub.dev/documentation/record/latest/record/RecordConfig-class.html

## 4. Non-negotiable implementation policy

- Do not start Android work until toolchain facts are captured in a runlog.
- Do not claim Android support from web or unit tests.
- Do not add schema values to hide app bugs unless the schema owner intentionally versions the schema.
- Do not add Android permissions that are not required by a current feature and upstream docs.
- Do not use web model artifacts on Android.
- Do not use a package API symbol only because a changelog mentioned it. Compile it or do not write it.
- Do not keep stale docs that claim absent directories, CI, runner files, or console apps exist.
- Every phase below has a gate. If the gate fails, fix inside the phase or stop.

## 5. Execution phases

### Phase 0 - toolchain and runlog gate

Scope: prove the machine and target Android device can build and install a Flutter APK.

Create `docs/android_repivot_v4_runlog.md` and paste raw command output from:

```powershell
flutter --version
dart --version
adb version
java -version
flutter doctor -v
flutter doctor --android-licenses
adb devices
adb shell getprop ro.product.model
adb shell getprop ro.hardware.chipname
adb shell getprop ro.soc.model
adb shell getprop ro.build.version.sdk
adb shell dumpsys meminfo | Select-String -Pattern "Total RAM"
adb shell df -h /sdcard
```

Gate:

- Flutter, Dart, and ADB commands exist.
- `flutter doctor -v` has no unresolved Android toolchain blocker.
- At least one device is listed by `adb devices`.
- Device has enough free storage for a 2.58 GB model plus captured media and reports. Treat 6 GB free as the minimum practical gate for E2B experiments.

Do not continue to Android scaffold work if this fails.

### Phase 1 - dependency and API pin gate

Scope: make package versions exact and prove the exact API before code changes rely on it.

Edits:

1. Pin `flutter_gemma` exactly after checking latest package docs at implementation time.
   - Current recommendation from this audit: `flutter_gemma: 0.14.0`.
   - Do not use `^0.14.0` for this phase. The plan is about reproducibility.
2. Decide whether to keep `record` 5.2.1 or upgrade to latest.
   - If audio implementation uses current locked APIs, keep it.
   - If upgrading, pin exactly and read the changelog first.
3. Add direct `path_provider` dependency only when file-backed vault work begins, or in this phase if the team wants all dependency churn isolated.
4. Run a tiny API probe or compile-time test proving:
   - `FlutterGemma.installModel(modelType: ..., fileType: ModelFileType.task)` compiles.
   - `FlutterGemma.getActiveModel(supportImage: true, supportAudio: true, maxNumImages: 5)` compiles.
   - `InferenceModel.createChat(supportAudio: true, isThinking: true, systemInstruction: ...)` compiles.
   - `Message.withAudio(...)` compiles.
   - `ModelFileType.values` is recorded in the runlog.

Gate:

```powershell
flutter pub get
flutter analyze
flutter test
```

Expected:

- All commands pass on the restored Flutter toolchain.
- Runlog records exact resolved versions from `pubspec.lock`.
- If `ModelFileType.litertlm` is absent or docs still say to use `task`, all `.litertlm` installs use `ModelFileType.task`.

### Phase 2 - prompt and schema alignment

Scope: remove ambiguity before making Android behavior depend on the contract.

Edits:

1. Update `docs/prompts/system_prompt_v1.txt` so `model_tags` lists the exact snake_case enum from `docs/schema/evidence_packet_v1.schema.json`.
2. Keep schema version at v1. This is a prompt clarification, not a schema change.
3. Sync the prompt asset with `apps/cairn_mobile/assets/prompts/system_prompt_v1.txt`.
4. Add a schema asset path for offline validation:
   - `apps/cairn_mobile/assets/schema/evidence_packet_v1.schema.json`
   - Add it to `pubspec.yaml`.
5. Add or update sync tooling so prompt and schema assets are copied from `docs/`.
   - Current `tool/sync_assets.sh` only handles the prompt.
   - Add a PowerShell-friendly command or document that Git Bash is required on Windows.
6. Strengthen `scripts/data/validate_seeds.py`:
   - Check every seed `model_tags` value against the schema enum.
   - Check `ask_followup` output is object/null, not a string.
   - Check `synthesize` does not set `priority_score` or `priority_band`.

Gate:

```powershell
python -m data.validate_seeds
PYTHONPATH=scripts python -m pytest -q scripts\tests
```

Expected:

- Prompt and app asset are byte-identical.
- Seed validation passes.
- Python tests pass.

### Phase 3 - app schema-safety pass

Scope: make the current app capable of sealing schema-valid packets before Android-specific functionality is added.

Edits:

1. Add observation ID allocation to session state.
   - Add a sequence counter to `SessionDraft`.
   - Preserve it in `cloneShallow()`.
   - Add a controller method such as `allocateObservationId()` returning `obs-N`.
   - Replace all three `obs-${uuid.v7()}` call sites.
2. Remove invalid human-only tags.
   - Change volunteer notes from `modelTags: ['user_note']` to an empty tag list or a valid structural tag only when justified by content.
   - Change humility answers from `modelTags: ['user_override']` to an empty tag list or valid structural tag only when justified by content.
   - Replace downstream filtering by tag with filtering by `promptId`.
3. Fix ask-followup shape.
   - Result type should represent `targetObservationId` and `question` as nullable fields.
   - `{"followup": null}` must skip the question.
   - `{"followup": {"target_observation_id": "...", "question": "..."}}` must render the question.
   - A bare string should be treated as model drift only if an explicit compatibility mode is enabled and logged.
4. Add `apps/cairn_mobile/lib/core/models/evidence_packet_validator.dart`.
   - It should validate sealed packet maps against the key invariants the app can enforce without a full JSON Schema runtime:
     - observation ID/ref regexes,
     - closed `model_tags`,
     - audio constants,
     - bbox length/range/order,
     - protocol key/value domains,
     - triage priority band and non-empty rationale.
5. Add Dart tests for:
   - observation ID sequence allocation and clone preservation,
   - invalid tag rejection,
   - invalid audio metadata rejection,
   - bbox range/order rejection,
   - ask-followup null/object/malformed cases.
6. Fix existing tests that build invalid packet examples.
   - Some current `evidence_packet_test.dart` values are intentionally minimal but schema-invalid. Keep serializer tests, but add a separate schema-valid sample for validator/golden tests.

Gate:

```powershell
flutter test
PYTHONPATH=scripts python -m pytest -q scripts\tests
```

Expected:

- No `obs-${` call sites under `apps/cairn_mobile/lib`.
- No `user_note` or `user_override` literal used as a `model_tags` value.
- Validator tests pass.

### Phase 4 - Android scaffold restoration

Scope: restore Android platform files without mixing in feature changes.

Command from `apps/cairn_mobile`:

```powershell
flutter create --org app.cairn --platforms=android,web --project-name cairn_mobile .
```

Immediate inspections:

- `android/app/build.gradle.kts` or `android/app/build.gradle` exists.
- `applicationId` is `app.cairn.cairn_mobile`.
- `namespace` is `app.cairn.cairn_mobile`.
- `MainActivity.kt` package path matches `app/cairn/cairn_mobile`.
- `compileSdk`, `minSdk`, and `targetSdk` are Flutter/plugin-compatible.
- Do not hardcode `minSdk = 26` unless Gradle/plugin docs or build errors require it.

Manifest policy:

- Add `INTERNET` for model downloads.
- Add `ACCESS_FINE_LOCATION` and optionally `ACCESS_COARSE_LOCATION` because `geolocator` is already in the app.
- Add OpenCL `uses-native-library` entries if GPU backend is the target.
- Do not add `CAMERA` for the current `image_picker` implementation.
- Do not add storage/media permissions for app-specific storage or photo picker.
- Do not add `RECORD_AUDIO` until the audio phase.

Gate:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter install -d <serial>
adb shell am start -n app.cairn.cairn_mobile/.MainActivity
```

Expected:

- App launches to the existing Start screen.
- No Android scaffold command has clobbered source files outside expected platform files.

### Phase 5 - per-platform model artifacts

Scope: use the right model artifact for each platform.

Edits:

1. Replace single `taskFilename` with per-platform artifact metadata.
2. Web artifact:
   - E2B: `gemma-4-E2B-it-web.task`
   - E4B: matching E4B web task only after confirming the E4B HF tree.
3. Android artifact:
   - E2B default: `gemma-4-E2B-it.litertlm`
   - Qualcomm-specific artifacts only after target device SoC is verified and a manual A/B run justifies them.
4. Use `ModelFileType.task` for `.litertlm` unless Phase 1 proves a distinct enum is required and supported.
5. Pass `fileType` into `FlutterGemma.installModel(...)`.
6. Add `TargetPlatform` or platform resolver logic in one place only.
7. Mirror the richer struct in `scripts/cairn/constants.py`.
8. Extend `scripts/tests/test_constants_parity.py` to compare web and Android artifact fields.

Gate:

```powershell
flutter test
PYTHONPATH=scripts python -m pytest -q scripts\tests\test_constants_parity.py
flutter run -d <serial> --release
```

Expected:

- Android logs show the resolved URL ends in `.litertlm`.
- Web logs/build still resolve `-web.task`.
- No 404 from Hugging Face.

### Phase 6 - LLM session multimodal hardening

Scope: wire image, audio, and thinking flags explicitly and reject malformed model output.

Edits:

1. `GemmaSession` should take per-turn capability flags or have separate session factories:
   - describe photo: image true, audio false, thinking false,
   - describe audio: image false, audio true, thinking false,
   - synthesize: image false, audio false, thinking true,
   - protocol/followup: image false, audio false, thinking false.
2. Pass `supportAudio` to both `getActiveModel()` and `createChat()` when audio is needed.
3. Add a `Message.withAudio(...)` path, but do not combine image and audio in one message unless upstream docs and tests prove the package supports the exact behavior needed.
4. Add model-output contract checks:
   - `describe_photo` rejects tags outside schema enum,
   - `describe_photo` rejects malformed bbox,
   - `synthesize` rejects model-supplied `priority_score` or `priority_band`,
   - `protocol_answer` keeps exactly-one-key behavior.
5. Add TTFT and wall-clock instrumentation for each LLM call.
6. Do not claim UI synthesize is done until `/synthesize` is no longer a placeholder.

Gate:

```powershell
flutter test
flutter run -d <serial>
```

Expected:

- One real photo description returns parseable JSON.
- One followup object/null response is handled correctly.
- One synthesize run uses a fresh `isThinking: true` chat when supported by the resolved package and artifact.

### Phase 7 - Android photo, location, and lost-data behavior

Scope: make existing non-audio Android inputs robust.

Edits:

1. Add Android lost-data recovery for `image_picker.retrieveLostData()` at startup or in the photos flow.
2. Persist picked/captured image bytes out of image_picker cache immediately.
3. Keep gallery/photo picker storage-permission-free.
4. Ensure location screen handles:
   - denied,
   - denied forever,
   - services disabled,
   - timeout.
5. Add UI tests or controller tests for the error states where feasible.

Gate:

```powershell
flutter test
flutter run -d <serial>
```

Manual expected behavior:

- Camera/system image capture returns to app.
- Gallery selection returns to app.
- Location permission denial has a clean user path.
- No storage permission prompt appears.

### Phase 8 - Android audio capture

Scope: record schema-valid audio evidence and optionally describe it with Gemma.

Preconditions:

- Phase 1 proves the selected `record` API.
- Phase 6 proves `supportAudio` and `Message.withAudio`.

Edits:

1. If staying on `record` 5.2.1, verify exact `RecordConfig` API from local package docs or compile.
2. If upgrading to `record` 6.2.0, pin exactly and update code to latest API.
3. Add `RECORD_AUDIO` to Android manifest.
4. Add an Android-only recorder UI:
   - idle,
   - recording,
   - encoded,
   - error.
5. Encode WAV or PCM in a format confirmed by `record` and accepted by `flutter_gemma`.
6. Enforce in `SessionController.addAudio()`:
   - `durationS >= 0`,
   - `durationS <= 30`,
   - `sampleRateHz == 16000`,
   - `channels == 1`.
7. Add audio refs as `aud-N`.
8. If Gemma audio output quality is poor, still persist the audio asset but treat audio description as optional.

Gate:

```powershell
flutter test
flutter run -d <serial>
```

Manual expected behavior:

- 5 second recording saves as `aud-1`.
- Audio metadata validates against schema.
- If `ffprobe` or `mediainfo` is available, it confirms mono 16000 Hz.
- A real audio LLM turn either returns valid observation JSON or is logged as unsupported without blocking packet finalization.

### Phase 9 - file-backed vault, draft restore, export, and report

Scope: replace in-memory evidence storage with device-persistent storage and produce exportable artifacts.

Edits:

1. Promote `path_provider` to direct dependency if not already done.
2. Implement file-backed `EvidenceVault`.
3. Use app-specific internal storage for drafts.
4. Use app-specific external storage or app documents for exportable packet folders.
5. Persist:
   - `packet.json`,
   - original images,
   - original audio,
   - `turns.jsonl`,
   - `report.pdf`.
6. Use atomic writes through temp file then rename.
7. Implement `/synthesize` UI.
8. Implement `/report` UI and PDF generation using existing `pdf`, `printing`, and `qr_flutter` deps.
9. Validate final packet before saving report.

Gate:

```powershell
flutter test
flutter run -d <serial>
```

Manual expected behavior:

- Kill and relaunch mid-flow restores draft.
- Finalize writes a packet folder.
- `adb pull` can retrieve the folder.
- Pulled `packet.json` validates with Python JSON Schema tests.
- `report.pdf` opens on desktop.

### Phase 10 - S2 spike repair

Scope: make `/spike` match its checklist or update the checklist.

Edits:

1. Decide whether to commit a non-sensitive test image or keep `s2_probe.jpg` operator-provided.
2. If operator-provided, `runBurst()` must fail with a clear UI message instead of throwing.
3. Either implement the documented Toggle LoRA/Reboot behavior or remove it from `apps/cairn_mobile/docs/s2_checklist.md`.
4. Update S2 output path docs for Android and web.
5. Recheck web bootstrap after any `flutter_gemma` upgrade:
   - MediaPipe tasks-genai version,
   - cache helper URL/version,
   - OPFS helper compatibility.

Gate:

```powershell
flutter test
flutter run -d chrome
flutter run -d <serial>
```

Expected:

- Web S2 still runs or gives a clear unsupported message.
- Android S2 runs with the Android artifact and produces a report.

### Phase 11 - device eval runner

Scope: make the documented `device_adb` runner real or remove the documentation that claims it.

Edits:

1. Add `scripts/cairn/runners/adb.py`.
2. Add app-side eval entry point. Options:
   - Android broadcast receiver plus method channel,
   - or a debug-only deep link route that reads a request path and writes a response path.
3. Update `scripts/eval/eval_baseline.py` to instantiate `device_adb:<pkg>@<serial>`.
4. Create `data/eval/gold.jsonl` or update the command examples to use an existing fixture.
5. Update `scripts/eval/README.md`.

Gate:

```powershell
PYTHONPATH=scripts python -m eval.eval_baseline `
  --gold data\eval\gold.jsonl `
  --runner device_adb:app.cairn.cairn_mobile@<serial> `
  --strategy strict_schema `
  --out scripts\eval\reports\device_e2b_strict.json `
  --limit 5
```

Expected:

- 5 rows complete.
- Report includes parse failure rate, median TTFT, and per-row raw response path.

### Phase 12 - CI and docs cleanup

Scope: make future claims testable.

Edits:

1. Add `.github/workflows/ci.yml`.
2. Python job:
   - install script package,
   - run `pytest -q scripts/tests`,
   - run `python -m data.validate_seeds`.
3. Flutter job:
   - use pinned Flutter version from Phase 0 runlog,
   - `flutter pub get`,
   - `flutter analyze`,
   - `flutter test`,
   - `flutter build apk --debug --target-platform android-arm64`.
4. Schema job:
   - validate golden packets against `docs/schema/evidence_packet_v1.schema.json`.
5. Docs cleanup:
   - `README.md`: remove or mark absent `apps/cairn_console/` and CI.
   - `QUICKSTART.md`: remove false CI claim, clarify S2 probe image.
   - `PROJECT_OVERVIEW.md`: update model artifact table and screen status.
   - `apps/cairn_mobile/README.md`: update from spike-only language.
   - `docs/schema/README.md`: mark console validator as future unless implemented.
   - `scripts/eval/README.md`: do not mention `runners/adb.py` until it exists.
   - `scripts/data/README.md`: remove or implement `coverage_report.py`.

Gate:

- CI is green on a branch.
- Docs no longer claim absent files/directories exist.

### Phase 13 - final device evidence

Scope: produce the evidence that Android repivot is complete.

Artifacts to commit or archive:

- Phase 0 runlog.
- Device model, SoC, Android SDK, storage, RAM.
- S1 harness JSON.
- S2 report JSON.
- One pulled packet folder containing:
  - `packet.json`,
  - images,
  - optional audio,
  - `turns.jsonl`,
  - `report.pdf`.
- Python schema validation output for pulled packet.
- Notes on backend used: GPU, CPU fallback, or NPU.
- Notes on thermal behavior and crashes.

Completion gate:

- A fresh clone plus documented Flutter/Android toolchain can build the APK.
- A real Android device can complete one synthetic survey.
- The pulled packet validates against `evidence_packet_v1.schema.json`.
- The report PDF opens.
- The web fallback still launches or is explicitly documented as temporarily unsupported.

## 6. Test matrix

| Layer | Existing or new | Test |
|---|---|---|
| Python | existing | `scripts/tests/test_schema.py` validates schema fixtures. |
| Python | existing | `scripts/tests/test_seeds.py` plus strengthened `validate_seeds.py`. |
| Python | extend | `scripts/tests/test_constants_parity.py` checks per-platform artifacts. |
| Dart | existing | `test/json_extract_test.dart` covers JSON extraction. |
| Dart | existing | `test/session_controller_test.dart`, extended for `obs-N` allocation and audio validation. |
| Dart | existing | `test/evidence_packet_test.dart`, corrected so schema-valid samples are separate from serializer minimal cases. |
| Dart | new | `test/evidence_packet_validator_test.dart`. |
| Dart | new | `test/orchestrator_followup_test.dart`. |
| Dart | new | `test/model_registry_platform_test.dart`. |
| Dart widget | new | photos lost-data/error states where feasible. |
| Device | new | Android launch, model install, photo describe, optional audio describe, synthesize, finalize, pull, validate. |
| Web | existing/extend | `test/web_bootstrap_test.dart` should assert bootstrap helper version policy after `flutter_gemma` upgrade. |

## 7. Open questions that must be answered by gates

These are not assumptions in v4; they are blockers until the gate captures the answer.

1. Which exact Flutter SDK version will be used?
2. Which exact Android device and SoC will be used?
3. Is the device Qualcomm SM8750 or QCS8275, justifying a Qualcomm artifact, or should it use generic E2B?
4. How much free storage is available after model download?
5. Does `flutter_gemma` 0.14.0 compile cleanly with this app and current Flutter SDK?
6. What are the actual `ModelFileType.values` after dependency pinning?
7. Does the current target device run Gemma 4 E2B audio acceptably, or is audio asset capture only?
8. Is release signing in scope, or only debug/internal APK?
9. Is `apps/cairn_console/` in scope for this milestone? v4 default: no.
10. Is a committed non-sensitive S2 image acceptable, or must the operator provide one locally?

## 8. Immediate next actions

The safest next work sequence is:

1. Run Phase 0 on a machine with Flutter, Dart, ADB, and the target Android device.
2. Pin and verify `flutter_gemma` using Phase 1.
3. Do Phase 2 and Phase 3 before restoring Android feature work, because they fix current schema/prompt violations independent of Android.
4. Restore Android scaffold in Phase 4.
5. Split model artifacts in Phase 5.

If Flutter/ADB are still unavailable, the only safe code work before toolchain restoration is Phase 2 plus the Python portions of Phase 3. Do not claim Flutter/Dart gates without running them.
