/// Persistence interface for `EvidencePacket` objects + their binary assets.
///
/// Phase 1 implementation is in-memory only. Phase 9 adds a file-backed
/// implementation (`FileEvidenceVaultIo`) that writes to
/// `getApplicationSupportDirectory()/cairn_vault/<packetId>/`:
///
/// ```
/// packet.json      — atomic-write sealed EvidencePacket
/// img-1.jpg        — original JPEG bytes from the camera
/// aud-1.wav        — mono 16 kHz WAV bytes
/// turns.jsonl      — one JSON object per LLM inference turn
/// report.pdf       — generated PDF (written by the Report screen)
/// ```
library;

import 'dart:typed_data';

import '../models/evidence_packet.dart';

class PacketSummary {
  const PacketSummary({
    required this.packetId,
    required this.createdAtUtc,
    required this.priorityScore,
    required this.priorityBand,
    required this.buildingType,
    required this.locale,
    required this.addressText,
    required this.photoCount,
    required this.hasReportPdf,
  });

  final String packetId;
  final DateTime createdAtUtc;
  final int priorityScore;
  final String priorityBand;
  final String buildingType;
  final String locale;
  final String addressText;
  final int photoCount;
  final bool hasReportPdf;

  factory PacketSummary.fromPacket(
    EvidencePacket p, {
    bool hasReportPdf = false,
  }) =>
      PacketSummary(
        packetId: p.packetId,
        createdAtUtc: p.createdAtUtc,
        priorityScore: p.triage.priorityScore,
        priorityBand: p.triage.priorityBand,
        buildingType: p.building.type,
        locale: p.volunteer.locale,
        addressText: p.location.addressText,
        photoCount: p.images.length,
        hasReportPdf: hasReportPdf,
      );
}

abstract class EvidenceVault {
  Future<void> savePacket(EvidencePacket packet);
  Future<EvidencePacket?> loadPacket(String packetId);
  Future<void> deletePacket(String packetId);
  Future<List<PacketSummary>> listPackets();

  Future<void> putAsset(String packetId, String ref, Uint8List bytes);
  Future<Uint8List?> getAsset(String packetId, String ref);

  /// Append inference turn records as JSONL to the packet folder.
  ///
  /// Each [turns] entry must be the `Map` returned by `TurnRecord.toJson()`.
  /// No-op for in-memory implementations.
  Future<void> saveTurnsJsonl(
      String packetId, List<Map<String, Object?>> turns);

  /// Persist the generated report PDF for [packetId].
  ///
  /// Stored as `report.pdf` inside the packet folder on file-backed vaults.
  Future<void> saveReportPdf(String packetId, Uint8List pdfBytes);

  /// Load a previously saved report PDF, or null if not yet generated.
  Future<Uint8List?> loadReportPdf(String packetId);

  /// True when [packetId] already has a generated `report.pdf`.
  Future<bool> hasReportPdf(String packetId);

  /// Load the persisted `turns.jsonl`, or null if no turn log was written.
  Future<Uint8List?> loadTurnsJsonl(String packetId);
}

class InMemoryEvidenceVault implements EvidenceVault {
  final Map<String, EvidencePacket> _packets = {};
  final Map<String, Map<String, Uint8List>> _assets = {};

  @override
  Future<void> savePacket(EvidencePacket packet) async {
    _packets[packet.packetId] = packet;
  }

  @override
  Future<EvidencePacket?> loadPacket(String packetId) async =>
      _packets[packetId];

  @override
  Future<void> deletePacket(String packetId) async {
    _packets.remove(packetId);
    _assets.remove(packetId);
  }

  @override
  Future<List<PacketSummary>> listPackets() async {
    final list = _packets.values.map(PacketSummary.fromPacket).toList()
      ..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
    return list;
  }

  @override
  Future<void> putAsset(String packetId, String ref, Uint8List bytes) async {
    (_assets[packetId] ??= {})[ref] = bytes;
  }

  @override
  Future<Uint8List?> getAsset(String packetId, String ref) async =>
      _assets[packetId]?[ref];

  @override
  Future<void> saveTurnsJsonl(
      String packetId, List<Map<String, Object?>> turns) async {
    // In-memory: no-op. Turns are tested via FileEvidenceVaultIo.
  }

  @override
  Future<void> saveReportPdf(String packetId, Uint8List pdfBytes) async {
    (_assets[packetId] ??= {})['report.pdf'] = pdfBytes;
  }

  @override
  Future<Uint8List?> loadReportPdf(String packetId) async =>
      _assets[packetId]?['report.pdf'];

  @override
  Future<bool> hasReportPdf(String packetId) async =>
      _assets[packetId]?.containsKey('report.pdf') ?? false;

  @override
  Future<Uint8List?> loadTurnsJsonl(String packetId) async =>
      _assets[packetId]?['turns.jsonl'];
}
