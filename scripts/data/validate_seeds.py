"""CI-grade validator for `data/seeds/dialogues.seed.jsonl`.

Fails loud on:
- non-parseable JSON line
- unknown `task` value
- assistant turn not a JSON object / fails task-specific structural check
- unknown `system_ref`
- unknown `locale` / `building_type` / `scenario`
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from cairn.constants import SEED_JSONL_PATH
from cairn.prompts import SYSTEM_REF

ALLOWED_TASKS = {"describe_photo", "ask_followup", "protocol_answer", "synthesize"}
ALLOWED_LOCALES = {"en", "es", "tr"}
ALLOWED_BUILDINGS = {
    "concrete_moment_frame",
    "unreinforced_masonry",
    "wood_light_frame",
    "steel",
    "mixed",
    "unknown",
}
ALLOWED_SCENARIOS = {"none", "cosmetic", "moderate", "severe"}


def _check_assistant(task: str, value: Any) -> list[str]:
    errs: list[str] = []
    if not isinstance(value, dict):
        return [f"assistant value not a JSON object"]
    if task == "describe_photo":
        for k in ("observation_id", "prompt_id", "asked_in", "image_refs",
                  "model_description", "model_tags", "model_confidence"):
            if k not in value:
                errs.append(f"missing key {k!r}")
        if "model_confidence" in value and not 0.0 <= float(value["model_confidence"]) <= 1.0:
            errs.append("model_confidence outside [0,1]")
    elif task == "ask_followup":
        if "followup" not in value:
            errs.append("missing key 'followup'")
    elif task == "protocol_answer":
        if "protocol_answers_delta" not in value or len(value["protocol_answers_delta"]) != 1:
            errs.append("protocol_answers_delta must have exactly one key")
    elif task == "synthesize":
        td = value.get("triage_draft")
        if not isinstance(td, dict):
            errs.append("missing 'triage_draft' object")
        else:
            for k in ("rationale_bullets", "recommend_engineer_followup"):
                if k not in td:
                    errs.append(f"triage_draft missing {k!r}")
    return errs


def validate(path: Path) -> int:
    rc = 0
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError as e:
            print(f"[{i}] invalid json: {e}")
            rc = 1
            continue
        errs: list[str] = []
        if rec.get("system_ref") != SYSTEM_REF:
            errs.append(f"unknown system_ref {rec.get('system_ref')!r}")
        if rec.get("task") not in ALLOWED_TASKS:
            errs.append(f"unknown task {rec.get('task')!r}")
        if rec.get("locale") not in ALLOWED_LOCALES:
            errs.append(f"unknown locale {rec.get('locale')!r}")
        if rec.get("building_type") not in ALLOWED_BUILDINGS:
            errs.append(f"unknown building_type {rec.get('building_type')!r}")
        if rec.get("scenario") not in ALLOWED_SCENARIOS:
            errs.append(f"unknown scenario {rec.get('scenario')!r}")
        convs = rec.get("conversations")
        if not (isinstance(convs, list) and len(convs) == 2):
            errs.append("conversations must be a 2-item list [human, gpt]")
        else:
            human, gpt = convs
            if human.get("from") != "human" or gpt.get("from") != "gpt":
                errs.append("conversations must be human → gpt")
            try:
                hv = json.loads(human["value"])
                gv = json.loads(gpt["value"])
            except Exception as e:
                errs.append(f"non-JSON conversation value: {e}")
            else:
                if hv.get("task") != rec.get("task"):
                    errs.append("human.value.task != record.task")
                errs.extend(_check_assistant(rec["task"], gv))
        if errs:
            rc = 1
            print(f"[{i}] {rec.get('seed_id')}:")
            for e in errs:
                print(f"   - {e}")
    if rc == 0:
        print(f"ok — {path}")
    return rc


if __name__ == "__main__":
    sys.exit(validate(SEED_JSONL_PATH))
