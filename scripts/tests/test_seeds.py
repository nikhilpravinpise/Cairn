"""CI — the 30 hand-authored seeds parse cleanly and match the contract.

Also contains per-task unit tests for the _check_assistant validator so that
each rule is independently verified and failures are immediately locatable.
"""
from __future__ import annotations

from cairn.constants import SEED_JSONL_PATH
from data.validate_seeds import ALLOWED_MODEL_TAGS, ALLOWED_PROTOCOL_KEYS, _check_assistant, validate


# ── integration: all 30 seeds must pass ───────────────────────────────────────

def test_seeds_validate() -> None:
    assert validate(SEED_JSONL_PATH) == 0


# ── describe_photo ─────────────────────────────────────────────────────────────

def _valid_describe_photo() -> dict:
    return {
        "observation_id": "obs-1",
        "prompt_id": "fema_p154_q03",
        "asked_in": "en",
        "image_refs": ["img-1"],
        "model_description": "Diagonal crack visible.",
        "model_tags": ["diagonal_crack"],
        "model_confidence": 0.75,
    }


def test_describe_photo_valid_passes() -> None:
    assert _check_assistant("describe_photo", _valid_describe_photo()) == []


def test_describe_photo_rejects_unknown_tag() -> None:
    v = _valid_describe_photo()
    v["model_tags"] = ["definitely_not_a_real_tag"]
    errs = _check_assistant("describe_photo", v)
    assert any("invalid model tag" in e for e in errs)


def test_describe_photo_rejects_confidence_above_one() -> None:
    v = _valid_describe_photo()
    v["model_confidence"] = 1.5
    errs = _check_assistant("describe_photo", v)
    assert errs


def test_describe_photo_rejects_confidence_below_zero() -> None:
    v = _valid_describe_photo()
    v["model_confidence"] = -0.1
    errs = _check_assistant("describe_photo", v)
    assert errs


def test_describe_photo_rejects_missing_model_tags() -> None:
    v = _valid_describe_photo()
    del v["model_tags"]
    errs = _check_assistant("describe_photo", v)
    assert any("model_tags" in e for e in errs)


def test_describe_photo_rejects_non_list_tags() -> None:
    v = _valid_describe_photo()
    v["model_tags"] = "diagonal_crack"
    errs = _check_assistant("describe_photo", v)
    assert errs


def test_describe_photo_rejects_non_dict() -> None:
    errs = _check_assistant("describe_photo", ["not", "a", "dict"])
    assert errs


def test_describe_photo_every_schema_tag_accepted() -> None:
    v = _valid_describe_photo()
    for tag in ALLOWED_MODEL_TAGS:
        v["model_tags"] = [tag]
        assert _check_assistant("describe_photo", v) == [], f"schema tag {tag!r} incorrectly rejected"


# ── ask_followup ───────────────────────────────────────────────────────────────

def test_ask_followup_null_accepted() -> None:
    assert _check_assistant("ask_followup", {"followup": None}) == []


def test_ask_followup_dict_accepted() -> None:
    v = {"followup": {"target_observation_id": "obs-1", "question": "Can you get closer?"}}
    assert _check_assistant("ask_followup", v) == []


def test_ask_followup_missing_followup_key() -> None:
    errs = _check_assistant("ask_followup", {})
    assert any("followup" in e for e in errs)


def test_ask_followup_rejects_string_value() -> None:
    errs = _check_assistant("ask_followup", {"followup": "should be dict or null"})
    assert errs


def test_ask_followup_dict_missing_target_observation_id() -> None:
    v = {"followup": {"question": "What is this crack?"}}
    errs = _check_assistant("ask_followup", v)
    assert any("target_observation_id" in e for e in errs)


def test_ask_followup_dict_missing_question() -> None:
    v = {"followup": {"target_observation_id": "obs-1"}}
    errs = _check_assistant("ask_followup", v)
    assert any("question" in e for e in errs)


def test_ask_followup_rejects_non_dict_assistant() -> None:
    errs = _check_assistant("ask_followup", "not a dict at all")
    assert errs


# ── protocol_answer ────────────────────────────────────────────────────────────

