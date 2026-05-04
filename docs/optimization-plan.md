# Cairn Optimization Plan

**Date:** 2026-05-03
**Status:** Grilled, source-verified implementation plan
**Scope:** Android-first optimization and correctness plan for `apps/cairn_mobile`
**Device target:** Samsung S23 FE family, `SM-S711B`, Exynos 2200, Android API 36, from `docs/android_repivot_v5_runlog.md`
**Current manifest pin:** `flutter_gemma: 0.14.0`
**Recommended target:** `flutter_gemma: ^0.14.2`

This file replaces the previous optimization plan after a file-by-file audit of
the app code, project docs, schema, prompt, local package cache, and current
upstream docs. Do not treat `docs/optimization-research.md` as implementation
truth; it is useful background, but several claims need gates or correction.

## Source Precedence

When sources conflict, use this order:

1. Live source in `apps/cairn_mobile/lib`, tests, and `docs/schema/evidence_packet_v1.schema.json`.
2. `docs/android_repivot_v5_runlog.md` for validated Android device/toolchain evidence.
3. Current upstream docs checked on 2026-05-03:
   - `flutter_gemma` pub.dev changelog and README.
   - Google Gemma vision docs.
   - Google AI Edge MediaPipe LLM Inference docs.
4. Older overview docs (`README.md`, `PROJECT_OVERVIEW.md`, archived repivot plans) only as history.

## What Changed After Grilling

The old plan was too optimistic in three ways:

- It treated some optimizations as safe before the app could measure them on the
  target device.
- It missed several correctness bugs that can block final packets or hide
  performance evidence.
- It assumed APIs such as multi-image batch inference and unified capability
  sessions without proving that the current package interface supports them.

The implementation order below fixes correctness and observability first. Speed
work starts only after `turns.jsonl` and upstream `[*/perf]` logs can prove
which phase is slow.

## 0. Correctness Blockers

These are not optional optimizations. Fix them before claiming a performance
baseline.

### BUG-0: Skip GPS Creates Schema-Invalid Packets

**Files**

- `apps/cairn_mobile/lib/core/location/location_service.dart`
- `apps/cairn_mobile/lib/features/location/location_screen.dart`
- `apps/cairn_mobile/lib/core/models/evidence_packet_validator.dart`
- `docs/schema/evidence_packet_v1.schema.json`
- `apps/cairn_mobile/test/location_service_test.dart`

**Evidence**

`docs/schema/evidence_packet_v1.schema.json` requires
`location.accuracy_m >= 0`. The Dart validator mirrors this in
`EvidencePacketValidator._checkLocation`.

Current code defines:

```dart
const kSkippedGeoLocation = GeoLocation(
  lat: 0.0,
  lng: 0.0,
  accuracyMeters: -1.0,
  addressText: '[GPS unavailable - location not recorded]',
);
```

`SessionController.sealAndSave()` validates before saving. Therefore any user
who taps Skip GPS can reach Report and then fail finalization.

**Fix**

For the current v1 schema, make Skipped Location schema-valid:

```dart
const kSkippedGeoLocation = GeoLocation(
  lat: 0.0,
  lng: 0.0,
  accuracyMeters: 0.0,
  addressText: '[GPS unavailable - location not recorded]',
);

bool isSkippedLocation(GeoLocation loc) =>
    loc.lat == 0.0 &&
    loc.lng == 0.0 &&
    loc.accuracyMeters == 0.0 &&
    loc.addressText == '[GPS unavailable - location not recorded]';
```

Do not use negative numeric sentinels in schema-constrained fields. If a future
schema needs explicit absence semantics, add a schema field such as
`location.status`; do not overload `accuracy_m`.

**Tests**

- Update `location_service_test.dart` to assert skipped GPS validates through
  `EvidencePacketValidator`.
- Add a `sealAndSave` regression: set skipped location, compute triage, save,
  and assert no `SchemaValidationException`.

### BUG-1: `ModelType.gemmaIt` Is Wrong For Gemma 4, But The Fix Requires The Upgrade

**Files**

- `apps/cairn_mobile/lib/core/llm/gemma_session.dart`
- `apps/cairn_mobile/pubspec.yaml`
- `apps/cairn_mobile/tool/api_probe.dart`

**Evidence**

Current code uses `ModelType.gemmaIt` in both `FlutterGemma.installModel()` and
`InferenceModel.createChat()`.

The local `flutter_gemma-0.14.0` cache does not expose `ModelType.gemma4` in
`lib/core/model.dart`, so changing the enum before upgrading will not compile.
The upstream `flutter_gemma` 0.14.1 changelog says the Gemma 4 E2B/E4B example
entries switched to `ModelType.gemma4`, and 0.14.1 introduced the Gemma 4
routing path. The 0.14.2 release is current on 2026-05-03.

