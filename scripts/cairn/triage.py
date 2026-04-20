"""Deterministic priority score. Python mirror of the Dart function.

This is the ground truth for eval; the app computes the identical value on device.
Both must stay byte-identical — see `tests/test_triage_parity.py`.
"""
from __future__ import annotations

from typing import Any

from cairn.constants import HAZARD_SEVERITY_POINTS, PRIORITY_BAND_BOUNDS


def priority_score(packet: dict[str, Any]) -> int:
    pa = packet["protocol_answers"]
    if pa["visible_collapse"]:
        return 10
    if pa["building_off_foundation"]:
        return 10
    if pa["leaning"] == "severe":
        return 9

    s = 0
    for h in packet.get("hazards_flagged", []):
        s += HAZARD_SEVERITY_POINTS.get(h["severity"], 0)

    if pa["ground_failure_adjacent"]:
        s += 2
    if pa["falling_hazards"]:
        s += 2
    if packet["building"]["type"] == "unreinforced_masonry":
        s += 2
    if any(h["code"] == "H01_soft_story" for h in packet.get("hazards_flagged", [])):
        s += 2

    return max(1, min(10, s))


def priority_band(score: int) -> str:
    for name, lo, hi in PRIORITY_BAND_BOUNDS:
        if lo <= score <= hi:
            return name
    raise ValueError(f"score out of range: {score}")
