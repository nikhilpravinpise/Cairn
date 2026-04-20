# S5 — LoRA round-trip spike (D5–D6)

Goal: **measurable behavior delta** between base-E2B and E2B + tiny LoRA on the
device, with MediaPipe flatbuffer conversion in the loop.

## Procedure

1. **Train a tiny LoRA** (≤ 5 min on A100 / L4) on 50 dialogues from the seed
   set, with intentionally skewed labels (e.g. all answers tagged
   `soft_story_condition`). A skewed tiny LoRA guarantees an unambiguous
   behavior delta — it's a detector for "LoRA actually attached", not a
   quality claim.

   ```bash
   python finetune/phase_a_text_lora.py \
       --base unsloth/gemma-4-E2B-it \
       --data data/seeds/dialogues.seed.jsonl \
       --out runs/s5_tiny_lora/ \
       --max-steps 50 --batch 4 --lr 2e-4 --r 16 --alpha 32 \
       --target q_proj k_proj v_proj o_proj
   ```

2. **Convert adapters → MediaPipe flatbuffer**

   ```bash
   python finetune/convert_mediapipe_lora.py \
       --adapters runs/s5_tiny_lora/adapter_model \
       --out       runs/s5_tiny_lora/e2b_lora.fb \
       --rank 16 --backend gpu
   ```

3. **Sideload flatbuffer to the phone**

   ```bash
   adb push runs/s5_tiny_lora/e2b_lora.fb \
       /sdcard/Android/data/app.cairn.cairn_mobile/files/e2b_lora.fb
   ```

4. **Run S2 spike app** with `Load E2B + LoRA`, run 5 prompts, save
   `s2_report.json`. Diff vs the base `s2_report.json` on these columns:
   `model_tags`, `model_confidence`. Any difference → pass.

## Pass criteria
- Non-empty `tag_set_diff` between base and LoRA runs on ≥ 3/5 prompts.
- No new SIGSEGV or load regressions introduced by the LoRA.

## Fail → Plan B
Ship base in the Android app; keep the LoRA in the Colab demo only. Writeup
frames Phase A as a Colab artifact rather than an on-device adapter. Lose the
Unsloth prize angle but not the LiteRT prize.