**Fix order**

1. Upgrade `flutter_gemma` to `^0.14.2`.
2. Run `flutter pub get`.
3. Update API probe to prove `ModelType.gemma4` exists.
4. Change both call sites in `gemma_session.dart` from `ModelType.gemmaIt` to
   `ModelType.gemma4`.

**Tests**

- Compile-time probe for `ModelType.gemma4`.
- Unit/API wrapper test or probe that proves install and chat use the same model type.
- `flutter analyze` and `flutter test`.

### BUG-2: Upgrade To `flutter_gemma` 0.14.2 For Instrumentation And History Safety

**File**

- `apps/cairn_mobile/pubspec.yaml`

**Evidence**

Current manifest pins `flutter_gemma: 0.14.0`.

Upstream 0.14.2 adds `[*/perf]` logs for dylib load, engine creation, prefill,
and decode. It also fixes Gemma 4 escape-token leakage in chat history. Those
two changes are prerequisites for measuring or safely changing history handling.

Important correction: 0.14.0 already introduced the shared Dart FFI path for
Android `.litertlm` models. Do not describe 0.14.2 as the first FFI/LiteRT-LM
release. The reason to upgrade is measurement, Gemma 4 routing availability
through 0.14.1, history cleanup, web build fixes, and better platform failure
messages.

**Fix**

```yaml
dependencies:
  flutter_gemma: ^0.14.2
```

After this, rerun:

```powershell
flutter pub get
dart analyze lib test
flutter test
dart analyze tool/api_probe.dart
```

### BUG-3: Start Screen Loads A Model That Photos Immediately Unloads

**Files**

- `apps/cairn_mobile/lib/features/start/start_screen.dart`
- `apps/cairn_mobile/lib/features/photos/photos_screen.dart`
- `apps/cairn_mobile/lib/core/providers.dart`

**Evidence**

`StartScreen` disables "Start building screening" until a model is loaded.
`PhotosScreen.initState()` then unconditionally calls
`gemmaSessionProvider.notifier.unload()` to protect camera capture from OOM.

Resume does the same waste:

- `StartScreen._resumeDraft()` reloads `SessionProfile.vision`.
- If the draft already has photos, it navigates to `/photos`.
- `PhotosScreen._initAsync()` immediately unloads the model.

This adds a model load to the critical path before any photo can be captured,
then discards it. It is a correctness/UX bug and a large performance bug.

**Fix**

- Split "model installed/available" from "model currently loaded".
- Allow Start without a live model after install has succeeded or after the
  model is already in the package cache.
- Keep `PhotosScreen` as the only place that loads the vision model, and only
  after capture when the user taps Describe photos.
- On resume, navigate directly to the right screen; do not reload vision before
  `/photos`.

**Tests**

- Widget test: Start can create a session without a live `GemmaSession`.
- Resume test: draft with photos navigates to `/photos` without calling
  `load(profile: SessionProfile.vision)`.

### BUG-4: Audio Describe Is Effectively Unreachable And The Prompt Has No `describe_audio` Task

**Files**

- `apps/cairn_mobile/lib/features/audio/audio_screen.dart`
- `apps/cairn_mobile/lib/core/llm/orchestrator.dart`
- `apps/cairn_mobile/assets/prompts/system_prompt_v1.txt`
- `docs/prompts/system_prompt_v1.txt`

**Evidence**

`AudioScreen._maybeDescribeAudio()` only runs Gemma if the current session has
`supportAudio == true`. The normal route into `/audio` comes from photos after a
vision session has been loaded, so the current session either has
`supportAudio == false` or has been unloaded. No screen currently calls
`load(profile: SessionProfile.audio)` before audio describe.

Separately, `GemmaOrchestrator.describeAudio()` sends:

```dart
'task': 'describe_photo'
```

but reports errors as `describe_audio`, and the system prompt only lists
`describe_photo`, `ask_followup`, `protocol_answer`, and `synthesize`.

**Decision required before implementation**

Pick exactly one contract:

- Option A: Audio is record-only in v1. Remove automatic `describeAudio()` from
  the UI, keep audio assets in the packet, and remove the dead profile path from
  the user flow until quality is proven.
- Option B: Audio is model-authored. Add a real `describe_audio` task to docs
  and assets, sync prompts, load `SessionProfile.audio` explicitly after WAV
  enrollment, record the turn, and accept the extra model reload.

**Recommendation**

