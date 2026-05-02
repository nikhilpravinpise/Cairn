/// Conditional export — dart:io-backed implementation on native targets,
/// no-op stub on web.
///
/// Import this file everywhere: callers always get [persistCapturedBytes]
/// regardless of platform.
library;

export 'photo_cache_stub.dart' if (dart.library.io) 'photo_cache_io.dart';
