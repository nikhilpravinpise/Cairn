# Cairn Mobile App Implementation Analysis Report

**Generated:** 2025-01-15  
**Analysis Scope:** Complete codebase review of `apps/cairn_mobile/`  
**Documentation Sources:**
- `docs/cairn-implementation-plan-0b751e.md` (Original implementation plan)
- `docs/android_repivot_v5.md` (Current execution plan)
- `docs/android_repivot_v5_runlog.md` (Phase completion log)

---

## Executive Summary

The Cairn mobile application implements a FEMA P-154 Level 1 rapid visual screening protocol using on-device Gemma LLM inference. The project follows a phased execution plan (`android_repivot_v5.md`) with **Phase 0-9 marked as COMPLETE** according to the runlog.

**Implementation Status:**  
- Phases 0-9: **COMPLETE** (all automated gates pass: dart analyze clean, flutter test 331/331 passed)
- Manual gate pending: Full flow test on Android device (flutter run -d RZCX920ARVA)

**Key Metrics:**
- Total source files: 47 Dart files
- Test files: 17 test suites
- Core library modules: 8 (models, state, providers, llm, storage, io, audio, location, photos, pdf, triage)
- Feature screens: 10 screens (Bootstrap, Start, Location, Photos, Audio, Describe, Protocol, Humility, Synthesize, Report)

---

## Phase-by-Phase Implementation Status

Based on `docs/android_repivot_v5_runlog.md`:

### Phase 0: Bootstrap & Navigation ✅ COMPLETE
**Deliverables:**
- Flutter project scaffold
- GoRouter navigation configuration
- Permission handling (camera, microphone, location)

**Implementation Verified:**
- `lib/main.dart`: Entry point with FlutterGemma initialization, ProviderScope, MaterialApp.router
- `lib/core/routing/app_router.dart`: GoRouter config with 9-screen FEMA P-154 flow routes
- `lib/features/bootstrap/bootstrap_screen.dart`: Permission request screen with camera, microphone, location permissions

### Phase 1: Core Data Models ✅ COMPLETE
**Deliverables:**
- EvidencePacket schema (v1)
- Schema validator
- In-memory evidence vault

**Implementation Verified:**
- `lib/core/models/evidence_packet.dart`: Complete data model with GeoLocation, BuildingInfo, BBox, Observation, HazardFlagRecord, ProtocolAnswersRecord, TriageResult, VolunteerAttestation, ImageAsset, AudioAsset
- `lib/core/models/evidence_packet_validator.dart`: Stateless validator mirroring `evidence_packet_v1.schema.json`
- `lib/core/storage/evidence_vault.dart`: EvidenceVault interface with InMemoryEvidenceVault implementation
- Schema version: `cairn.evidence.v1`

### Phase 2: Session State Management ✅ COMPLETE
**Deliverables:**
- SessionDraft class
- SessionController (Riverpod Notifier)
- Session lifecycle (start, mutate, seal)

**Implementation Verified:**
- `lib/core/state/session_controller.dart`: SessionDraft with all fields (location, building, photos, audios, observations, hazards, protocol answers, triage, turns), SessionController with startNew, setLocation, setBuilding, addPhoto, addAudio, recordObservation, applyProtocolDelta, computeAndStoreTriage, recordTurn, sealAndSave, restoreDraft, abandon
- Auto-save listener in `main.dart`: Saves draft meta on state changes, clears draft on abandon

### Phase 3: Model Registry & Gemma Session ✅ COMPLETE
**Deliverables:**
- ModelSpec registry
- GemmaSession wrapper
- Session profiles (vision, audio, synthesis, standard)

**Implementation Verified:**
- `lib/core/llm/model_registry.dart`: ModelSpec class with 2 models (e2b, e4b), platform-specific file type resolution
- `lib/core/llm/gemma_session.dart`: GemmaSession with openForVision, openForAudio, openForSynthesis, openStandard profiles, GemmaInferenceResult with text, thinking, ttftMs, wallclockMs, outputCharCount

### Phase 4: LLM Orchestrator ✅ COMPLETE
**Deliverables:**
- GemmaOrchestrator
- Four task contracts (describe_photo, ask_followup, protocol_answer, synthesize)
- Contract enforcement

**Implementation Verified:**
- `lib/core/llm/orchestrator.dart`: Complete orchestrator with DescribePhotoResult, DescribeAudioResult, AskFollowupResult, ProtocolAnswerResult, SynthesizeResult
- Contract checks:
  - model_tags enum validation against kAllowedModelTags
  - bbox_annotations validation (4 integers in 0..1000)
  - priority_score/priority_band rejection in synthesize (rule 8)
- `lib/core/llm/json_extract.dart`: JSON extraction utility

### Phase 5: Start & Location Screens ✅ COMPLETE
**Deliverables:**
- Start screen (model selection, load, draft resume)
- Location screen (GPS acquisition, building typology)