Use Option A for the optimization sprint unless audio description is required by
a product gate. It removes an unmeasured model reload from the critical path and
keeps audio capture as reliable evidence.

### BUG-5: `turns.jsonl` Is Not Complete

**Files**

- `apps/cairn_mobile/lib/features/photos/photos_screen.dart`
- `apps/cairn_mobile/lib/features/audio/audio_screen.dart`
- `apps/cairn_mobile/lib/features/humility/humility_screen.dart`
- `apps/cairn_mobile/lib/features/synthesize/synthesize_screen.dart`
- `apps/cairn_mobile/lib/core/state/session_controller.dart`

**Evidence**

`TurnRecord` exists and `sealAndSave()` persists `turns.jsonl`, but only
`SynthesizeScreen` currently calls `recordTurn()`.

The runlog says every orchestrator call is logged, but the source does not do
that. This blocks trustworthy performance baselines because the slow photo turns
are absent from `turns.jsonl`.

**Fix**

Record a turn after every successful orchestrator call:

- `describe_photo`
- `describe_audio` if retained
- `ask_followup`
- `synthesize`

Protocol currently uses tap-only UI and does not call `protocolAnswer()`.
If a free-text protocol path is restored, record `protocol_answer` too.

Add a small module if needed:

```dart
TurnRecord turnRecordFromResult({
  required String task,
  String? observationId,
  required int ttftMs,
  required int wallclockMs,
  required int outputCharCount,
  int thinkingChars = 0,
})
```

The module earns its depth if it becomes the one place that maps orchestrator
results to provenance records.

### BUG-6: Shared JSON Uses A Hand-Written Encoder That Can Produce Invalid JSON

**File**

- `apps/cairn_mobile/lib/features/report/report_screen.dart`

**Evidence**

`_PrettyEncoder` only escapes double quotes in strings. It does not escape
backslashes, control characters, newlines, tabs, or map keys. Any observation or
address containing those characters can produce invalid shared JSON.

**Fix**

Replace `_PrettyEncoder` with the standard encoder:

```dart
import 'dart:convert';

final json = const JsonEncoder.withIndent('  ').convert(packet.toJson());
```

Delete `_PrettyEncoder`.

**Tests**

- Add a packet with a newline, quote, and backslash in `model_description`.
- Assert shared JSON decodes through `jsonDecode`.

### BUG-7: Contract Validation Is Close, But Still Has Holes

**Files**

- `apps/cairn_mobile/lib/core/llm/orchestrator.dart`
- `apps/cairn_mobile/lib/core/models/evidence_packet_validator.dart`
- `apps/cairn_mobile/test/orchestrator_contract_test.dart`

**Holes**

- `describePhoto()` checks bbox length and range but does not enforce
  `y1 < y2` and `x1 < x2`, even though the system prompt requires it.
- `EvidencePacketValidator._checkBbox()` has the same shape gap.
- `protocolAnswer()` checks that the delta has exactly one key but does not
  check that the key is one of the six schema protocol keys before returning.
  `SessionController.applyProtocolDelta()` throws later, but locality is worse:
  the orchestrator should reject invalid model output at the model contract seam.

**Fix**

- Enforce bbox ordering in both orchestrator and validator.
- Add an allowed protocol key set to the orchestrator, preferably derived from
  the same constants used by `SessionController` or the validator.

### BUG-8: Bootstrap Permission Gate Contradicts The Flow

**File**

- `apps/cairn_mobile/lib/features/bootstrap/bootstrap_screen.dart`

**Evidence**

Bootstrap requests camera, microphone, and location at app launch, then blocks
the app if any are denied. Later screens already support:

- Skip GPS.
- Skip audio.
- Camera fallback to gallery.

This creates a hard upfront block for permissions that the flow treats as
optional or deferrable.

**Fix**

Use feature-local permission prompts:

- Camera permission at capture time.
- Microphone permission at recording time.
- Location permission on the location screen, with Skip GPS.

Bootstrap should only initialize app prerequisites that truly must run before
navigation.

## 1. Measured Optimization Work

### MEASURE-1: Establish A Real Android Baseline

**Goal**

Create a reproducible timing baseline on `RZCX920ARVA` before changing
performance knobs.

**Required evidence**

- `turns.jsonl` has one entry per model turn.
- `flutter_gemma` `[*/perf]` lines captured from a release or profile build.
- Wall-clock timing for:
  - model install/download check
  - `engine_create`
  - first photo prefill
  - first photo decode
  - each subsequent photo prefill/decode
  - synthesis reload and decode

**Do not use**

