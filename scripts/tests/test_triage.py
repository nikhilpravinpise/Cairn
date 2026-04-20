"""Priority-score rules table. Mirrors expected Dart output exactly."""
from __future__ import annotations

from cairn.triage import priority_band, priority_score


def _packet(**overrides) -> dict:
    base = {
        "building": {"type": "wood_light_frame", "stories_above_grade": 2},
        "protocol_answers": {
            "visible_collapse": False, "building_off_foundation": False,
            "leaning": "none", "ground_failure_adjacent": False,
            "falling_hazards": False, "adjacent_leaning": False,
        },
        "hazards_flagged": [],
    }
    base.update(overrides)
    return base


def test_collapse_is_10() -> None:
    p = _packet()
    p["protocol_answers"]["visible_collapse"] = True
    assert priority_score(p) == 10
    assert priority_band(10) == "CRITICAL"


def test_off_foundation_is_10() -> None:
    p = _packet()
    p["protocol_answers"]["building_off_foundation"] = True
    assert priority_score(p) == 10


def test_severe_lean_is_9() -> None:
    p = _packet()
    p["protocol_answers"]["leaning"] = "severe"
    assert priority_score(p) == 9
    assert priority_band(9) == "CRITICAL"


def test_urm_plus_soft_story() -> None:
    p = _packet(
        building={"type": "unreinforced_masonry", "stories_above_grade": 3},
        hazards_flagged=[
            {"code": "H01_soft_story", "severity": "high"},
            {"code": "H02_unreinforced_masonry", "severity": "moderate"},
        ],
    )
    # 3 (high) + 2 (moderate) + 2 (urm bonus) + 2 (soft-story bonus) = 9
    assert priority_score(p) == 9


def test_clean_building_is_1() -> None:
    p = _packet()
    assert priority_score(p) == 1
    assert priority_band(1) == "LOW"


def test_ground_and_falling() -> None:
    p = _packet()
    p["protocol_answers"]["ground_failure_adjacent"] = True
    p["protocol_answers"]["falling_hazards"] = True
    assert priority_score(p) == 4  # 0 hazards + 2 + 2, clamped lower bound 1
    assert priority_band(4) == "MEDIUM"


def test_band_mapping_boundaries() -> None:
    assert priority_band(1) == "LOW"
    assert priority_band(3) == "LOW"
    assert priority_band(4) == "MEDIUM"
    assert priority_band(6) == "MEDIUM"
    assert priority_band(7) == "HIGH"
    assert priority_band(8) == "HIGH"
    assert priority_band(9) == "CRITICAL"
    assert priority_band(10) == "CRITICAL"
