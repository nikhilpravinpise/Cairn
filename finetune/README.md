# `finetune/` — LoRA training + MediaPipe conversion

## Phase A (P0) — text-only LoRA on E2B + E4B

Designed for **Unsloth FastLanguageModel** on Colab Pro (A100 or L4). The CLI
below also runs locally on any Linux box with a CUDA GPU; Mac is **not**
supported because Unsloth requires `xformers` + CUDA.

```bash
python finetune/phase_a_text_lora.py \
  --base unsloth/gemma-4-E2B-it \
  --data data/train/phase_a.jsonl \
  --out  runs/phase_a_e2b/ \
  --epochs 3 --batch 4 --grad-accum 4 --lr 2e-4 --max-seq 4096 \
  --r 16 --alpha 32 --dropout 0.05 \
  --target q_proj k_proj v_proj o_proj
```

**MediaPipe-compatibility constraints** (plan §4.1):
- LoRA targets **attention layers only** (`q_proj,k_proj,v_proj,o_proj`).
- `finetune_vision_layers=False`, `finetune_mlp_modules=False`.
- `r ∈ {4, 8, 16}` — MediaPipe converter accepts these ranks.

## Convert to MediaPipe flatbuffer

```bash
python finetune/convert_mediapipe_lora.py \
  --adapters runs/phase_a_e2b/adapter_model \
  --out      runs/phase_a_e2b/e2b_lora.fb \
  --rank 16 --backend gpu
```

On-device load path is `MediaPipe LlmInferenceOptions.setLoraPath(...)`, which
`flutter_gemma` exposes via `InferenceChat(loraPath: ...)`.

## Phase B (P1) — vision-conditioned LoRA
Stub `phase_b_vision_lora.py` is provided but intentionally empty until W3
(§4.2). Ship only if the §3.3 gate passes.
