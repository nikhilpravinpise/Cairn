/// Screen 3 — **Walk around (4 required photos + optional 5th)**.
///
/// The volunteer walks the perimeter of the building and captures one photo
/// per FEMA P-154 reference view.
///
/// ### Two-Phase Capture → Describe (OOM fix)
///
/// **Phase A (Capture):** model is NEVER loaded. All camera work happens here.
/// Each capture enrolls the photo in the draft and persists bytes to disk.
/// Slots transition: `empty → captured`.
///
/// **Phase B (Describe):** camera is NEVER used. The user taps
/// "Describe photos (N)" which loads the model once, then describes every
/// captured slot sequentially. Slots transition:
/// `captured → describing → done/error`.
///
/// This separation prevents the OOM crash that occurred when the Gemma model
/// (~1.5 GB) and the camera ISP competed for GPU/RAM simultaneously on
/// resource-constrained Android devices (e.g. Samsung Android 16).
///
/// ### Android robustness (Phase 7)
///
/// On Android the camera intent may cause the host Activity to be destroyed
/// by the OS to reclaim RAM. Two mechanisms defend against data loss:
///
/// 1. **Lost-data recovery** — `initState` calls
///    `ImagePicker.retrieveLostData()`. If data is found the slot being
///    captured when the Activity was killed is read from [PendingSlotStore]
///    (a SharedPreferences-backed key written before every camera intent)
///    and the image is processed for that slot as normal.
///
/// 2. **Immediate byte persistence** — after `XFile.readAsBytes()` the raw
///    bytes are written to `<tmpDir>/cairn_capture/<packetId>/<ref>.jpg`
///    via [persistCapturedBytes] before the LLM turn starts. This ensures the
///    image survives image_picker cache eviction during a long LLM call.
///
/// Web-first notes:
/// - `image_picker` on web surfaces a native file-picker with a `capture`
///   attribute; on desktop browsers this falls back to a plain file chooser.
///   That's acceptable for Week-1 fallback.
/// - Dimensions are read from the decoded bytes via `ui.instantiateImageCodec`
///   so we stay off `dart:io`.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/io/photo_cache.dart';
import '../../core/llm/orchestrator.dart';
import '../../core/models/evidence_packet.dart';
import '../../core/photos/pending_slot_store.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/state/session_controller.dart';
import '../../core/widgets/flow_stepper.dart';

/// The four required reference views + one optional extra. Kept in display
/// order; prompt_ids match the locked system-prompt contract.
const _slots = <_SlotSpec>[
  _SlotSpec(
    slot: 'front',
    label: 'Front elevation',
    promptId: 'fema_p154_q01',
    hint: 'Stand across the street. Whole facade in frame.',
    required: true,
  ),
  _SlotSpec(
    slot: 'ground_floor',
    label: 'Ground floor',
    promptId: 'fema_p154_q02',
    hint: 'Corner view that shows first-story windows / openings.',
    required: true,
  ),
  _SlotSpec(
    slot: 'cracks',
    label: 'Visible cracks',
    promptId: 'fema_p154_q03',
    hint: 'Close-up of any diagonal / X-pattern / out-of-plane crack.',
    required: true,
  ),
  _SlotSpec(
    slot: 'foundation',
    label: 'Foundation',
    promptId: 'fema_p154_q04',
    hint: 'Sill plate / stem wall / any offset at the ground line.',
    required: true,
  ),
  _SlotSpec(
    slot: 'extra',
    label: 'Extra (optional)',
    promptId: 'fema_p154_qextra',
    hint: 'Anything else the algorithm should know about.',
    required: false,
  ),
];

class _SlotSpec {
  const _SlotSpec({
    required this.slot,
    required this.label,
    required this.promptId,
    required this.hint,
    required this.required,
  });
  final String slot;
  final String label;
  final String promptId;
  final String hint;
  final bool required;
}

/// Per-slot UI status. Kept *outside* the SessionDraft because the draft is
/// append-only and doesn't know about in-flight LLM turns.
enum _SlotStatus { empty, captured, describing, done, error }

class _SlotState {
  _SlotState({required this.status});
  _SlotStatus status;
  String? ref; // 'img-N' once the draft accepts the photo
  Uint8List? thumb; // shown in the card; identical to what the draft stores
  Object? error;
}

