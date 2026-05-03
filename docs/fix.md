# Fix: Photos Screen OOM Crash on 2nd+ Capture

## Root Cause

After photo 1 is **described**, the Gemma model is fully loaded (GPU + ~1.5 GB RAM). When the user taps Capture for photo 2:

1. `unload()` is called → GemmaSession.close() is async; GPU/RAM not yet released
2. Camera ISP starts up — it also needs GPU/OpenCL + its own RAM allocation
3. App heap at this point: model weights (partial GC) + photo-1 bytes + camera buffers = **OOM**
4. OS kills the process

The previous fix (unload before camera) worked for photo 1 because at that point the model was loaded but **no photo bytes were held**. By photo 2, both exist simultaneously during the unload/camera overlap window.

## Fix: Two-Phase Capture → Describe

**Core idea:** never load the model while any camera capture is possible.
Split the screen into two clearly separated phases:

```
Phase A (Capture)   → model is NEVER loaded; all camera work happens here
Phase B (Describe)  → camera is NEVER used; model loads once, describes all photos
```

---

## Phase A — Capture all photos (model absent)

- On `_initAsync()` entry: call `unload()` unconditionally (whether session is null or not). The model must be gone before any camera intent fires.
- Each Capture button: calls `pickImage()` directly — **no unload/reload**. Saves bytes to disk via `persistCapturedBytes`, enrolls in draft. Slot status → `captured`.
- No model loading banner. No model needed at all in Phase A.
- All 5 slots show Capture/Retake buttons freely.
- A **"Describe photos (N)"** button appears in the bottom action area as soon as ≥ 1 required photo is `captured`. It shows the count of captured slots.

## Phase B — Describe all (model loads once)

- Triggered when user taps "Describe photos (N)".
- Capture buttons become disabled (no camera while model is loading/running).
- Model loads once with `SessionProfile.vision`.
- Each captured slot is described **sequentially** — slot status cycles through `captured → describing → done/error`.
- A top banner shows "Describing photo N of M…".
- On completion: model **stays loaded** (the next screen, Audio, immediately switches to audio profile so no double-load).
- **"Continue →"** button becomes active when all 4 required slots are `done`.

---

## Slot Status State Machine

```
empty → captured → describing → done
                              ↘ error → (retry describe)
```

Add `captured` as a new `_SlotStatus` value. The UI for `captured` looks like `done` visually (thumbnail shown) but with an amber chip "ready" instead of green "described".

---

## Changes Required

### 1. `lib/features/photos/photos_screen.dart`

**`_SlotStatus` enum** — add `captured`:
```dart
enum _SlotStatus { empty, captured, describing, done, error }
```

**`_initAsync()`** — unload unconditionally on entry:
```dart
// Always unload on entry — Phase A must never have the model loaded
await ref.read(gemmaSessionProvider.notifier).unload();
```
Remove the `if (session == null && draft != null)` reload block entirely.

**`_capture(_SlotSpec spec)`** — remove ALL unload/reload logic:
```dart
Future<void> _capture(_SlotSpec spec) async {
  await _pendingSlotStore?.save(spec.slot);

  XFile? picked;
  try {
    picked = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
  } catch (_) {
    if (!mounted) return;
    picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
  }

  await _pendingSlotStore?.clear();
  if (picked == null) return;
  await _processPickedFile(spec, picked); // enroll + persist; do NOT call _describe yet
}
```

**`_processPickedFile()`** — stop at enroll, do not call `_describe()`:
```dart
// After controller.addPhoto() + persistCapturedBytes():
setState(() => _state[spec.slot]!.status = _SlotStatus.captured);
// Do NOT call _describe() here
```

**New `_describeAll()`** — triggered by "Describe photos" button:
```dart
Future<void> _describeAll() async {
  setState(() { _modelLoading = true; _modelLoadingLabel = 'Loading Gemma…'; });
  try {
    await ref.read(gemmaSessionProvider.notifier).load(profile: SessionProfile.vision);
  } catch (e) {
    setState(() => _modelLoading = false);
    return;
  }
  setState(() => _modelLoading = false);

  final toDescribe = _slots.where(
    (s) => _state[s.slot]!.status == _SlotStatus.captured
  ).toList();

  for (int i = 0; i < toDescribe.length; i++) {
    final spec = toDescribe[i];
    final st = _state[spec.slot]!;
    if (!mounted) return;
    setState(() {
      _modelLoadingLabel = 'Describing photo ${i+1} of ${toDescribe.length}…';
      st.status = _SlotStatus.describing;
    });
    final obsId = ref.read(sessionControllerProvider.notifier).generateObservationId();
    await _describe(spec, st.thumb!, st.ref!, obsId);
  }
}
```

**`build()` bottom action area** — replace single `FilledButton` with conditional logic:
- If any required slot is `empty`: "Capture all 4 reference photos" (disabled)
- If all required are `captured` or better, and some are still `captured`: "Describe photos (N)" → calls `_describeAll()`
- If all required are `done`: "Continue →"

**`_checkLostData()`** — after recovering file, set slot to `captured` (not `describing`), let `_describeAll()` handle it. Or auto-trigger describe for just the recovered slot if model is already loaded.

**`_StatusChip`** — add `captured` case:
```dart
_SlotStatus.captured => ('ready', Colors.orange.shade800, Colors.orange.shade50),
```

### 2. No changes needed to:
- `providers.dart`
- `session_controller.dart`
- `start_screen.dart`
- Any tests (the `_processPickedFile` contract is unchanged at the data layer)

---

## UX Flow (after fix)

```
/photos screen opens
  → model unloaded immediately (silent)

User taps Capture [Front] → camera → photo → "ready" chip
User taps Capture [Ground floor] → camera → photo → "ready" chip
User taps Capture [Cracks] → camera → photo → "ready" chip
User taps Capture [Foundation] → camera → photo → "ready" chip
  (optional: Capture [Extra])

"Describe photos (4)" button appears

User taps "Describe photos (4)"
  → banner: "Loading Gemma…" (~15 s, first load)
  → banner: "Describing photo 1 of 4…" → slot turns green
  → banner: "Describing photo 2 of 4…" → slot turns green
  → banner: "Describing photo 3 of 4…" → slot turns green
  → banner: "Describing photo 4 of 4…" → slot turns green
  → "Continue →" button appears

User taps Continue → /audio
```

---

## Why this is safe / no data loss

- Photo bytes are persisted to disk in `persistCapturedBytes()` before description — unchanged.
- `PendingSlotStore` recovery (`_checkLostData`) still works: recovered file → `captured` status → described in next `_describeAll()` call.
- If the app is killed after Phase A (all photos captured, model unloaded), draft resume (`start_screen.dart` → `restoreDraft`) takes the user back to /photos with the draft intact. The captured-but-not-described slots will be `empty` in the UI (since `_SlotState` is in-memory), but the photo bytes are in the draft. A banner can remind the user to tap "Describe photos".

---

## Test impact

- Update `test/photos_screen_test.dart` (if it exists): `_processPickedFile` now leaves slot as `captured`; need to call `_describeAll()` to get to `done`.
- `dart analyze` and existing 331 tests should be unaffected (no public API changes).
