/// dart:io — immediate byte persistence for captured audio clips.
///
/// Writes [bytes] to `<appSupportDir>/cairn_capture/<packetId>/<ref>.wav` so
/// the audio survives process death and Activity round-trips while the
/// SessionDraft is still in-progress. (Earlier versions wrote to
/// `getTemporaryDirectory()`; Android may evict that dir between launches and
/// the audio would be lost on resume.)
library;

import 'dart:io';
import 'dart:typed_data';

import 'photo_cache_io.dart' show capturedBytesDir;

/// Write [bytes] for the audio clip identified by [ref] to durable per-packet
/// storage so a kill/restart can restore the in-progress draft.
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
    final folder = await capturedBytesDir(packetId);
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
    final file = File('${folder.path}/$ref.wav');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  } catch (_) {
    // Best-effort; in-memory copy in SessionDraft is authoritative.
  }
}
