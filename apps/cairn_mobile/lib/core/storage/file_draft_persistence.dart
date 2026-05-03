/// Conditional export — file-backed [DraftPersistence] factory and draft
/// restore helper on native targets; no-ops on web.
///
/// Import this file to get [createDraftPersistence()] and
/// [restoreDraftWithBytes()] on any platform.
library;

export 'file_draft_persistence_stub.dart'
    if (dart.library.io) 'file_draft_persistence_io.dart';
