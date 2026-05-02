# Android Repivot v3 — End-to-End Execution Plan

Status date: 2026-04-30
Supersedes: `docs/android_repivot.md`, `docs/android_repivot_v2.md`.
Owner: Cairn maintainers.
Scope: Take the codebase from "web fallback works on `/spike`" to "an installable Android APK that produces a schema-valid `EvidencePacket` end-to-end on a real device, with web kept as a graceful degraded fallback."

This document is **ground-truthed against the current source tree** (file/line citations below). Where v2 was right, the rationale is preserved. Where v2 was wrong, under-specified, or silent, the correction is called out by name.

---

## 0. How to read this plan

- Every claim about the codebase is anchored to a `path:line` citation; if you can't find it on disk, treat the claim as stale and stop.
- Every external API claim is anchored to the **pinned `flutter_gemma 0.13.6`** doc surface unless an explicit upgrade decision is taken in §2.
- Every step has an **acceptance gate** (a copy-pastable command and the output you must see) and a **rollback** (what to revert if the gate fails).
- Steps are numbered. Do them in order. Do not parallelize across phases without first marking the upstream gate green.
- "Operator" = the human running the commands. "Driver" = the Cascade/coding agent making the edits.

---

## 1. Verified current state (do not restate, link)

These are observed facts in the working tree at the status date. If any drifts, fix this section first.

### 1.1 Repo / Flutter

- `apps/cairn_mobile/.metadata` declares only `root` + `web` platforms. There is **no `apps/cairn_mobile/android/` directory** in the workspace layout. Android must be regenerated.
- `apps/cairn_mobile/pubspec.yaml` pins `flutter_gemma: 0.13.6` (locked in `pubspec.lock`).
- `path_provider` is present **transitively only**; promoting it to a direct dependency is required before any file-backed vault work.
- `apps/cairn_mobile/assets/images/` exists but is empty — `s2_probe.jpg` referenced from `apps/cairn_mobile/lib/spike/s2_spike_page.dart:157` does not exist on disk. `runBurst()` will throw on first run.
- `apps/cairn_mobile/assets/prompts/system_prompt_v1.txt` is wired into `pubspec.yaml` and consumed by `s2_spike_page.dart:118`. The canonical source lives at `docs/prompts/system_prompt_v1.txt`.

### 1.2 Schema and contract

- Locked schema: `docs/schema/evidence_packet_v1.schema.json` (referenced by `scripts/cairn/constants.py:9`).
- Locked system prompt: `docs/prompts/system_prompt_v1.txt`. Key contract clauses:
  - **Closed enum for `model_tags`** (`docs/prompts/system_prompt_v1.txt:20-27`): only the FEMA-P-154 vocabulary plus `uncertain_structural`, `uncertain_cosmetic`, `no_visible_damage`. **`user_note` and `user_override` are not in the enum.**
  - **`ask_followup` output shape** (`:76-80`): `{ "followup": { "target_observation_id": "...", "question": "..." } }` or `{ "followup": null }`. **Not a bare string.**
  - **`box_2d` is `[y1, x1, y2, x2]` 0..1000** (`:44-46`).
  - **App computes triage; LLM only suggests bullets** (`:48-53`).
- Schema constraints worth pinning to acceptance tests:
  - `observation_id` matches `^obs-[0-9]+$`.
  - `assets.images[].ref` matches `^img-[0-9]+$`.
  - `assets.audio[].sample_rate_hz` is `const 16000`, `channels` is `const 1`, `duration_s` ≤ 30.
  - `protocol_answers` requires the six keys with the exact value domains in `apps/cairn_mobile/lib/core/models/evidence_packet.dart:199-256`.

### 1.3 Cairn Flutter app — known contract violations

These are **bugs against the locked schema/prompt**. They will fail any golden-packet test the moment one is added.

- `obs-${uuid.v7()}` violates `^obs-[0-9]+$`. Three sites:
  - `apps/cairn_mobile/lib/features/photos/photos_screen.dart:187`
  - `apps/cairn_mobile/lib/features/humility/humility_screen.dart:134`
  - `apps/cairn_mobile/lib/features/describe/describe_screen.dart:52`
- `model_tags: ['user_note']` violates the closed enum: `apps/cairn_mobile/lib/features/describe/describe_screen.dart:61`.
- `model_tags: ['user_override']` violates the closed enum: `apps/cairn_mobile/lib/features/humility/humility_screen.dart:141`.
- `AskFollowupResult.followup` is typed as a single `String`, not a nullable `{target_observation_id, question}` record. See `apps/cairn_mobile/lib/core/llm/orchestrator.dart` (the `askFollowup` return shape and its caller `humility_screen.dart:95-108`).
- Synthesize is invoked through `_session.generate(...)` on the same chat that was opened with `isThinking: false`; there is no thinking-mode swap. See `apps/cairn_mobile/lib/core/llm/gemma_session.dart:65` and the synthesize call site.
- `createChat(...)` in `gemma_session.dart` passes `supportImage: wantImage` but **never passes `supportAudio`**, so the locked prompt's audio modality is wired up nowhere. `getActiveModel(...)` must mirror that flag.