class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  final _picker = ImagePicker();
  final _state = <String, _SlotState>{
    for (final s in _slots) s.slot: _SlotState(status: _SlotStatus.empty),
  };

  /// Initialised in [_initAsync]; null until SharedPreferences is ready.
  PendingSlotStore? _pendingSlotStore;

  /// True while the Gemma model is being loaded/unloaded.
  bool _modelLoading = false;
  String _modelLoadingLabel = '';

  /// True while [_describeAll] is running — disables capture buttons.
  bool _describeAllInProgress = false;

  @override
  void initState() {
    super.initState();
    _initAsync();
  }

  /// Async init: unconditionally unload the model (Phase A must never have
  /// the model loaded), then check for lost camera data.
  Future<void> _initAsync() async {
    // Always unload on entry — Phase A must never have the model loaded.
    // This prevents the OOM that occurs when camera ISP and model weights
    // compete for GPU/RAM simultaneously.
    await ref.read(gemmaSessionProvider.notifier).unload();

    final store = await PendingSlotStore.create();
    if (!mounted) return;
    _pendingSlotStore = store;
    await _checkLostData(store);
  }

  /// Recover an image that was in-flight when Android killed the Activity.
  ///
  /// `image_picker` caches the camera result and returns it exactly once via
  /// `retrieveLostData()`. We pair it with the pending slot name saved in
  /// [PendingSlotStore] to know which slot to assign the recovered image to.
  Future<void> _checkLostData(PendingSlotStore store) async {
    final lost = await _picker.retrieveLostData();
    if (lost.isEmpty) return;
    if (!mounted) return;

    final pendingSlot = store.read();
    await store.clear();

    if (lost.exception != null) {
      // The recovery itself failed — nothing we can do; show error on the
      // pending slot if known, otherwise silently swallow.
      if (pendingSlot != null) {
        final spec = _slots.firstWhere(
          (s) => s.slot == pendingSlot,
          orElse: () => _slots.first,
        );
        setState(() {
          _state[spec.slot]!
            ..status = _SlotStatus.error
            ..error = lost.exception;
        });
      }
      return;
    }

    final file = lost.file;
    if (file == null) return;

    // Find the spec for the recovered slot (fall back to first if unknown).
    final spec = _slots.firstWhere(
      (s) => s.slot == pendingSlot,
      orElse: () => _slots.first,
    );

    // Process the recovered image — set to captured, not describing.
    // _describeAll() will handle description when the user triggers Phase B.
    await _processPickedFile(spec, file);
  }

  bool get _requiredInFlight => _slots
      .where((s) => s.required)
      .any((s) => _state[s.slot]!.status == _SlotStatus.describing);

  /// How many slots have been captured (or better) and are ready for describe.
  int get _capturedCount => _slots
      .where((s) => _state[s.slot]!.status == _SlotStatus.captured)
      .length;

  /// True when all 4 required slots are done (described successfully).
  bool get _allRequiredDone => _slots
      .where((s) => s.required)
      .every((s) => _state[s.slot]!.status == _SlotStatus.done);

  // ---------------------------------------------------------------------------
  // Phase A — Capture (model is NEVER loaded)
  // ---------------------------------------------------------------------------

  Future<void> _capture(_SlotSpec spec) async {
    // Save pending slot BEFORE firing the camera intent so Activity-kill
    // recovery knows which slot to restore.
    await _pendingSlotStore?.save(spec.slot);

    // No model unload/reload — Phase A never has the model loaded.
    // This is the core of the OOM fix: camera ISP and model weights never
    // compete for GPU/RAM simultaneously.

    // Launch camera (or gallery fallback on web / permission denied).
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
    } catch (_) {
      // Camera not available in this browser / user cancelled the permission
      // dialog — fall back to gallery.
      if (!mounted) return;
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
    }

    // Clear pending slot — either we have the file now or the user cancelled.
    await _pendingSlotStore?.clear();

    if (picked == null) return; // User cancelled.
    await _processPickedFile(spec, picked);
  }

  /// Core pick → enrol pipeline, shared by [_capture] and [_checkLostData].
  ///
  /// Enrolls the photo in the draft and sets slot to [_SlotStatus.captured].
  /// Does NOT call [_describe] — that happens in [_describeAll] (Phase B).
  Future<void> _processPickedFile(_SlotSpec spec, XFile file) async {
    final bytes = await file.readAsBytes();
    final size = await _decodeSize(bytes);
    if (!mounted) return;

    setState(() {
      _state[spec.slot]!
        ..thumb = bytes
        ..status = _SlotStatus.captured
        ..error = null;
    });

    // Enroll in SessionDraft — even if the LLM later fails, we keep the photo
    // so the Report screen can still ship it.
    final controller = ref.read(sessionControllerProvider.notifier);
    final imgRef = controller.generateImageId();
    controller.addPhoto(
      ref: imgRef,
      bytes: bytes,
      widthPx: size.$1,
      heightPx: size.$2,
      slot: spec.slot,
    );
    _state[spec.slot]!.ref = imgRef;

    // Persist bytes to app-specific storage immediately so the image survives
    // image_picker cache eviction during the (potentially long) LLM call.
    final draft = ref.read(sessionControllerProvider);
    if (draft != null) {
      await persistCapturedBytes(draft.packetId, imgRef, bytes);
    }
  }

  // ---------------------------------------------------------------------------
  // Phase B — Describe all captured photos (camera is NEVER used)
  // ---------------------------------------------------------------------------

  /// Triggered by the "Describe photos (N)" button. Loads the model once,
  /// then describes every [_SlotStatus.captured] slot sequentially using
  /// [GemmaOrchestrator.describeAll] (Sprint 3).
  ///
  /// The orchestrator owns: preprocessing, inference, contract validation,
  /// and [TurnRecord] construction. The UI here owns: slot-status rendering,
  /// retry buttons, and navigation.
  Future<void> _describeAll() async {
    setState(() {
      _describeAllInProgress = true;
      _modelLoading = true;
      _modelLoadingLabel = 'Loading Gemma\u2026';
    });
    try {
      await ref
          .read(gemmaSessionProvider.notifier)
          .load(profile: SessionProfile.vision);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelLoading = false;
        _describeAllInProgress = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _modelLoading = false);

    final draft = ref.read(sessionControllerProvider);
    final orch = ref.read(orchestratorProvider);
    if (orch == null || draft == null) {
      if (!mounted) return;
      setState(() => _describeAllInProgress = false);
      return;
    }

    final ctrl = ref.read(sessionControllerProvider.notifier);
    final toDescribe = _slots
        .where((s) => _state[s.slot]!.status == _SlotStatus.captured)
        .toList();

    // Observation IDs are generated upfront so each DescribePhotoRequest
    // carries its ID before the stream starts. This keeps obs-ID allocation
    // deterministic and independent of async event ordering.
    final requests = [
      for (final spec in toDescribe)
        DescribePhotoRequest(
          observationId: ctrl.generateObservationId(),
          promptId: spec.promptId,
          askedIn: draft.askedIn,
          imageBytes: _state[spec.slot]!.thumb!,
          imageRef: _state[spec.slot]!.ref!,
        ),
    ];

    // Lookup: imageRef → slot spec, for routing stream events to slots.
    final refToSpec = <String, _SlotSpec>{
      for (var i = 0; i < toDescribe.length; i++)
        requests[i].imageRef: toDescribe[i],
    };

    await for (final event in orch.describeAll(requests)) {
      if (!mounted) break;
      switch (event) {
        case DescribePhotoStarted(:final request, :final index, :final total):
          final spec = refToSpec[request.imageRef];
          if (spec != null) {
            setState(() {
              _state[spec.slot]!.status = _SlotStatus.describing;
              _modelLoadingLabel =
                  'Describing photo ${index + 1} of $total\u2026';
              _modelLoading = true;
            });
          }
        case DescribePhotoSucceeded(:final result, :final turn):
          final imgRef =
              result.imageRefs.isNotEmpty ? result.imageRefs.first : '';
          final spec = refToSpec[imgRef];
          ctrl.recordObservation(
            _observationFrom(result,
                imgRef: imgRef, obsId: result.observationId),
          );
          ctrl.recordTurn(turn);
          if (spec != null && mounted) {
            setState(() => _state[spec.slot]!.status = _SlotStatus.done);
          }
        case DescribePhotoFailed(:final request, :final error):
          debugPrint('describeAll: photo ${request.imageRef} failed: $error');
          final spec = refToSpec[request.imageRef];
          if (spec != null && mounted) {
            setState(() {
              _state[spec.slot]!.status = _SlotStatus.error;
              _state[spec.slot]!.error = error;
            });
          }
      }
    }

    if (!mounted) return;
    setState(() {
      _modelLoading = false;
      _describeAllInProgress = false;
    });
  }

  Future<void> _describe(
    _SlotSpec spec,
    Uint8List bytes,
    String imgRef,
    String obsId,
  ) async {
    if (!mounted) return;
    final orch = ref.read(orchestratorProvider);
    final draft = ref.read(sessionControllerProvider);
    if (orch == null || draft == null) {
      if (!mounted) return;
      setState(() {
        _state[spec.slot]!
          ..status = _SlotStatus.error
          ..error = StateError(
              'model not loaded — go back to Start and tap "Load model"');
      });
      return;
    }
    try {
      final res = await orch.describePhoto(
        observationId: obsId,
        promptId: spec.promptId,
        askedIn: draft.askedIn,
        imageBytes: bytes,
        imageRef: imgRef,
      );
      ref.read(sessionControllerProvider.notifier).recordObservation(
            _observationFrom(res, imgRef: imgRef, obsId: obsId),
          );
      ref.read(sessionControllerProvider.notifier).recordTurn(
            TurnRecord(
              ts: DateTime.now().toUtc(),
              task: 'describe_photo',
              observationId: obsId,
              ttftMs: res.ttftMs,
              wallclockMs: res.wallclockMs,
              outputCharCount: res.outputCharCount,
            ),
          );
      if (!mounted) return;
      setState(() => _state[spec.slot]!.status = _SlotStatus.done);
    } on GemmaContractError catch (e) {
      debugPrint('describe_photo contract error: $e');
      if (!mounted) return;
      setState(() {
        _state[spec.slot]!
          ..status = _SlotStatus.error
          ..error = e;
      });
    } catch (e) {
      debugPrint('describe_photo failed: $e');
      if (!mounted) return;
      setState(() {
        _state[spec.slot]!
          ..status = _SlotStatus.error
          ..error = e;
      });
    }
  }

  Future<void> _retry(_SlotSpec spec) async {
    final st = _state[spec.slot]!;
    final bytes = st.thumb;
    final imgRef = st.ref;
    if (bytes == null || imgRef == null) return;
    setState(() {
      st.status = _SlotStatus.describing;
      st.error = null;
    });
    final obsId =
        ref.read(sessionControllerProvider.notifier).generateObservationId();
    await _describe(spec, bytes, imgRef, obsId);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(sessionControllerProvider);
    if (draft == null) {
      return const Scaffold(
        body: Center(child: Text('No active session — return to Start.')),
      );
    }
    final requiredCaptured = draft.requiredPhotoSlotCount;
    final canContinue = _allRequiredDone && !_requiredInFlight;
    final canDescribe =
        _capturedCount > 0 && !_describeAllInProgress && !_modelLoading;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Walk around'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                '$requiredCaptured / ${kRequiredPhotoSlots.length}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const FlowStepper(
                steps: FlowStepper.kScreeningSteps, currentIndex: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_modelLoading)
                    _Banner(
                      color: Colors.blue,
                      icon: Icons.memory_outlined,
                      text: _modelLoadingLabel,
                    ),
                  const Text(
                    'Take one photo per reference view. When all photos are '
                    'captured, tap "Describe photos" to run Gemma on all of them.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  for (final spec in _slots)
                    _SlotCard(
                      spec: spec,
                      state: _state[spec.slot]!,
                      onCapture:
                          _describeAllInProgress ? null : () => _capture(spec),
                      onRetry: (_describeAllInProgress || _modelLoading)
                          ? null
                          : () => _retry(spec),
                      lastObs: _findLastObsForSlot(draft, spec.slot),
                    ),
                  const SizedBox(height: 16),
                  // Phase B trigger: "Describe photos (N)"
                  if (canDescribe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FilledButton.tonal(
                        onPressed: _describeAll,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'Describe photos ($_capturedCount)',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: canContinue
                        ? () => context.push(AppRoutes.audio)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        canContinue
                            ? 'Continue'
                            : 'Capture all ${kRequiredPhotoSlots.length} '
                                'reference photos',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Return the most recent observation attached to a given slot's img-ref.
  /// (There can be >1 if the user retries a describe_photo.)
  Observation? _findLastObsForSlot(SessionDraft draft, String slot) {
    final ref = _state[slot]?.ref;
    if (ref == null) return null;
    for (final o in draft.observations.reversed) {
      if (o.imageRefs.contains(ref)) return o;
    }
    return null;
  }
}

/// Single card per photo slot.
class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.spec,
    required this.state,
    required this.onCapture,
    required this.onRetry,
    required this.lastObs,
  });
  final _SlotSpec spec;
  final _SlotState state;
  final VoidCallback? onCapture;
  final VoidCallback? onRetry;
  final Observation? lastObs;

  @override
  Widget build(BuildContext context) {
    final status = state.status;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (state.thumb != null)
                  Image.memory(state.thumb!, fit: BoxFit.cover)
                else
                  Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.photo_camera_outlined,
                        size: 48, color: Colors.black38),
                  ),
                if (status == _SlotStatus.describing)
                  Container(
                    color: Colors.black38,
                    child: const Center(
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${spec.label}${spec.required ? '' : '  (optional)'}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    _StatusChip(status: status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(spec.hint,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 8),
                if (lastObs != null) _ObsSummary(obs: lastObs!),
                if (status == _SlotStatus.error) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    state.error?.toString() ?? 'unknown error',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (status == _SlotStatus.empty)
                      ElevatedButton.icon(
                        onPressed: onCapture,
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Capture'),
                      )
                    else ...[
                      OutlinedButton.icon(
                        onPressed: onCapture,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retake'),
                      ),
                      if (status == _SlotStatus.error) ...[
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.replay),
                          label: const Text('Retry describe'),
                        ),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final _SlotStatus status;
  @override
  Widget build(BuildContext context) {
    final (text, fg, bg) = switch (status) {
      _SlotStatus.empty => ('empty', Colors.black54, Colors.grey.shade200),
      _SlotStatus.captured => (
          'ready',
          Colors.orange.shade800,
          Colors.orange.shade50
        ),
      _SlotStatus.describing => (
          'describing…',
          Colors.blue.shade800,
          Colors.blue.shade50
        ),
      _SlotStatus.done => (
          'described',
          Colors.green.shade800,
          Colors.green.shade50
        ),
      _SlotStatus.error => ('error', Colors.red.shade800, Colors.red.shade50),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style:
              TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _ObsSummary extends StatelessWidget {
  const _ObsSummary({required this.obs});
  final Observation obs;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (obs.modelDescription != null)
            Text(obs.modelDescription!, style: const TextStyle(fontSize: 13)),
          if (obs.modelTags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final t in obs.modelTags)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(t,
                        style: TextStyle(
                            fontSize: 11, color: Colors.indigo.shade800)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'confidence ${obs.modelConfidence.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});
  final MaterialColor color;
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.shade50,
          border: Border.all(color: color.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color.shade700),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: TextStyle(color: color.shade900, fontSize: 13))),
          ],
        ),
      );
}

// ---- helpers ----

Observation _observationFrom(
  DescribePhotoResult r, {
  required String imgRef,
  required String obsId,
}) {
  return Observation(
    observationId: obsId,
    promptId: r.promptId,
    askedIn: r.askedIn,
    imageRefs: r.imageRefs.isEmpty ? [imgRef] : r.imageRefs,
    audioRefs: const [],
    modelDescription: r.modelDescription,
    modelTags: r.modelTags,
    modelConfidence: r.modelConfidence,
    bboxAnnotations: [
      for (final b in r.bbox)
        BBox(
          imageRef: (b['image_ref'] as String?) ?? imgRef,
          box2d: ((b['box_2d'] as List?) ?? const <int>[])
              .cast<num>()
              .map((n) => n.toInt())
              .toList(),
          label: (b['label'] as String?) ?? '',
        ),
    ],
  );
}

Future<(int, int)> _decodeSize(Uint8List bytes) async {
  // `ui.instantiateImageCodec` is available on all Flutter targets including
  // web (it decodes via ImageBitmap there), so we stay off `dart:io`.
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final w = frame.image.width;
  final h = frame.image.height;
  frame.image.dispose();
  codec.dispose();
  return (w, h);
}
