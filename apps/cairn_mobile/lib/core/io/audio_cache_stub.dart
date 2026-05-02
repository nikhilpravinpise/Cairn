/// Web / test stub — audio byte persistence is a no-op on platforms without
/// dart:io. Bytes are kept in the in-memory [SessionDraft] until Phase 9
/// adds file-backed vault support.
library;

import 'dart:typed_data';

/// Write [bytes] for the audio clip identified by [ref] to app-specific
/// storage.
///
/// On web this is a no-op; on native targets [audio_cache_io.dart] provides
/// the real implementation via the conditional export in [audio_cache.dart].
Future<void> persistCapturedAudio(
  String packetId,
  String ref,
  Uint8List bytes,
) async {
  // No-op on web: in-memory [SessionDraft] is the only store.
}