- Emulator timings.
- Web timings.
- Inferred timing from UI spinners.
- Research estimates as proof.

### OPT-1: Inference Image Preprocessor

**Files**

- New: `apps/cairn_mobile/lib/core/images/image_preprocessor.dart`
- `apps/cairn_mobile/lib/core/llm/orchestrator.dart`
- `apps/cairn_mobile/lib/core/llm/model_registry.dart`
- `apps/cairn_mobile/lib/features/photos/photos_screen.dart`

**Evidence**

Google Gemma vision docs state that Gemma 4 uses variable resolution with token
budgets of 70, 140, 280, 560, or 1120 tokens, and that lower-resolution images
process faster while preserving less detail. `flutter_gemma` does not expose an
image token budget parameter, so Cairn can only control the bytes sent to
`Message.withImage()`.

Current capture uses `maxWidth: 1600, imageQuality: 85`, then sends those same
bytes to inference.

**Implementation**

- Preserve original capture bytes in `SessionDraft.photos` and the report.
- Add preprocessing only on the inference path.
- Bound the longest edge, preserving aspect ratio. Do not force every image into
  a square unless the model/package docs prove that is required.
- Start with `maxLongEdgePx: 512` as a benchmark candidate, not an eternal
  constant.

**Module shape**

```dart
abstract interface class ImagePreprocessor {
  Future<Uint8List> prepareForInference(Uint8List rawBytes);
}

final class BoundedImagePreprocessor implements ImagePreprocessor {
  const BoundedImagePreprocessor({required this.maxLongEdgePx});
  final int maxLongEdgePx;
}

final class PassthroughImagePreprocessor implements ImagePreprocessor {
  const PassthroughImagePreprocessor();
}
```

Two adapters make this a real seam:

- Production: `BoundedImagePreprocessor`.
- Tests/diagnostics: `PassthroughImagePreprocessor`.

**Gate**

Compare `[*/perf]` prefill and total wallclock for the same 5 images at:

- raw capture bytes
- 768 longest edge
- 512 longest edge

Pick the lowest size that preserves contract-valid output on the held-out photo
set. Do not claim an absolute speedup until this gate runs on the device.

### OPT-2: Prompt Output Constraints

**Files**

- `docs/prompts/system_prompt_v1.txt`
- `apps/cairn_mobile/assets/prompts/system_prompt_v1.txt`
- `apps/cairn_mobile/tool/sync_assets.ps1`
- `scripts/tests/test_prompt_sync.py`

**Mechanism**

`model_description` is currently unconstrained, so decode can spend time on
narrative prose. Add concise output limits to the prompt, then sync assets.

**Proposed constraint**

```text
For task = "describe_photo":
- model_description: maximum 3 sentences and maximum 60 words.
- model_tags: 1 to 5 values from the permitted enum.
- bbox_annotations: include only when localization is clear; at most 1 box per high-severity visible finding.
```

**Gate**

- Prompt sync tests pass.
- Evaluation samples remain schema-valid.
- `GemmaContractError` rate does not increase.

### OPT-3: SessionConfig, Max Tokens, And Temperature

**Files**

- New: `apps/cairn_mobile/lib/core/llm/session_config.dart`
- `apps/cairn_mobile/lib/core/llm/gemma_session.dart`
- `apps/cairn_mobile/lib/core/providers.dart`

**Evidence**

MediaPipe LLM Inference docs define `maxTokens` as input tokens plus output
tokens. The current app sets `maxTokens: 4096`; `flutter_gemma` README says to
reduce `maxTokens` for memory issues. The local 0.14.0 FFI implementation also
uses `maxTokens` for chat history token accounting and engine settings.

**Grilled correction**

Do not immediately change `4096 -> 2048` as a "safe" optimization. The system
prompt, image tokens, user JSON, and output must fit. Lower values need token
count and contract tests first.

**Implementation**

Move hardcoded values into a deep configuration module:

```dart
class SessionConfig {
  const SessionConfig({
    required this.maxTokens,
    required this.temperature,
    required this.preferredBackend,
    required this.maxNumImages,
  });

  static const vision = SessionConfig(...);
  static const audio = SessionConfig(...);
  static const synthesis = SessionConfig(...);
  static const standard = SessionConfig(...);
}
```

Candidate values to benchmark:

- Vision: `maxTokens` 4096, 3072, 2048; temperature 0.2 then 0.1.
- Synthesis: do not blindly lower temperature; it uses reasoning/rationale text.
- Standard: temperature 0.1 is likely appropriate for JSON mapping.

**Gate**

- No truncation.
- No increase in parse/contract failures.
- `[*/perf] engine_create` and peak memory improve enough to justify the
  smaller value.

