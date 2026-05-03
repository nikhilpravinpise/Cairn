/// Cairn report PDF builder — pure Dart, no Flutter dependency.
///
/// Produces a two-page A4 report from a sealed [EvidencePacket]:
///
///   Page 1: header + priority badge + triage rationale + building/location
///   Page 2: observations + protocol answers + volunteer attestation + footer
///
/// Photos are embedded (up to 4) on Page 2 if [imageBytes] is provided.
///
/// The function is synchronous internally but returns a [Future] to allow
/// the caller to `await` it without blocking the UI thread on long packets.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/evidence_packet.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Build a PDF report for [packet].
///
/// [imageBytes]: optional map of `image_ref → JPEG bytes`.  Photos are
/// embedded in the report if provided; omitted otherwise.
///
/// Returns raw PDF bytes suitable for writing to disk or sharing.
Future<Uint8List> buildReportPdf(
  EvidencePacket packet, {
  Map<String, Uint8List> imageBytes = const {},
}) async {
  final doc = pw.Document(
    title: 'Cairn FEMA P-154 L1 Report — ${packet.packetId}',
    author: 'Cairn v${packet.appVersion}',
    creator: 'Cairn',
    subject: 'Rapid Visual Screening Report',
  );

  final bandColor = _bandColor(packet.triage.priorityBand);
  final bandTextColor =
      packet.triage.priorityBand == 'LOW' ? PdfColors.white : PdfColors.white;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context ctx) => [
        _header(),
        pw.SizedBox(height: 12),
        _priorityBadge(packet.triage, bandColor, bandTextColor),
        pw.SizedBox(height: 16),
        _infoRow(packet),
        pw.SizedBox(height: 14),
        _section('Triage Rationale', _bulletList(packet.triage.rationaleBullets)),
        if (packet.triage.uncertaintyNotes.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          _section(
              'Uncertainty Notes', _bulletList(packet.triage.uncertaintyNotes)),
        ],
        if (packet.triage.recommendEngineerFollowup) ...[
          pw.SizedBox(height: 10),
          _engineerBanner(),
        ],
        pw.SizedBox(height: 14),
        _observationsSection(packet.observations),
        pw.SizedBox(height: 14),
        _protocolSection(packet.protocolAnswers),
        if (imageBytes.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          _photosSection(packet.images, imageBytes),
        ],
        pw.SizedBox(height: 14),
        _attestationSection(packet.volunteer),
        pw.SizedBox(height: 14),
        _footer(packet),
      ],
    ),
  );

  return doc.save();
}

// ---------------------------------------------------------------------------
// Section builders
// ---------------------------------------------------------------------------

pw.Widget _header() => pw.Container(
      color: const PdfColor.fromInt(0xFF2F5D62),
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'CAIRN',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'FEMA P-154 Level 1',
                style: pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Rapid Visual Screening Report',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
              ),
            ],
          ),
        ],
      ),
    );

pw.Widget _priorityBadge(
  TriageResult triage,
  PdfColor bg,
  PdfColor fg,
) =>
    pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: pw.Row(
        children: [
          pw.Container(
            width: 64,
            height: 64,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Center(
              child: pw.Text(
                '${triage.priorityScore}',
                style: pw.TextStyle(
                  fontSize: 36,
                  fontWeight: pw.FontWeight.bold,
                  color: bg,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'PRIORITY ${triage.priorityBand}',
                style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white),
              ),
              pw.Text(
                'Score ${triage.priorityScore} / 10',
                style: const pw.TextStyle(
                    fontSize: 13, color: PdfColors.white),
              ),
            ],
          ),
        ],
      ),
    );

pw.Widget _infoRow(EvidencePacket packet) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _labelBox('Building', [
            '${_buildingLabel(packet.building.type)}, '
                '${packet.building.storiesAboveGrade} '
                'stor${packet.building.storiesAboveGrade == 1 ? 'y' : 'ies'}',
            if (packet.building.occupancyHint.isNotEmpty)
              'Occupancy: ${packet.building.occupancyHint}',
            if (packet.building.yearBuiltEst != null)
              'Built ~${packet.building.yearBuiltEst}',
          ]),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: _labelBox('Location / Date', [
            if (packet.location.addressText.isNotEmpty)
              packet.location.addressText,
            '${packet.location.lat.toStringAsFixed(5)}, '
                '${packet.location.lng.toStringAsFixed(5)}',
            'Accuracy: ±${packet.location.accuracyMeters.toStringAsFixed(0)} m',
            'Assessed: ${_fmtDate(packet.createdAtUtc)}',
          ]),
        ),
      ],
    );

pw.Widget _section(String title, pw.Widget body) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFF2F5D62)),
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFF5F5F5),
            borderRadius: pw.BorderRadius.circular(4),
            border: pw.Border.all(color: const PdfColor.fromInt(0xFFDDDDDD)),
          ),
          child: body,
        ),
      ],
    );

pw.Widget _labelBox(String title, List<String> lines) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF2F5D62))),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFF5F5F5),
            borderRadius: pw.BorderRadius.circular(4),
            border:
                pw.Border.all(color: const PdfColor.fromInt(0xFFDDDDDD)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final l in lines)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Text(l, style: const pw.TextStyle(fontSize: 10)),
                ),
            ],
          ),
        ),
      ],
    );

