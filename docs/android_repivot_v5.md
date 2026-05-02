# Android Repivot v5 — Final execution plan

**Status date:** 2026-04-30
**Supersedes:** `docs/android_repivot.md`, `docs/android_repivot_v2.md`, `docs/android_repivot_v3.md`, `docs/android_repivot_v4.md`
**Target device:** Samsung Galaxy S23 FE (Exynos 2200, Mali-G710, 8 GB RAM, Android 13+)

## 0. Audit scope and local constraints

This v5 plan was authored at the date above on a Windows workstation without Flutter, Dart, or ADB on PATH. The target Android device is available for Phase 0 execution. No device facts (SoC, storage free, Android SDK) are embedded here; Phase 0 records them.

### 0.1 Repository facts (re-verified at v5 authoring)

| Fact | State |
|------|-------|
| `apps/cairn_mobile/android/` | Absent — Phase 4 creates it |
| `.github/workflows/` | Absent — Phase 12 creates it |
| `apps/cairn_console/` | Absent — out of scope |
| `data/eval/gold.jsonl` | Absent — Phase 11 creates it |
| `apps/cairn_mobile/assets/images/s2_probe.jpg` | Absent — Phase 10 keeps it operator-provided |
| Python verification | 19 passed, seeds validated |
| Git state | Dirty before this file was added |

### 0.2 Toolchain status

- Flutter, Dart, ADB not on PATH in this authoring shell.
- `java -version` reports OpenJDK 24.0.2.
- Phase 0 runlog (§7) must capture actual Flutter/Dart/ADB versions on the execution machine.

---

## 1. Decisions locked through grilling

### 1.1 Plan philosophy

- **Single source of truth:** v5 is the final Android repivot plan. After it lands, v1–v4 are deleted (see §8).
- **Lock decisions with rationale:** Where facts are unknown, v5 picks a **default** and defines the gate that would override it.
- **Device-class defaults:** Target is S23 FE; any modern Android 13+ with ≥8 GB RAM and ≥6 GB free storage satisfies the plan if the target is unavailable.

### 1.2 Device identity

| Attribute | Locked value |
|-----------|--------------|
| Make/Model | Samsung Galaxy S23 FE |
| SoC | Exynos 2200 |
| GPU | Mali-G710 (supports OpenCL) |
| RAM | 8 GB |
| Android baseline | 13+ |
| Storage gate | ≥6 GB free for E2B model + media + reports |

**Implications:**
- Qualcomm-specific `.litertlm` variants are **out of scope** — they will not run on Exynos.
- E4B (4B params) is **out of scope** — 8 GB RAM is too tight for a ~5 GB model + OS overhead.
- GPU backend is Mali OpenCL; Phase 4 manifest keeps optional OpenCL `uses-native-library` entries.

### 1.3 Web fallback policy

**Frozen in maintenance mode.** Web code stays, but:
- No phase blocks on web verification.
- CI builds web as non-required (`continue-on-error`).
- `flutter_gemma` upgrade is judged by Android only.
- `test/web_bootstrap_test.dart` gets a TODO to re-verify after Android stabilizes.

### 1.4 Audio scope

**Capture + Gemma describe with two gates:**
- **Capability (mandatory):** `Message.withAudio` compiles, runs, returns parseable schema-valid JSON.
- **Quality (informational):** Reviewer judges description plausibility; logged in runlog, not blocking.

Rationale: Gemma 4 audio quality on Exynos GPU is unverified in public docs; failing the entire repivot on upstream model quality is unacceptable.

### 1.5 Dependency pinning

Exact versions locked in `pubspec.yaml`:

| Package | Version | Notes |
|---------|---------|-------|
| `flutter_gemma` | `0.14.0` (exact) | Chosen for `supportAudio`, `isThinking`, documented `ModelFileType.task` |
| `record` | `5.2.1` (exact) | Keep current locked; avoid 6.x churn mid-audio work |
| `path_provider` | `^2.1.5` (direct, exact) | Promote from transitive for Phase 9 file-backed vault |

Phase 1 also runs `flutter pub outdated` once and records any newer versions in the runlog as deferred upgrades.

### 1.6 Observation identity allocation

Three independent monotonic counters in `SessionDraft`:
- `nextObsSeq` → `obs-N`
- `nextImgSeq` → `img-N`
- `nextAudSeq` → `aud-N`

All start at 1, never decrement, all preserved by `cloneShallow()`. Replaces v4's length-based allocators (which would collide on retake/remove).

