"""Cross-language parity — Dart `model_registry.dart` vs Python `constants.py`.

Parses the Dart file as text (no pub.dev runtime), extracts the identifying
fields, and asserts they match the Python `MODELS` dict.
"""
from __future__ import annotations

import re
from pathlib import Path

from cairn.constants import FILE_TYPE_ANDROID, FILE_TYPE_WEB, MODELS, REPO_ROOT

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
        for field in ("key", "hfRepo", "taskFilenameWeb", "taskFilenameAndroid", "quant"):
            m = re.search(rf"{field}:\s*'([^']+)'", body)
            if m:
                fields[field] = m.group(1)
        out[key] = fields
    return out


def _dart_hf_url(hf_repo: str, filename: str) -> str:
    return f"https://huggingface.co/{hf_repo}/resolve/main/{filename}"


# ---------------------------------------------------------------------------
# Cross-language parity
# ---------------------------------------------------------------------------


def test_dart_python_parity() -> None:
    dart = _parse_dart_models(DART)
    # Every Python model must appear in Dart with the same repo + filename.
    for key, spec in MODELS.items():
        assert key in dart, f"dart model_registry missing {key!r}"
        d = dart[key]
        assert d["key"] == spec.key
        assert d["hfRepo"] == spec.hf_repo
        assert d["taskFilenameWeb"] == spec.task_filename_web
        assert d["taskFilenameAndroid"] == spec.task_filename_android
        assert d["quant"] == spec.quant


# ---------------------------------------------------------------------------
# Phase 5 — artifact extension and platform file-type conventions
# ---------------------------------------------------------------------------


def test_web_artifact_uses_task_extension() -> None:
    """All web model artifacts must carry the .task extension (MediaPipe web format).

    Mirrors the FILE_TYPE_WEB constant and ModelFileType.task in model_registry.dart.
    """
    for key, spec in MODELS.items():
        assert spec.task_filename_web.endswith(f".{FILE_TYPE_WEB}"), (
            f"MODELS[{key!r}].task_filename_web must end with .{FILE_TYPE_WEB},"
            f" got {spec.task_filename_web!r}"
        )


def test_android_artifact_uses_litertlm_extension() -> None:
    """All Android model artifacts must carry the .litertlm extension (LiteRT-LM format).

    Mirrors the FILE_TYPE_ANDROID constant and ModelFileType.litertlm in model_registry.dart.
    Phase 1 confirmed ModelFileType.litertlm exists in flutter_gemma 0.14.0.
    """
    for key, spec in MODELS.items():
        assert spec.task_filename_android.endswith(f".{FILE_TYPE_ANDROID}"), (
            f"MODELS[{key!r}].task_filename_android must end with .{FILE_TYPE_ANDROID},"
            f" got {spec.task_filename_android!r}"
        )


def test_android_artifacts_are_not_qualcomm_specific() -> None:
    """Android artifacts must be generic LiteRT-LM files, not Qualcomm AI Hub variants.

    Target device is Samsung Galaxy S23 FE (Exynos 2200 / Mali-G710) per §1.2.
    Qualcomm-specific variants use QDSP optimisations that cannot run on Exynos.
    """
    for key, spec in MODELS.items():
        filename = spec.task_filename_android.lower()
        repo = spec.hf_repo.lower()
        for forbidden in ("qualcomm", "qdsp", "aiehub", "aihub"):
            assert forbidden not in filename, (
                f"MODELS[{key!r}] android artifact must not be Qualcomm-specific"
                f" (found {forbidden!r} in filename {spec.task_filename_android!r})"
            )
            assert forbidden not in repo, (
                f"MODELS[{key!r}] hf_repo must not reference Qualcomm"
                f" (found {forbidden!r} in repo {spec.hf_repo!r})"
            )


def test_e2b_is_primary_android_target() -> None:
    """E2B must be present as the primary Android model.

    §1.2: E4B is out of scope for the S23 FE (8 GB RAM too tight for ~5 GB model + OS).
    providers.dart selectedModelKeyProvider defaults to 'e2b'.
    """
    assert "e2b" in MODELS, "e2b model must be present — it is the S23-FE Android target"
    e2b = MODELS["e2b"]
    assert e2b.task_filename_android == f"gemma-4-E2B-it.{FILE_TYPE_ANDROID}", (
        f"e2b android artifact mismatch: {e2b.task_filename_android!r}"
    )
    assert e2b.task_filename_web == f"gemma-4-E2B-it-web.{FILE_TYPE_WEB}", (
        f"e2b web artifact mismatch: {e2b.task_filename_web!r}"
    )
    assert e2b.hf_repo.startswith("litert-community/"), (
        f"e2b hf_repo must be a litert-community repo: {e2b.hf_repo!r}"
    )


def test_web_and_android_artifacts_are_distinct() -> None:
    """Each model must have different filenames for web vs Android."""
    for key, spec in MODELS.items():
        assert spec.task_filename_web != spec.task_filename_android, (
            f"MODELS[{key!r}] web and android artifacts must differ"
        )


def test_dart_url_structure_matches_python() -> None:
    """Dart-derived HF URLs must match the Python-derived canonical form."""
    dart = _parse_dart_models(DART)
    for key, spec in MODELS.items():
        assert key in dart
        d = dart[key]
        expected_web = _dart_hf_url(spec.hf_repo, spec.task_filename_web)
        expected_android = _dart_hf_url(spec.hf_repo, spec.task_filename_android)
        # Reconstruct the URL using parsed Dart fields and compare.
        dart_web = _dart_hf_url(d["hfRepo"], d["taskFilenameWeb"])
        dart_android = _dart_hf_url(d["hfRepo"], d["taskFilenameAndroid"])
        assert dart_web == expected_web, (
            f"{key!r} web URL mismatch: dart={dart_web!r} python={expected_web!r}"
        )
        assert dart_android == expected_android, (
            f"{key!r} android URL mismatch: dart={dart_android!r} python={expected_android!r}"
        )
