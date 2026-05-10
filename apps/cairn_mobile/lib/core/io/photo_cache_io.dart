/// dart:io — immediate byte persistence for captured photos.
///
/// Writes [bytes] to `<tmpDir>/cairn_capture/<packetId>/<ref>.jpg` so the
/// image survives image_picker's internal cache being evicted by the OS
/// before the [SessionDraft] is sealed. The temp directory is the right
/// location: Phase 9's file-backed vault will move the sealed packet to
/// `getApplicationSupportDirectory()` on finalisation.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Write [bytes] for the image identified by [ref] to app-specific storage.
///
/// Uses `getTemporaryDirectory()` which maps to:
/// - Android: `getCacheDir()` — survives camera intent round-trips
/// - iOS:     `NSTemporaryDirectory()`
/// - Desktop: OS temp dir
///
/// Silently swallows I/O errors so a disk-full or permissions edge case never
/// blocks the photo capture flow. The in-memory [SessionDraft] copy remains
/// the source of truth.
Future<void> persistCapturedBytes(
  String packetId,
  String ref,
  Uint8List bytes,
) async {
  await _persistBytes(packetId, '$ref.jpg', bytes);
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
  await _persistBytes(packetId, '$ref.inference', bytes);
}

Future<void> _persistBytes(
  String packetId,
  String filename,
  Uint8List bytes,
) async {
  try {
    final base = await getTemporaryDirectory();
    final folder = Directory('${base.path}/cairn_capture/$packetId');
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
    final file = File('${folder.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
  } catch (_) {
    // Best-effort; in-memory copy in SessionDraft is authoritative.
  }
}
