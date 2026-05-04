/// Screen 9 — **Report**.
///
/// On first build the screen seals the [SessionDraft] into an
/// [EvidencePacket], validates it via [EvidencePacketValidator], writes it
/// to the vault, and clears the draft. Then it renders:
///
///  - Coloured priority badge (CRITICAL / HIGH / MEDIUM / LOW)
///  - Triage rationale bullets + uncertainty notes
///  - Building / location summary
///  - Photo thumbnails (from in-memory bytes captured before the draft is abandoned)
///  - Action bar: **Save PDF · Share JSON · Start new screening**
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/evidence_packet.dart';
import '../../core/pdf/report_pdf_builder.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/state/session_controller.dart';

// ---------------------------------------------------------------------------
// Colours for priority bands
// ---------------------------------------------------------------------------

Color _bandColor(String band) => switch (band) {
      'CRITICAL' => const Color(0xFFC62828),
      'HIGH' => const Color(0xFFBF360C),
      'MEDIUM' => const Color(0xFFE65100),
      _ => const Color(0xFF2E7D32),
    };

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  bool _sealing = true;
  EvidencePacket? _packet;
  List<CapturedPhoto> _photos = [];
  Map<String, Uint8List> _photoBytes = {};
  Object? _sealError;

  bool _pdfGenerating = false;
  bool _pdfDone = false;
  Object? _pdfError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sealSession());
  }

  // ---------------------------------------------------------------------------
  // Seal + validate
  // ---------------------------------------------------------------------------

  Future<void> _sealSession() async {
    final draft = ref.read(sessionControllerProvider);
    if (draft == null) {
      setState(() {
        _sealing = false;
        _sealError = 'No active session. Return to Start.';
      });
      return;
    }

    // Capture media bytes before abandoning the draft.
    final photos = List<CapturedPhoto>.from(draft.photos);
    final photoBytes = {for (final p in photos) p.ref: p.bytes};

    try {
      final vault = ref.read(evidenceVaultProvider);
      final packet =
          await ref.read(sessionControllerProvider.notifier).sealAndSave(vault);

      // Clear the draft — the listener in main.dart will call clearDraft().
      ref.read(sessionControllerProvider.notifier).abandon();

      setState(() {
        _packet = packet;
        _photos = photos;
        _photoBytes = photoBytes;
        _sealing = false;
      });
    } catch (e) {
      setState(() {
        _sealing = false;
        _sealError = e;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // PDF generation + share
  // ---------------------------------------------------------------------------

  Future<void> _generateAndSharePdf() async {
    final packet = _packet;
    if (packet == null) return;
    setState(() {
      _pdfGenerating = true;
      _pdfError = null;
    });
    try {
      final bytes = await buildReportPdf(packet, imageBytes: _photoBytes);
      await ref.read(evidenceVaultProvider).saveReportPdf(packet.packetId, bytes);
      if (!mounted) return;
      if (kIsWeb) {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else {
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'cairn_${packet.packetId.substring(0, 8)}.pdf',
        );
      }
      setState(() {
        _pdfDone = true;
        _pdfGenerating = false;
      });
    } catch (e) {
      setState(() {
        _pdfError = e;
        _pdfGenerating = false;
      });
    }
  }

  Future<void> _shareJson() async {
    final packet = _packet;
    if (packet == null) return;
    try {
      final json = const JsonEncoder.withIndent('  ').convert(packet.toJson());
      await Share.share(json,
          subject: 'Cairn packet ${packet.packetId.substring(0, 8)}');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_sealing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Finalising report…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_sealError != null) {
      return _ErrorScaffold(
        error: _sealError.toString(),
        onRetry: () {
          setState(() {
            _sealing = true;
            _sealError = null;
          });
          _sealSession();
        },
      );
    }

    final packet = _packet!;
    final triage = packet.triage;
    final color = _bandColor(triage.priorityBand);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Screening Report'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Priority badge
            _PriorityBadge(triage: triage, color: color),
            const SizedBox(height: 16),

            // Building + location
            _InfoCard(packet: packet),
            const SizedBox(height: 12),

            // Rationale
            _Section(
              title: 'Triage Rationale',
              child: _BulletList(items: triage.rationaleBullets),
            ),
            if (triage.uncertaintyNotes.isNotEmpty) ...[
              const SizedBox(height: 10),
              _Section(
                title: 'Uncertainty Notes',
                child: _BulletList(items: triage.uncertaintyNotes),
              ),
            ],
            if (triage.recommendEngineerFollowup) ...[
              const SizedBox(height: 10),
              _EngineerBanner(),
            ],

            // Photos
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Section(
                title: 'Photos (${_photos.length})',
                child: _PhotoGrid(photos: _photos),
              ),
            ],

            // Packet QR
            const SizedBox(height: 12),
            _PacketIdRow(packetId: packet.packetId),

            // PDF errors
            if (_pdfError != null) ...[
              const SizedBox(height: 8),
              Text('PDF error: $_pdfError',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ],

            // Action buttons
            const SizedBox(height: 20),
            _ActionButtons(
              pdfGenerating: _pdfGenerating,
              pdfDone: _pdfDone,
              onSavePdf: _generateAndSharePdf,
              onShareJson: _shareJson,
              onStartNew: () {
                context.go(AppRoutes.start);
              },
            ),
            const SizedBox(height: 24),

            // Disclaimer
            const _Disclaimer(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.triage, required this.color});
  final TriageResult triage;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '${triage.priorityScore}',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PRIORITY ${triage.priorityBand}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Score ${triage.priorityScore} / 10',
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.packet});
  final EvidencePacket packet;

  @override
  Widget build(BuildContext context) {
    final b = packet.building;
    final l = packet.location;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(
              Icons.domain,
              '${_buildingLabel(b.type)}, ${b.storiesAboveGrade} '
                  'stor${b.storiesAboveGrade == 1 ? 'y' : 'ies'}'
                  '${b.yearBuiltEst != null ? ' (~${b.yearBuiltEst})' : ''}',
            ),
            if (l.addressText.isNotEmpty)
              _row(Icons.place_outlined, l.addressText),
            _row(Icons.gps_fixed_outlined,
                '${l.lat.toStringAsFixed(5)}, ${l.lng.toStringAsFixed(5)}'),
            _row(Icons.schedule_outlined,
                _fmtDate(packet.createdAtUtc)),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.black54),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: child,
          ),
        ],
      );
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ',
                      style: TextStyle(fontSize: 14)),
                  Expanded(
                      child: Text(item,
                          style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          if (items.isEmpty)
            const Text('—', style: TextStyle(color: Colors.black45)),
        ],
      );
}

