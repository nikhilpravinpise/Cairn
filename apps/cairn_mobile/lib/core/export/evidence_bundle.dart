library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/evidence_packet.dart';
import '../storage/evidence_vault.dart';

class EvidenceBundleResult {
  const EvidenceBundleResult({
    required this.filename,
    required this.bytes,
    required this.includedFiles,
  });

  final String filename;
  final Uint8List bytes;
  final List<String> includedFiles;
}

Future<EvidenceBundleResult> buildEvidenceBundle(
  EvidenceVault vault,
  EvidencePacket packet,
) async {
  final archive = Archive();
  final included = <String>[];

  void addBytes(String name, List<int> bytes) {
    archive.addFile(ArchiveFile.bytes(name, bytes));
    included.add(name);
  }

  addBytes(
    'packet.json',
    utf8.encode(const JsonEncoder.withIndent('  ').convert(packet.toJson())),
  );

  final report = await vault.loadReportPdf(packet.packetId);
  if (report != null) {
    addBytes('report.pdf', report);
  }

  final turns = await vault.loadTurnsJsonl(packet.packetId);
  if (turns != null) {
    addBytes('turns.jsonl', turns);
  }

  for (final image in packet.images) {
    final bytes = await vault.getAsset(packet.packetId, image.ref);
    if (bytes != null) {
      addBytes('photos/${image.filename}', bytes);
    }
  }

  for (final audio in packet.audio) {
    final bytes = await vault.getAsset(packet.packetId, audio.ref);
    if (bytes != null) {
      addBytes('audio/${audio.filename}', bytes);
    }
  }

  final zipBytes = ZipEncoder().encodeBytes(archive);
  return EvidenceBundleResult(
    filename: 'cairn_${packet.packetId.substring(0, 8)}_bundle.zip',
    bytes: zipBytes,
    includedFiles: included,
  );
}
