"""CI — the 30 hand-authored seeds parse cleanly and match the contract."""
from __future__ import annotations

from cairn.constants import SEED_JSONL_PATH
from data.validate_seeds import validate


def test_seeds_validate() -> None:
    assert validate(SEED_JSONL_PATH) == 0
