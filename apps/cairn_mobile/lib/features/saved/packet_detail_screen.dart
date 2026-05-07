library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/export/evidence_bundle.dart';
import '../../core/models/evidence_packet.dart';
import '../../core/pdf/report_pdf_builder.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/cairn_theme.dart';

class PacketDetailScreen extends ConsumerStatefulWidget {
  const PacketDetailScreen({super.key, required this.packetId});

  final String packetId;

  @override
  ConsumerState<PacketDetailScreen> createState() => _PacketDetailScreenState();
}

class _PacketDetailScreenState extends ConsumerState<PacketDetailScreen> {
  Object? _error;
  bool _busy = false;

  Future<_PacketDetailData> _load() async {
    final vault = ref.read(evidenceVaultProvider);
    final packet = await vault.loadPacket(widget.packetId);
    if (packet == null) {
      throw StateError('Packet ${widget.packetId} was not found.');
    }
    final images = <String, Uint8List>{};
    for (final image in packet.images) {
      final bytes = await vault.getAsset(packet.packetId, image.ref);
      if (bytes != null) images[image.ref] = bytes;
    }
    final pdfReady = await vault.hasReportPdf(packet.packetId);
    final turns = await vault.loadTurnsJsonl(packet.packetId);
    return _PacketDetailData(
      packet: packet,
      imageBytes: images,
      pdfReady: pdfReady,
      turnsBytes: turns,
    );
  }

  Future<void> _shareJson(EvidencePacket packet) async {
    await Share.share(
      const JsonEncoder.withIndent('  ').convert(packet.toJson()),
      subject: 'Cairn packet ${packet.packetId.substring(0, 8)}',
    );
  }

  Future<void> _sharePdf(_PacketDetailData data) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final vault = ref.read(evidenceVaultProvider);
      final existing = await vault.loadReportPdf(data.packet.packetId);
      final bytes = existing ??
          await buildReportPdf(data.packet, imageBytes: data.imageBytes);
      if (existing == null) {
        await vault.saveReportPdf(data.packet.packetId, bytes);
      }
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'cairn_${data.packet.packetId.substring(0, 8)}.pdf',
      );
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareBundle(EvidencePacket packet) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bundle = await buildEvidenceBundle(
        ref.read(evidenceVaultProvider),
        packet,
      );
      await Share.shareXFiles(
        [
          XFile.fromData(
            bundle.bytes,
            mimeType: 'application/zip',
            name: bundle.filename,
            length: bundle.bytes.length,
          ),
        ],
        subject: 'Cairn packet ${packet.packetId.substring(0, 8)} bundle',
        fileNameOverrides: [bundle.filename],
      );
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Screening Details')),
      body: FutureBuilder<_PacketDetailData>(
        future: _load(),
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
          final packet = data.packet;
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _PriorityHeader(packet: packet),
                const SizedBox(height: 12),
                _InfoSection(packet: packet, pdfReady: data.pdfReady),
                const SizedBox(height: 12),
                _ObservationSection(packet: packet),
                const SizedBox(height: 12),
                _PhotoSection(packet: packet, imageBytes: data.imageBytes),
                const SizedBox(height: 12),
                _TurnLogSection(turnsBytes: data.turnsBytes),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text('Share error: $_error',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _sharePdf(data),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(data.pdfReady ? 'Share PDF' : 'Generate PDF'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _shareJson(packet),
                  icon: const Icon(Icons.data_object),
                  label: const Text('Share packet JSON'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _shareBundle(packet),
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: const Text('Share export bundle'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PacketDetailData {
  const _PacketDetailData({
    required this.packet,
    required this.imageBytes,
    required this.pdfReady,
    required this.turnsBytes,
  });

  final EvidencePacket packet;
  final Map<String, Uint8List> imageBytes;
  final bool pdfReady;
  final Uint8List? turnsBytes;
}

class _PriorityHeader extends StatelessWidget {
  const _PriorityHeader({required this.packet});

  final EvidencePacket packet;

  @override
  Widget build(BuildContext context) {
    final triage = packet.triage;
    final color = CairnColors.forBand(triage.priorityBand);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            foregroundColor: color,
            child: Text('${triage.priorityScore}',
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'PRIORITY ${triage.priorityBand}\n'
              '${packet.createdAtUtc.toLocal()}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.packet, required this.pdfReady});

  final EvidencePacket packet;
  final bool pdfReady;

  @override
  Widget build(BuildContext context) => _Section(
        title: 'Packet',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('ID', packet.packetId),
            _kv('Address',
                packet.location.addressText.isEmpty ? '-' : packet.location.addressText),
            _kv('Location',
                '${packet.location.lat.toStringAsFixed(5)}, ${packet.location.lng.toStringAsFixed(5)}'),
            _kv('Building', packet.building.type),
            _kv('Photos', '${packet.images.length}'),
            _kv('PDF', pdfReady ? 'ready' : 'not saved yet'),
          ],
        ),
      );
}

class _ObservationSection extends StatelessWidget {
  const _ObservationSection({required this.packet});

  final EvidencePacket packet;

  @override
  Widget build(BuildContext context) => _Section(
        title: 'Observations',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final obs in packet.observations) ...[
              Text(obs.promptId,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (obs.modelDescription != null)
                Text(obs.modelDescription!,
                    style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final tag in obs.modelTags) _Tag(tag),
                  _Tag('confidence ${obs.modelConfidence.toStringAsFixed(2)}'),
                ],
              ),
              const Divider(height: 18),
            ],
            if (packet.observations.isEmpty)
              const Text('No model observations stored.'),
          ],
        ),
      );
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({required this.packet, required this.imageBytes});

  final EvidencePacket packet;
  final Map<String, Uint8List> imageBytes;

  @override
  Widget build(BuildContext context) => _Section(
        title: 'Photos',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final image in packet.images)
              GestureDetector(
                onTap: () => context.push(
                  AppRoutes.packetPhotoPath(packet.packetId, image.ref),
                ),
                child: SizedBox(
                  width: 104,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: imageBytes[image.ref] == null
                            ? Container(
                                width: 104,
                                height: 78,
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.broken_image_outlined),
                              )
                            : Image.memory(
                                imageBytes[image.ref]!,
                                width: 104,
                                height: 78,
                                fit: BoxFit.cover,
                              ),
                      ),
                      const SizedBox(height: 4),
                      Text(image.ref,
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

class _TurnLogSection extends StatelessWidget {
  const _TurnLogSection({required this.turnsBytes});

  final Uint8List? turnsBytes;

  @override
  Widget build(BuildContext context) {
    final text =
        turnsBytes == null ? '' : const Utf8Decoder().convert(turnsBytes!);
    final lines = text.trim().isEmpty ? 0 : text.trim().split('\n').length;
    return _Section(
      title: 'Model Turn Log',
      child: Text(lines == 0 ? 'No turns.jsonl stored.' : '$lines turns stored'),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );
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

Widget _kv(String key, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(key,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