### 1.7 Volunteer-authored observation convention

For both `volunteer_note_v1` (describe screen) and `humility_override_v1` (humility screen):

| Field | Convention |
|-------|------------|
| `prompt_id` | `volunteer_note_v1` or `humility_override_v1` |
| `model_description` | **Omitted** (field is optional in schema) |
| `user_text` | The volunteer's typed text |
| `model_tags` | `[]` (empty, schema enum contains only model-damage tags) |
| `model_confidence` | `1.0` — documented as "human ground truth sentinel" |

Filtering everywhere uses `prompt_id`, never `model_tags`.

### 1.8 S2 spike scope

Minimal Android-only repair:
- Operator-provided `s2_probe.jpg`; runBurst shows clean error UI when asset missing.
- `s2_checklist.md` rewritten to remove unimplemented "Toggle LoRA / Reboot" docs.
- Web S2 untouched (frozen per §1.3).
- S23 FE runs S2 once in Phase 13 as baseline; results archived in evidence bundle.

### 1.9 Device eval runner (Phase 11)

**Implement with seeds-as-gold:**
- Build `scripts/cairn/runners/adb.py` via debug-only deep-link entry point.
- Build `scripts/data/build_gold_from_seeds.py` to derive `data/eval/gold.jsonl` from existing seeds.
- Eval reports: parse failure rate, schema validity rate, median TTFT.
- No human-in-the-loop quality eval; this is wiring verification, not model benchmarking.

### 1.10 Release signing

**Phase 14 added: Play Store internal track publish.** Sub-gates:

1. Generate upload keystore; document handling in `docs/release_signing.md`; add to `.gitignore`.
2. Configure `android/key.properties` (gitignored) + `signingConfigs` in Gradle.
3. Build signed `.aab` (Android App Bundle).
4. Privacy policy authored from `LEGAL.md`, hosted at stable URL (ops task external to this repo).
5. Play Console: app entry, content rating, target audience 18+, data safety (on-device only, no upload, no telemetry), listing assets (icon, screenshots from Phase 13 evidence run, descriptions echoing `LEGAL.md`).
6. Internal testing track with at least one tester.
7. CI builds both `--debug` APK and `--release` `.aab`; both artifacts retained.

---

## 2. Glossary

Domain terms resolved during v5 grilling. Canonical definitions live in `CONTEXT.md` (created by this plan).

| Term | Definition |
|------|------------|
| **EvidencePacket** | The top-level artifact produced by Cairn. Schema-valid JSON per `evidence_packet_v1.schema.json` plus binary assets (images, audio, PDF). |
| **Observation** | One structured finding within an EvidencePacket. May be **model-authored** (from `describe_photo`, `protocol_answer`, `synthesize`) or **volunteer-authored** (from `volunteer_note_v1`, `humility_override_v1`). |
| **Model-authored** | An Observation where `model_description` is present and `model_tags` are from the schema enum. `model_confidence` is model-supplied (0–1). |
| **Volunteer-authored** | An Observation where `model_description` is omitted, `user_text` holds the text, `model_tags` is empty, and `model_confidence: 1.0` is a sentinel for "human ground truth." Distinct `prompt_id` values make filtering explicit. |
| **Capability gate** | A mandatory phase gate proving a code path works (compiles, runs, returns schema-valid output). Example: audio capability in Phase 8. |
| **Quality gate** | An informational gate where a reviewer judges output quality; logged but not blocking. Example: audio description quality in Phase 8. |
| **ID spaces** | Three independent monotonic ID sequences: `obs-N` (observations), `img-N` (images), `aud-N` (audio). Never reused within a session. |

---

## 3. Execution phases

### Phase 0 — Toolchain and runlog

**Scope:** prove the machine and target device can build and install a Flutter APK.

Create `docs/android_repivot_v5_runlog.md` and paste raw command output from:

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

**Gate:**
- Commands exist and return version info.
- `flutter doctor -v` has no unresolved Android toolchain blocker.
- At least one device listed by `adb devices`.
- Device storage free ≥6 GB.

If any gate fails, stop. Do not proceed to Phase 1 until resolved.

---

### Phase 1 — Dependency and API pin

**Scope:** exact versions locked; compile-time probe proves API surface.

Edits:
1. In `apps/cairn_mobile/pubspec.yaml`, set exact pins per §1.5.
2. Add `path_provider: ^2.1.5` as direct dependency.
3. Add `tool/api_probe.dart` (compile-only test proving `flutter_gemma` symbols):

