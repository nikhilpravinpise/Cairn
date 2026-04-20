"""Phase A — text-only LoRA on Gemma E2B / E4B via Unsloth.

Designed to run in Colab Pro. Unsloth is a CUDA-only dependency; do not call
this script on macOS.

Input data is ShareGPT JSONL (one object per line with `conversations` list).
The `system_ref` field in each line is resolved to the live system prompt by
`scripts/data/assemble_dialogues.py` before this script runs.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="unsloth/gemma-4-E2B-it")
    ap.add_argument("--data", required=True, type=Path,
                    help="ShareGPT JSONL already assembled (system prompt inlined)")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--max-steps", type=int, default=-1)
    ap.add_argument("--batch", type=int, default=4)
    ap.add_argument("--grad-accum", type=int, default=4)
    ap.add_argument("--lr", type=float, default=2e-4)
    ap.add_argument("--max-seq", type=int, default=4096)
    ap.add_argument("--r", type=int, default=16, choices=[4, 8, 16],
                    help="LoRA rank — restricted to MediaPipe-supported values")
    ap.add_argument("--alpha", type=int, default=32)
    ap.add_argument("--dropout", type=float, default=0.05)
    ap.add_argument("--target", nargs="+",
                    default=["q_proj", "k_proj", "v_proj", "o_proj"],
                    help="target_modules — attention only for MediaPipe compat")
    ap.add_argument("--seed", type=int, default=3407)
    args = ap.parse_args()

    if sys.platform == "darwin":
        sys.exit("Unsloth requires CUDA; run this on Colab / Linux.")

    try:
        import torch
        from datasets import load_dataset
        from unsloth import FastLanguageModel  # type: ignore[import-not-found]
        from unsloth.chat_templates import standardize_sharegpt  # type: ignore[import-not-found]
        from trl import SFTTrainer, SFTConfig
    except ImportError as e:
        sys.exit(f"install finetune extras: pip install -e 'scripts[finetune]'\n{e}")

    args.out.mkdir(parents=True, exist_ok=True)

    # --- Unsloth load + LoRA attach ------------------------------------------
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=args.base,
        max_seq_length=args.max_seq,
        dtype=None,
        load_in_4bit=True,
    )
    model = FastLanguageModel.get_peft_model(
        model,
        r=args.r,
        target_modules=args.target,
        lora_alpha=args.alpha,
        lora_dropout=args.dropout,
        bias="none",
        use_gradient_checkpointing="unsloth",
        random_state=args.seed,
        use_rslora=False,
        finetune_vision_layers=False,
        finetune_language_layers=True,
        finetune_attention_modules=True,
        finetune_mlp_modules=False,
    )

    ds = load_dataset("json", data_files=str(args.data), split="train")
    ds = standardize_sharegpt(ds)
    ds = ds.map(
        lambda ex: {"text": tokenizer.apply_chat_template(ex["conversations"],
                                                          tokenize=False)},
        remove_columns=ds.column_names,
    )

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=ds,
        dataset_text_field="text",
        args=SFTConfig(
            per_device_train_batch_size=args.batch,
            gradient_accumulation_steps=args.grad_accum,
            num_train_epochs=args.epochs,
            max_steps=args.max_steps,
            learning_rate=args.lr,
            warmup_ratio=0.03,
            lr_scheduler_type="cosine",
            logging_steps=5,
            optim="adamw_8bit",
            weight_decay=0.01,
            seed=args.seed,
            output_dir=str(args.out / "checkpoints"),
            report_to="none",
            dataset_text_field="text",
            max_seq_length=args.max_seq,
        ),
    )
    trainer.train()

    adapter_dir = args.out / "adapter_model"
    model.save_pretrained(str(adapter_dir))
    tokenizer.save_pretrained(str(adapter_dir))
    (args.out / "run_manifest.json").write_text(json.dumps(
        {
            "base": args.base,
            "r": args.r, "alpha": args.alpha, "dropout": args.dropout,
            "target_modules": args.target,
            "max_seq": args.max_seq,
            "cuda": torch.cuda.is_available(),
        },
        indent=2,
    ))
    print(f"saved adapter to {adapter_dir}")


if __name__ == "__main__":
    main()
