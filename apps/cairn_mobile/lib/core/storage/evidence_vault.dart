/// Persistence interface for `EvidencePacket` objects + their binary assets.
///
/// Pass-1 implementation is in-memory only. Persistent web (OPFS / IndexedDB)
/// and mobile (sembast / sqlite) implementations land in later passes; the
/// interface is the contract the rest of the app codes against.
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
  });

  final String packetId;
  final DateTime createdAtUtc;
  final int priorityScore;
  final String priorityBand;
  final String buildingType;
  final String locale;

  factory PacketSummary.fromPacket(EvidencePacket p) => PacketSummary(
        packetId: p.packetId,
        createdAtUtc: p.createdAtUtc,
        priorityScore: p.triage.priorityScore,
        priorityBand: p.triage.priorityBand,
        buildingType: p.building.type,
        locale: p.volunteer.locale,
      );
}

abstract class EvidenceVault {
  Future<void> savePacket(EvidencePacket packet);
  Future<EvidencePacket?> loadPacket(String packetId);
  Future<void> deletePacket(String packetId);
  Future<List<PacketSummary>> listPackets();

  Future<void> putAsset(String packetId, String ref, Uint8List bytes);
  Future<Uint8List?> getAsset(String packetId, String ref);
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
}
