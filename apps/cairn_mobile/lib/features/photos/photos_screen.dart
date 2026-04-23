/// Screen 3 — **Walk around (4 required photos + optional 5th)**.
///
/// The volunteer walks the perimeter of the building and captures one photo
/// per FEMA P-154 reference view. Each capture fires an async
/// `describe_photo` turn against Gemma; the resulting `Observation` is
/// recorded into the `SessionDraft` so later screens (Humility, Synthesize,
/// Report) can reason over it.
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
import 'package:uuid/uuid.dart';

import '../../core/llm/orchestrator.dart';
import '../../core/models/evidence_packet.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';

const _uuid = Uuid();

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
enum _SlotStatus { empty, describing, done, error }

class _SlotState {
  _SlotState({required this.status, this.ref, this.thumb, this.error});
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

  int get _requiredDone => _slots
      .where((s) => s.required)
      .where((s) => _state[s.slot]!.status == _SlotStatus.done)
      .length;

  bool get _canContinue => _requiredDone >= 1; // soft gate, see plan §3.3

  Future<void> _capture(_SlotSpec spec) async {
    // On web ImageSource.camera opens the webcam via getUserMedia; on desktop
    // browsers it falls back to a file chooser. Either way we end up with an
    // XFile whose bytes we can read directly.
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
    } catch (_) {
      // Camera not available in this browser / user cancelled the permission
      // dialog — fall back to gallery.
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
    }
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final size = await _decodeSize(bytes);

    setState(() {
      _state[spec.slot]!
        ..thumb = bytes
        ..status = _SlotStatus.describing
        ..error = null;
    });

    // Enroll in SessionDraft first — even if the LLM fails, we keep the photo
    // so the Report screen can still ship it.
    final controller = ref.read(sessionControllerProvider.notifier);
    final imgRef = controller.addPhoto(
      bytes: bytes,
      widthPx: size.$1,
      heightPx: size.$2,
      slot: spec.slot,
    );
    _state[spec.slot]!.ref = imgRef;

    await _describe(spec, bytes, imgRef);
  }

  Future<void> _describe(
    _SlotSpec spec,
    Uint8List bytes,
    String imgRef,
  ) async {
    final orch = ref.read(orchestratorProvider);
    final draft = ref.read(sessionControllerProvider);
    if (orch == null || draft == null) {
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
        observationId: 'obs-${_uuid.v7()}',
        promptId: spec.promptId,
        askedIn: draft.askedIn,
        imageBytes: bytes,
        imageRef: imgRef,
      );
      ref.read(sessionControllerProvider.notifier).recordObservation(
            _observationFrom(res, imgRef: imgRef),
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
    final ref = st.ref;
    if (bytes == null || ref == null) return;
    setState(() {
      st.status = _SlotStatus.describing;
      st.error = null;
    });
    await _describe(spec, bytes, ref);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(sessionControllerProvider);
    final orch = ref.watch(orchestratorProvider);
    if (draft == null) {
      return const Scaffold(
        body: Center(child: Text('No active session — return to Start.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Walk around'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text('$_requiredDone / 4',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (orch == null)
              const _Banner(
                color: Colors.red,
                icon: Icons.error_outline,
                text: 'Model not loaded. Go back to Start and load the model '
                    'before capturing photos.',
              ),
            const Text(
              'Take one photo per reference view. Each photo is described by '
              'Gemma right after capture.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            for (final spec in _slots)
              _SlotCard(
                spec: spec,
                state: _state[spec.slot]!,
                onCapture: orch == null ? null : () => _capture(spec),
                onRetry: orch == null ? null : () => _retry(spec),
                lastObs: _findLastObsForSlot(draft, spec.slot),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  _canContinue ? () => context.push(AppRoutes.describe) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  _canContinue
                      ? 'Continue'
                      : 'Capture at least one reference photo',
                  style: const TextStyle(fontSize: 16),
                ),
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
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 8),
                if (lastObs != null) _ObsSummary(obs: lastObs!),
                if (status == _SlotStatus.error) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    state.error?.toString() ?? 'unknown error',
                    style: TextStyle(
                        color: Colors.red.shade700, fontSize: 12),
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
      _SlotStatus.describing =>
        ('describing…', Colors.blue.shade800, Colors.blue.shade50),
      _SlotStatus.done => ('described', Colors.green.shade800, Colors.green.shade50),
      _SlotStatus.error => ('error', Colors.red.shade800, Colors.red.shade50),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(
              color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
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
          Text(obs.modelDescription,
              style: const TextStyle(fontSize: 13)),
          if (obs.modelTags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final t in obs.modelTags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(t,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.indigo.shade800)),
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

Observation _observationFrom(DescribePhotoResult r, {required String imgRef}) {
  return Observation(
    observationId: r.observationId,
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