### OPT-4: Move Existing Describe-All Loop Into The Orchestrator

**Files**

- `apps/cairn_mobile/lib/core/llm/orchestrator.dart`
- `apps/cairn_mobile/lib/features/photos/photos_screen.dart`

**Evidence**

`PhotosScreen._describeAll()` already sequences captured slots. The previous
plan described this like a new capability; it is actually a module-depth issue.

**Problem**

The UI owns sequencing, progress state, observation IDs, error isolation, and
eventual turn logging. That creates a shallow orchestrator interface: callers
must know too much about how multi-photo inference works.

**Fix**

Add an orchestrator-level stream:

```dart
Stream<DescribePhotoEvent> describeAll(List<DescribePhotoRequest> photos);
```

The orchestrator owns:

- preprocessing
- `describePhoto`
- contract errors
- turn-record metadata
- optional future batching fallback

The UI owns:

- slot status rendering
- retry buttons
- navigation

**Leverage**

Future batch inference changes one module instead of the photo screen.

**Locality**

Contract and performance bugs for photo inference live in the orchestrator path,
not scattered between UI and session code.

### OPT-5: History Retention Is An Experiment, Not A Planned Change Yet

**File**

- `apps/cairn_mobile/lib/core/llm/gemma_session.dart`

**Evidence**

Current code calls `chat.clearHistory()` after every generation. The old plan
assumed removing this would reduce repeated system-prompt prefill. That is not
proven for the LiteRT-LM FFI path.

0.14.2 is required first because it fixes Gemma 4 escape-token leakage in
history.

**Gate**

After upgrading:

1. Run 5 sequential photo descriptions with `clearHistory()`.
2. Run the same 5 without clearing between same-profile photo turns.
3. Compare `[*/perf] prefill`, TTFT, JSON validity, and cross-photo contamination.

Only remove per-turn clearing if:

- prefill/TTFT improves materially,
- no output references prior photos incorrectly,
- no contract failure rate increase appears on the held-out set.

### OPT-6: Backend Selection Must Be A Diagnostic Path First

**File**

- `apps/cairn_mobile/lib/core/llm/gemma_session.dart`

**Problem**

`PreferredBackend.gpu` is hardcoded. That may or may not be optimal on Exynos
2200. But loading both CPU and GPU during first user flow can be slower and can
increase memory pressure.

**Fix**

Start with a diagnostics-only benchmark command or hidden debug screen. Do not
run dual backend benchmarks during normal first-run UX until memory impact is
measured.

**Gate**

On the target phone, compare CPU and GPU for:

- text-only standard turn
- vision turn
- synthesis turn

Then decide whether adaptive selection is worth an implementation module.

### OPT-7: Batch Inference Is Blocked Until Multi-Image Semantics Are Proven

**Files**

- `apps/cairn_mobile/lib/core/llm/gemma_session.dart`
- `apps/cairn_mobile/lib/core/llm/orchestrator.dart`
- local package cache for `flutter_gemma`

**Evidence**

The app creates models with `maxNumImages: 5`, but current `GemmaSession`
supports only one `Uint8List? image` per `generate()` call.

The local 0.14.0 FFI implementation stores a single `_pendingImage`, not a list.
That means `maxNumImages: 5` does not by itself prove that a single chat turn can
pass five images through this wrapper.

**Gate before any implementation**

- Inspect 0.14.2 source after upgrade.
- Prove the public API can send more than one image in one turn.
- If it cannot, do not add `describePhotoBatch()` yet.

If the API supports it later, implement batch as an optional fast path with
sequential fallback. Never remove the sequential path; it is the reliability
adapter.

### OPT-8: Fine-Tuning Is Post-Benchmark Work

**Files**

- `finetune/phase_a_text_lora.py`
- `finetune/phase_b_vision_lora.py`
- `finetune/convert_mediapipe_lora.py`

**Correction**

Fine-tuning may reduce prompt length and improve task contract adherence, but it
is not a quick speed fix. It depends on:

- measured prompt/prefill contribution,
- available training data,
- conversion compatibility,
- on-device LoRA support for the selected `.litertlm` path.

The local 0.14.0 FFI implementation throws `UnsupportedError` for `loraPath` on
the `.litertlm` FFI path. Re-check after upgrading before planning LoRA for
Android `.litertlm`.

## 2. Architecture Deepening Opportunities

These use the `improve-codebase-architecture` vocabulary: Module, Interface,
Implementation, Depth, Seam, Adapter, Leverage, and Locality.

### ARCH-1: `GemmaSession` Needs A Deeper Configuration Interface

