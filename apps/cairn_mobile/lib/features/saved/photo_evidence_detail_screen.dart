library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/evidence_packet.dart';
import '../../core/providers.dart';
import '../../core/theme/cairn_theme.dart';

class PhotoEvidenceDetailScreen extends ConsumerWidget {
  const PhotoEvidenceDetailScreen({
    super.key,
    required this.packetId,
    required this.imageRef,
  });

  final String packetId;
  final String imageRef;

  Future<_PhotoEvidenceData> _load(WidgetRef ref) async {
    final vault = ref.read(evidenceVaultProvider);
    final packet = await vault.loadPacket(packetId);
    if (packet == null) throw StateError('Packet $packetId was not found.');
    final image = packet.images.firstWhere(
      (item) => item.ref == imageRef,
      orElse: () => throw StateError('Photo $imageRef was not found.'),
    );
    final bytes = await vault.getAsset(packetId, imageRef);
    if (bytes == null) throw StateError('Photo bytes for $imageRef are missing.');
    final observations = packet.observations
        .where((obs) => obs.imageRefs.contains(imageRef))
        .toList();
    return _PhotoEvidenceData(
      image: image,
      bytes: bytes,
      observations: observations,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('Photo $imageRef')),
      body: FutureBuilder<_PhotoEvidenceData>(
        future: _load(ref),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${snap.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final data = snap.data!;
          final obs = data.observations.isEmpty ? null : data.observations.last;
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AspectRatio(
                  aspectRatio: data.image.widthPx / data.image.heightPx,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(data.bytes, fit: BoxFit.contain),
                      if (obs != null)
                        CustomPaint(
                          painter: _BboxPainter(obs.bboxAnnotations),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _InfoCard(image: data.image),
                const SizedBox(height: 12),
                _ObservationCard(observation: obs),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PhotoEvidenceData {
  const _PhotoEvidenceData({
    required this.image,
    required this.bytes,
    required this.observations,
  });

  final ImageAsset image;
  final Uint8List bytes;
  final List<Observation> observations;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.image});

  final ImageAsset image;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Slot/ref', image.ref),
              _kv('Filename', image.filename),
              _kv('Dimensions', '${image.widthPx} x ${image.heightPx}'),
              _kv('Taken UTC', image.takenAtUtc.toIso8601String()),
              _kv('SHA-256', image.sha256),
            ],
          ),
        ),
      );
}

class _ObservationCard extends StatelessWidget {
  const _ObservationCard({required this.observation});

  final Observation? observation;

  @override
  Widget build(BuildContext context) {
    final obs = observation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: obs == null
            ? const Text('No model observation is attached to this photo.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(obs.promptId,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (obs.modelDescription != null)
                    Text(obs.modelDescription!),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final tag in obs.modelTags) _Tag(tag),
                      _Tag('confidence ${obs.modelConfidence.toStringAsFixed(2)}'),
                      _Tag('${obs.bboxAnnotations.length} boxes'),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: CairnColors.info.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11)),
      );
}

class _BboxPainter extends CustomPainter {
  const _BboxPainter(this.boxes);

  final List<BBox> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CairnColors.high
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final labelPaint = Paint()..color = CairnColors.high;
    for (final box in boxes) {
      if (box.box2d.length != 4) continue;
      final y1 = box.box2d[0] / 1000 * size.height;
      final x1 = box.box2d[1] / 1000 * size.width;
      final y2 = box.box2d[2] / 1000 * size.height;
      final x2 = box.box2d[3] / 1000 * size.width;
      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      canvas.drawRect(rect, paint);
      final labelRect = Rect.fromLTWH(x1, y1 - 20, box.label.length * 7 + 10, 18);
      canvas.drawRect(labelRect, labelPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: box.label,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: labelRect.width);
      tp.paint(canvas, Offset(x1 + 5, y1 - 18));
    }
  }

  @override
  bool shouldRepaint(covariant _BboxPainter oldDelegate) =>
      oldDelegate.boxes != boxes;
}

Widget _kv(String key, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(key,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
