"""S3 prompt strategies.

Every strategy returns (system_prompt, user_text). Images are attached by the
caller; strategies never touch image bytes.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Callable

from cairn.prompts import system_prompt

BuildFn = Callable[[dict], tuple[str, str]]


def _base_user_text(item: dict) -> str:
    return json.dumps(
        {
            "task": "describe_photo",
            "asked_in": item["asked_in"],
            "prompt_id": item["prompt_id"],
            "image_refs": ["img-1"],
            "user_text": item.get("user_text"),
        },
        ensure_ascii=False,
    )


def strict_schema(item: dict) -> tuple[str, str]:
    return system_prompt(), _base_user_text(item)


def cot_then_schema(item: dict) -> tuple[str, str]:
    sys = system_prompt() + (
        "\n\nWhen the user turn's `task` is `describe_photo`, you MAY first reason in "
        "a single-line comment prefixed exactly with `// cot:` up to 400 characters, "
        "then a newline, then the JSON object. The parser ignores anything before the "
        "first `{`."
    )
    return sys, _base_user_text(item)


def schema_only(item: dict) -> tuple[str, str]:
    sys = (
        "Return a single JSON object with keys: observation_id, prompt_id, asked_in, "
        "image_refs, audio_refs, user_text, model_description, model_tags, "
        "model_confidence, bbox_annotations. No prose."
    )
    return sys, _base_user_text(item)


@dataclass(frozen=True)
class Strategy:
    name: str
    build: BuildFn


STRATEGIES: dict[str, Strategy] = {
    "strict_schema": Strategy("strict_schema", strict_schema),
    "cot_then_schema": Strategy("cot_then_schema", cot_then_schema),
    "schema_only": Strategy("schema_only", schema_only),
}
