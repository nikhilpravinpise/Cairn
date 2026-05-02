"""Project-wide constants. Fail loud if any locked resource is missing."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[2]

SCHEMA_PATH: Path = REPO_ROOT / "docs" / "schema" / "evidence_packet_v1.schema.json"
SYSTEM_PROMPT_PATH: Path = REPO_ROOT / "docs" / "prompts" / "system_prompt_v1.txt"
SEED_JSONL_PATH: Path = REPO_ROOT / "data" / "seeds" / "dialogues.seed.jsonl"

for _p, _label in [
    (SCHEMA_PATH, "schema"),
    (SYSTEM_PROMPT_PATH, "system prompt"),
    (SEED_JSONL_PATH, "seed dialogues"),
]:
    if not _p.is_file():
        raise FileNotFoundError(f"locked {_label} missing at {_p}")


# Per-platform artifact file-type extensions.
# Mirrors ModelSpec.fileType(isWeb:) in apps/cairn_mobile/lib/core/llm/model_registry.dart.
# Changing these must be accompanied by matching changes in Dart + test_constants_parity.py.
FILE_TYPE_WEB = "task"
FILE_TYPE_ANDROID = "litertlm"


@dataclass(frozen=True, slots=True)
class ModelSpec:
    """Identifies a single model + quant we actually run somewhere."""

    key: str                # short handle used everywhere else
    display: str            # human name for reports
    hf_repo: str            # HuggingFace litert-community repo
    task_filename_web: str      # .task filename inside that repo
    task_filename_android: str  # .litertlm filename inside that repo
    ollama_tag: str | None  # ollama tag (None if we don't run it in Ollama)
    quant: str              # "int4" | "int8" | "fp16" | "bf16"
    modalities: tuple[str, ...]  # subset of ("text","image","audio")
    context_tokens: int


# Target ids from the implementation plan (§2.4). These are aspirational strings; the
# actual repo slugs may need updating as the litert-community catalog evolves.
# Code that loads models should fail loud if the resolved artifact 404s.
MODELS: dict[str, ModelSpec] = {
    "e2b": ModelSpec(
        key="e2b",
        display="Gemma E2B IT (LiteRT-LM)",
        hf_repo="litert-community/gemma-4-E2B-it-litert-lm",
        task_filename_web="gemma-4-E2B-it-web.task",
        task_filename_android="gemma-4-E2B-it.litertlm",
        ollama_tag=None,
        quant="int4",
        modalities=("text", "image"),
        context_tokens=8192,
    ),
    "e4b": ModelSpec(
        key="e4b",
        display="Gemma E4B IT (LiteRT-LM)",
        hf_repo="litert-community/gemma-4-E4B-it-litert-lm",
        task_filename_web="gemma-4-E4B-it-web.task",
        task_filename_android="gemma-4-E4B-it.litertlm",
        ollama_tag="gemma3n:e4b",  # best-effort; verify in S3
        quant="int4",
        modalities=("text", "image"),
        context_tokens=8192,
    ),
}


# --- priority scoring ---------------------------------------------------------
# Mirrored verbatim in Dart (`apps/cairn_mobile/lib/core/triage/priority.dart`).
# DO NOT diverge without bumping schema version.
HAZARD_SEVERITY_POINTS: dict[str, int] = {"high": 3, "moderate": 2, "low": 1}

PRIORITY_BAND_BOUNDS: tuple[tuple[str, int, int], ...] = (
    ("LOW", 1, 3),
    ("MEDIUM", 4, 6),
    ("HIGH", 7, 8),
    ("CRITICAL", 9, 10),
)