**Problem**

`GemmaSession._create()` owns lifecycle and tuning knobs. `maxTokens`,
`temperature`, backend, and image count are buried in the implementation.

**Solution**

`SessionConfig` becomes the interface for profile-specific inference behavior.
`GemmaSession` remains the lifecycle module.

**Benefits**

- More depth: one small config interface controls several native engine knobs.
- Better locality: profile tuning bugs live in one file.
- Better tests: config can be asserted without creating a native model.

### ARCH-2: Inference Image Policy Belongs Behind A Seam

**Problem**

Capture size, stored bytes, report bytes, and inference bytes are different
concepts but currently use the same byte array.

**Solution**

Add an `ImagePreprocessor` seam with production and passthrough adapters.

**Benefits**

- More leverage: callers pass raw capture bytes and get model-appropriate input.
- Better locality: image decoding/downscale bugs are isolated.
- Tests become the interface: input dimensions, output dimensions, and byte
  validity.

### ARCH-3: Turn Recording Should Be Attached To The Orchestrator Path

**Problem**

The existence of `TurnRecord` did not ensure it was called. Screens can forget
to record turns.

**Solution**

Either:

- make `GemmaOrchestrator.describeAll()` emit events that include a `TurnRecord`,
  or
- add a small `TurnRecorder` module used at each orchestrator call site.

**Recommendation**

Start with orchestrator events for photo flow because that is the slow path.
Avoid abstracting every task until at least two call sites use the same helper.

### ARCH-4: Location Absence Needs A Domain Term, Not A Numeric Sentinel

**Problem**

The app has a real domain concept: the volunteer explicitly skipped GPS or no
fix was available. The implementation encoded that as `accuracyMeters == -1`,
which violates the schema.

**Solution**

Use the domain term `Skipped Location` in `CONTEXT.md` and keep v1 packets
schema-valid. If richer semantics are needed, add them in a schema revision.

### ARCH-5: Packet JSON Encoding Is A Module, Not A Widget Detail

**Problem**

Report UI owns custom JSON encoding. That implementation is shallow and wrong.

**Solution**

Delete the custom encoder and use `JsonEncoder.withIndent`. If export behavior
grows, move it to a `PacketExporter` module.

### ARCH-6: Bootstrap Permission Logic Is Too Shallow

**Problem**

Bootstrap asks for all permissions and blocks on all denials, while feature
screens contain the real domain handling.

**Solution**

Delete permission gating from bootstrap and let feature modules own their
permission interfaces. Camera, audio, and location have different recovery
semantics; one bootstrap gate cannot represent them correctly.

## 3. Implementation Roadmap

### Sprint 0: Correctness And Contract Repair

1. Fix Skipped Location to be schema-valid and update tests.
2. Replace `_PrettyEncoder` with `JsonEncoder.withIndent`.
3. Remove Start/Resume live-model requirement and wasted reload.
4. Decide audio contract: record-only now, or real `describe_audio` task.
5. Add bbox ordering and protocol key validation.
6. Move permission prompts out of Bootstrap.

**Gate**

```powershell
dart analyze lib test
flutter test
```

### Sprint 1: Upstream Upgrade And Measurement

1. Upgrade `flutter_gemma` to `^0.14.2`.
2. Prove `ModelType.gemma4` in `tool/api_probe.dart`.
3. Switch install/chat model type to `ModelType.gemma4`.
4. Capture `[*/perf]` logs on the physical device.
5. Ensure `turns.jsonl` records all successful model turns.

**Gate**

- `dart analyze lib test`
- `flutter test`
- one real-device full-flow smoke, or at minimum photo describe plus synthesize
  on `RZCX920ARVA`.

### Sprint 2: Conservative Speed Levers

1. Add prompt output constraints and sync prompt assets.
2. Add `SessionConfig`, but keep `maxTokens: 4096` until the first benchmark
   matrix runs.
3. Benchmark `maxTokens` 4096, 3072, 2048.
4. Benchmark vision temperature 0.2 vs 0.1.

**Gate**

- No contract regression.
- Timing evidence attached to the runlog.

### Sprint 3: Inference Image Policy And Orchestrator Depth

**STATUS: IMPLEMENTED — pending device benchmark gate**

1. ✅ `ImagePreprocessor` seam — `lib/core/images/image_preprocessor.dart`
   - `BoundedImagePreprocessor(maxLongEdgePx)` — downscales longest edge, aspect-ratio-preserving, uses `dart:ui`; images already within bound returned unchanged (zero re-encode cost).
   - `PassthroughImagePreprocessor` — no-op for baseline benchmarks and unit tests.