```dart
// Compile-only probe; does not run.
void probe() {
  // ignore: unused_local_variable
  final ft = FlutterGemma.instance;
  // ignore: unused_local_variable
  final m = FlutterGemma.instance.getActiveModel(
    supportImage: true,
    supportAudio: true,
    maxNumImages: 5,
  );
}
```

Gate:
```powershell
flutter pub get
flutter analyze
flutter test
cd tool && dart analyze api_probe.dart
```

Expected: no errors. Record exact resolved versions from `pubspec.lock` in runlog.

**Default override gate:** If `flutter_gemma` 0.14.0 fails to analyze, evaluate 0.13.6 fallback or latest per `flutter pub outdated`, pin that instead, and document in runlog.

---

### Phase 2 — Prompt and schema alignment

**Scope:** remove ambiguity before Android behavior depends on the contract.

Edits:
1. Update `docs/prompts/system_prompt_v1.txt`: `model_tags` lists the exact 20-tag enum from schema.
2. Sync to `apps/cairn_mobile/assets/prompts/system_prompt_v1.txt`.
3. Add schema asset: `apps/cairn_mobile/assets/schema/evidence_packet_v1.schema.json`; add to `pubspec.yaml`.
4. Update `tool/sync_assets.sh` (or add `tool/sync_assets.ps1`) to copy both prompt and schema.
5. Strengthen `scripts/data/validate_seeds.py`: check `model_tags` against schema enum; check `ask_followup` output is object/null; check `synthesize` does not set forbidden fields.

Gate:
```powershell
python -m data.validate_seeds
PYTHONPATH=scripts python -m pytest -q scripts\tests
```

Expected: seeds pass; prompt and app asset byte-identical.

---

### Phase 3 — App schema-safety pass

**Scope:** current app capable of sealing schema-valid packets before Android-specific work.

Edits:
1. Add three counters to `SessionDraft`: `nextObsSeq`, `nextImgSeq`, `nextAudSeq`. Preserve in `cloneShallow()`.
2. Add controller methods: `allocateObservationId()` → `obs-N`, `allocateImageRef()` → `img-N`, `allocateAudioRef()` → `aud-N`.
3. Replace three UUID-based observation allocators in UI screens with `allocateObservationId()`.
4. Replace length-based allocators in `addImage()`, `addAudio()` with counter methods.
5. Remove `user_note` and `user_override` from `model_tags` everywhere; use empty list.
6. Implement volunteer-authored convention per §1.7 (omit `model_description`, use distinct `prompt_id`).
7. Add `EvidencePacketValidator` covering: ID/ref regexes, closed `model_tags`, audio invariants, bbox invariants, protocol domains, triage requirements.
8. Add Dart tests for validator, ID allocation/clone, ask-followup shapes.

Gate:
```powershell
flutter test
PYTHONPATH=scripts python -m pytest -q scripts\tests
```

Expected: no `obs-${` call sites remain; no `user_note`/`user_override` literals remain.

---

### Phase 4 — Android scaffold restoration

**Scope:** restore Android platform files; no feature changes mixed in.

Command from `apps/cairn_mobile`:
```powershell
flutter create --org app.cairn --platforms=android,web --project-name cairn_mobile .
```

Immediate inspections:
- `android/app/build.gradle.kts` (or `.gradle`) exists.
- `applicationId = app.cairn.cairn_mobile`, `namespace = app.cairn.cairn_mobile`.
- `MainActivity.kt` package matches.
- Do **not** hardcode `minSdk = 26`; let Gradle resolve from plugin manifests.

Manifest additions:
- `INTERNET` (model downloads)
- `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` (geolocator)
- `RECORD_AUDIO` (Phase 8 audio)
- OpenCL `uses-native-library` entries (GPU backend)

Do **not** add storage/media permissions; app uses app-specific directories and photo picker.

**Sub-gate (Android API probe):**
After scaffold exists, re-run the probe from Phase 1 targeting Android:
```powershell
flutter build apk --debug
```
This proves `flutter_gemma` API surface compiles for Android target.

Gate:
```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter install -d <serial>
adb shell am start -n app.cairn.cairn_mobile/.MainActivity
```

Expected: app launches to Start screen.

---

### Phase 5 — Per-platform model artifacts

**Scope:** correct artifact for each platform.

