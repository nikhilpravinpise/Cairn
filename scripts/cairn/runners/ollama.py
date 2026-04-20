"""Ollama runner — used for the E4B baseline on an M-series Mac (S3)."""
from __future__ import annotations

import base64
import time

from cairn.runners.base import ImageInput, LlmResponse, LlmRunner, Message


class OllamaRunner(LlmRunner):
    def __init__(self, model: str, *, host: str = "http://127.0.0.1:11434") -> None:
        try:
            import ollama  # type: ignore[import-not-found]
        except ImportError as e:
            raise RuntimeError("install extras: pip install -e '.[ollama]'") from e
        self._ollama = ollama
        self._client = ollama.Client(host=host)
        self.model = model
        self.name = f"ollama:{model}"

        # Fail loud on missing model — no silent pull.
        tags = {m["name"] for m in self._client.list().get("models", [])}
        if model not in tags and f"{model}:latest" not in tags:
            raise RuntimeError(
                f"ollama model {model!r} not installed. run: `ollama pull {model}`"
            )

    @staticmethod
    def _b64(img: ImageInput) -> str:
        return base64.b64encode(img.data).decode("ascii")

    def generate(
        self,
        messages: list[Message],
        *,
        temperature: float = 0.2,
        max_tokens: int = 1024,
    ) -> LlmResponse:
        payload: list[dict] = []
        for m in messages:
            item: dict = {"role": m.role, "content": m.text}
            if m.images:
                item["images"] = [self._b64(i) for i in m.images]
            payload.append(item)

        t0 = time.perf_counter()
        resp = self._client.chat(
            model=self.model,
            messages=payload,
            options={"temperature": temperature, "num_predict": max_tokens},
        )
        wall = time.perf_counter() - t0

        # Ollama timings are in nanoseconds.
        eval_ns = resp.get("eval_duration") or 0
        eval_count = resp.get("eval_count") or 0
        prompt_ns = resp.get("prompt_eval_duration") or 0
        ttft = (prompt_ns / 1e9) if prompt_ns else None
        tok_s = (eval_count / (eval_ns / 1e9)) if eval_ns and eval_count else None

        return LlmResponse(
            text=resp["message"]["content"],
            ttft_s=ttft,
            decode_tok_per_s=tok_s,
            prompt_tokens=resp.get("prompt_eval_count"),
            completion_tokens=eval_count or None,
            wallclock_s=wall,
            raw=resp,
        )