class _EngineerBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3CD),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFFE082)),
        ),
        child: const Row(
          children: [
            Icon(Icons.warning_amber_outlined,
                color: Color(0xFF856404)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Licensed structural engineer follow-up is recommended.',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF856404)),
              ),
            ),
          ],
        ),
      );
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.photos});
  final List<CapturedPhoto> photos;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in photos)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                p.bytes,
                width: 90,
                height: 70,
                fit: BoxFit.cover,
              ),
            ),
        ],
      );
}

class _PacketIdRow extends StatelessWidget {
  const _PacketIdRow({required this.packetId});
  final String packetId;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Packet ID',
                    style: TextStyle(
                        fontSize: 11, color: Colors.black54)),
                SelectableText(
                  packetId,
                  style: const TextStyle(
                      fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          QrImageView(
            data: packetId,
            version: QrVersions.auto,
            size: 64,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
          ),
        ],
      );
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.pdfGenerating,
    required this.pdfDone,
    required this.onSavePdf,
    required this.onShareJson,
    required this.onStartNew,
  });
  final bool pdfGenerating;
  final bool pdfDone;
  final VoidCallback onSavePdf;
  final VoidCallback onShareJson;
  final VoidCallback onStartNew;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: pdfGenerating ? null : onSavePdf,
            icon: pdfGenerating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(pdfDone ? Icons.check : Icons.picture_as_pdf),
            label: Text(pdfGenerating
                ? 'Generating PDF…'
                : pdfDone
                    ? 'PDF saved ✓'
                    : 'Save / Share PDF'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onShareJson,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share packet JSON'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onStartNew,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Start new screening'),
          ),
        ],
      );
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Text(
          'DISCLAIMER: This report is produced by a non-licensed volunteer '
          'using AI-assisted screening software. It is NOT a structural '
          'engineering assessment and must not be used as the sole basis for '
          'any safety or evacuation decision. A licensed structural engineer '
          'must confirm all findings.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
      );
}

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Report error')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 64, color: cs.error),
              const SizedBox(height: 16),
              Text('Could not finalise report',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: cs.error)),
              const SizedBox(height: 8),
              Text(error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------


String _buildingLabel(String type) => type
    .replaceAll('_', ' ')
    .split(' ')
    .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String _fmtDate(DateTime dt) {
  final u = dt.toUtc();
  return '${u.year}-${u.month.toString().padLeft(2, '0')}-'
      '${u.day.toString().padLeft(2, '0')} '
      '${u.hour.toString().padLeft(2, '0')}:'
      '${u.minute.toString().padLeft(2, '0')} UTC';
}
