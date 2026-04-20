"""Unit tests for eval metrics. Small hand-built cases."""
from __future__ import annotations

from cairn.metrics import (
    confidence_calibration,
    damage_presence_f1,
    damage_type_topk,
    severity_spearman,
    tag_jaccard,
)


def test_perfect_agreement() -> None:
    preds = [["diagonal_crack"], ["no_visible_damage"], ["concrete_spalling"]]
    golds = [["diagonal_crack"], ["no_visible_damage"], ["concrete_spalling"]]
    assert damage_presence_f1(preds, golds) == 1.0
    assert damage_type_topk(preds, golds, k=1) == 1.0
    assert damage_type_topk(preds, golds, k=3) == 1.0
    assert tag_jaccard(preds, golds) == 1.0


def test_partial_agreement() -> None:
    preds = [["concrete_spalling"], ["no_visible_damage"]]
    golds = [["concrete_spalling", "exposed_rebar"], ["no_visible_damage"]]
    assert damage_presence_f1(preds, golds) == 1.0
    # top-1: first pred tag is in gold set → hit
    assert damage_type_topk(preds, golds, k=1) == 1.0
    # Jaccard: 1/2 + 1/1 = 1.5, mean = 0.75
    assert round(tag_jaccard(preds, golds), 3) == 0.75


def test_severity_spearman_monotonic() -> None:
    preds = [["no_visible_damage"], ["diagonal_crack"], ["exposed_rebar"]]
    golds = [["no_visible_damage"], ["diagonal_crack"], ["exposed_rebar"]]
    assert severity_spearman(preds, golds) == 1.0


def test_calibration_perfect() -> None:
    # A well-calibrated model with conf=1.0 that is always right, and conf=0.0 that
    # is always wrong, has zero ECE.
    assert confidence_calibration([1.0, 1.0, 1.0], [1, 1, 1]) == 0.0
    assert confidence_calibration([0.0, 0.0, 0.0], [0, 0, 0]) == 0.0


def test_calibration_mild_miscalibration() -> None:
    # conf 0.9 but always right => ECE = 0.1
    assert round(confidence_calibration([0.9] * 10, [1] * 10), 3) == 0.1


def test_calibration_bad() -> None:
    # model says 0.9 confident, is always wrong → large ECE
    ece = confidence_calibration([0.9] * 10, [0] * 10)
    assert ece > 0.8
