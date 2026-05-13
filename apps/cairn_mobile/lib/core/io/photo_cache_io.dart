/// dart:io — immediate byte persistence for captured photos.
///
/// Original capture bytes are written to
/// `<appSupportDir>/cairn_capture/<packetId>/<ref>.jpg`. App support survives
/// process death, OS-driven cache eviction, and reboots, so the volunteer can
/// always resume a draft with their photos intact. (Earlier versions wrote to
/// `getTemporaryDirectory()` which Android may evict between launches — this
/// caused the resume-session-loses-photos bug.)
///
/// Regenerable preprocessed inference bytes still live in
/// `<tmpDir>/cairn_capture/<packetId>/<ref>.inference`. Losing them only costs
/// one re-preprocess on the next describe.
///
/// On packet seal the file-backed vault copies originals to
/// `<appSupportDir>/cairn_vault/<packetId>/` and the capture cache for that
/// packet should be cleared via [clearCapturedBytes].
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Write [bytes] for the image identified by [ref] to durable per-packet
/// storage so a kill/restart can restore the in-progress draft.
///
/// Silently swallows I/O errors so a disk-full or permissions edge case never
/// blocks the photo capture flow. The in-memory [SessionDraft] copy remains
/// the source of truth.
Future<void> persistCapturedBytes(
  String packetId,
  String ref,
  Uint8List bytes,
) async {
  await _persistBytes(
    base: await _captureBaseDir(),
    packetId: packetId,
    filename: '$ref.jpg',
    bytes: bytes,
  );
}

/// Write preprocessed inference bytes for [ref].
///
/// These bytes are a performance sidecar only. If this write fails or the temp
/// cache is later evicted, the app falls back to preprocessing original bytes.
Future<void> persistInferenceBytes(
  String packetId,
  String ref,
  Uint8List bytes,
) async {
  await _persistBytes(
    base: await getTemporaryDirectory(),
    packetId: packetId,
    filename: '$ref.inference',
    bytes: bytes,
  );
}

/// Returns the durable per-packet capture directory used by
/// [persistCapturedBytes] and [persistCapturedAudio]. Internal — exported via
/// `photo_cache.dart` only for the draft restorer.
Future<Directory> capturedBytesDir(String packetId) async {
  final base = await _captureBaseDir();
  return Directory('${base.path}/cairn_capture/$packetId');
}

/// Returns the regenerable inference sidecar directory for [packetId].
Future<Directory> inferenceBytesDir(String packetId) async {
  final base = await getTemporaryDirectory();
  return Directory('${base.path}/cairn_capture/$packetId');
}

/// Delete every captured byte for [packetId] from both the durable capture
/// directory and the inference sidecar cache. Called on packet seal and on
/// draft discard to release storage.
Future<void> clearCapturedBytes(String packetId) async {
  try {
    for (final dir in [
      await capturedBytesDir(packetId),
      await inferenceBytesDir(packetId),
    ]) {
      try {
        if (dir.existsSync()) await dir.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  } catch (_) {
    // Best-effort: directory resolution may fail in test environments or when
    // the platform channel is unavailable. Never block the caller.
  }
}

Future<Directory> _captureBaseDir() async {
  // Android: /data/user/0/<pkg>/files (durable, app-private).
  // iOS:     ~/Library/Application Support/<bundle>.
  // Desktop: platform-specific app-support dir.
  return getApplicationSupportDirectory();
}

Future<void> _persistBytes({
  required Directory base,
  required String packetId,
  required String filename,
  required Uint8List bytes,
}) async {
  try {
    final folder = Directory('${base.path}/cairn_capture/$packetId');
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
    final file = File('${folder.path}/$filename');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  } catch (_) {
    // Best-effort; in-memory copy in SessionDraft is authoritative.
  }
}