def test_protocol_answer_valid_passes() -> None:
    v = {"protocol_answers_delta": {"visible_collapse": True}}
    assert _check_assistant("protocol_answer", v) == []


def test_protocol_answer_all_known_keys_accepted() -> None:
    values = {
        "visible_collapse": True,
        "building_off_foundation": False,
        "leaning": "moderate",
        "ground_failure_adjacent": False,
        "falling_hazards": True,
        "adjacent_leaning": False,
    }
    for key, val in values.items():
        v = {"protocol_answers_delta": {key: val}}
        assert _check_assistant("protocol_answer", v) == [], f"known key {key!r} incorrectly rejected"


def test_protocol_answer_rejects_unknown_key() -> None:
    v = {"protocol_answers_delta": {"made_up_question": True}}
    errs = _check_assistant("protocol_answer", v)
    assert errs


def test_protocol_answer_rejects_empty_delta() -> None:
    errs = _check_assistant("protocol_answer", {"protocol_answers_delta": {}})
    assert errs


def test_protocol_answer_rejects_multiple_keys() -> None:
    v = {"protocol_answers_delta": {"visible_collapse": True, "leaning": "none"}}
    errs = _check_assistant("protocol_answer", v)
    assert errs


def test_protocol_answer_rejects_missing_delta() -> None:
    errs = _check_assistant("protocol_answer", {})
    assert errs


# ── synthesize ─────────────────────────────────────────────────────────────────

def _valid_synthesize() -> dict:
    return {
        "triage_draft": {
            "rationale_bullets": ["Soft story at ground floor.", "Exposed rebar on column."],
            "recommend_engineer_followup": True,
        }
    }


def test_synthesize_valid_passes() -> None:
    assert _check_assistant("synthesize", _valid_synthesize()) == []


def test_synthesize_rejects_priority_score() -> None:
    v = _valid_synthesize()
    v["triage_draft"]["priority_score"] = 7
    errs = _check_assistant("synthesize", v)
    assert any("priority_score" in e for e in errs)


def test_synthesize_rejects_priority_band() -> None:
    v = _valid_synthesize()
    v["triage_draft"]["priority_band"] = "HIGH"
    errs = _check_assistant("synthesize", v)
    assert any("priority_band" in e for e in errs)


def test_synthesize_requires_rationale_bullets() -> None:
    v = _valid_synthesize()
    del v["triage_draft"]["rationale_bullets"]
    errs = _check_assistant("synthesize", v)
    assert errs


def test_synthesize_rejects_empty_rationale_bullets() -> None:
    v = _valid_synthesize()
    v["triage_draft"]["rationale_bullets"] = []
    errs = _check_assistant("synthesize", v)
    assert any("rationale_bullets" in e for e in errs)


def test_synthesize_requires_recommend_engineer_followup() -> None:
    v = _valid_synthesize()
    del v["triage_draft"]["recommend_engineer_followup"]
    errs = _check_assistant("synthesize", v)
    assert errs


def test_synthesize_missing_triage_draft() -> None:
    errs = _check_assistant("synthesize", {})
    assert errs


def test_synthesize_both_forbidden_fields_caught() -> None:
    v = _valid_synthesize()
    v["triage_draft"]["priority_score"] = 5
    v["triage_draft"]["priority_band"] = "MEDIUM"
    errs = _check_assistant("synthesize", v)
    assert any("priority_score" in e for e in errs)
    assert any("priority_band" in e for e in errs)


# ── ALLOWED_PROTOCOL_KEYS completeness ─────────────────────────────────────────

def test_allowed_protocol_keys_nonempty() -> None:
    assert len(ALLOWED_PROTOCOL_KEYS) > 0


def test_known_protocol_keys_all_present() -> None:
    expected = {
        "visible_collapse", "building_off_foundation", "leaning",
        "ground_failure_adjacent", "falling_hazards", "adjacent_leaning",
    }
    assert expected <= ALLOWED_PROTOCOL_KEYS, (
        f"Missing from ALLOWED_PROTOCOL_KEYS: {expected - ALLOWED_PROTOCOL_KEYS}"
    )
