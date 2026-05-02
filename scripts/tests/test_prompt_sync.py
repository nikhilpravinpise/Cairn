"""Phase 2 gate: canonical docs/ assets are byte-identical to their Flutter copies.

Three checks:
1. system_prompt_v1.txt is byte-identical between docs/prompts/ and app assets/.
2. evidence_packet_v1.schema.json is byte-identical between docs/schema/ and app assets/.
3. Rule 3 model_tags list in the system prompt exactly matches the schema enum
   (no drift possible: if the schema changes, this test will fail until the prompt
   is updated and sync_assets is re-run).

Fix failures by running:
  Windows: apps\\cairn_mobile\\tool\\sync_assets.ps1
  Unix:    apps/cairn_mobile/tool/sync_assets.sh
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from cairn.constants import REPO_ROOT, SCHEMA_PATH, SYSTEM_PROMPT_PATH

APP_PROMPT_PATH: Path = REPO_ROOT / "apps/cairn_mobile/assets/prompts/system_prompt_v1.txt"
APP_SCHEMA_PATH: Path = REPO_ROOT / "apps/cairn_mobile/assets/schema/evidence_packet_v1.schema.json"


def test_prompt_asset_byte_identical() -> None:
    """docs/prompts/system_prompt_v1.txt and the Flutter asset copy are byte-identical."""
    assert APP_PROMPT_PATH.exists(), (
        f"App asset missing: {APP_PROMPT_PATH}\n"
        "Run tool/sync_assets.ps1 (Windows) or tool/sync_assets.sh to create it."
    )
    src = SYSTEM_PROMPT_PATH.read_bytes()
    dst = APP_PROMPT_PATH.read_bytes()
    assert src == dst, (
        f"Prompt out of sync (byte mismatch).\n"
        f"  Source : {SYSTEM_PROMPT_PATH} ({len(src)} bytes)\n"
        f"  Asset  : {APP_PROMPT_PATH} ({len(dst)} bytes)\n"
        "Run tool/sync_assets.ps1 (Windows) or tool/sync_assets.sh to fix."
    )


def test_schema_asset_byte_identical() -> None:
    """docs/schema/evidence_packet_v1.schema.json and the Flutter asset copy are byte-identical."""
    assert APP_SCHEMA_PATH.exists(), (
        f"App asset missing: {APP_SCHEMA_PATH}\n"
        "Run tool/sync_assets.ps1 (Windows) or tool/sync_assets.sh to create it."
    )
    src = SCHEMA_PATH.read_bytes()
    dst = APP_SCHEMA_PATH.read_bytes()
    assert src == dst, (
        f"Schema out of sync (byte mismatch).\n"
        f"  Source : {SCHEMA_PATH} ({len(src)} bytes)\n"
        f"  Asset  : {APP_SCHEMA_PATH} ({len(dst)} bytes)\n"
        "Run tool/sync_assets.ps1 (Windows) or tool/sync_assets.sh to fix."
    )


def _schema_model_tags() -> list[str]:
    """Extract the model_tags enum values from the schema JSON."""
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    return schema["properties"]["observations"]["items"]["properties"]["model_tags"]["items"]["enum"]


def _prompt_rule3_tags() -> list[str]:
    """Extract the tag list from rule 3 of the system prompt.

    Rule 3 reads:
        Permitted `model_tags` are restricted strictly to:
            tag_a, tag_b, ..., tag_z.
            Do NOT use words like ...
    """
    text = SYSTEM_PROMPT_PATH.read_text(encoding="utf-8")
    m = re.search(
        r"Permitted `model_tags` are restricted strictly to:\s+([\w ,\n]+?)\.\s+Do NOT",
        text,
        re.DOTALL,
    )
    assert m, (
        "Could not locate the rule-3 tag list in the system prompt. "
        "Expected text starting with 'Permitted `model_tags` are restricted strictly to:'"
    )
    raw = m.group(1).replace("\n", " ")
    tags = [t.strip() for t in raw.split(",") if t.strip()]
    return tags


def test_prompt_rule3_tags_match_schema_enum() -> None:
    """Every tag in the schema enum appears in rule 3, and vice versa.

    This is the zero-drift check: if a tag is added to the schema, the test
    fails until the prompt is updated and sync_assets is re-run.
    """
    schema_tags = set(_schema_model_tags())
    prompt_tags = set(_prompt_rule3_tags())

    missing_from_prompt = schema_tags - prompt_tags
    extra_in_prompt = prompt_tags - schema_tags

    assert not missing_from_prompt, (
        f"Tags in schema enum but MISSING from system prompt rule 3: {sorted(missing_from_prompt)}\n"
        "Update docs/prompts/system_prompt_v1.txt rule 3, then re-run sync_assets."
    )
    assert not extra_in_prompt, (
        f"Tags in system prompt rule 3 but NOT in schema enum: {sorted(extra_in_prompt)}\n"
        "Either add the tag to the schema or remove it from the prompt."
    )
