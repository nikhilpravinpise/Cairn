/// dart:io-backed [DraftPersistence] for Phase 9.
///
/// Saves draft metadata to:
///   `<appSupportDir>/cairn_draft/active.json`
///
/// Binary assets:
///   `<appSupportDir>/cairn_capture/<packetId>/<ref>.jpg` (durable original)
///   `<appSupportDir>/cairn_capture/<packetId>/<ref>.wav` (durable original)
///   `<tmpDir>/cairn_capture/<packetId>/<ref>.inference`  (regenerable sidecar)
///
/// Originals are durable so a kill/restart can fully restore the draft
/// (resume-session bug fix). Inference sidecars live in tmp because they are
/// cheap to regenerate and there is no benefit to keeping them across reboots.
///
/// All writes are atomic (`*.tmp` → rename). Errors are silently swallowed so
/// an I/O failure never blocks the volunteer's data-capture flow.
///
/// [restoreDraftWithBytes] reads the saved metadata JSON, resolves the bytes
/// from the durable capture directory, and builds a [SessionDraft] ready for
/// injection into [SessionController].
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../io/photo_cache_io.dart' show capturedBytesDir, inferenceBytesDir;
import '../state/session_controller.dart';
import 'draft_persistence.dart';

// ---------------------------------------------------------------------------
// Factory — conditional export entry point
// ---------------------------------------------------------------------------

/// Returns a file-backed [DraftPersistence] on native targets.
DraftPersistence createDraftPersistence() => _FileBackedDraftPersistence();

/// Returns a [DraftPersistence] that writes to [testBaseDir] instead of
/// `getApplicationSupportDirectory()`. Use in unit tests only.
DraftPersistence createDraftPersistenceForTest(Directory testBaseDir) =>
    _FileBackedDraftPersistence(testBaseDir: testBaseDir);

// ---------------------------------------------------------------------------
// Restore helper — conditional export entry point
// ---------------------------------------------------------------------------

/// Restore a [SessionDraft] from saved [meta] by loading bytes from the
/// photo/audio cache directories.
///
/// Returns null if bytes for any expected asset cannot be read (e.g., OS
/// cleared the tmp cache). Photos/audio with missing bytes are silently
/// omitted — the draft is still usable with reduced media.
Future<SessionDraft?> restoreDraftWithBytes(Map<String, Object?> meta) async {
  try {
    final packetId = meta['packet_id'] as String;
    final originals = await capturedBytesDir(packetId);
    final sidecars = await inferenceBytesDir(packetId);

    // Photos: originals from durable app-support; inference sidecars from tmp.
    final photosMeta =
        (meta['photos'] as List? ?? []).cast<Map<String, Object?>>();
    final photoBytes = <String, Uint8List>{};
    final photoInferenceBytes = <String, Uint8List>{};
    for (final pm in photosMeta) {
      final ref = pm['ref'] as String;
      final f = File('${originals.path}/$ref.jpg');
      if (f.existsSync()) photoBytes[ref] = await f.readAsBytes();
      final inference = File('${sidecars.path}/$ref.inference');
      if (inference.existsSync()) {
        photoInferenceBytes[ref] = await inference.readAsBytes();
      }
    }

    // Audio
    final audiosMeta =
        (meta['audios'] as List? ?? []).cast<Map<String, Object?>>();
    final audioBytes = <String, Uint8List>{};
    for (final am in audiosMeta) {
      final ref = am['ref'] as String;
      final f = File('${originals.path}/$ref.wav');
      if (f.existsSync()) audioBytes[ref] = await f.readAsBytes();
    }

    return SessionDraft.fromMetaMap(meta,
        photoBytes: photoBytes,
        audioBytes: audioBytes,
        photoInferenceBytes: photoInferenceBytes);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// _FileBackedDraftPersistence
// ---------------------------------------------------------------------------

class _FileBackedDraftPersistence implements DraftPersistence {
  _FileBackedDraftPersistence({this.testBaseDir});

  /// Overrides [getApplicationSupportDirectory()] — used by tests only.
  final Directory? testBaseDir;

  static const _kDraftDir = 'cairn_draft';
  static const _kDraftFile = 'active.json';

  Future<File> _file() async {
    final base = testBaseDir ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_kDraftDir');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File('${dir.path}/$_kDraftFile');
  }

  @override
  Future<void> saveDraftMeta(Map<String, Object?> meta) async {
    try {
      final f = await _file();
      final json = const JsonEncoder.withIndent('  ').convert(meta);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      // Best-effort — never block the UI.
    }
  }

  @override
  Future<Map<String, Object?>?> loadDraftMeta() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return null;
      return jsonDecode(await f.readAsString()) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> hasActiveDraft() async {
    try {
      return (await _file()).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> clearDraft() async {
    try {
      final f = await _file();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }
}