2. ✅ `inferenceMaxLongEdgePx: 768` added to `ModelSpec` and both registry entries (`e2b`, `e4b`).
3. ✅ Preprocessing wired into `GemmaOrchestrator.describePhoto` — preprocessor applied before every `_session.generate` call; original capture bytes in `SessionDraft` never modified.
4. ✅ `GemmaOrchestrator.describeAll(List<DescribePhotoRequest>)` stream — sealed `DescribePhotoEvent` hierarchy (`DescribePhotoStarted` / `DescribePhotoSucceeded` / `DescribePhotoFailed`); errors isolated per-photo; `TurnRecord` built by orchestrator and yielded in `DescribePhotoSucceeded`.
5. ✅ `PhotosScreen._describeAll()` rewritten to consume the `describeAll` stream.
6. ✅ `BoundedImagePreprocessor` wired from model spec in `orchestratorProvider`.
7. ✅ `TurnRecord` extracted to `lib/core/llm/turn_record.dart` to avoid circular dependency.

Test coverage added:
- `test/image_preprocessor_test.dart` — passthrough identity, bounded within-bounds no-op, downscale dimensions/ratio, benchmark dimensions (1600×900 → 768×432, 512×288).
- `test/describe_all_test.dart` — event ordering, `TurnRecord` fields, error isolation, preprocessor forwarding, empty batch, contract-error surfacing.
- `test/model_registry_platform_test.dart` — extended with `inferenceMaxLongEdgePx` group.

**Gate**

- Device benchmark for raw, 768px, and 512px inputs (`tool/benchmark_session_config.ps1`).
- Held-out photo set remains schema-valid and useful.

### Sprint 4: Measured Experiments — IMPLEMENTED (device gate pending)

Sprint 4 is fully implemented. All three experiment paths are wired and tested.
Device benchmarks are the remaining gate before any promotion.

#### OPT-5: History retention A/B — IMPLEMENTED

**What was built:**

- `SessionConfig.clearHistoryBetweenTurns` field added (default `true`).
- `GemmaSession._generateOnce` conditionally calls `chat.clearHistory()` when the
  field is `true`; skips it when `false`.
- `SessionConfig.visionHistoryRetained` constant: identical to `vision` but with
  `clearHistoryBetweenTurns: false`.
- `BENCH_CONFIG=vision_history_retained` dart-define activates the variant at build
  time via `providers.dart` `_benchConfigForKey`.
- Test: `test/history_retention_test.dart` (32 tests).

**Device gate (run on RZCX920ARVA):**

```powershell
# From apps/cairn_mobile:
.\tool\benchmark_session_config.ps1 -Variant vision_history_retained
```

Capture `[*/perf]` prefill/TTFT for 5 sequential photo descriptions.
Manually inspect each description to confirm obs[n] does not reference photo[n-1].
Promote (set production default `clearHistoryBetweenTurns: false`) only when:
- TTFT / prefill improves materially.
- Zero cross-photo contamination.
- `GemmaContractError` rate unchanged.

#### OPT-6: CPU/GPU backend diagnostic — IMPLEMENTED

**What was built:**

- `SessionConfig.visionCpu`, `synthesisCpu`, `standardCpu` constants.
- `SessionConfig.copyWith({PreferredBackend? preferredBackend, ...})` helper.
- `BENCH_BACKEND=cpu` dart-define: `providers.dart` `_applyBenchBackend` applies
  `copyWith(preferredBackend: PreferredBackend.cpu)` on top of any resolved config.
- `tool/benchmark_backend.ps1`: four-variant runner (vision_gpu, vision_cpu,
  synthesis_gpu, synthesis_cpu).
- Tests: `test/session_config_test.dart` — CPU variant groups + `copyWith` group.

**Device gate (run on RZCX920ARVA):**

```powershell
# From apps/cairn_mobile:
.\tool\benchmark_backend.ps1 -Variant vision_gpu    # GPU baseline
.\tool\benchmark_backend.ps1 -Variant vision_cpu    # CPU candidate
.\tool\benchmark_backend.ps1 -Variant synthesis_gpu # GPU baseline
.\tool\benchmark_backend.ps1 -Variant synthesis_cpu # CPU candidate
```

Compare `[FfiInferenceModelSession/perf] time_to_first_chunk_ms` and
`[Cairn/perf] phase=generate ttft=...ms` across variants.
If CPU is competitive or faster, update the corresponding `SessionConfig` production
constant's `preferredBackend`. Expected: GPU wins for vision (multimodal);
synthesis may be comparable.

