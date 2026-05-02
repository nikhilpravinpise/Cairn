/// Conditional export — dart:io-backed implementation on native targets,
/// no-op stub on web.
///
/// Import this file everywhere: callers always get [persistCapturedAudio]
/// regardless of platform.
library;

export 'audio_cache_stub.dart' if (dart.library.io) 'audio_cache_io.dart';
