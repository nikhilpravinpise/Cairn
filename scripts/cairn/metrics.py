"""Vision + text eval metrics shared across S3 baseline + tuned eval.

- damage-presence F1  (binary: any structural damage tag vs none)
- damage-type top-k  (set overlap between model_tags and gold_tags, rank-sensitive)
- severity Spearman  (model inferred severity from tags vs gold ordinal)
- tag Jaccard        (set IoU over the canonical tag enum)
"""
from __future__ import annotations

from collections import Counter
from typing import Iterable, Sequence

import numpy as np
from scipy.stats import spearmanr
from sklearn.metrics import f1_score

STRUCTURAL_TAGS: frozenset[str] = frozenset(
    {
        "diagonal_crack",
        "horizontal_crack",
        "vertical_crack",
        "x_pattern_crack",
        "concrete_spalling",
        "exposed_rebar",
        "column_base_damage",
        "beam_column_joint_damage",
        "soft_story_condition",
        "pounding_damage",
        "infill_wall_crack",
        "out_of_plane_failure",
        "foundation_displacement",
        "chimney_damage",
        "parapet_damage",
    }
)

# 0..3 ordinal severity inferred from gold tags for Spearman.
SEVERITY_WEIGHT: dict[str, int] = {
    # mild
    "diagonal_crack": 1, "horizontal_crack": 1, "vertical_crack": 1, "infill_wall_crack": 1,
    "chimney_damage": 1, "parapet_damage": 1, "uncertain_cosmetic": 0, "no_visible_damage": 0,
    # moderate
    "concrete_spalling": 2, "x_pattern_crack": 2, "pounding_damage": 2,
    "uncertain_structural": 1, "falling_hazard_unsecured": 2,
    # severe
    "exposed_rebar": 3, "column_base_damage": 3, "beam_column_joint_damage": 3,
    "soft_story_condition": 3, "out_of_plane_failure": 3, "foundation_displacement": 3,
}


def _any_structural(tags: Iterable[str]) -> int:
    return int(any(t in STRUCTURAL_TAGS for t in tags))


def damage_presence_f1(
    pred_tags_per_item: Sequence[Sequence[str]],
    gold_tags_per_item: Sequence[Sequence[str]],
) -> float:
    if len(pred_tags_per_item) != len(gold_tags_per_item):
        raise ValueError("length mismatch")
    y_pred = [_any_structural(t) for t in pred_tags_per_item]
    y_true = [_any_structural(t) for t in gold_tags_per_item]
    return float(f1_score(y_true, y_pred, zero_division=0))


def damage_type_topk(
    pred_tags_per_item: Sequence[Sequence[str]],
    gold_tags_per_item: Sequence[Sequence[str]],
    *,
    k: int = 3,
) -> float:
    """Fraction of items where at least one gold tag appears in the first-k pred tags."""
    hits = 0
    for pred, gold in zip(pred_tags_per_item, gold_tags_per_item):
        gold_set = {g for g in gold if g in STRUCTURAL_TAGS}
        if not gold_set:
            # If gold has no structural damage, count as hit iff pred agrees.
            if not any(p in STRUCTURAL_TAGS for p in pred):
                hits += 1
            continue
        if any(p in gold_set for p in list(pred)[:k]):
            hits += 1
    return hits / len(pred_tags_per_item) if pred_tags_per_item else 0.0


def _severity(tags: Iterable[str]) -> int:
    return max((SEVERITY_WEIGHT.get(t, 0) for t in tags), default=0)


def severity_spearman(
    pred_tags_per_item: Sequence[Sequence[str]],
    gold_tags_per_item: Sequence[Sequence[str]],
) -> float:
    p = [_severity(t) for t in pred_tags_per_item]
    g = [_severity(t) for t in gold_tags_per_item]
    if len(set(p)) < 2 or len(set(g)) < 2:
        return 0.0
    rho, _ = spearmanr(p, g)
    return float(rho) if rho is not None and not np.isnan(rho) else 0.0


def tag_jaccard(
    pred_tags_per_item: Sequence[Sequence[str]],
    gold_tags_per_item: Sequence[Sequence[str]],
) -> float:
    vals = []
    for pred, gold in zip(pred_tags_per_item, gold_tags_per_item):
        ps, gs = set(pred), set(gold)
        if not ps and not gs:
            vals.append(1.0)
            continue
        if not ps or not gs:
            vals.append(0.0)
            continue
        vals.append(len(ps & gs) / len(ps | gs))
    return float(np.mean(vals)) if vals else 0.0


def confidence_calibration(
    confidences: Sequence[float],
    correctness: Sequence[int],
    *,
    bins: int = 10,
) -> float:
    """Expected Calibration Error (lower is better)."""
    if not confidences:
        return 0.0
    conf = np.asarray(confidences, dtype=float)
    corr = np.asarray(correctness, dtype=float)
    edges = np.linspace(0.0, 1.0, bins + 1)
    ece = 0.0
    for lo, hi in zip(edges[:-1], edges[1:]):
        mask = (conf >= lo) & (conf < hi if hi < 1.0 else conf <= hi)
        if not mask.any():
            continue
        ece += (mask.mean()) * abs(conf[mask].mean() - corr[mask].mean())
    return float(ece)


def summarize(
    preds: Sequence[dict],
    golds: Sequence[dict],
) -> dict[str, float | int]:
    if len(preds) != len(golds):
        raise ValueError("preds/golds length mismatch")
    pt = [p.get("model_tags", []) for p in preds]
    gt = [g.get("model_tags", []) for g in golds]
    conf = [float(p.get("model_confidence", 0.0)) for p in preds]
    correct = [int(set(p.get("model_tags", [])) & set(g.get("model_tags", [])) != set()) for p, g in zip(preds, golds)]
    out: dict[str, float | int] = {
        "n": len(preds),
        "f1_damage_presence": damage_presence_f1(pt, gt),
        "top1_damage_type": damage_type_topk(pt, gt, k=1),
        "top3_damage_type": damage_type_topk(pt, gt, k=3),
        "severity_spearman": severity_spearman(pt, gt),
        "tag_jaccard": tag_jaccard(pt, gt),
        "confidence_ece": confidence_calibration(conf, correct),
    }
    # tag-level support counts for easier triage in the report
    tag_counter = Counter(t for tags in gt for t in tags)
    for tag, n in tag_counter.most_common(5):
        out[f"gold_support:{tag}"] = n
    return out