#### OPT-7: Batch inference feasibility — IMPLEMENTED (finding: not supported)

**Finding:**

`flutter_gemma 0.14.2` exposes `Message.withImage(imageBytes: Uint8List)` — a
single-image message. There is no `Message.withImages()` constructor. The
`maxNumImages: 5` parameter controls the model's image-token capacity per turn, not
the number of images Cairn can send in one generation pass.

Calling `addQueryChunk()` multiple times before `generateChatResponseAsync()` is
undocumented and breaks the `InferenceChat` state machine.

**Consequence:**

The sequential `describeAll()` stream is the correct and only supported adapter.
Each `describe_photo` turn is one `generate()` call. This is documented in:
- `tool/api_probe.dart` (compile-time probe comment).
- `test/batch_feasibility_test.dart` (8 tests proving sequential correctness).

**Future:** If a future `flutter_gemma` version adds a multi-image message type,
re-run `dart analyze tool/api_probe.dart` and extend `GemmaOrchestrator`.

#### Sprint 3 image-size benchmark — benchmark runner added

```powershell
# From apps/cairn_mobile:
.\tool\benchmark_image_px.ps1 -Variant 768px   # production default (spec.inferenceMaxLongEdgePx)
.\tool\benchmark_image_px.ps1 -Variant 512px   # aggressive candidate
.\tool\benchmark_image_px.ps1 -Variant raw     # passthrough baseline (BENCH_IMAGE_PX=-1)
```

The `BENCH_IMAGE_PX` dart-define wires into `orchestratorProvider` in `providers.dart`.

4. Optional audio describe quality/performance gate if the product still wants
   model-authored audio observations.
   Status: Not yet benchmarked. The `describeAudio` path is fully wired;
   requires a separate device session to measure quality and latency.

### Sprint 5: Fine-Tuning

Start only after the measured profile shows prompt/prefill is still a dominant
cost and the selected `flutter_gemma` path supports the intended adapter.

## 4. Explicit Non-Goals For This Optimization Pass

- Do not replace device validation with emulator or web validation.
- Do not promise `<= 90 s` for five photos until the target device proves it.
- Do not lower `maxTokens` below the measured safe value.
- Do not pre-warm multiple sessions during normal UX until memory pressure is
  measured.
- Do not implement multi-image batch inference until the public package API
  proves it can send multiple images in one turn.
- Do not change `docs/schema/evidence_packet_v1.schema.json` just to preserve a
  negative sentinel; v1 can represent skipped GPS with a schema-valid value.

## 5. Verification Matrix

| Area | Required proof |
|---|---|
| Schema | `EvidencePacketValidator.validateOrThrow` accepts skipped GPS packets |
| JSON export | Shared packet JSON decodes with `jsonDecode` after special characters |
| Model type | Compile-time probe confirms `ModelType.gemma4`; install and chat use it |
| Turns | `turns.jsonl` contains every successful model turn |
| Prompt | docs and app prompt assets are byte-identical after sync |
| Image preprocessing | Output image dimensions and bytes are valid; device prefill improves |
| Max tokens | No truncation or contract increase at chosen value |
| History | No cross-photo contamination and lower TTFT/prefill before removing clear |
| Backend | CPU/GPU decision backed by target-device benchmark |
| Full flow | Manual Android run completes start to report on `RZCX920ARVA` |

## 6. References Checked On 2026-05-03

- `flutter_gemma` changelog: https://pub.dev/packages/flutter_gemma/changelog
  - 0.14.2 adds `[*/perf]` timing logs and fixes Gemma 4 history token leakage.
  - 0.14.1 introduces `ModelType.gemma4` routing and switches Gemma 4 E2B/E4B examples.
  - 0.14.0 moves Android `.litertlm` models to the Dart FFI LiteRT-LM path.
- `flutter_gemma` README: https://pub.dev/packages/flutter_gemma
  - `Message.withImage()` supports common image formats.
  - `supportImage` is required for multimodal model/chat creation.
  - Lower `maxTokens` can help memory issues, but must be measured.
- Google Gemma vision docs: https://ai.google.dev/gemma/docs/capabilities/vision
  - Gemma 4 supports variable resolution and token budgets.
  - Lower-resolution images process faster but lose detail.
- MediaPipe LLM Inference docs: https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference
  - `maxTokens` is input tokens plus output tokens.
- Local schema: `docs/schema/evidence_packet_v1.schema.json`
  - `location.accuracy_m` minimum is 0.
  - Protocol answer keys and model tags are closed enums.
- Local runlog: `docs/android_repivot_v5_runlog.md`
  - Physical target and previous automated gates.
