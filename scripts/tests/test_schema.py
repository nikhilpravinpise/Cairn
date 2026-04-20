"""Round-trip the canonical EvidencePacket example through the Python validator."""
from __future__ import annotations

import copy

from cairn.schema import assert_valid, validate_packet

_VALID = {
    "schema": "cairn.evidence.v1",
    "packet_id": "0190c6b0-3f0a-7a7b-bc1c-8cbfb1f9aaaa",
    "created_at_utc": "2026-05-02T14:23:11Z",
    "app_version": "0.1.0",
    "protocol": "FEMA-P-154-L1",
    "model": {"name": "gemma-4-e2b-it", "quant": "int4", "lora": "cairn-protocol-v1"},
    "location": {"lat": 34.05, "lng": -118.24, "accuracy_m": 8.0, "address_text": ""},
    "building": {"type": "unreinforced_masonry", "stories_above_grade": 3,
                 "occupancy_hint": "retail+residential", "year_built_est": 1930},
    "observations": [
        {
            "observation_id": "obs-1",
            "prompt_id": "fema_p154_q03_visible_collapse",
            "asked_in": "es",
            "image_refs": ["img-1"],
            "audio_refs": [],
            "user_text": None,
            "model_description": "…",
            "model_tags": ["diagonal_crack"],
            "model_confidence": 0.72,
            "bbox_annotations": [
                {"image_ref": "img-1", "box_2d": [120, 40, 340, 280], "label": "diagonal_crack"}
            ],
        }
    ],
    "hazards_flagged": [
        {"code": "H01_soft_story", "severity": "high", "evidence_refs": ["obs-1"]},
    ],
    "protocol_answers": {
        "visible_collapse": False, "building_off_foundation": False,
        "leaning": "slight", "ground_failure_adjacent": True,
        "falling_hazards": True, "adjacent_leaning": False,
    },
    "triage": {
        "priority_score": 7, "priority_band": "HIGH",
        "rationale_bullets": ["a", "b", "c"],
        "uncertainty_notes": ["x"],
        "recommend_engineer_followup": True,
    },
    "volunteer": {
        "attestation": "I am not a licensed engineer. This is preliminary screening only.",
        "signature_hash": "sha256:" + "0" * 64,
        "locale": "es-MX",
    },
    "assets": {
        "images": [
            {"ref": "img-1", "filename": "img-1.jpg", "sha256": "0" * 64,
             "width_px": 1024, "height_px": 768, "taken_at_utc": "2026-05-02T14:22:11Z"}
        ],
        "audio": [],
    },
}


def test_valid_round_trip() -> None:
    assert validate_packet(copy.deepcopy(_VALID)) == []
    assert_valid(copy.deepcopy(_VALID))


def test_reject_unknown_tag() -> None:
    p = copy.deepcopy(_VALID)
    p["observations"][0]["model_tags"] = ["crackzzz"]
    assert validate_packet(p), "should fail on unknown enum tag"


def test_reject_bbox_out_of_range() -> None:
    p = copy.deepcopy(_VALID)
    p["observations"][0]["bbox_annotations"][0]["box_2d"] = [0, 0, 9999, 9999]
    assert validate_packet(p), "box_2d must be 0..1000"


def test_reject_score_out_of_range() -> None:
    p = copy.deepcopy(_VALID)
    p["triage"]["priority_score"] = 11
    assert validate_packet(p)