**Implementation Verified:**
- `lib/features/start/start_screen.dart`: Model selection UI, model loading with progress, draft resume/discard banner, recent reports display
- `lib/features/location/location_screen.dart`: GPS acquisition with error taxonomy (denied, deniedForever, servicesDisabled, timeout, unknown), address editing, building type/stories selection, skip GPS option
- `lib/core/location/location_service.dart`: LocationResolver interface, GeolocatorLocationResolver, resolveLocation function, kSkippedGeoLocation sentinel

### Phase 6: Photos Screen (Two-Phase Capture) ✅ COMPLETE
**Deliverables:**
- Photos screen with capture-describe two-phase flow
- OOM prevention
- Android lost-data recovery
- Photo cache persistence

**Implementation Verified:**
- `lib/features/photos/photos_screen.dart`: Two-phase capture (Capture → Describe), required photo slots (front, ground_floor, cracks, foundation), optional slot, Gemma description integration
- `lib/core/photos/pending_slot_store.dart`: SharedPreferences-based slot persistence for Android activity kill recovery
- `lib/core/io/photo_cache.dart`: Conditional export for photo byte persistence
- `lib/core/io/photo_cache_io.dart`: Writes to `<tmpDir>/cairn_capture/<packetId>/<ref>.jpg`

### Phase 7: Audio Screen ✅ COMPLETE
**Deliverables:**
- Audio screen with record-stop-encode pipeline
- Optional Gemma audio description
- Web fallback

**Implementation Verified:**
- `lib/features/audio/audio_screen.dart`: Audio recording with amplitude visualization, 30-second max duration, Gemma audio description, web fallback UI
- `lib/core/audio/cairn_audio_recorder.dart`: Conditional export
- `lib/core/audio/cairn_audio_recorder_native.dart`: Real audio capture via `record` package, mono 16kHz WAV encoding
- `lib/core/audio/cairn_audio_recorder_stub.dart`: Web stub (isSupported = false)
- `lib/core/io/audio_cache.dart`: Conditional export
- `lib/core/io/audio_cache_io.dart`: Writes to `<tmpDir>/cairn_capture/<packetId>/<ref>.wav`

### Phase 8: Describe, Protocol, Humility Screens ✅ COMPLETE
**Deliverables:**
- Describe screen (volunteer notes)
- Protocol screen (FEMA P-154 questions)
- Humility screen (follow-up for low-confidence obs)

**Implementation Verified:**
- `lib/features/describe/describe_screen.dart`: Free-text volunteer notes as `volunteer_note_v1` observations, displays prior Gemma observations
- `lib/features/protocol/protocol_screen.dart`: 6 FEMA P-154 Level 1 questions (visible collapse, building off foundation, leaning, ground failure adjacent, falling hazards, adjacent leaning), LLM protocol_answer integration
- `lib/features/humility/humility_screen.dart`: Finds lowest-confidence observation, askFollowup turn, records `humility_override_v1` observation, skips if confidence >= 0.8 or no observations

### Phase 9: Synthesize, Report, File Persistence ✅ COMPLETE
**Deliverables:**
- Synthesize screen (thinking-mode synthesis)
- Report screen (PDF generation, QR code, share)
- File-backed evidence vault
- Draft persistence
- turns.jsonl logging

**Implementation Verified:**
- `lib/features/synthesize/synthesize_screen.dart`: Reloads model with synthesis profile (thinking=true), calls orchestrator.synthesize, records TurnRecord, computes triage, navigates to report
- `lib/features/report/report_screen.dart`: Seals SessionDraft into EvidencePacket, validates, saves to vault, displays priority badge, rationale, photos, QR code, PDF generation, JSON sharing, new session action
- `lib/core/pdf/report_pdf_builder.dart`: Two-page A4 PDF with header, priority badge, rationale, building/location, observations, protocol answers, photos, attestation, footer
- `lib/core/storage/file_evidence_vault.dart`: Conditional export
- `lib/core/storage/file_evidence_vault_io.dart`: File-backed vault to `<appSupportDir>/cairn_vault/<packetId>/` with atomic writes, packet.json, assets, turns.jsonl, report.pdf
- `lib/core/storage/file_evidence_vault_stub.dart`: Web stub (InMemoryEvidenceVault)
- `lib/core/storage/draft_persistence.dart`: DraftPersistence interface, NoOpDraftPersistence
- `lib/core/storage/file_draft_persistence.dart`: Conditional export
- `lib/core/storage/file_draft_persistence_io.dart`: File-backed draft to `<appSupportDir>/cairn_draft/active.json`, restoreDraftWithBytes helper
- `lib/core/storage/file_draft_persistence_stub.dart`: Web stub (NoOpDraftPersistence)
- TurnRecord class in session_controller.dart: ts, task, observationId, ttftMs, wallclockMs, outputCharCount, thinkingChars
- sealAndSave now calls validateOrThrow and saveTurnsJsonl

### Phase 10: Manual Device Test ⏳ PENDING
**Status:** Not started per runlog  
**Required:** Full flow test on Android device (flutter run -d RZCX920ARVA)

---

