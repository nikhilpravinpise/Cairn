/// Web / non-io stub.  Draft persistence is a no-op on web; binary assets
/// are never written to the cache directory on web so byte restoration is
/// also a no-op.
library;

import '../state/session_controller.dart';
import 'draft_persistence.dart';

/// Returns the no-op [DraftPersistence] on web.
DraftPersistence createDraftPersistence() => NoOpDraftPersistence();

/// On web, draft restoration is not supported.
Future<SessionDraft?> restoreDraftWithBytes(
    Map<String, Object?> meta) async =>
    null;
