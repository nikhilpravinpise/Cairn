/// Persistence contract for the in-progress [SessionDraft].
///
/// The interface operates on raw `Map<String, Object?>` (the metadata JSON from
/// `SessionDraft.toMetaMap()`) rather than on [SessionDraft] directly, which
/// avoids a circular import with `session_controller.dart`.
///
/// Binary assets (photos/audio bytes) live in the photo/audio caches
/// (`<tmpDir>/cairn_capture/<packetId>/`). Only metadata is persisted here.
///
/// Platform implementations:
/// - [NoOpDraftPersistence] — web and tests (no file I/O).
/// - `_FileBackedDraftPersistence` from `file_draft_persistence_io.dart` — Android.
library;

/// Persistence contract for draft metadata.
abstract class DraftPersistence {
  /// Persist draft metadata (from `SessionDraft.toMetaMap()`).
  ///
  /// Called by the [main.dart] listener on every state change. Writes are
  /// best-effort: implementations must silently swallow I/O errors.
  Future<void> saveDraftMeta(Map<String, Object?> meta);

  /// Load the most recently saved draft metadata, or null if none.
  Future<Map<String, Object?>?> loadDraftMeta();

  /// Returns true if a previously saved draft exists on disk.
  Future<bool> hasActiveDraft();

  /// Delete the saved draft (called after sealing or when user starts fresh).
  Future<void> clearDraft();
}

/// No-op [DraftPersistence] for web targets and unit tests.
class NoOpDraftPersistence implements DraftPersistence {
  @override
  Future<void> saveDraftMeta(Map<String, Object?> meta) async {}

  @override
  Future<Map<String, Object?>?> loadDraftMeta() async => null;

  @override
  Future<bool> hasActiveDraft() async => false;

  @override
  Future<void> clearDraft() async {}
}