## Core Library Implementation Analysis

### Models (`lib/core/models/`)

**Files:**
- `evidence_packet.dart` (500 lines)
- `evidence_packet_validator.dart` (495 lines)

**Analysis:**
- Complete implementation of EvidencePacket schema matching `evidence_packet_v1.schema.json`
- All nested models implemented: GeoLocation, BuildingInfo, BBox, Observation, HazardFlagRecord, ProtocolAnswersRecord, TriageResult, VolunteerAttestation, ImageAsset, AudioAsset
- Validator enforces all schema constraints including:
  - Schema version: `cairn.evidence.v1`
  - Allowed model tags: 19 tags (diagonal_crack, horizontal_crack, vertical_crack, x_pattern_crack, concrete_spalling, exposed_rebar, column_base_damage, beam_column_joint_damage, soft_story_condition, pounding_damage, infill_wall_crack, out_of_plane_failure, foundation_displacement, chimney_damage, parapet_damage, falling_hazard_unsecured, uncertain_structural, uncertain_cosmetic, no_visible_damage)
  - Allowed priority bands: LOW, MEDIUM, HIGH, CRITICAL
  - Allowed building types: concrete_moment_frame, unreinforced_masonry, wood_light_frame, steel, mixed, unknown
  - Allowed quants: int4, int8, fp16, fp32, bf16
  - Allowed languages: en, es, tr
- All classes include toJson() and fromJson() methods for serialization

### State Management (`lib/core/state/`)

**Files:**
- `session_controller.dart` (711 lines)

**Analysis:**
- SessionDraft class with all required fields:
  - packetId, createdAtUtc, modelName, modelQuant, modelLora, localeBCP47
  - location (GeoLocation), building (BuildingInfo)
  - photos (List<CapturedPhoto>), audios (List<CapturedAudio>)
  - observations (List<Observation>), hazardsFlagged (List<HazardFlagRecord>)
  - protocolAnswers (ProtocolAnswersRecord), triage (TriageResult)
  - turns (List<TurnRecord>)
  - Internal counters: _imageCounter, _audioCounter, _obsCounter
- SessionController (Riverpod Notifier) methods:
  - startNew, abandon
  - setLocation, setBuilding
  - addPhoto, addAudio
  - recordObservation
  - applyProtocolDelta
  - computeAndStoreTriage
  - recordTurn
  - restoreDraft
  - sealAndSave
- seal() method creates EvidencePacket with:
  - App version: 0.1.0
  - Protocol: FEMA-P-154-L1
  - Volunteer attestation with SHA256 signature hash
  - Image assets with SHA256 hashes
  - Audio assets with SHA256 hashes
- toMetaMap/fromMetaMap for draft persistence
- cloneShallow preserves counters
- lowestConfidenceObservation helper for humility screen
- packetSummaryForSynthesis omits model_description for volunteer observations

### Providers (`lib/core/providers.dart`)

**Files:**
- `providers.dart` (140 lines)

**Analysis:**
- Centralized Riverpod providers:
  - systemPromptProvider
  - selectedModelKeyProvider, selectedModelSpecProvider
  - gemmaSessionProvider with GemmaSessionNotifier
  - orchestratorProvider
  - evidenceVaultProvider (uses createFileEvidenceVault)
  - draftPersistenceProvider (uses createDraftPersistence)
  - sessionControllerProvider
- Conditional exports for file-backed persistence (dart:io available check)

### LLM Integration (`lib/core/llm/`)

**Files:**
- `gemma_session.dart` (335 lines)
- `orchestrator.dart` (485 lines)
- `model_registry.dart` (78 lines)
- `json_extract.dart` (49 lines)

**Analysis:**
- GemmaSession wrapper around flutter_gemma:
  - Session profiles: openForVision, openForAudio, openForSynthesis, openStandard
  - Capability flags: supportImage, supportAudio, isThinking
  - GemmaInferenceResult: text, thinking, ttftMs, wallclockMs, outputCharCount
  - Model installation from HuggingFace URLs
  - Chat history clearing after each turn
- GemmaOrchestrator implements four task contracts:
  - describePhoto: tag validation, bbox validation (4 coords in 0..1000)
  - describeAudio: tag validation
  - askFollowup: returns null question if no follow-up needed
  - protocolAnswer: exactly one delta key
  - synthesize: rejects priority_score/priority_band (rule 8)
- Model registry with 2 models:
  - e2b: Gemma E2B IT (LiteRT-LM), int4, text+image, 8192 context
  - e4b: Gemma E4B IT (LiteRT-LM), int4, text+image, 8192 context
- Platform-specific file type resolution (.task for web, .litertlm for Android)
- JSON extraction with brace-depth tracking

### Storage (`lib/core/storage/`)

**Files:**
- `evidence_vault.dart` (122 lines)
- `file_evidence_vault.dart` (10 lines)
- `file_evidence_vault_io.dart` (191 lines)
- `file_evidence_vault_stub.dart` (9 lines)
- `draft_persistence.dart` (47 lines)
- `file_draft_persistence.dart` (10 lines)
- `file_draft_persistence_io.dart` (144 lines)
- `file_draft_persistence_stub.dart` (16 lines)

