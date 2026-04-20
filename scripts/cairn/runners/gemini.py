"""Gemini API runner — used for D5 synthetic dialogue expansion.

Not used for eval baselines (that's Ollama). Pure data-generation role.
"""
from __future__ import annotations

import os
import time

from cairn.runners.base import LlmResponse, LlmRunner, Message


class GeminiRunner(LlmRunner):
    def __init__(self, model: str = "gemini-2.5-pro", api_key_env: str = "GEMINI_API_KEY") -> None:
        try:
            import google.generativeai as genai  # type: ignore[import-not-found]
        except ImportError as e:
            raise RuntimeError("install extras: pip install -e '.[gemini]'") from e
        key = os.environ.get(api_key_env)
        if not key:
            raise RuntimeError(f"missing env var {api_key_env}")
        genai.configure(api_key=key)
        self._genai = genai
        self.model_name = model
        self.name = f"gemini:{model}"

    def generate(
        self,
        messages: list[Message],
        *,
        temperature: float = 0.2,
        max_tokens: int = 1024,
    ) -> LlmResponse:
        system = "\n".join(m.text for m in messages if m.role == "system") or None
        model = self._genai.GenerativeModel(self.model_name, system_instruction=system)

        parts: list = []
        for m in messages:
            if m.role == "system":
                continue
            if m.images:
                for img in m.images:
                    parts.append({"mime_type": img.mime, "data": img.data})
            parts.append(m.text)

        t0 = time.perf_counter()
        resp = model.generate_content(
            parts,
            generation_config={
                "temperature": temperature,
                "max_output_tokens": max_tokens,
                "response_mime_type": "application/json",
            },
        )
        wall = time.perf_counter() - t0

        usage = getattr(resp, "usage_metadata", None)
        return LlmResponse(
            text=resp.text,
            ttft_s=None,
            decode_tok_per_s=None,
            prompt_tokens=getattr(usage, "prompt_token_count", None),
            completion_tokens=getattr(usage, "candidates_token_count", None),
            wallclock_s=wall,
            raw=None,
        )