### 1.4 Cairn Flutter app — model registry mismatch

- `apps/cairn_mobile/lib/core/llm/model_registry.dart` (and its Python mirror `scripts/cairn/constants.py:39-60`) hardcodes `gemma-4-E2B-it-web.task` for **both** web and Android targets. The HF repo `litert-community/gemma-4-E2B-it-litert-lm` actually publishes:
  - `gemma-4-E2B-it.litertlm` — 2.58 GB, native (Android/iOS/Desktop via LiteRT-LM).
  - `gemma-4-E2B-it-web.task` — 2 GB, web/MediaPipe only.
  - `gemma-4-E2B-it_qualcomm_qcs8275.litertlm` — 3.29 GB, Qualcomm NPU.
  - `gemma-4-E2B-it_qualcomm_sm8750.litertlm` — 3.02 GB, Qualcomm NPU (recent SM8750 silicon).
  Source: HF tree at `litert-community/gemma-4-E2B-it-litert-lm/tree/main`.
- The `constants_parity` test (Python ↔ Dart) currently enforces the wrong `-web.task` pairing for Android; once we add per-platform resolution we must extend the parity test to compare a richer struct.

### 1.5 `flutter_gemma 0.13.6` API surface (verified)

These are the exact symbols available under the pinned version. Do not invent others.

- `Message` constructors: `Message.text`, `Message.withImage`, `Message.imageOnly`, `Message.withAudio`, `Message.audioOnly`, `Message.systemInfo`, `Message.thinking`, `Message.toolCall`, `Message.toolResponse`, plus a base positional `Message(...)` constructor with both `Uint8List` slots. (Source: `pub.dev/documentation/flutter_gemma/0.13.6/core_message/Message-class.html`.)
- `FlutterGemma.installModel({ required ModelType modelType, ModelFileType fileType = ModelFileType.task })` returns a fluent `InferenceInstallationBuilder` with `.fromNetwork(url, {token})`, `.fromAsset(name)`, `.withProgress(cb)`, `.withLoraFromNetwork(url)`, `.withLoraFromAsset(name)`, `.install()`.
- `FlutterGemma.getActiveModel({ int maxTokens = 1024, PreferredBackend? preferredBackend, bool supportImage = false, bool supportAudio = false, int? maxNumImages })` is the documented entry. The current code calls `getActiveModel(... supportImage: true, maxNumImages: 5, maxTokens: 4096)` but **omits `supportAudio`**.
- `InferenceModel.createChat({ ..., bool? supportImage, bool? supportAudio, String? loraPath, bool isThinking = false, ModelType? modelType, String? systemInstruction, int? maxFunctionBufferLength, ToolChoice toolChoice = ToolChoice.auto, List<Tool> tools = const [], int tokenBuffer = 256 })`. **There is no `maxNumImages` argument on `createChat`.**
- `ModelFileType` distinguishes `task` (`.task`/`.bin`) from a newer `litertlm` value introduced in 0.13.x. Use `ModelFileType.task` for the web `-web.task` artifact and `ModelFileType.litertlm` for the Android `.litertlm` artifact. **Verify this enum value compiles after `flutter pub get`**; if the pinned version only exposes `task`/`binary`, fall back to `task` for `.litertlm` (the upstream code paths still route by file extension on Android), and document the constraint.
- `WebStorageMode.streaming` (used in `apps/cairn_mobile/lib/main.dart:20-22`) is web-only. Android ignores `webStorageMode`.

### 1.6 Tooling, scripts, and CI

