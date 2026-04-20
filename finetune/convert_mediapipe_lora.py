"""Convert a PEFT LoRA adapter to a MediaPipe LLM Inf flatbuffer.

Thin wrapper around `mediapipe.tasks.python.genai.converter.convert_checkpoint`.
Intentional fail-loud: we do NOT paper over incompatible ranks or targets.
Run in the same CUDA env as `phase_a_text_lora.py`.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--adapters", required=True, type=Path,
                    help="PEFT adapter_model dir from phase_a_text_lora.py")
    ap.add_argument("--out", required=True, type=Path, help="output .fb flatbuffer")
    ap.add_argument("--rank", type=int, required=True, choices=[4, 8, 16])
    ap.add_argument("--backend", choices=["gpu", "cpu"], default="gpu")
    args = ap.parse_args()

    try:
        from mediapipe.tasks.python.genai import converter  # type: ignore[import-not-found]
    except ImportError as e:
        sys.exit(f"install mediapipe:  pip install mediapipe>=0.10.22\n{e}")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    # The converter signature expects a ConversionConfig. Field names have drifted
    # across MediaPipe minor versions; we set the ones that have been stable and
    # let newer fields default.
    cfg = converter.ConversionConfig(
        backend=args.backend,
        lora_ckpt=str(args.adapters),
        lora_rank=args.rank,
        lora_output_tflite_file=str(args.out),
    )
    converter.convert_checkpoint(cfg)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