Edits:
1. `ModelRegistry` gains per-platform metadata:
   - Web: E2B `gemma-4-E2B-it-web.task`
   - Android: E2B `gemma-4-E2B-it.litertlm` (generic, not Qualcomm-specific)
2. Pass `fileType: ModelFileType.task` for both `.task` and `.litertlm` (per package docs; distinct `litertlm` enum only if Phase 1 proves it exists).
3. Add `TargetPlatform` resolver in one place.
4. Mirror in `scripts/cairn/constants.py`.
5. Extend `scripts/tests/test_constants_parity.py` to compare artifacts.

Gate:
```powershell
flutter test
PYTHONPATH=scripts python -m pytest -q scripts\tests\test_constants_parity.py
flutter run -d <serial> --release
```

Expected: Android logs show `.litertlm` URL; web still uses `-web.task`.

---

### Phase 6 — LLM session multimodal hardening

**Scope:** wire image, audio, thinking explicitly; reject malformed output.

Edits:
1. `GemmaSession` takes per-turn capability flags or separate session factories:
   - `describe_photo`: image true, audio false, thinking false
   - `describe_audio`: image false, audio true, thinking false
   - `synthesize`: image false, audio false, thinking true
   - `protocol`/`followup`: image false, audio false, thinking false
2. Pass `supportAudio` to `getActiveModel()` and `createChat()` when audio needed.
3. Add `Message.withAudio()` path for audio turns.
4. Add contract checks:
   - `describe_photo`: reject tags outside schema enum, malformed bbox
   - `synthesize`: reject model-supplied `priority_score` or `priority_band`
5. Add TTFT and wall-clock instrumentation per LLM call.

Gate:
```powershell
flutter test
flutter run -d <serial>
```

Manual expected:
- Real photo description returns parseable JSON.
- Followup null/object handled.
- Synthesize uses `isThinking: true` when package/artifact support it.

---

### Phase 7 — Android photo, location, lost-data

**Scope:** existing non-audio inputs robust on Android.

Edits:
1. Add `image_picker.retrieveLostData()` at startup or in photos flow.
2. Persist picked/captured image bytes out of image_picker cache immediately to app-specific storage.
3. Location screen handles: denied, denied forever, services disabled, timeout.
4. Add controller tests for error states.

Gate:
```powershell
flutter test
flutter run -d <serial>
```

Manual expected:
- Camera/gallery return to app.
- Location denial has clean user path.
- No storage permission prompt appears.

---

### Phase 8 — Android audio capture (capability mandatory, quality informational)

**Scope:** record schema-valid audio; Gemma describe capability proven.

Preconditions: Phase 1 `record` API, Phase 6 `supportAudio`/`Message.withAudio`.

Edits:
1. Keep `record: 5.2.1` exact per §1.5.
2. Add `RECORD_AUDIO` to manifest.
3. Android recorder UI: idle, recording, encoded, error states.
4. Encode mono 16 kHz WAV via `RecordConfig`.
5. `SessionController.addAudio()` enforces:
   - `durationS >= 0`
   - `durationS <= 30`
   - `sampleRateHz == 16000`
   - `channels == 1`
6. Audio refs as `aud-N` via counter.
7. Optional Gemma turn: run `Message.withAudio`, capture parseable JSON, log quality in runlog.

**Capability gate (mandatory):**
- `Message.withAudio` compiles, runs without crash, returns parseable schema-valid JSON.

**Quality gate (informational):**
- Reviewer judges description plausibility; logged in runlog.

Gate:
```powershell
flutter test
flutter run -d <serial>
```

Manual expected:
- 5-second recording saves as `aud-1`.
- Audio metadata validates against schema.
- If `ffprobe` available, confirms mono 16 kHz.
- Real audio turn returns valid JSON or logs as unsupported without blocking packet finalization.

---

### Phase 9 — File-backed vault, synthesize UI, report UI

**Scope:** replace in-memory storage with device persistence; complete UI placeholders.

Edits:
1. Promote `path_provider` to direct dependency (already done Phase 1).
2. Implement file-backed `EvidenceVault` using app-specific internal storage.
3. Persist: `packet.json`, original images/audio, `turns.jsonl`, `report.pdf`.
4. Atomic writes: temp file + rename.
5. Implement `/synthesize` UI (no longer placeholder).
6. Implement `/report` UI using existing `pdf`, `printing`, `qr_flutter`.
7. Validate final packet before saving report.