pw.Widget _bulletList(List<String> items) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final item in items)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('- ', style: const pw.TextStyle(fontSize: 10)),
                pw.Expanded(
                  child: pw.Text(item,
                      style: const pw.TextStyle(fontSize: 10)),
                ),
              ],
            ),
          ),
      ],
    );

pw.Widget _engineerBanner() => pw.Container(
      color: const PdfColor.fromInt(0xFFFFF3CD),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Row(
        children: [
          pw.Text('[!] ',
              style: const pw.TextStyle(
                  fontSize: 12, color: PdfColor.fromInt(0xFF856404))),
          pw.Expanded(
            child: pw.Text(
              'Licensed structural engineer follow-up is recommended.',
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF856404)),
            ),
          ),
        ],
      ),
    );

pw.Widget _observationsSection(List<Observation> observations) {
  if (observations.isEmpty) {
    return _section('Observations',
        pw.Text('No observations recorded.', style: const pw.TextStyle(fontSize: 10)));
  }
  return _section(
    'Observations (${observations.length})',
    pw.Column(
      children: [
        for (final o in observations)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text(
                      o.promptId,
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF555555)),
                    ),
                    pw.Spacer(),
                    pw.Text(
                      'conf: ${o.modelConfidence.toStringAsFixed(2)}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColor.fromInt(0xFF777777)),
                    ),
                  ],
                ),
                if (o.modelDescription != null)
                  pw.Text(o.modelDescription!,
                      style: const pw.TextStyle(fontSize: 10)),
                if (o.modelTags.isNotEmpty)
                  pw.Text(
                    'Tags: ${o.modelTags.join(', ')}',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColor.fromInt(0xFF555555)),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

pw.Widget _protocolSection(ProtocolAnswersRecord pa) => _section(
      'Protocol Answers (FEMA P-154 §6)',
      pw.Table(
        border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFDDDDDD)),
        children: [
          _protocolRow('Visible collapse / severe racking', pa.visibleCollapse),
          _protocolRow('Building off foundation', pa.buildingOffFoundation),
          _protocolRow('Significant leaning', _leaningText(pa.leaning)),
          _protocolRow('Ground failure adjacent', pa.groundFailureAdjacent),
          _protocolRow('Falling hazards present', pa.fallingHazards),
          _protocolRow('Adjacent building leaning', pa.adjacentLeaning),
        ],
      ),
    );

pw.TableRow _protocolRow(String label, Object? value) => pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(_boolText(value),
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _protocolValueColor(value))),
        ),
      ],
    );

pw.Widget _photosSection(
    List<ImageAsset> assets, Map<String, Uint8List> imageBytes) {
  final photos = assets
      .where((a) => imageBytes.containsKey(a.ref))
      .take(4)
      .toList();
  if (photos.isEmpty) return pw.SizedBox();
  return _section(
    'Photos (${photos.length})',
    pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final asset in photos)
          pw.Container(
            width: 120,
            height: 90,
            child: pw.Image(
              pw.MemoryImage(imageBytes[asset.ref]!),
              fit: pw.BoxFit.cover,
            ),
          ),
      ],
    ),
  );
}

pw.Widget _attestationSection(VolunteerAttestation v) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Volunteer Attestation',
          style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFF2F5D62)),
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: const PdfColor.fromInt(0xFFDDDDDD))),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(v.attestation, style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 4),
              pw.Text(
                'Signature: ${v.signatureHash}',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColor.fromInt(0xFF777777)),
              ),
              pw.Text(
                'Locale: ${v.locale}',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColor.fromInt(0xFF777777)),
              ),
            ],
          ),
        ),
      ],
    );

pw.Widget _footer(EvidencePacket packet) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: const PdfColor.fromInt(0xFFCCCCCC)),
        pw.SizedBox(height: 4),
        pw.Text(
          'DISCLAIMER: This report was produced by a non-licensed volunteer '
          'using AI-assisted screening software. It is NOT a structural '
          'engineering assessment and must NOT be used as the sole basis for '
          'any safety or evacuation decision. A licensed structural engineer '
          'must confirm all findings.',
          style: const pw.TextStyle(
              fontSize: 8, color: PdfColor.fromInt(0xFF777777)),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Packet ID: ${packet.packetId}  |  '
          'Model: ${packet.modelName} (${packet.modelQuant})  |  '
          'App: ${packet.appVersion}',
          style: const pw.TextStyle(
              fontSize: 7, color: PdfColor.fromInt(0xFF999999)),
        ),
      ],
    );

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

PdfColor _bandColor(String band) => switch (band) {
      'CRITICAL' => const PdfColor.fromInt(0xFFC62828),
      'HIGH' => const PdfColor.fromInt(0xFFBF360C),
      'MEDIUM' => const PdfColor.fromInt(0xFFE65100),
      _ => const PdfColor.fromInt(0xFF2E7D32),
    };

PdfColor _protocolValueColor(Object? v) {
  if (v == true) return const PdfColor.fromInt(0xFFC62828);
  if (v is String && v != 'none') return const PdfColor.fromInt(0xFFE65100);
  return const PdfColor.fromInt(0xFF2E7D32);
}

String _boolText(Object? v) {
  if (v == true) return 'YES';
  if (v == false) return 'NO';
  if (v is String) return v.toUpperCase();
  return '—';
}

String _leaningText(String leaning) => leaning;

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
