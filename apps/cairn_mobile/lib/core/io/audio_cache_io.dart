/// dart:io — immediate byte persistence for captured audio clips.
///
/// Writes [bytes] to `<tmpDir>/cairn_capture/<packetId>/<ref>.wav` so the
/// audio survives [SessionDraft] between screen transitions during the
/// (potentially long) LLM describe turn. Phase 9's file-backed vault will
/// move the sealed packet to `getApplicationSupportDirectory()` on
/// finalisation.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Write [bytes] for the audio clip identified by [ref] to app-specific
/// storage.
///
/// Uses `getTemporaryDirectory()` which maps to:
/// - Android: `getCacheDir()` — survives Activity round-trips
/// - iOS:     `NSTemporaryDirectory()`
/// - Desktop: OS temp dir
///
/// Silently swallows I/O errors so a disk-full or permissions edge case never
/// blocks the audio capture flow. The in-memory [SessionDraft] copy remains
/// the source of truth.
Future<void> persistCapturedAudio(
  String packetId,
  String ref,
  Uint8List bytes,
) async {
  try {
    final base = await getTemporaryDirectory();
    final folder = Directory('${base.path}/cairn_capture/$packetId');
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
    final file = File('${folder.path}/$ref.wav');
    await file.writeAsBytes(bytes, flush: true);
  } catch (_) {
    // Best-effort; in-memory copy in SessionDraft is authoritative.
  }
}