**Analysis:**
- EvidenceVault interface:
  - savePacket, loadPacket, deletePacket, listPackets
  - putAsset, getAsset
  - saveTurnsJsonl, saveReportPdf, loadReportPdf
- InMemoryEvidenceVault for web/tests
- FileEvidenceVaultIo for Android:
  - Writes to `<appSupportDir>/cairn_vault/<packetId>/`
  - Atomic writes (write to .tmp then rename)
  - File layout: packet.json, img-*.jpg, aud-*.wav, turns.jsonl, report.pdf
- DraftPersistence interface:
  - saveDraftMeta, loadDraftMeta, hasActiveDraft, clearDraft
- NoOpDraftPersistence for web/tests
- _FileBackedDraftPersistence for Android:
  - Writes to `<appSupportDir>/cairn_draft/active.json`
  - Atomic writes, silent error swallowing (best-effort)
- restoreDraftWithBytes helper loads bytes from cache directory

### I/O Caching (`lib/core/io/`)

**Files:**
- `photo_cache.dart` (9 lines)
- `photo_cache_io.dart` (42 lines)
- `audio_cache.dart` (9 lines)
- `audio_cache_io.dart` (43 lines)

**Analysis:**
- persistCapturedBytes: writes to `<tmpDir>/cairn_capture/<packetId>/<ref>.jpg`
- persistCapturedAudio: writes to `<tmpDir>/cairn_capture/<packetId>/<ref>.wav`
- Silent error swallowing (in-memory SessionDraft is authoritative)
- Conditional exports for dart:io availability

### Audio Recording (`lib/core/audio/`)

**Files:**
- `cairn_audio_recorder.dart` (10 lines)
- `cairn_audio_recorder_native.dart` (173 lines)
- `cairn_audio_recorder_stub.dart` (59 lines)

**Analysis:**
- CairnAudioRecorder interface:
  - isSupported, hasPermission, start, isRecording, stop, cancel, dispose
  - amplitudeStream with normalized 0.0-1.0 values
- Native implementation via `record` package:
  - Config: mono, 16kHz, WAV encoder, no AGC/noise suppression
  - Max duration: 30 seconds
  - Temp file cleanup after stop
- Web stub: isSupported = false, all methods no-op

### Location Service (`lib/core/location/`)

**Files:**
- `location_service.dart` (235 lines)

**Analysis:**
- LocationErrorKind enum: denied, deniedForever, servicesDisabled, timeout, unknown
- LocationErrorKindX extensions: label, guidance, canRetryInApp, requiresSettings
- LocationResult sealed class: LocationSuccess, LocationFailure
- kSkippedGeoLocation sentinel (accuracyMeters = -1)
- LocationResolver interface for test injection
- GeolocatorLocationResolver production implementation
- resolveLocation function with 30-second timeout, best-effort reverse geocoding

### Photos (`lib/core/photos/`)

**Files:**
- `pending_slot_store.dart` (42 lines)

**Analysis:**
- PendingSlotStore: SharedPreferences-based slot persistence
- Saves slot key before camera intent launch for Android activity kill recovery
- Used by PhotosScreen to recover which slot lost-data belongs to

### PDF Generation (`lib/core/pdf/`)

**Files:**
- `report_pdf_builder.dart` (508 lines)

**Analysis:**
- buildReportPdf function: Two-page A4 report
- Page 1: header, priority badge, info row, triage rationale, uncertainty notes, engineer banner
- Page 2: observations, protocol answers, photos (up to 4), attestation, footer
- Color-coded priority bands: CRITICAL (red), HIGH (orange), MEDIUM (orange), LOW (green)
- ASCII-only output (replaced Unicode symbols with ASCII)
- Optional imageBytes map for photo embedding
- Disclaimer about non-licensed volunteer status

### Triage (`lib/core/triage/`)

**Files:**
- `priority.dart` (79 lines)

**Analysis:**
- PriorityBand enum: low, medium, high, critical
- ProtocolAnswers class with 6 fields
- HazardFlag class with code and severity
- BuildingMeta class with type and stories
- kHazardSeverityPoints: high=3, moderate=2, low=1
- priorityScore function (byte-identical to Python):
  - Collapse/off-foundation → 10
  - Severe lean → 9
  - Sum of hazard severity points + ground failure + falling hazards + URM + soft story
  - Clamped to 1-10
- priorityBand function: ≤3=LOW, ≤6=MEDIUM, ≤8=HIGH, else=CRITICAL
- priorityBandLabel function

---

## Feature Screens Implementation Analysis

### Bootstrap Screen (`lib/features/bootstrap/bootstrap_screen.dart`)
**Lines:** 102  
**Purpose:** Permission request on app launch  
**Implementation:**
- Requests camera, microphone, location permissions
- Displays error with "Open Settings" button for permanently denied permissions
- Navigates to /start on success
- Retry button for permission re-request

