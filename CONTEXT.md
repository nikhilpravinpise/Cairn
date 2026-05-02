# Cairn Context

Domain language for the Cairn mobile application. Terms are meaningful to both domain experts (disaster response volunteers, engineers) and implementers.

## Core Artifacts

### EvidencePacket

The single artifact produced by a Cairn session. A schema-valid JSON document per `docs/schema/evidence_packet_v1.schema.json` plus binary assets (images, audio, PDF report).

Key invariants:
- `packet_id`: UUIDv7 for time-ordered uniqueness.
- `observations`: 0–16 structured findings.
- `assets.images`: References as `img-N`.
- `assets.audio`: References as `aud-N`.
- `triage`: Priority score (1–10) and band (LOW/MEDIUM/HIGH/CRITICAL) with rationale bullets.

### Observation

One finding within an EvidencePacket. Every observation has:
- `observation_id`: `obs-N` pattern.
- `prompt_id`: Identifies which question/task produced this observation.
- `asked_in`: Locale (`en`, `es`, `tr`).
- `model_confidence`: 0.0–1.0.

Two kinds of observations:

#### Model-authored Observation

Produced by Gemma LLM (describe_photo, describe_audio, protocol_answer, synthesize).

| Field | Presence | Meaning |
|-------|----------|---------|
| `model_description` | Required | Model-generated finding text. |
| `model_tags` | Optional | From closed schema enum (damage types). |
| `model_confidence` | Required | Model-supplied confidence (0–1). |
| `user_text` | Null | No user override. |

#### Volunteer-authored Observation

Produced by human volunteer input (volunteer_note_v1, humility_override_v1).

| Field | Presence | Meaning |
|-------|----------|---------|
| `model_description` | **Omitted** | Field optional in schema; not used for human authorship. |
| `user_text` | Required | Volunteer-typed text. |
| `model_tags` | Empty `[]` | Schema enum contains only model-damage tags. |
| `model_confidence` | `1.0` | **Sentinel value** documented as "human ground truth." |

Distinction rationale: Human ground truth is not model confidence, but the schema lacks a separate field. `1.0` + distinct `prompt_id` + empty `model_tags` + omitted `model_description` together signal volunteer authorship unambiguously.

## Identity Allocation

Three independent monotonic counters per session:

| Space | Pattern | Allocated by |
|-------|---------|--------------|
| Observations | `obs-N` | `SessionDraft.allocateObservationId()` |
| Images | `img-N` | `SessionDraft.allocateImageRef()` |
| Audio | `aud-N` | `SessionDraft.allocateAudioRef()` |

All counters:
- Start at 1.
- Never decrement (survive clone, survive hypothetical remove).
- Preserved by `cloneShallow()`.

This prevents collision bugs present in v4 (length-based allocation would collide on retake/remove).

## Session Lifecycle

### Start

User begins a session. Location capture (optional). Locale selection.

### Photos

User captures or selects images. Each image gets `img-N` ref. Lost-data recovery handles process death.

### Describe

Gemma runs `describe_photo` per image. Produces model-authored observations. Volunteer may add volunteer-authored observations via free-text notes.

### Protocol

Structured yes/no/sliding questions per FEMA P-154. Produces model-authored observations with single-key responses.

### Humility

Screening for model over-confidence. Picks lowest-confidence model observation; Gemma asks follow-up question; volunteer answers. Answer recorded as volunteer-authored observation (`humility_override_v1`).

### Synthesize

Gemma produces triage recommendation (`priority_score`, `priority_band`, `rationale_bullets`).

### Report

PDF generation with QR code linking to packet.

### Finalize

Schema validation → atomic write to device storage → EvidencePacket sealed.

## Gates

### Capability Gate

A mandatory phase gate proving a code path works: compiles, runs without crash, returns parseable schema-valid output. Example: audio capture capability in Phase 8.

### Quality Gate

An informational gate where a human reviewer judges output plausibility. Logged in runlog, not blocking. Example: audio description quality in Phase 8.

Rationale: Upstream model quality (e.g., Gemma audio describe on Exynos GPU) is outside code control; failing the entire repivot on it is unacceptable.

## Model Artifacts

### E2B

Gemma 4 2B parameter model. Primary target for Android deployment.

- Web: `gemma-4-E2B-it-web.task`
- Android: `gemma-4-E2B-it.litertlm` (generic, not Qualcomm-specific on Exynos devices)

### E4B

Gemma 4 4B parameter model. **Out of scope for v5** — requires ~5 GB model + RAM headroom; S23 FE 8 GB insufficient.

## Protocol

### FEMA P-154 Level 1 "Sidewalk Survey"

The standardized rapid visual screening protocol. Cairn implements the Level 1 (non-invasive, exterior-only) variant.

Key constraints from `LEGAL.md`:
- Cairn is **not** an ATC-20 placard.
- Cairn is **not** a structural-engineering determination.
- Output is preliminary screening for licensed engineer triage.

## Data Safety

### On-device only

All capture stays on device. Packets not uploaded by default. "Share packet" produces a local zip the user chooses to share.

### No telemetry

v1 has no analytics, no crash reporting, no remote logging.

### Play Store data safety

- Data collected: Location, photos, audio.
- Data shared: None (user-initiated export only).
- Data transferred: None.

## References

- Schema: `docs/schema/evidence_packet_v1.schema.json`
- Legal: `docs/LEGAL.md`
- Plan: `docs/android_repivot_v5.md`
