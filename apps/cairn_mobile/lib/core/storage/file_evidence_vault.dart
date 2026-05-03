/// Conditional export — file-backed [EvidenceVault] on native targets,
/// in-memory stub on web.
///
/// Import this file everywhere: callers always get [createFileEvidenceVault]
/// regardless of platform.
library;

export 'file_evidence_vault_stub.dart'
    if (dart.library.io) 'file_evidence_vault_io.dart';