### Start Screen (`lib/features/start/start_screen.dart`)
**Lines:** 387  
**Purpose:** Model selection, loading, draft resume  
**Implementation:**
- Model selection dropdown (e2b, e4b)
- Model loading with progress display (download, load phases)
- Draft banner with Resume/Discard actions
- Recent reports list from vault
- _DraftBanner widget for draft management
- Model unload on abandon

### Location Screen (`lib/features/location/location_screen.dart`)
**Lines:** 409  
**Purpose:** GPS acquisition, building info entry  
**Implementation:**
- GPS acquisition with 30-second timeout
- Error handling for all LocationErrorKind types
- Address text editing
- Building type dropdown (6 types)
- Stories above grade selector
- Retry GPS button
- Skip GPS option (uses kSkippedGeoLocation)
- Open Settings button for deniedForever/servicesDisabled

### Photos Screen (`lib/features/photos/photos_screen.dart`)
**Lines:** 788  
**Purpose:** Photo capture and description  
**Implementation:**
- Two-phase flow: Capture → Describe (prevents OOM)
- Required photo slots: front, ground_floor, cracks, foundation
- Optional slot: other
- PendingSlotStore for Android activity kill recovery
- Lost data recovery via image_picker.retrieveLostData
- Gemma description integration with orchestrator.describePhoto
- Photo thumbnail display
- Progress indicator for description
- Error handling with retry option

### Audio Screen (`lib/features/audio/audio_screen.dart`)
**Lines:** 991  
**Purpose:** Audio recording and description  
**Implementation:**
- Audio recording with amplitude visualization
- 30-second max duration with countdown
- Record/Stop/Cancel/Retry actions
- CairnAudioRecorder integration
- Optional Gemma audio description (if session loaded with audio support)
- Web fallback UI (recording not supported)
- Permission handling
- Processing state after recording

### Describe Screen (`lib/features/describe/describe_screen.dart`)
**Lines:** 166  
**Purpose:** Volunteer free-text notes  
**Implementation:**
- Free-text input for volunteer observations
- Records as `volunteer_note_v1` observation (modelDescription=null, modelTags=[], modelConfidence=1.0)
- Displays prior Gemma observations for context
- Submit or Skip actions
- Navigates to /protocol

### Protocol Screen (`lib/features/protocol/protocol_screen.dart`)
**Lines:** 292  
**Purpose:** FEMA P-154 Level 1 questions  
**Implementation:**
- 6 protocol questions presented one at a time:
  1. Visible collapse / severe racking
  2. Building off foundation
  3. Significant leaning (none/slight/moderate/severe)
  4. Ground failure adjacent
  5. Falling hazards present
  6. Adjacent building leaning
- Yes/No or leaning severity selection
- LLM protocol_answer integration via orchestrator
- Skip question option
- Back navigation
- Progress indicator

### Humility Screen (`lib/features/humility/humility_screen.dart`)
**Lines:** 349  
**Purpose:** Follow-up for low-confidence observations  
**Implementation:**
- Finds lowest-confidence observation
- Skips if confidence >= 0.8 or no observations
- LLM askFollowup integration
- Displays target observation with photo
- Free-text answer input
- Records as `humility_override_v1` observation (modelDescription=null, modelTags=[], modelConfidence=1.0)
- Skip option
- Auto-navigates to /synthesize if no follow-up needed

### Synthesize Screen (`lib/features/synthesize/synthesize_screen.dart`)
**Lines:** 343  
**Purpose:** Thinking-mode synthesis  
**Implementation:**
- Reloads model with synthesis profile (thinking=true)
- Orchestrator.synthesize call with packetSummary
- Records TurnRecord with ttftMs, wallclockMs, outputCharCount, thinkingChars
- Calls computeAndStoreTriage with rationale and uncertainty
- Displays progress phases: reloading model, synthesizing, done
- Optional thinking trace display
- Auto-navigates to /report after 900ms delay
- Error handling with retry/skip options

### Report Screen (`lib/features/report/report_screen.dart`)
**Lines:** 691  
**Purpose:** Final report display and export  
**Implementation:**
- Seals SessionDraft into EvidencePacket on first build
- Validates via EvidencePacketValidator.validateOrThrow
- Saves to vault via sealAndSave
- Clears draft after sealing
- Displays:
  - Priority badge with score and band (color-coded)
  - Building/location info card
  - Triage rationale bullets
  - Uncertainty notes
  - Engineer follow-up banner
  - Photo thumbnails (from in-memory bytes)
  - Packet ID with QR code
  - Disclaimer
- Actions:
  - Save/Share PDF (via printing package)
  - Share JSON (via share_plus)
  - Start new screening
- Error handling with retry

---

## Test Coverage Analysis

### Test Files (17 total)