Gate:
```powershell
flutter test
flutter run -d <serial>
```

Manual expected:
- Kill/relaunch mid-flow restores draft.
- Finalize writes packet folder.
- `adb pull` retrieves folder.
- Pulled `packet.json` validates with Python schema tests.
- `report.pdf` opens on desktop.

---

### Phase 10 — S2 spike repair (Android only)

**Scope:** minimal S2 repair for Android; web frozen.

Edits:
1. Keep `s2_probe.jpg` operator-provided.
2. `runBurst()` shows clean error UI when asset missing instead of throwing.
3. Rewrite `s2_checklist.md` to remove unimplemented "Toggle LoRA / Reboot" behavior.
4. Android S2 runs once in Phase 13; web S2 untouched.

Gate:
```powershell
flutter test
flutter run -d <serial>
```

Expected:
- Android S2 runs or gives clear unsupported message.
- Phase 13 captures baseline.

---

### Phase 11 — Device eval runner

**Scope:** on-device eval infrastructure with seeds-as-gold.

Edits:
1. Add `scripts/cairn/runners/adb.py` via debug-only deep-link entry point.
2. Add app-side eval entry point (debug route reading request path, writing response path).
3. Build `scripts/data/build_gold_from_seeds.py` deriving `data/eval/gold.jsonl` from seeds.
4. Wire `eval_baseline.py` to instantiate `device_adb:<pkg>@<serial>`.
5. Reports: parse failure rate, schema validity rate, median TTFT, per-row raw response path.

Gate:
```powershell
PYTHONPATH=scripts python -m eval.eval_baseline --gold data\eval\gold.jsonl --runner device_adb:app.cairn.cairn_mobile@<serial> --strategy strict_schema --out scripts\eval\reports\device_e2b_strict.json --limit 5
```

Expected:
- 5 rows complete.
- Report includes metrics above.

---

### Phase 12 — CI and docs cleanup

**Scope:** make future claims testable; delete stale predecessors.

Edits:
1. Add `.github/workflows/ci.yml`.
2. Python job: install script package, pytest, validate seeds.
3. Flutter job (required):
   - Pinned Flutter version from Phase 0 runlog.
   - `flutter pub get`, `flutter analyze`, `flutter test`.
   - `flutter build apk --debug --target-platform android-arm64`.
4. Schema job: validate golden packets against `docs/schema/evidence_packet_v1.schema.json`.
5. Web job: `flutter build web` with `continue-on-error: true` (frozen).
6. Docs cleanup per §8.

Gate:
- CI green on a branch.

---

### Phase 13 — Final device evidence

**Scope:** evidence that Android repivot is complete.

Artifacts to commit or archive:
- Phase 0 runlog (`docs/android_repivot_v5_runlog.md`).
- Device model, SoC, Android SDK, storage, RAM.
- S1 harness JSON (if applicable).
- S2 report JSON.
- One pulled packet folder: `packet.json`, images, optional audio, `turns.jsonl`, `report.pdf`.
- Python schema validation output for pulled packet.
- Backend notes: GPU vs CPU, thermal behavior, crashes.

Completion gate:
- Fresh clone + documented Flutter/Android toolchain builds APK.
- S23 FE completes one synthetic survey.
- Pulled packet validates against schema.
- Report PDF opens.
- Web fallback documented as frozen.

---

### Phase 14 — Play Store internal track (new)

**Scope:** publish to Play Store internal testing track.

Edits:
1. Generate upload keystore; document in `docs/release_signing.md`; add to `.gitignore`.
2. Configure `android/key.properties` (gitignored) + `signingConfigs`.
3. CI builds signed `.aab`.
4. Privacy policy authored from `LEGAL.md`; hosted at stable URL (external ops task).
5. Play Console: app entry, content rating, target audience 18+, data safety, listing assets (icon, screenshots from Phase 13, descriptions echoing `LEGAL.md`).
6. Internal testing track with minimum 1 tester.

Gate:
- CI produces both `--debug` APK and `--release` `.aab`.
- Play Console shows internal track build uploaded and available to tester.

---

## 4. Test matrix

