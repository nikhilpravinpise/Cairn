"""EvidencePacket v1 schema loading + validation helpers.

Source of truth is `docs/schema/evidence_packet_v1.schema.json`. Every Python
entry point (eval, data pipeline, CI) uses THIS validator so the Dart app, the
Next.js console, and the training data all agree on what a packet looks like.
"""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError

from cairn.constants import SCHEMA_PATH


@lru_cache(maxsize=1)
def _schema() -> dict[str, Any]:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def _validator() -> Draft202012Validator:
    Draft202012Validator.check_schema(_schema())
    return Draft202012Validator(_schema())


def validate_packet(packet: dict[str, Any]) -> list[str]:
    """Return a list of human-readable error strings; empty list ⇒ valid."""
    return [
        f"{'/'.join(str(p) for p in err.absolute_path)}: {err.message}"
        for err in sorted(_validator().iter_errors(packet), key=lambda e: e.path)
    ]


def assert_valid(packet: dict[str, Any]) -> None:
    errs = validate_packet(packet)
    if errs:
        raise ValidationError("EvidencePacket invalid:\n  - " + "\n  - ".join(errs))


def validate_jsonl(path: Path) -> dict[int, list[str]]:
    """Validate a file containing one packet per line. Returns {line_no: errors}."""
    failures: dict[int, list[str]] = {}
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as e:
            failures[i] = [f"invalid json: {e}"]
            continue
        errs = validate_packet(obj)
        if errs:
            failures[i] = errs
    return failures