**Files Identified:**
1. `audio_capture_test.dart`
2. `draft_persistence_test.dart`
3. `evidence_packet_test.dart`
4. `evidence_packet_validator_test.dart`
5. `json_extract_test.dart`
6. `location_service_test.dart`
7. `model_registry_platform_test.dart`
8. `orchestrator_contract_test.dart`
9. `orchestrator_followup_test.dart`
10. `photos_lost_data_test.dart`
11. `photos_screen_test.dart`
12. `priority_test.dart`
13. `report_pdf_test.dart`
14. `session_controller_test.dart`
15. `vault_test.dart`
16. `volunteer_authored_test.dart`
17. `web_bootstrap_test.dart`

### Test Coverage Details (from reviewed files)

**session_controller_test.dart (459 lines):**
- startNew populates packetId + createdAt
- addPhoto assigns refs (img-1 to img-100)
- generateImageId yields sequential IDs
- applyProtocolDelta mutates exactly one field
- required photo coverage requires all four FEMA slots
- lowestConfidenceObservation returns correct one
- computeAndStoreTriage uses Dart scorer (not LLM)
- mutators emit new state instance (Riverpod listener regression test)
- cloneShallow preserves counters
- generateObservationId yields obs-1 to obs-100
- generateAudioId yields aud-1 to aud-10
- counters are independent across id spaces
- addAudio records ref and metadata
- volunteer_note_v1 observation has correct shape
- humility_override_v1 observation has correct shape
- packetSummaryForSynthesis omits model_description for volunteer obs
- seal + save into vault with signature hash
- TurnRecord toJson/fromJson round-trip
- recordTurn appends to draft.turns
- restoreDraft replaces current state
- sealAndSave writes turns to vault.saveTurnsJsonl

**vault_test.dart (265 lines):**
- savePacket/loadPacket round-trip
- atomic writes (no .tmp file remains)
- loadPacket returns null for missing id
- packet.json is valid JSON with expected keys
- listPackets returns empty when vault dir absent
- listPackets returns saved packets in descending date order
- deletePacket removes directory and from listing
- deletePacket is no-op for missing id
- putAsset/getAsset stores and retrieves image bytes
- putAsset/getAsset stores and retrieves audio bytes
- getAsset returns null for unknown ref
- asset file named <ref>.jpg for images
- asset file named <ref>.wav for audio
- saveTurnsJsonl writes JSONL with one object per line
- saveTurnsJsonl no-op when turns list empty
- saveReportPdf/loadReportPdf round-trips PDF bytes
- loadReportPdf returns null before PDF written

**orchestrator_contract_test.dart (417 lines):**
- describePhoto tag validation (valid tags, empty tags, unknown tag throws)
- describePhoto bbox validation (valid bbox, boundary values, wrong element count, out of range, second entry invalid, empty list)
- describePhoto TTFT/wallclock propagation
- describeAudio tag validation
- describeAudio missing model_description throws
- describeAudio no JSON throws
- describeAudio TTFT/wallclock propagated
- synthesize contract (valid response, priority_score throws, priority_band throws, task in error, missing triage_draft throws, no JSON throws)
- synthesize TTFT/wallclock propagated
- protocolAnswer TTFT/wallclock propagation

**evidence_packet_test.dart (140 lines):**
- toJson/fromJson preserves all fields
- top-level schema string is correct
- omits null model.lora when not set

**priority_test.dart (106 lines):**
- priorityScore parity with Python (collapse=10, off-foundation=10, severe lean=9, urm+soft_story=9, clean=1, ground+falling=4)
- priorityBand matches Python (1-3=LOW, 4-6=MEDIUM, 7-8=HIGH, 9-10=CRITICAL)

**report_pdf_test.dart (173 lines):**
- returns bytes starting with %PDF signature
- completes without error for LOW/MEDIUM/HIGH/CRITICAL priorities
- accepts empty imageBytes without error
- accepts packet with no observations

**Test Status per Runlog:**
- flutter test: 331/331 passed
- Phase 9 added 52 tests
- All automated gates pass

---

## Configuration and Constants

### App Version
- **kAppVersion**: '0.1.0' (from `session_controller.dart`)

### Schema Version
- **kSchemaVersion**: 'cairn.evidence.v1' (from `evidence_packet.dart`)

### Volunteer Attestation
- **kAttestationEn**: 'I am not a licensed engineer. This is preliminary screening only.' (from `session_controller.dart`)

### Required Photo Slots
- **kRequiredPhotoSlots**: {'front', 'ground_floor', 'cracks', 'foundation'} (from `session_controller.dart`)

### Allowed Leaning Values
- **kAllowedLeaningValues**: {'none', 'slight', 'moderate', 'severe'} (from `session_controller.dart`)

### Model Registry
- **e2b**: Gemma E2B IT (LiteRT-LM), int4, text+image, 8192 context
- **e4b**: Gemma E4B IT (LiteRT-LM), int4, text+image, 8192 context

### Audio Configuration
- **_kMaxDurationS**: 30.0 (from `audio_screen.dart`)
- **_kSampleRate**: 16000 Hz (from `cairn_audio_recorder_native.dart`)
- **_kChannels**: 1 (mono) (from `cairn_audio_recorder_native.dart`)