- `scripts/cairn/runners/` contains `__init__.py`, `base.py`, `gemini.py`, `ollama.py`. The README at `scripts/eval/README.md:38` claims a `device_adb` runner; it does not exist on disk. `scripts/eval/eval_baseline.py:35-41` explicitly raises if `--runner` starts with anything other than `ollama:`.
- `scripts/spikes/s1_adb_harness.py` accepts `--pkg`, **not** `--model` (matches v2's correction).
- There is no `.github/workflows/*.yml` in the repo today; CI must be created. Any plan that says "CI is green" without first authoring the workflow is a lie.

### 1.7 Local toolchain (operator-machine, not repo)

These must be re-checked at the start of each work session. v2 listed them; v3 keeps the same gate (§3.1) and adds the `flutter doctor --android-licenses` check.

---

## 2. Strategic decisions (resolve before phase 1)

These are not "tasks" — they are architectural choices that change the rest of the plan. The driver must surface them to the operator and get an explicit answer before phase 1 begins.

### 2.1 `flutter_gemma` version pin: stay on 0.13.6 vs upgrade to ≥0.14.0

| Capability we need on Android | Available in 0.13.6? | Available in 0.14.0+? |
|---|---|---|
| `Message.withImage` / `Message.withAudio` | Yes | Yes |
| `createChat(supportAudio: true)` | Yes (verified above) | Yes |
| `ModelFileType.litertlm` distinct enum value | Likely (introduced in 0.13.x) — **verify** | Yes |
| Gemma 4 E2B/E4B `.litertlm` on Android via FFI | Partial (MediaPipe path only) | Yes (changelog: "Android: drop Kotlin LiteRtLm dependency — `.litertlm` via FFI") |
| `isThinking: true` on Gemma 4 (Android) | **No** — the changelog explicitly lists "Gemma 4 Thinking Mode: `isThinking: true` now works with Gemma 4 E2B/E4B (Android, iOS, Desktop; not Web)" as a 0.14.0 entry | Yes |
| Audio modality on Android with Gemma 4 | Listed under 0.14.0 ("Android: Audio modality support") | Yes |

**Recommendation:** upgrade to the latest 0.14.x as part of phase 2, in a single isolated commit, and re-run all unit/widget tests. The cost of staying on 0.13.6 is that synthesize-with-thinking-mode and Android audio simply will not work, which guts the spec.

If the operator overrides this and insists on 0.13.6, then phase 6 (audio) and the thinking-mode portion of phase 5 (synthesize) are de-scoped to "best-effort, no thinking" and the schema/prompt notes must reflect that.

### 2.2 Android model artifact: `.litertlm` vs Qualcomm-NPU `.litertlm`

- Default Android primary: **`gemma-4-E2B-it.litertlm`** (2.58 GB, generic).
- If the target device's SoC matches `qualcomm_sm8750` (e.g., Snapdragon 8 Elite-class), prefer the `_qualcomm_sm8750.litertlm` for NPU acceleration. Detect via `adb shell getprop ro.hardware.chipname` / `ro.soc.model` and gate selection in `model_registry.dart` only after a verified A/B run.
- E4B remains optional. Don't promise E4B on a 4–6 GB-RAM phone; it will OOM.

### 2.3 Engineer console (`apps/cairn_console/`)

- The README/plan references it but there is **no `apps/cairn_console/` directory** today. v3 explicitly **defers** the console to a follow-up plan. All Android device evidence in this plan is exported as JSON/PDF and inspected on a desktop browser/IDE. If the operator wants the console in scope, that is a separate plan with its own gates.

### 2.4 Schema version

- Default: **schema v1 stays frozen.** All app-side bugs in §1.3 are fixed by changing the app, not the schema. Any temptation to add `user_note` to the closed `model_tags` enum should be rejected: volunteer text already has a first-class home in `user_text` + `model_description`, and humility overrides are recorded by setting `model_confidence = 1.0` on a fresh observation with the appropriate **structural** tag (or `no_visible_damage`).

---

## 3. Phase plan

Each phase has: scope, exact edits, exact commands, acceptance gate, rollback. Do not start phase N until phase N−1's gate is green.

### Phase 1 — Toolchain + Android platform restoration

**Scope:** prove the operator's machine and target device can build, install, and launch a stock Flutter app under the Cairn package id.

**Edits / commands (in this exact order):**

1. Operator gate (record output verbatim into `docs/android_repivot_v3_runlog.md`):

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
   adb shell df -h /sdcard
   ```

2. Restore Android platform from the app dir (driver runs this; do **not** prefix with `cd`, set `Cwd`):

   ```powershell
   flutter create --org app.cairn --platforms=android,web --project-name cairn_mobile .
   ```

3. Verify the regenerated files (driver inspects, not regenerates if already present):
   - `android/app/build.gradle.kts` (or `.gradle`): `applicationId = "app.cairn.cairn_mobile"`, `namespace = "app.cairn.cairn_mobile"`, `minSdk = 26` (Gemma 3n / 4 require it; bump from default 21 if needed), `targetSdk = 34` or current Flutter default.
   - `android/app/src/main/AndroidManifest.xml`: package id consistent, `MainActivity` path matches, **only** `INTERNET` declared at this point (other perms added in their phases).
   - `android/app/src/main/kotlin/app/cairn/cairn_mobile/MainActivity.kt` exists.
   - `android/app/proguard-rules.pro` exists or is created empty.

4. Acceptance:

   ```powershell
   flutter pub get
   flutter analyze
   flutter test
   flutter build apk --debug
   flutter install -d <serial>
   adb shell am start -n app.cairn.cairn_mobile/.MainActivity
   ```

   Expected: APK installs, app launches to the existing Start screen (no crash), `flutter analyze` is clean modulo pre-existing warnings (record them).

**Rollback:** if `flutter create` clobbers something we wanted to keep, the `git diff` is the rollback. Do not commit the Android scaffold until phase 1 acceptance is green.

### Phase 2 — `flutter_gemma` upgrade decision and pin

**Scope:** lock `flutter_gemma` at the version that supports Gemma 4 thinking mode on Android.

**Edits:**

- Bump `apps/cairn_mobile/pubspec.yaml` to `flutter_gemma: ^0.14.0` (or the latest stable confirmed in the live changelog at start-of-work). Do **not** mix this with any other change; this commit is a dependency bump only.
- `flutter pub upgrade flutter_gemma`.
- If `ModelFileType.litertlm` is now a distinct enum value, capture the import path in a one-line note in `apps/cairn_mobile/lib/core/llm/model_registry.dart` (header comment, no logic change yet).

**Acceptance:**

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

All four green. If `flutter analyze` flags API renames (e.g., `WebStorageMode`, `PreferredBackend`), patch them to the new symbol in this same commit and re-run. Do not start phase 3 until tests pass.

**Rollback:** revert the `pubspec.yaml` / `pubspec.lock` change; the rest of the plan can proceed against 0.13.6 with the de-scopes noted in §2.1.

### Phase 3 — Schema-safety pass (no Android features yet)

**Scope:** make the existing app produce a schema-valid `EvidencePacket`. This is platform-agnostic and gives every later phase a stable contract test to lean on.

**Edits — in order:**

1. **Centralize observation ID allocation.** In `apps/cairn_mobile/lib/core/state/session_controller.dart`, add a private `int _nextObsSeq = 0;` to `SessionDraft` and a public `String allocateObservationId() => 'obs-${++_nextObsSeq}';`. Replace all three `obs-${uuid.v7()}` sites with `controller.allocateObservationId()` (or an equivalent draft-side accessor). The existing `addPhoto` / `addAudio` `img-N` / `aud-N` allocators are already correct; mirror their style.

2. **Drop closed-enum violations.**
   - `describe_screen.dart:50-65`: change `modelTags: const ['user_note']` to `modelTags: const <String>[]`. The volunteer note is already faithfully captured by `userText` + `modelDescription`. The downstream filter at `describe_screen.dart:78-80` (`o.modelTags.contains('user_note') == false`) needs to be replaced by a `promptId == 'volunteer_note_v1'` check instead.
   - `humility_screen.dart:131-144`: change `modelTags: const ['user_override']` to `modelTags: const <String>[]` and keep `promptId: 'humility_followup_v1'`. Downstream code that distinguishes "this came from a human" should check `modelConfidence >= 1.0 && userText != null`, not a tag.

3. **Fix `ask_followup` result shape.** In `orchestrator.dart`, replace the `AskFollowupResult` whose `followup` is `String` with:

   ```dart
   class AskFollowupResult {
     const AskFollowupResult({this.targetObservationId, this.question});
     final String? targetObservationId;
     final String? question;
     bool get hasQuestion => question != null && question!.isNotEmpty;
   }
   ```

   Parse the JSON as `{"followup": null}` ⇒ `AskFollowupResult()` (both fields null), and `{"followup": {"target_observation_id": "...", "question": "..."}}` ⇒ populated. Treat any other shape as `GemmaContractError`.

   Update `humility_screen.dart` to call `_q.hasQuestion ? show(_q.question) : context.go(synthesize)`. Stop reading `_q.followup` as a string.

4. **Add a Dart packet validator.** New file `apps/cairn_mobile/lib/core/models/evidence_packet_validator.dart` (referenced by the doc comment in `evidence_packet.dart:5`). Implement a shallow validator that:
   - Loads `docs/schema/evidence_packet_v1.schema.json` from a hardcoded `assets/schema/evidence_packet_v1.schema.json` (add it to `pubspec.yaml` assets).
   - Walks the sealed `EvidencePacket.toJson()` and asserts: required keys present, `observation_id` matches `^obs-[0-9]+$`, `model_tags` ⊆ closed enum (define enum constant in this file, mirroring the system prompt §3), `protocol_answers` keys/values, `assets.audio[].sample_rate_hz == 16000`, `assets.audio[].channels == 1`, `box_2d` shape and 0..1000 range, `priority_band ∈ {LOW, MEDIUM, HIGH, CRITICAL}`.
   - Does **not** depend on a JSON Schema runtime — a hand-rolled validator is faster than pulling in `json_schema` and avoids a new transitive surface. Acceptance is "matches the python `tests/test_schema.py` golden expectations".

5. **Add a golden packet test.** New file `apps/cairn_mobile/test/evidence_packet_golden_test.dart`:
   - Builds a deterministic `SessionDraft` (fixed `packetId`, fixed `createdAtUtc`, two photos, one audio asset, one volunteer note, one humility answer, full `protocol_answers`, hand-rolled triage).
   - Calls `seal(...)`, runs the new validator, asserts no errors.
   - Snapshots the JSON to `test/golden/evidence_packet_v1.golden.json` on first run; subsequent runs diff against it.

6. **Mirror in Python.** Add `scripts/tests/test_evidence_packet_v1_golden.py` that loads the same golden JSON and runs `jsonschema.validate(...)` against `docs/schema/evidence_packet_v1.schema.json`. This double-checks that the Dart validator and the canonical schema agree.

**Acceptance:**

```powershell
flutter test
PYTHONPATH=scripts python -m pytest -q scripts\tests
```

Both green. The golden file exists and is committed. The three `obs-${uuid.v7()}` callsites are gone (ripgrep `obs-\$\{` returns zero matches under `apps/cairn_mobile/lib`). The two `'user_note'` / `'user_override'` literals are gone.

**Rollback:** all edits are local to the app and tests; revert is straightforward.

### Phase 4 — Per-platform model registry

**Scope:** stop pretending `-web.task` is the Android artifact.

**Edits:**

1. In `apps/cairn_mobile/lib/core/llm/model_registry.dart`, replace the single `taskFilename` field with a per-platform record:

   ```dart
   class ModelArtifact {
     const ModelArtifact({required this.filename, required this.fileType});
     final String filename;
     final ModelFileType fileType; // task or litertlm
   }
   class ModelSpec {
     // ... existing fields ...
     final ModelArtifact webArtifact;
     final ModelArtifact androidArtifact;
     String hfDownloadUrlFor(TargetPlatform p) =>
         'https://huggingface.co/$hfRepo/resolve/main/'
         '${(p == TargetPlatform.android ? androidArtifact : webArtifact).filename}';
   }
   ```

   E2B Android: `filename: 'gemma-4-E2B-it.litertlm', fileType: ModelFileType.litertlm`.
   E2B Web: `filename: 'gemma-4-E2B-it-web.task', fileType: ModelFileType.task`.
   E4B parallel.

2. In `gemma_session.dart`, pass `fileType: spec.artifactForPlatform(...).fileType` to `FlutterGemma.installModel(...)` and use the platform-resolved URL on `.fromNetwork(...)`. Mirror the change in `getActiveModel(...)` if the new flutter_gemma version requires it.

3. Mirror the struct in `scripts/cairn/constants.py`: add `web_task_filename` and `android_litertlm_filename` fields to `ModelSpec`; update the parity test to compare the union.

4. Optional, gated on phase 1 device data: add `qualcomm_sm8750` / `qualcomm_qcs8275` overrides to `androidArtifact` selection based on `ro.soc.model`. Default to the generic `.litertlm` if unrecognised.

**Acceptance:**

```powershell
flutter test
PYTHONPATH=scripts python -m pytest -q scripts\tests\test_constants_parity.py
flutter run -d <serial> --release
```

App startup logs (`adb logcat | findstr /i flutter_gemma`) show the URL ending in `.litertlm` on Android and `-web.task` on web. No 404 from HF.

**Rollback:** revert the registry struct changes; the unified-`-web.task` codepath is the previous behaviour.

### Phase 5 — Orchestrator hardening (followup, synthesize, JSON extraction)

**Scope:** make every LLM-output codepath enforce the locked prompt's contract.

**Edits:**

1. **`describe_photo`:** keep the existing JSON extraction at `apps/cairn_mobile/lib/core/llm/json_extract.dart` (already covered by `test/json_extract_test.dart`). Add a contract assertion: every parsed `model_tags` element must be in the closed enum (re-exported from the validator in phase 3); on violation throw `GemmaContractError` with the bad tag and the first 200 chars of the raw response. Show that in the photos screen error chip instead of the raw exception.

2. **`ask_followup`:** new shape from phase 3 plus: parse must tolerate a model that emits `"followup": "some string"` (older fine-tuned snapshots) by treating it as `{question: "some string", target_observation_id: null}` **and** logging a `model_drift_event` to the run log. Any field-name typo (e.g., `target_obs_id`) is `GemmaContractError`.

3. **`protocol_answer`:** the `applyProtocolDelta` switch in `session_controller.dart:313-327` is already strict. Add an integration test that feeds it `{key: 'leaning', value: 'severe'}` and `{key: 'visible_collapse', value: true}` to lock the wire format.

4. **`synthesize`:** create a fresh thinking-mode chat at synthesize time:

   ```dart
   final thinkingChat = await _model.createChat(
     supportImage: false,
     supportAudio: false,
     isThinking: true,                  // requires flutter_gemma ≥ 0.14
     systemInstruction: _systemPrompt,
     temperature: 0.4,
     topK: 40,
     topP: 0.9,
   );
   try {
     final raw = await _generateOnChat(thinkingChat, packetSummaryJson);
     final draft = _parseTriageDraft(raw);   // enforces no priority_score / priority_band keys
     return draft;
   } finally {
     await thinkingChat.session.close();
   }
   ```

   Persist a flag `triage.thinkingModeUsed` (transient field on the run log, not in the schema) so device reports can distinguish thinking vs non-thinking outputs.

5. **TTFT instrumentation:** the existing `s2_spike_page.dart` already records `ttftMs`. Lift the same hooks into `gemma_session.dart` for `describe_photo` and `synthesize` so every Android run produces a per-turn TTFT. Dump them into `<app_files_dir>/runs/<packetId>/turns.jsonl` keyed by `observationId`.

**Acceptance:**

- Unit tests cover all four parse paths (good, null-followup, drift-string-followup, malformed).
- The integration test in (3) is green.
- A manual run on web (no Android needed) produces a `turns.jsonl` line per LLM turn.

### Phase 6 — Android audio capture

**Scope:** record mono 16 kHz WAV on Android, hand it to `Message.withAudio`, persist as `aud-N` evidence.

**Preconditions:** phase 2 (so `supportAudio` is wired) and phase 3 (so the schema enforces `sample_rate_hz=16000, channels=1`).

**Edits:**

1. Add `record: ^5.x` to `pubspec.yaml`. Choose the version that ships `RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1)`. Verify on `pub.dev` at start-of-work.

2. Manifest: add `<uses-permission android:name="android.permission.RECORD_AUDIO"/>` and the OpenCL `<uses-native-library>` entries from the flutter_gemma README (`libOpenCL.so` / `libOpenCL-car.so` / `libOpenCL-pixel.so`).

3. New widget under `apps/cairn_mobile/lib/features/describe/`: `AudioRecorder` (Android-only behind `Platform.isAndroid`). Web keeps the existing text fallback. The button states are `idle → recording → encoded`. Hard-cap duration at 30 s (schema). Show a level meter via `record`'s amplitude stream.

4. Wire into `DescribeScreen`:
   - On Android, after recording, call `controller.addAudio(bytes: wavBytes, durationS: d, sampleRateHz: 16000, channels: 1)` (the existing `SessionController.addAudio` already enforces these defaults).
   - Then fire an `orchestrator.describeAudio({observation_id, prompt_id: 'volunteer_audio_v1', asked_in, audio_ref, audio_bytes})` turn that, server-side, calls `chat.addQueryChunk(Message.withAudio(text: '...', audioBytes: bytes, isUser: true))` and parses the same `describe_photo`-style response (model description, tags, confidence, no bbox).
   - The resulting `Observation` has `imageRefs: []`, `audioRefs: ['aud-N']`, no `user_text` unless the user typed it.

5. **Do not** attempt combined image+audio in a single `Message`. The locked prompt is one observation per turn.

6. **Web fallback** stays as-is: text area, tagged `promptId: 'volunteer_note_v1'`, no audio asset.

**Acceptance:**

- `adb shell pm grant app.cairn.cairn_mobile android.permission.RECORD_AUDIO` then app records 5 s, the resulting `aud-1.wav` is saved under app-files, `ffprobe` (or `mediainfo`) confirms `mono / 16000 Hz / pcm_s16le`.
- Golden packet test (phase 3) is extended with an audio asset and stays green.
- A real Gemma 4 audio turn returns a JSON-parseable response on the test device.

### Phase 7 — File-backed vault and export

**Scope:** persist drafts and sealed packets across app restart, export PDF + JSON.

**Edits:**

1. Promote `path_provider` to a direct dep in `pubspec.yaml`.
2. New file `apps/cairn_mobile/lib/core/storage/evidence_vault_files.dart` implementing `EvidenceVault`:
   - `getApplicationSupportDirectory()` for `drafts/<packetId>.json` (mutable in-progress).
   - `getApplicationDocumentsDirectory()` (or `getExternalStorageDirectory()` for adb-pullable evidence) for `packets/<packetId>/packet.json`, `images/<ref>.jpg`, `audio/<ref>.wav`, `report.pdf`.
   - Atomic write via `File.writeAsBytes(..., flush: true)` to a `.tmp` then `rename`.
3. `SessionController.startNew()` writes a draft on every mutator. `sealAndSave(...)` writes the final packet + assets under `packets/`.
4. PDF: add `pdf: ^3.x` and `printing: ^5.x`. Build a 1–2 page report from the sealed packet (front photo, triage band, rationale bullets, hazards, attestation). Save under `packets/<id>/report.pdf`.

**Acceptance:**

- Kill-and-relaunch the app mid-flow; the draft restores.
- After "Finalize" the operator runs `adb pull /sdcard/Android/data/app.cairn.cairn_mobile/files/packets/<id>` and the directory contains `packet.json`, `report.pdf`, the original photos, and audio.
- `packet.json` validates against the JSON schema (Python `pytest`).

### Phase 8 — Device eval runner (`device_adb`)

**Scope:** make `scripts/eval/eval_baseline.py --runner device_adb:...` actually work, so D16 is honest.

**Edits:**

1. New file `scripts/cairn/runners/adb.py`:
   - `class AdbDeviceRunner(LlmRunner)` with `__init__(self, device, pkg, ...)`.
   - `run(...)` pushes the prompt + image to the device's app-files dir under a known path, broadcasts an `Intent` (`am broadcast -a app.cairn.RUN_EVAL --es payload_path ...`), polls for the response file, parses `text` / `ttft_s` / `decode_tok_per_s`.
2. App side: register a `BroadcastReceiver` (Kotlin) and a Dart-side method channel that ingests the payload, calls `orchestrator.describePhoto(...)`, writes the response next to the request.
3. Update `scripts/eval/eval_baseline.py:35-41` to recognise `device_adb:<pkg>@<serial>` and instantiate the new runner.
4. Update `scripts/eval/README.md` to document the protocol.

**Acceptance:** running

```powershell
PYTHONPATH=scripts python -m eval.eval_baseline `
  --gold data\eval\gold.jsonl `
  --runner device_adb:app.cairn.cairn_mobile@<serial> `
  --strategy strict_schema `
  --out scripts\eval\reports\device_e2b_strict.json `
  --limit 5
```

produces a `summary.json` with `parse_fail_rate`, `median_ttft_s`, and 5 per-item rows.

### Phase 9 — S1 / S2 device gates and final report

**Scope:** capture the device evidence the cairn pitch requires.

**Commands (operator, recorded into the runlog):**

```powershell
python scripts\spikes\s1_adb_harness.py `
  --device <serial> --pkg app.cairn.cairn_mobile `
  --out scripts\spikes\out\s1_e2b_<UTC>.json --duration 120 --hz 1
```

S2: launch app, navigate to `/spike`, run the burst (after phase 6 the page can also exercise the audio path), download `s2_report.json` from the export icon, commit it under `scripts/spikes/out/`.

End-to-end: walk one synthetic survey on the device, finalize, pull the packet+PDF, validate the packet against the schema.

**Acceptance checklist (final):**

- [ ] `s1_e2b_<timestamp>.json` exists with non-empty per-second samples.
- [ ] `s2_report.json` exists; ≥ 9 of 10 prompts return parseable JSON.
- [ ] One sealed packet exists on disk and validates against `evidence_packet_v1.schema.json` via Python `jsonschema`.
- [ ] One `report.pdf` exists.
- [ ] Per-turn `turns.jsonl` includes load-time, TTFT, decode chars/s on at least one `describe_photo` and one `synthesize` turn.
- [ ] Device thermal/crash log notes appended to runlog.

### Phase 10 — CI

**Scope:** pre-empt regressions; this is **not** "device CI" (we will not pay for a self-hosted Android runner). It is "every PR has a green Flutter+Python smoke build."

**New file `.github/workflows/ci.yml`:**

- Job `python`: matrix on `3.12`. `pip install -e scripts` (or `pip install -r requirements.txt`), `pytest -q scripts/tests`, `python -m data.validate_seeds`.
- Job `flutter`: `subosito/flutter-action@v2` pinned to the same Flutter version `flutter doctor` reports on the operator's machine. `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --debug --target-platform android-arm64`.
- Job `schema`: re-validates every `*.golden.json` under `apps/cairn_mobile/test/golden/` against `docs/schema/evidence_packet_v1.schema.json`.

**Acceptance:** PR opened against a branch, all three jobs green.

---

## 4. Test matrix

| Layer | File | Asserts |
|---|---|---|
| Dart unit | `test/session_controller_test.dart` (existing) | `obs-N` allocation, protocol_answers deltas, photo/audio enrolment. |
| Dart unit (new) | `test/evidence_packet_validator_test.dart` | closed-enum `model_tags`, `obs-N` regex, audio constants, box_2d range. |
| Dart golden (new) | `test/evidence_packet_golden_test.dart` | sealed packet bytes match `golden/evidence_packet_v1.golden.json`. |
| Dart unit (new) | `test/orchestrator_followup_test.dart` | `{followup: null}`, `{followup: {...}}`, drift string, malformed. |
| Dart widget (new) | `test/humility_screen_test.dart` | renders question / skips when null / surfaces parse error. |
| Python | `scripts/tests/test_constants_parity.py` (extend) | per-platform model artifact mirrors Dart. |
| Python (new) | `scripts/tests/test_evidence_packet_v1_golden.py` | golden JSON validates against schema. |
| Device manual | runlog | S1 + S2 + finalize, see phase 9. |

---

## 5. Risks and mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `flutter_gemma 0.14.x` ships an API rename that breaks `gemma_session.dart` | Medium | Phase 2 is an isolated commit; revert is one git op. Tests will catch it. |
| `.litertlm` 2.58 GB download fails midway on first device run | High on slow networks | `flutter_gemma` supports resumable progress; surface the percent in UI; keep cached artifact across launches via `path_provider`. |
| Target device lacks OpenCL → GPU backend silently falls back to CPU and TTFT 10× regresses | Medium | Phase 1 records `ro.hardware.egl`; phase 9 logs `PreferredBackend` actually used; if CPU, mark the eval as CPU-only. |
| Gemma 4 thinking mode is slow enough that volunteers abandon | Medium | Surface a progress spinner with "thinking…" copy; keep non-thinking fallback toggle in `/spike`. |
| Audio modality on Gemma 4 returns gibberish for survey-relevant cues (gas, water, voices) | High (model not specifically trained on this) | Audio is **optional**, never gates triage. The schema allows zero audio assets. |
| `RECORD_AUDIO` runtime denial | Low | Show a one-time rationale dialog; on denial, hide the recorder and show the text fallback. |
| App-specific external dir is wiped on app uninstall | By design | Document in QUICKSTART; the report PDF is meant to be exported via Share, not survive an uninstall. |
| HF repo path renames (`gemma-4-E2B-it.litertlm` becomes `…-int4.litertlm`) | Low–medium | Pin a known-good commit SHA in `model_registry.dart`'s URL where HF supports it; otherwise add a 404-then-fail-loud path. |
| 0.13.6 fallback path: thinking mode unavailable on Android | Certain if §2.1 is overridden | Run synthesize without thinking; mark `triage.thinking_mode_used = false` in the runlog; add a release-note line. |

---

## 6. Open questions (must be answered, not assumed)

1. Target device(s) for phase 9? Specifically: SoC family (snapdragon vs tensor vs mediatek), free storage on `/sdcard`, RAM, Android version. Drives §2.2 and the OpenCL declaration set.
2. Are we shipping a signed release APK in phase 9, or only `--debug`? If release, signing config + `proguard-rules.pro` for `flutter_gemma` need verification.
3. Is the engineer-side console in scope for the same milestone as this plan? v3 default: **no** (deferred). Operator override changes phases 7 and 9.
4. Does the operator have an HF token? Needed for some `litert-community/*` repos that gate access; the public Gemma 4 repos currently don't, but this can change.

---

## 7. References

- `flutter_gemma` 0.13.6 docs index: https://pub.dev/documentation/flutter_gemma/0.13.6/
- `flutter_gemma` `Message`: https://pub.dev/documentation/flutter_gemma/0.13.6/core_message/Message-class.html
- `flutter_gemma` `InferenceModel.createChat`: https://pub.dev/documentation/flutter_gemma/0.13.6/flutter_gemma_interface/InferenceModel/createChat.html
- `flutter_gemma` `FlutterGemma.getActiveModel`: https://pub.dev/documentation/flutter_gemma/latest/core_api_flutter_gemma/FlutterGemma/getActiveModel.html
- `flutter_gemma` changelog (for 0.13.x → 0.14.0 features): https://pub.dev/packages/flutter_gemma/changelog
- HF model files: https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/tree/main
- LiteRT-LM project: https://github.com/google-ai-edge/LiteRT-LM
- MediaPipe Android LLM guide: https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference/android
- Flutter Android deployment / `applicationId`: https://docs.flutter.dev/deployment/android
- Android scoped storage: https://developer.android.com/training/data-storage/app-specific
- Android 13 media perms: https://developer.android.com/about/versions/13/behavior-changes-13

---

## 8. Diff vs v2 (so reviewers don't have to re-read v2)

**Kept from v2 (verified correct):**
- Android platform restoration command shape and package id `app.cairn.cairn_mobile`.
- S1 harness uses `--pkg`.
- Per-platform model artifact split (`.litertlm` for Android, `-web.task` for web).
- `obs-N` schema fix.
- Drop `user_note` / `user_override` from `model_tags`.
- `ask_followup` nullable-object contract.
- Synthesize must use thinking-mode session.
- `RECORD_AUDIO` runtime perm; mono 16 kHz WAV.
- No `READ_EXTERNAL_STORAGE`.
- Promote `path_provider` to direct dep.
- Implement `device_adb` runner or stop claiming D16.

**Corrected from v2:**
- `Message.withAudio` and `Message.withImage` are real 0.13.6 constructors; the base `Message(...)` positional constructor is **undocumented for combined image+audio** — v3 explicitly avoids combined turns rather than guessing.
- v2 said "camera permission only if direct camera capture is implemented." The current `photos_screen.dart:126` already calls `ImageSource.camera`, so `<uses-permission android:name="android.permission.CAMERA"/>` **is** required. Phase 1 manifest must add it.
- `flutter_gemma` 0.13.6 does **not** ship Gemma 4 thinking mode on Android (changelog evidence above); v2 was silent on this and would fail at phase 5. v3 makes the upgrade an explicit phase 2 decision.
- v2's parity test note was a one-liner; v3 specifies the new struct shape and the test to extend.
- `getActiveModel` does take `supportAudio` — v3 wires it in tandem with `createChat(supportAudio: ...)`. v2 only mentioned `createChat`.

**Added in v3 (not in v2):**
- Strategic decisions block (§2) — version pin, NPU artifact, console scope, schema freeze.
- Dart packet validator + Dart/Python golden packet tests (§3.3 / §4).
- Per-turn TTFT instrumentation pipeline into `turns.jsonl` (§3.5).
- Phase 10 CI workflow (no device).
- Open-questions block, risk register with likelihoods.
- Explicit rollback per phase.
- Explicit defer of `apps/cairn_console/` rather than silent omission.
- `s2_probe.jpg` blocker called out in §1.1; phase 9 acceptance requires it before S2.
- `assets/schema/evidence_packet_v1.schema.json` bundling (so the validator works offline on device).
- Model URL composes through `hfDownloadUrlFor(TargetPlatform)` so platform branching lives in one place.
