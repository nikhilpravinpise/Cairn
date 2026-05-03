/// Web / non-io stub — returns an [InMemoryEvidenceVault] on platforms without
/// dart:io (primarily web). Phase 9 file persistence is Android-only.
library;

import 'evidence_vault.dart';

/// Returns the in-memory vault on web; the io-backed vault on native targets.
EvidenceVault createFileEvidenceVault() => InMemoryEvidenceVault();