### Humility Screen Threshold
- **_kSkipIfConfidenceAtLeast**: 0.8 (from `humility_screen.dart`)

---

## Platform-Specific Implementation

### Android (Native)
- File-backed evidence vault to `<appSupportDir>/cairn_vault/`
- File-backed draft persistence to `<appSupportDir>/cairn_draft/`
- Photo/audio cache to `<tmpDir>/cairn_capture/`
- Real audio recording via `record` package
- GPS via `geolocator` package
- Camera via `image_picker` package
- PendingSlotStore for Android activity kill recovery
- Atomic file writes (write to .tmp then rename)

### Web
- InMemoryEvidenceVault (no file I/O)
- NoOpDraftPersistence (no draft persistence)
- CairnAudioRecorder stub (isSupported = false)
- No audio capture
- PDF generation via printing.layoutPdf
- Model files: .task format from HuggingFace

### iOS
- Same file-backed persistence as Android (via dart:io)
- Real audio recording
- GPS support
- Camera support

---

## Dependencies (from pubspec.yaml inference)

### Core Flutter
- flutter_riverpod (state management)
- go_router (navigation)
- permission_handler (permissions)

### LLM
- flutter_gemma (on-device Gemma inference)

### Media
- image_picker (camera)
- record (audio recording)
- geolocator (GPS)
- geocoding (reverse geocoding)

### Persistence
- path_provider (app directories)
- shared_preferences (slot store)

### PDF
- pdf (PDF generation)
- printing (PDF sharing)
- qr_flutter (QR codes)
- share_plus (JSON sharing)

### Testing
- flutter_test (unit tests)
- mockito (mocking, inferred from test patterns)

---

## Comparison with Documented Plans

### android_repivot_v5.md Plan vs Implementation

**Phase 0: Bootstrap & Navigation**
- Plan: Flutter scaffold, GoRouter, permissions
- Implementation: ✅ COMPLETE - All requirements met

**Phase 1: Core Data Models**
- Plan: EvidencePacket schema, validator, in-memory vault
- Implementation: ✅ COMPLETE - All requirements met, schema version v1

**Phase 2: Session State Management**
- Plan: SessionDraft, SessionController, lifecycle
- Implementation: ✅ COMPLETE - All requirements met, auto-save listener added

**Phase 3: Model Registry & Gemma Session**
- Plan: ModelSpec registry, GemmaSession wrapper, session profiles
- Implementation: ✅ COMPLETE - All requirements met, 4 profiles implemented

**Phase 4: LLM Orchestrator**
- Plan: Orchestrator, 4 task contracts, contract enforcement
- Implementation: ✅ COMPLETE - All requirements met, Phase 6 contract checks added

**Phase 5: Start & Location Screens**
- Plan: Start screen, Location screen, GPS, building typology
- Implementation: ✅ COMPLETE - All requirements met, error taxonomy implemented

**Phase 6: Photos Screen**
- Plan: Two-phase capture, OOM prevention, lost-data recovery, photo cache
- Implementation: ✅ COMPLETE - All requirements met, PendingSlotStore added

**Phase 7: Audio Screen**
- Plan: Audio screen, record-stop-encode, Gemma audio description, web fallback
- Implementation: ✅ COMPLETE - All requirements met, CairnAudioRecorder implemented

**Phase 8: Describe, Protocol, Humility Screens**
- Plan: Volunteer notes, protocol questions, humility follow-up
- Implementation: ✅ COMPLETE - All requirements met, humility threshold 0.8

**Phase 9: Synthesize, Report, File Persistence**
- Plan: Synthesize screen, Report screen, file vault, draft persistence, turns.jsonl
- Implementation: ✅ COMPLETE - All requirements met, PDF builder added

**Phase 10: Manual Device Test**
- Plan: Full flow test on Android device
- Implementation: ⏳ PENDING - Not started per runlog

### cairn-implementation-plan-0b751e.md vs Implementation

The original implementation plan outlines the overall architecture and requirements. The current implementation via android_repivot_v5 phases aligns with the original plan's core goals:

**Original Plan Requirements:**
- FEMA P-154 Level 1 protocol: ✅ IMPLEMENTED
- On-device Gemma LLM: ✅ IMPLEMENTED
- Evidence packet schema: ✅ IMPLEMENTED (v1)
- 9-screen flow: ✅ IMPLEMENTED
- Offline persistence: ✅ IMPLEMENTED (Phase 9)
- Photo capture with description: ✅ IMPLEMENTED
- Audio capture with description: ✅ IMPLEMENTED
- Volunteer notes: ✅ IMPLEMENTED
- Protocol questions: ✅ IMPLEMENTED
- Humility check: ✅ IMPLEMENTED
- Synthesis with thinking mode: ✅ IMPLEMENTED
- PDF report generation: ✅ IMPLEMENTED
- QR code sharing: ✅ IMPLEMENTED

---

## Architecture Quality Assessment

