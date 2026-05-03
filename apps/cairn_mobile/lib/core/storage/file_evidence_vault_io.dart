/// dart:io-backed [EvidenceVault] implementation for Phase 9.
///
/// Writes sealed packets to:
///   `<appSupportDir>/cairn_vault/<packetId>/packet.json`
///
/// Asset layout inside the folder:
///   `img-1.jpg`, `img-2.jpg`, …  — JPEG bytes per [ImageAsset.ref]
///   `aud-1.wav`, `aud-2.wav`, …  — WAV bytes per [AudioAsset.ref]
///   `turns.jsonl`                — one JSON object per LLM turn
///   `report.pdf`                 — generated PDF (from the Report screen)
///
/// All writes are atomic: bytes are flushed to `<dest>.tmp` first, then
/// the temp file is renamed to `<dest>`. This prevents half-written files
/// from appearing as valid entries after a process kill.
///
/// Exported via `file_evidence_vault.dart` conditional export; callers always
/// use [EvidenceVault] and never reference this file directly — except tests,
/// which instantiate [FileEvidenceVaultIo] with a [testBaseDir] to isolate I/O.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/evidence_packet.dart';
import 'evidence_vault.dart';

// ---------------------------------------------------------------------------
// Factory — conditional export entry point
// ---------------------------------------------------------------------------

/// Returns a platform-native file-backed [EvidenceVault].
EvidenceVault createFileEvidenceVault() => FileEvidenceVaultIo();

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

/// File-backed [EvidenceVault] using `getApplicationSupportDirectory()`.
///
/// Pass [testBaseDir] to redirect all I/O to a temp directory in unit tests.
class FileEvidenceVaultIo implements EvidenceVault {
  /// Creates a vault backed by [getApplicationSupportDirectory()].
  ///
  /// Specify [testBaseDir] to override the base directory (tests only).
  FileEvidenceVaultIo({this.testBaseDir});

  /// Overrides [getApplicationSupportDirectory()] — used by tests only.
  final Directory? testBaseDir;

  static const _kVaultDir = 'cairn_vault';

  Future<Directory> get _base async =>
      testBaseDir ?? await getApplicationSupportDirectory();

  Future<Directory> _packetDir(String packetId, {bool create = true}) async {
    final base = await _base;
    final dir = Directory('${base.path}/$_kVaultDir/$packetId');
    if (create && !dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ---------------------------------------------------------------------------
  // EvidenceVault — packet CRUD
  // ---------------------------------------------------------------------------

  @override
  Future<void> savePacket(EvidencePacket packet) async {
    final dir = await _packetDir(packet.packetId);
    final json = const JsonEncoder.withIndent('  ').convert(packet.toJson());
    await _atomicWrite(File('${dir.path}/packet.json'), utf8.encode(json));
  }

  @override
  Future<EvidencePacket?> loadPacket(String packetId) async {
    final base = await _base;
    final f = File('${base.path}/$_kVaultDir/$packetId/packet.json');
    if (!f.existsSync()) return null;
    try {
      final raw = jsonDecode(await f.readAsString()) as Map<String, Object?>;
      return EvidencePacket.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deletePacket(String packetId) async {
    final base = await _base;
    final dir = Directory('${base.path}/$_kVaultDir/$packetId');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  @override
  Future<List<PacketSummary>> listPackets() async {
    final base = await _base;
    final vaultDir = Directory('${base.path}/$_kVaultDir');
    if (!vaultDir.existsSync()) return const [];
    final summaries = <PacketSummary>[];
    await for (final entry in vaultDir.list()) {
      if (entry is Directory) {
        final f = File('${entry.path}/packet.json');
        if (!f.existsSync()) continue;
        try {
          final raw =
              jsonDecode(await f.readAsString()) as Map<String, Object?>;
          summaries.add(PacketSummary.fromPacket(EvidencePacket.fromJson(raw)));
        } catch (_) {
          // Skip corrupt entries without crashing.
        }
      }
    }
    summaries.sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
    return summaries;
  }

  // ---------------------------------------------------------------------------
  // EvidenceVault — binary assets
  // ---------------------------------------------------------------------------

  @override
  Future<void> putAsset(String packetId, String ref, Uint8List bytes) async {
    final dir = await _packetDir(packetId);
    final ext = ref.startsWith('img') ? 'jpg' : 'wav';
    await _atomicWrite(File('${dir.path}/$ref.$ext'), bytes);
  }

  @override
  Future<Uint8List?> getAsset(String packetId, String ref) async {
    final base = await _base;
    final dir = Directory('${base.path}/$_kVaultDir/$packetId');
    for (final ext in ['jpg', 'wav']) {
      final f = File('${dir.path}/$ref.$ext');
      if (f.existsSync()) return f.readAsBytes();
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // EvidenceVault — turns.jsonl
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveTurnsJsonl(
      String packetId, List<Map<String, Object?>> turns) async {
    if (turns.isEmpty) return;
    final dir = await _packetDir(packetId);
    final buf = StringBuffer();
    for (final t in turns) {
      buf.writeln(jsonEncode(t));
    }
    await _atomicWrite(
        File('${dir.path}/turns.jsonl'), utf8.encode(buf.toString()));
  }

  // ---------------------------------------------------------------------------
  // EvidenceVault — report PDF
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveReportPdf(String packetId, Uint8List pdfBytes) async {
    final dir = await _packetDir(packetId);
    await _atomicWrite(File('${dir.path}/report.pdf'), pdfBytes);
  }

  @override
  Future<Uint8List?> loadReportPdf(String packetId) async {
    final base = await _base;
    final f = File('${base.path}/$_kVaultDir/$packetId/report.pdf');
    if (!f.existsSync()) return null;
    return f.readAsBytes();
  }
}

// ---------------------------------------------------------------------------
// Atomic write helper (module-private)
// ---------------------------------------------------------------------------

/// Write [bytes] to [dest] atomically: flush to `<dest>.tmp` then rename.
///
/// Prevents partial writes from appearing as valid files after a process kill.
Future<void> _atomicWrite(File dest, List<int> bytes) async {
  final tmp = File('${dest.path}.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(dest.path);
}
