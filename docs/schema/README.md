# EvidencePacket schema v1 — **LOCKED D4**

Canonical source of truth: `evidence_packet_v1.schema.json` (JSON Schema draft 2020-12).

## Design rules
1. **Schema keys in English.** Free-text in user locale (`en`, `es`, `tr`).
2. **Enums are closed.** Any new tag / hazard / building type requires a schema bump.
3. **LLM never computes priority.** `triage.priority_score` is produced by the Dart
   `priorityScore` function from `protocol_answers` + `hazards_flagged` +
   `building.type`. The LLM fills `rationale_bullets` and `uncertainty_notes`.
4. **Bounding boxes** follow the Gemma vision convention: normalized
   `[y1, x1, y2, x2]` with integer coords in `0..1000`. Verify in D4 with
   `scripts/spikes/s3_bbox_probe.py`.
5. **Audio** is mono 16 kHz WAV, ≤ 30 s per clip, ≤ 1 clip per observation.
6. **Images** ≤ 5 per session (MediaPipe LLM Inf cap is 10).
7. Every asset stored in the packet has its `sha256` computed on-device — packets are
   content-addressable and tamper-evident.

## Priority band mapping (Dart + console must agree)
| band      | score |
|-----------|-------|
| LOW       | 1–3   |
| MEDIUM    | 4–6   |
| HIGH      | 7–8   |
| CRITICAL  | 9–10  |

## Validation
- Dart (app-side): `apps/cairn_mobile/lib/core/models/evidence_packet_validator.dart`.
- Python (training/eval): `scripts/cairn/schema.py` using `jsonschema`.

Both readers validate against the same canonical
`docs/schema/evidence_packet_v1.schema.json`. The Flutter app also bundles a
copy at `apps/cairn_mobile/assets/schema/evidence_packet_v1.schema.json`; keep
the copies byte-identical.

## Versioning
Breaking changes → bump to `cairn.evidence.v2` and keep a v1 reader. Non-breaking
additive fields (new optional properties, new enum values on `additionalProperties:false`
objects) still require a version bump because old readers will reject them.