### Strengths
1. **Clean Separation of Concerns**: Core library, features, and UI are well-separated
2. **Platform Abstraction**: Conditional exports for dart:io availability enable web support
3. **Type Safety**: Strong typing throughout, sealed classes for result types
4. **Error Handling**: Comprehensive error taxonomy (LocationErrorKind, GemmaContractError)
5. **State Management**: Riverpod provides reactive state with auto-save listener
6. **Contract Enforcement**: Orchestrator validates LLM responses before acceptance
7. **Atomic Persistence**: File writes use temp-then-rename pattern for crash safety
8. **Test Coverage**: 331/331 tests passing, comprehensive test suites
9. **Documentation**: Inline documentation explains design decisions
10. **Deterministic Triage**: Priority score computed in Dart, not by LLM (rule 8)

### Areas for Consideration
1. **Manual Test Pending**: Phase 10 device test not yet completed
2. **Web Limitations**: Audio recording not supported on web (stub only)
3. **Model Loading**: Large model downloads may be slow on poor connections
4. **Memory Management**: Two-phase photo capture prevents OOM but requires careful state management
5. **Error Recovery**: Some errors (e.g., LLM contract violations) currently surface to user without retry loops

---

## File Organization Summary

```
lib/
├── main.dart (entry point)
├── core/
│   ├── models/
│   │   ├── evidence_packet.dart
│   │   └── evidence_packet_validator.dart
│   ├── state/
│   │   └── session_controller.dart
│   ├── providers.dart
│   ├── routing/
│   │   └── app_router.dart
│   ├── llm/
│   │   ├── gemma_session.dart
│   │   ├── orchestrator.dart
│   │   ├── model_registry.dart
│   │   └── json_extract.dart
│   ├── storage/
│   │   ├── evidence_vault.dart
│   │   ├── file_evidence_vault.dart
│   │   ├── file_evidence_vault_io.dart
│   │   ├── file_evidence_vault_stub.dart
│   │   ├── draft_persistence.dart
│   │   ├── file_draft_persistence.dart
│   │   ├── file_draft_persistence_io.dart
│   │   └── file_draft_persistence_stub.dart
│   ├── io/
│   │   ├── photo_cache.dart
│   │   ├── photo_cache_io.dart
│   │   ├── audio_cache.dart
│   │   └── audio_cache_io.dart
│   ├── audio/
│   │   ├── cairn_audio_recorder.dart
│   │   ├── cairn_audio_recorder_native.dart
│   │   └── cairn_audio_recorder_stub.dart
│   ├── location/
│   │   └── location_service.dart
│   ├── photos/
│   │   └── pending_slot_store.dart
│   ├── pdf/
│   │   └── report_pdf_builder.dart
│   └── triage/
│       └── priority.dart
└── features/
    ├── bootstrap/
    │   └── bootstrap_screen.dart
    ├── start/
    │   └── start_screen.dart
    ├── location/
    │   └── location_screen.dart
    ├── photos/
    │   └── photos_screen.dart
    ├── audio/
    │   └── audio_screen.dart
    ├── describe/
    │   └── describe_screen.dart
    ├── protocol/
    │   └── protocol_screen.dart
    ├── humility/
    │   └── humility_screen.dart
    ├── synthesize/
    │   └── synthesize_screen.dart
    └── report/
        └── report_screen.dart

test/
├── audio_capture_test.dart
├── draft_persistence_test.dart
├── evidence_packet_test.dart
├── evidence_packet_validator_test.dart
├── json_extract_test.dart
├── location_service_test.dart
├── model_registry_platform_test.dart
├── orchestrator_contract_test.dart
├── orchestrator_followup_test.dart
├── photos_lost_data_test.dart
├── photos_screen_test.dart
├── priority_test.dart
├── report_pdf_test.dart
├── session_controller_test.dart
├── vault_test.dart
├── volunteer_authored_test.dart
└── web_bootstrap_test.dart
```

---

## Conclusion

The Cairn mobile application implementation is **substantially complete** through Phase 9 of the android_repivot_v5 execution plan. All core functionality has been implemented and tested:

- ✅ 9-screen FEMA P-154 Level 1 flow
- ✅ On-device Gemma LLM integration with 4 task contracts
- ✅ Evidence packet schema (v1) with validation
- ✅ Session state management with auto-save
- ✅ Photo capture with two-phase OOM prevention
- ✅ Audio capture with description
- ✅ Volunteer notes and protocol questions
- ✅ Humility check for low-confidence observations
- ✅ Thinking-mode synthesis
- ✅ PDF report generation
- ✅ File-backed persistence (Android)
- ✅ Draft persistence for crash recovery
- ✅ turns.jsonl logging
- ✅ 331/331 tests passing

**Remaining Work:**
- Phase 10: Manual device test on Android (flutter run -d RZCX920ARVA)

The implementation demonstrates high code quality with clean architecture, comprehensive error handling, platform abstraction, and strong test coverage. The project is ready for end-to-end device testing to validate the full user experience on target hardware.
