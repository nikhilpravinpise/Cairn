"""Minimal LLM runner abstraction.

One turn at a time. We only need: system prompt + a list of user/assistant turns,
optionally with attached images, out comes text + timings.

Every runner must:
  * Fail loud — no silent fallbacks.
  * Report TTFT and tokens/sec when the backend exposes them; otherwise set None.
  * Accept bytes-typed image payloads; no backend-specific formats leak up here.
"""
from __future__ import annotations

import abc
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal


@dataclass(frozen=True, slots=True)
class ImageInput:
    data: bytes
    mime: str = "image/jpeg"

    @classmethod
    def from_path(cls, p: Path) -> "ImageInput":
        mime = {
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".png": "image/png",
            ".webp": "image/webp",
        }[p.suffix.lower()]
        return cls(data=p.read_bytes(), mime=mime)


@dataclass(slots=True)
class Message:
    role: Literal["system", "user", "assistant"]
    text: str
    images: list[ImageInput] = field(default_factory=list)


@dataclass(slots=True)
class LlmResponse:
    text: str
    ttft_s: float | None
    decode_tok_per_s: float | None
    prompt_tokens: int | None
    completion_tokens: int | None
    wallclock_s: float
    raw: dict | None = None


class LlmRunner(abc.ABC):
    """Stateless per-call runner. Implementations may keep a client handle."""

    name: str = "abstract"

    @abc.abstractmethod
    def generate(
        self,
        messages: list[Message],
        *,
        temperature: float = 0.2,
        max_tokens: int = 1024,
    ) -> LlmResponse: ...

    # Convenience wrapper so every caller gets consistent wallclock timing.
    def run(
        self,
        *,
        system: str,
        user_text: str,
        images: list[ImageInput] | None = None,
        temperature: float = 0.2,
        max_tokens: int = 1024,
    ) -> LlmResponse:
        msgs = [
            Message("system", system),
            Message("user", user_text, list(images or [])),
        ]
        t0 = time.perf_counter()
        resp = self.generate(msgs, temperature=temperature, max_tokens=max_tokens)
        if resp.wallclock_s == 0.0:
            resp.wallclock_s = time.perf_counter() - t0
        return resp