| Layer | Test | New/Extended |
|-------|------|--------------|
| Python | `scripts/tests/test_schema.py` validates schema fixtures. | Existing |
| Python | `scripts/tests/test_seeds.py` + strengthened `validate_seeds.py`. | Extended |
| Python | `scripts/tests/test_constants_parity.py` checks per-platform artifacts. | Extended |
| Dart | `test/json_extract_test.dart` JSON extraction. | Existing |
| Dart | `test/session_controller_test.dart` extended for ID counters, audio validation, clone preservation. | Extended |
| Dart | `test/evidence_packet_test.dart` corrected with schema-valid samples. | Extended |
| Dart | `test/evidence_packet_validator_test.dart` (new). | New |
| Dart | `test/orchestrator_followup_test.dart` ask-followup null/object/malformed. | New |
| Dart | `test/model_registry_platform_test.dart` web vs Android artifacts. | New |
| Dart | `test/volunteer_authored_test.dart` (new): volunteer_note_v1, humility_override_v1, model_description omission. | New |
| Device | Android launch, model install, photo describe, audio describe capability, synthesize, finalize, pull, validate. | New |
| Device | Phase 11 device_adb eval smoke. | New |
| CI | Phase 14 signing config validation in build. | New |

---

## 5. Phase 0 runlog template

```markdown
# Android Repivot v5 Runlog

## Date
YYYY-MM-DD

## Host
- OS: Windows 11 / macOS / Linux
- User: 

## Commands and Output

### flutter --version
```
(paste)
```

### dart --version
```
(paste)
```

### adb version
```
(paste)
```

### java -version
```
(paste)
```

### flutter doctor -v
```
(paste)
```

### adb devices
```
(paste)
```

### adb shell getprop ro.product.model
```
(paste)
```

### adb shell getprop ro.hardware.chipname
```
(paste)
```

### adb shell getprop ro.soc.model
```
(paste)
```

### adb shell getprop ro.build.version.sdk
```
(paste)
```

### adb shell dumpsys meminfo | Select-String Total RAM
```
(paste)
```

### adb shell df -h /sdcard
```
(paste)
```

## Device Classification
- Matches §1.2 locked target (S23 FE Exynos): [ ] Yes [ ] No
- If No, note variance:

## Gate Result
- [ ] Flutter/Dart/ADB exist
- [ ] flutter doctor -v clean
- [ ] Device listed
- [ ] Storage free >= 6 GB

## Resolved Dependency Versions (from pubspec.lock)
- flutter_gemma: 
- record: 
- path_provider: 

## Overrides
If any default from §1 was overridden based on Phase 0/1 findings, document here:
```

---

## 6. Predecessor docs deletion checklist

After v5 lands and is verified canonical:

- [ ] Delete `docs/android_repivot.md`
- [ ] Delete `docs/android_repivot_v2.md`
- [ ] Delete `docs/android_repivot_v3.md`
- [ ] Delete `docs/android_repivot_v4.md`
- [ ] Verify Git history preserves them (do not force-push)
- [ ] Update any internal bookmarks/links to point to v5

---

## 7. Open questions that remain gates

These are not assumptions; they are answered by gates, with defaults documented.

| # | Question | Default | Gate that answers |
|---|----------|---------|-----------------|
| 1 | Exact Flutter SDK version | Latest stable at Phase 0 time | Phase 0 runlog |
| 2 | Exact Android SDK on device | Unknown | Phase 0 runlog |
| 3 | Free storage after model download | Assume ≥6 GB | Phase 0 runlog |
| 4 | Does flutter_gemma 0.14.0 compile cleanly? | Assume yes | Phase 1 analyze |
| 5 | ModelFileType.values after pin? | `task`, `binary` assumed | Phase 1 probe |
| 6 | Audio quality on S23 FE Exynos? | Unknown; logged, not blocking | Phase 8 quality gate |
| 7 | Does synthesize with isThinking work? | Assume yes if package supports | Phase 6 gate |
| 8 | Release APK vs signed .aab only? | Both (Phase 14) | Phase 12 + 14 CI |

---

## 8. References (external facts used by this plan)

- `flutter_gemma` 0.14.0 docs: https://pub.dev/packages/flutter_gemma
- MediaPipe tasks-genai: https://developers.google.com/mediapipe/solutions/genai
- Android app-specific storage: https://developer.android.com/training/data-storage/app-specific
- Android 13 media permissions: https://developer.android.com/about/versions/13/behavior-changes-13
- `geolocator`: https://pub.dev/packages/geolocator
- `image_picker`: https://pub.dev/packages/image_picker
- `record`: https://pub.dev/packages/record
- Flutter Android deployment: https://docs.flutter.dev/deployment/android
- Google Play Console: https://play.google.com/console
