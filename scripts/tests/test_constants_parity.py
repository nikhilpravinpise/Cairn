"""Cross-language parity — Dart `model_registry.dart` vs Python `constants.py`.

Parses the Dart file as text (no pub.dev runtime), extracts the identifying
fields, and asserts they match the Python `MODELS` dict.
"""
from __future__ import annotations

import re
from pathlib import Path

from cairn.constants import MODELS, REPO_ROOT

DART = REPO_ROOT / "apps/cairn_mobile/lib/core/llm/model_registry.dart"


def _parse_dart_models(path: Path) -> dict[str, dict[str, str]]:
    text = path.read_text(encoding="utf-8")
    # Each entry is `  'xxx': ModelSpec(\n    …\n  ),`; match up to the aligned
    # `  ),` that closes the ModelSpec constructor.
    blocks = re.findall(
        r"'(\w+)':\s*ModelSpec\(\s*(.*?)\n  \),",
        text,
        re.DOTALL,
    )
    out: dict[str, dict[str, str]] = {}
    for key, body in blocks:
        fields = {}
        for field in ("key", "hfRepo", "taskFilename", "quant"):
            m = re.search(rf"{field}:\s*'([^']+)'", body)
            if m:
                fields[field] = m.group(1)
        out[key] = fields
    return out


def test_dart_python_parity() -> None:
    dart = _parse_dart_models(DART)
    # Every Python model must appear in Dart with the same repo + filename.
    for key, spec in MODELS.items():
        assert key in dart, f"dart model_registry missing {key!r}"
        d = dart[key]
        assert d["key"] == spec.key
        assert d["hfRepo"] == spec.hf_repo
        assert d["taskFilename"] == spec.task_filename
        assert d["quant"] == spec.quant
