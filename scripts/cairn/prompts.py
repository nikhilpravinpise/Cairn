"""Loader for the locked system prompt v1.

Never inline the prompt text in another file. Always load it from here so the
system prompt lives in exactly one place.
"""
from __future__ import annotations

from functools import lru_cache

from cairn.constants import SYSTEM_PROMPT_PATH

SYSTEM_REF: str = "cairn.system.v1"


@lru_cache(maxsize=1)
def system_prompt() -> str:
    text = SYSTEM_PROMPT_PATH.read_text(encoding="utf-8").strip()
    if not text:
        raise RuntimeError(f"system prompt at {SYSTEM_PROMPT_PATH} is empty")
    return text


def resolve_system_ref(ref: str) -> str:
    if ref != SYSTEM_REF:
        raise ValueError(f"unknown system_ref {ref!r} (expected {SYSTEM_REF!r})")
    return system_prompt()
