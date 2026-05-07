# Cairn Pipeline Optimization Research

**Date:** 2026-05-03  
**Status:** Research only — no implementation yet  
**Problem:** 5 photos × ~2 min each = ~10 min total. Unacceptable for field use.

---

## 1. Current Pipeline Bottleneck Analysis

### What happens today (per the codebase)

```
User captures 5 photos (Phase A — model NOT loaded)
    ↓
User taps "Describe photos (5)" → Phase B begins
    ↓
1. Load model: GemmaSession.openForVision() → _install() + _create()
   - _install(): FlutterGemma.installModel() (idempotent, cached after first run)
   - _create(): FlutterGemma.getActiveModel(preferredBackend: gpu, maxTokens: 4096, maxNumImages: 5)
   - createChat(temperature: 0.2, topK: 40, topP: 0.95, supportImage: true)
    ↓
2. FOR EACH photo (sequential, 5 iterations):
   a. Build JSON prompt with task + metadata
   b. Create Message.withImage(text: jsonPrompt, imageBytes: rawBytes)
   c. chat.addQueryChunk(msg)
   d. chat.generateChatResponseAsync() → stream tokens until done
   e. chat.clearHistory()
   f. Parse JSON from response, validate contract
    ↓
3. Done — all 5 described
```

### Where the ~2 min per photo goes (estimated breakdown)

| Phase | Estimated Time | Why |
|---|---|---|
| **Image encoding (ViT prefill)** | ~30-50s | 1600px wide JPEG @ quality 85 → massive visual token count. No downscaling before inference. Gemma 4 default budget = 256 tokens but raw image is huge. |
| **LLM prefill (system prompt + image tokens + JSON prompt)** | ~20-30s | ~2K token system prompt re-processed every turn (history cleared). Image tokens dominate. |
| **Autoregressive decoding** | ~30-40s | Structured JSON output with model_description, model_tags, bbox_annotations. At ~4 tok/s that's 120-160 tokens = 30-40s. |
| **clearHistory + overhead** | ~5-10s | Native bridge overhead, GC pressure, memory shuffling. |
| **Exynos GPU variance** | ±52% | Samsung Exynos has wildly inconsistent GPU delegate performance (see research below). |

### Key architectural observations

1. **No image preprocessing**: Photos captured at `maxWidth: 1600, imageQuality: 85` are sent RAW to the model. No resize to Gemma's native resolution.
2. **Sequential processing**: Photos described one-by-one in a `for` loop. No parallelism.
3. **History cleared every turn**: System prompt re-ingested for every single photo. Enormous waste.
4. **maxTokens: 4096**: Way too high for describe_photo which needs ~100-200 tokens of output. This means the model allocates KV cache for 4096 tokens.
5. **Exynos + Mali GPU**: The S23 FE uses Exynos 2200 (Xclipse 920 GPU). Research shows ±52% latency variance on Exynos vs ±12% on Snapdragon. GPU delegate is unreliable.
6. **MediaPipe .task format**: Current pipeline uses older MediaPipe LLM Inference API, not the newer LiteRT-LM path.

---

## 2. Optimization Strategies (Ranked by Impact)

### 🔴 TIER 1 — HIGH IMPACT, LOW EFFORT (implement first)

#### 2A. Downscale images before inference

**The single biggest win.** Currently sending 1600px-wide JPEG bytes directly. Gemma 4 E2B's vision encoder processes images via a ViT that tokenizes into patches. More pixels = more patches = more visual tokens = quadratically more prefill compute.

**Gemma 4 variable resolution token budgets:**
| Budget | Tokens | Effective Resolution | Use Case |
|---|---|---|---|
| 70 | 64 | Very low | Quick classification |
| 140 | 121 | Low | Basic understanding |
| **280** | **256** | **Medium** | **Good for damage assessment** |
| 560 | 529 | High | Fine detail |
| 1120 | 1024 | Very high | Precise detection |

**Action:** Resize images to ~512×512 (or 768×768 max) BEFORE passing to the model. The image_picker already caps at 1600px wide, but the ViT still processes whatever resolution it receives. Resizing in Dart via `ui.instantiateImageCodec` + `canvas.drawImage` to exactly 512×512 before inference would:
- **Reduce visual tokens from ~256-1120 down to ~64-121**
- **Cut ViT encoding time by 3-8×**
- **Cut LLM prefill time proportionally** (fewer visual tokens in the sequence)

For building damage assessment, 512×512 is more than sufficient — FEMA P-154 is about gross structural features (cracks, lean, collapse), not pixel-level detail.

**Estimated speedup: 2-4× per photo** (from ~120s to ~30-60s)

#### 2B. Reduce maxTokens from 4096 to 1024-2048

Current: `maxTokens: 4096` in `_create()`. The describe_photo response is typically ~100-200 tokens of JSON. The 4096 token budget forces MediaPipe to allocate a massive KV cache upfront.

**Action:** Set `maxTokens: 1024` (or even 768) for the vision session profile. The system prompt is ~2K tokens and images are 64-256 tokens, so 1024 output tokens is still generous.

**Estimated speedup: 10-20% memory reduction + faster model init**

#### 2C. Stop clearing history between same-profile turns

Currently `chat.clearHistory()` is called after EVERY describe_photo turn. This means the system prompt (~2K tokens) must be re-prefilled for every single photo. For 5 photos, that's 5× the system prompt prefill.

**Alternative approach:** Keep the chat session alive across all 5 describe_photo turns within the `_describeAll()` loop. The system instruction is already set via `systemInstruction:` parameter at chat creation — it persists across turns. Only clear history once at the END of all 5 descriptions.

**Caveat:** Need to verify that prior turn context doesn't contaminate subsequent photo descriptions. The current code comments say "Cairn task turns are independent JSON contracts" — but if the model sees prior photos' descriptions, it might hallucinate consistency. Test this carefully.

**If safe: Estimated speedup: 15-25%** (saves 4× system prompt re-prefill = ~8K tokens of wasted prefill across 5 photos)

---

### 🟡 TIER 2 — HIGH IMPACT, MEDIUM EFFORT

#### 2D. Stay on the current flutter_gemma Gemma 4-compatible line

The codebase uses `flutter_gemma: ^0.14.5`. The active model path must remain
Gemma 4-compatible and use `ModelType.gemma4`.

The current registry defines `.task` files for web and `.litertlm` files for
Android/non-web runtime paths.

**Action:**
1. Keep `flutter_gemma` on the current Gemma 4-compatible line.
2. Keep the registry constrained to Gemma 4 E2B/E4B LiteRT-LM artifacts.
3. Benchmark the default runtime against the Android `native_mtp` bridge.

**Note on NPU:** The S23 FE (Exynos 2200) does NOT have a viable NPU for LLM inference. NPU acceleration is primarily for Qualcomm (Snapdragon 8 Gen 2+), MediaTek (Dimensity 9200+), and Google Tensor (Pixel 8+). However, the LiteRT-LM FFI path is still faster than the MediaPipe .task path even on GPU.

**Estimated speedup: 15-30%** (reduced bridge overhead, better GPU scheduling)

#### 2E. Gemma 4-only runtime acceleration

The active architecture is Gemma 4 only. Do not use this research document as
approval to add another model family.

Allowed optimization paths:

- Android LiteRT-LM MTP / speculative decoding.
- Image preprocessing and visual-token reduction.
- Shorter structured outputs.
- Lower session `maxTokens` after contract-failure gates pass.
- Temperature/backend benchmarking on the target device.

#### 2F. Prompt engineering for shorter output

The describe_photo JSON contract currently asks for:
- `model_description` (free text — model writes paragraphs)
- `model_tags` (array of strings)
- `model_confidence` (float)
- `bbox_annotations` (array of objects with box_2d)

The `model_description` field is where the model spends most of its decoding tokens. If the system prompt constrains this to "≤50 words" or "2-3 sentences max", decoding time drops proportionally.

**Action:** Add explicit length constraints to the system prompt for describe_photo output. E.g., "model_description MUST be ≤ 3 sentences."

**Estimated speedup: 20-40% on decoding phase** (from ~30-40s to ~15-25s)

---

### 🟢 TIER 3 — MEDIUM IMPACT, HIGHER EFFORT

#### 2G. Batch multiple images in a single inference call

Gemma 4 supports up to 5 images per session (`maxNumImages: 5` already set). Instead of 5 separate describe_photo calls, send ALL 5 images in a SINGLE prompt:

```json
{
  "task": "describe_photos_batch",
  "photos": [
    {"observation_id": "obs-0", "prompt_id": "fema_p154_q01", "image_refs": ["img-0"]},
    {"observation_id": "obs-1", "prompt_id": "fema_p154_q02", "image_refs": ["img-1"]},
    ...
  ]
}
```

**Advantages:**
- Single prefill of system prompt + all images
- Model sees full building context (better reasoning)
- Eliminates 4× overhead of clearHistory + re-prefill

**Risks:**
- Output length may exceed maxTokens
- Single failure = all 5 fail (no graceful degradation)
- May exceed context window (5 images × 256 tokens + 2K system + 1K output ≈ 4.3K)
- Harder to show per-photo progress in UI

**Estimated speedup: 2-3× vs sequential** (but risk of quality/reliability tradeoff)

#### 2H. Bypass flutter_gemma → Direct Kotlin Platform Channels to LiteRT-LM

A Reddit post (r/FlutterDev, 25 upvotes) documented severe issues with flutter_gemma causing phone reboots. Their solution: **bypass flutter_gemma entirely** and call the LiteRT-LM Kotlin API directly via Platform Channels.

**Advantages:**
- Full control over model lifecycle
- Direct access to LiteRT-LM tuning parameters
- Can implement custom image preprocessing in native code
- Reverse MethodChannel callback for token streaming
- No flutter_gemma abstraction overhead

**Disadvantages:**
- Significant engineering effort (3-4 days per the Reddit post)
- Lose cross-platform compatibility
- Must maintain native Android code
- flutter_gemma 0.14.2 already uses Dart FFI for .litertlm, partially addressing this

**Estimated speedup: 10-20%** (marginal over flutter_gemma 0.14.2 FFI path)

#### 2I. Speculative Decoding

Research shows speculative decoding can achieve **2-3× faster token generation**:
- Use a smaller "draft" model to propose multiple tokens
- Verify them in parallel with the main model
- Accept 3-4 tokens per iteration vs 1

**Current state for on-device:**
- Not available in MediaPipe LLM Inference API
- Not available in LiteRT-LM (as of current release)
- Would require custom native implementation
- Gemma 4 was trained with Multi-Token Prediction heads, but **Google stripped them from the published weights** (only available through Google's API)

**Verdict:** Not actionable today. Monitor LiteRT-LM releases.

#### 2J. CPU fallback for Exynos

Research shows Exynos GPU delegate has ±52% latency variance. On Samsung devices, **CPU with predictable latency may actually be better UX** than GPU with wild variance.

**Action:** Benchmark both paths on the S23 FE:
```dart
// Current
preferredBackend: PreferredBackend.gpu  // Mali GPU, inconsistent
// Alternative
preferredBackend: PreferredBackend.cpu  // XNNPACK, 4 threads, predictable
```

The predictability matters more than peak speed for user experience. A steady 90s is better than 60s-180s variance.

---

### 🔵 TIER 4 — FUTURE / RESEARCH-ONLY

#### 2K. Visual Token Compression (LiteVLM approach)

Recent paper (June 2025) "LiteVLM" achieves **2.5× latency reduction** by:
1. **Patch Selection:** Skip irrelevant image patches before ViT encoding
2. **Token Compression:** Prune less informative visual tokens before LLM prefill
3. **Speculative Decoding:** Draft model for faster generation

Not directly applicable to MediaPipe/LiteRT-LM pipeline today, but the image downscaling strategy (2A) captures some of this benefit.

#### 2L. Diffusion LLMs

Predict multiple tokens per step via denoising. 4-6× speedup potential. Still experimental. Not available for Gemma.

#### 2M. ExecuTorch (Meta)

Meta's production runtime. 50KB base footprint, supports 12+ hardware backends. Hit 1.0 GA October 2025. Would require porting Gemma to ExecuTorch format — not practical for hackathon timeline.

---

## 3. Recommended Implementation Plan

### Phase 1: Quick Wins (1-2 hours, no architecture change)

1. **Image downscaling** (2A): Resize to 512×512 before inference → **2-4× speedup**
2. **Reduce maxTokens** (2B): 4096 → 1024 → **10-20% speedup**
3. **Shorter output prompts** (2F): Constrain model_description length → **20-40% decoding speedup**

**Combined Phase 1 estimate: 10 min → ~3-4 min**

### Phase 2: Medium Effort (half day)

4. **Upgrade flutter_gemma** (2D): 0.14.0 → 0.14.2, use .litertlm path → **15-30% speedup**
5. **Test history retention** (2C): Don't clear between same-profile turns → **15-25% if safe**
6. **CPU vs GPU benchmark** (2J): Profile both on S23 FE, pick the consistent one

**Combined Phase 1+2 estimate: 10 min → ~2-3 min**

### Phase 3: Runtime Gate (1-2 days)

7. **Benchmark Gemma 4 MTP path** (2E): default runtime vs native MTP on target Android hardware.
8. **Keep model-registry guard green** before accepting runtime changes.

**Combined Phase 1+2+3 estimate:** device-gated; do not claim a final target
until the Gemma 4 runtime path is measured.

### Phase 4: Architecture Change (2-3 days, if needed)

9. **Batch inference** (2G): Single call for all 5 photos
10. **Native Kotlin bridge** (2H): Only if flutter_gemma remains a bottleneck

---

## 4. Competitive Analysis — Hackathon Submissions

### Hackathon Context

- **Competition:** Gemma 4 Good Hackathon (Kaggle × Google DeepMind)
- **Prize pool:** $200,000 USD
- **Deadline:** May 18, 2026
- **Requirements:** Working demo + public code repo + technical writeup + video
- **Focus areas:** Health, education, global resilience, digital equity, agriculture, assistive tech
- **Judging criteria:** Impact, technical execution, clear use case, functionality demonstration
- **Cairn project constraint:** Gemma 4 models only.

### 4A. EpiCast (janeodum/Epicast) — Disease Surveillance

**Architecture:** MedGemma 4B (local) + MedGemma 27B (cloud fallback) — **NOT truly on-device mobile**

| Aspect | Detail |
|---|---|
| **Mobile framework** | React Native (Expo) |
| **Local inference** | `llama-server` (llama.cpp) running MedGemma 27B Q3_K_M GGUF on Mac, NOT on phone |
| **Mobile ↔ Model** | Mobile app → HTTP → Flask server on Mac/RunPod → MedGemma |
| **On-device models** | HeAR (ONNX, ~512 dim embedding) for cough classification only |
| **Model loading** | `AutoModelForImageTextToText` + BitsAndBytes 4-bit NF4 quantization |
| **LoRA** | r=16, alpha=32, all-linear targets for syndromic extraction task |
| **Max tokens** | 1024 for 4B extraction, 2048 for 27B reports |
| **Temperature** | 0.1 for extraction (very low = deterministic), 0.3 for reports |

**Key takeaways for Cairn:**
- **They DON'T run the LLM on the phone.** The mobile app is just a UI shell that talks to a server. This means our truly on-device approach is a **competitive differentiator** — genuine offline capability in disaster zones.
- **max_new_tokens: 1024** for structured extraction is sensible (confirms our recommendation to lower from 4096).
- **Temperature 0.1** for structured JSON extraction — worth testing for our describe_photo task (currently 0.2).
- Their LoRA config (r=16, alpha=32, all-linear) is standard but effective for task-specific fine-tuning.

### 4B. Sunny (mrdbourke/sunny) — Skin Health Tracking (iOS)

**Architecture:** MedGemma 1.5 4B fine-tuned → MLX 4-bit → iOS native on-device

| Aspect | Detail |
|---|---|
| **Platform** | iOS native (Swift + SwiftUI) |
| **On-device runtime** | Apple MLX framework (mlx-swift-lm, mlx-vlm) |
| **Model** | MedGemma 1.5 4B → fine-tuned (SFT, frozen vision tower) → converted to MLX 4-bit |
| **Quantization** | 4-bit group-size-32 (RTN), struggled with quality degradation |
| **Prompt strategy** | Ultra-short: just `"skin extract"` or `"sunscreen extract"` + image |
| **Max tokens** | 2048 |
| **Temperature** | 0.5 |
| **Image input** | `UIImage` → `CIImage` → MLX VLM pipeline |
| **Auto-unload** | Model unloaded after 120s of inactivity to free memory |

**Critical optimization lessons for Cairn:**

1. **Ultra-short prompts are the killer optimization.** Sunny's prompt is literally just `"skin extract"` — two words. The model was **fine-tuned to understand this trigger** and output structured JSON. Compare to our verbose JSON prompt with task, observation_id, prompt_id, asked_in, image_refs, audio_refs, user_text. This is a massive prompt token savings.

2. **Fine-tune to internalize the task contract.** Instead of explaining the output schema in the system prompt every time, Sunny fine-tuned the model so it *knows* the schema. The system prompt went from a full page of instructions to nothing — the model just does the right thing when it sees `"skin extract"` + image.

3. **Prompt order matters.** Sunny explicitly documented: image must come BEFORE text in the prompt (`<image>` + `<text>` → `<text>`). They found wrong order = garbage output. **We should verify our ordering.**

4. **4-bit quantization causes generation loops.** They observed the model entering "infinite loops" at 4-bit RTN quantization, especially for longer outputs. Their workaround: shorter prompts = fewer output tokens = less chance of quality degradation. Learned quantization (dynamic quant, DWQ) helped but was more complex.

5. **Vision encoder is the bottleneck, not the LLM.** Their notes reinforce that vision encoding can dominate latency. For Cairn, address this through Gemma 4 image-size/token-budget control and LiteRT-LM runtime acceleration, not by changing model family.

6. **Auto-unload after inactivity.** Sunny unloads the model after 120s idle. Our two-phase approach (capture → describe) already does this, but their 120s timer is a nice UX pattern to avoid manual unload.

### 4C. Competitive Positioning

| Feature | EpiCast | Sunny | **Cairn (ours)** |
|---|---|---|---|
| **Truly on-device** | ❌ (server) | ✅ (iOS MLX) | ✅ (Android LiteRT-LM) |
| **Works offline** | ❌ | ✅ | ✅ |
| **Platform** | React Native | iOS only | Flutter (Android + Web) |
| **Model** | MedGemma 4B | MedGemma 1.5 4B | Gemma 4 E2B |
| **Vision** | SigLIP | SigLIP (MLX) | SigLIP (LiteRT-LM) |
| **Quantization** | NF4 (server-side) | RTN 4-bit | INT4 |
| **Fine-tuned** | Yes (LoRA) | Yes (full LM SFT) | Yes (LoRA) |

**Our advantages:**
- Only project with genuine offline on-device inference on Android
- Flutter = cross-platform potential (Android + iOS + Web)
- Disaster response use case = extremely compelling for "Global Resilience" track

**Our gap:**
- Speed. Both competitors avoid the 2-min-per-photo problem: EpiCast by using a server, Sunny by having shorter prompts + smaller output. We need to close this gap.

### 4D. Actionable Insights from Competitors

1. **Shorten prompts dramatically (Sunny pattern):** Fine-tune the model to respond to a short trigger like `"describe_photo"` + image, instead of sending the full JSON contract in the prompt. This alone could save 500+ tokens of input per photo.

2. **Lower temperature to 0.1 for structured extraction (EpiCast pattern):** More deterministic = less wasted decoding on rejected tokens.

3. **Consider SFT (supervised fine-tuning) over just LoRA:** Sunny fine-tuned the full LM (frozen vision tower) on 1.1K samples. This gave them a model that produces the right output schema from a 2-word prompt. Our LoRA approach could be augmented with similar task-specific SFT.

4. **Keep model policy fixed:** Faster vision architectures are useful context, but Cairn's active implementation remains Gemma 4-only.

5. **maxTokens alignment:** Both competitors use 1024-2048, not 4096. We should reduce to 1024.

---

## 5. Key External References

| Resource | URL | Relevance |
|---|---|---|
| Gemma 4 Variable Resolution | https://ai.google.dev/gemma/docs/capabilities/vision | Token budget control |
| flutter_gemma Changelog | https://pub.dev/packages/flutter_gemma/changelog | FFI rewrite, NPU support |
| LiteRT-LM GitHub | https://github.com/google-ai-edge/LiteRT-LM | Production inference framework |
| On-Device LLMs: State of the Union 2026 | https://v-chandra.github.io/on-device-llms/ | Speculative decoding, quantization |
| LiteVLM Paper | https://arxiv.org/html/2506.07416v1 | Visual token compression techniques |
| Exynos GPU Variance | dev.to article (see research) | ±52% variance on Samsung chips |
| Reddit: Bypass flutter_gemma | r/FlutterDev thread | Direct Kotlin LiteRT-LM approach |
| FastVLM (Apple CVPR 2025) | https://machinelearning.apple.com/research/fast-vision-language-models | Efficient vision encoding |
| MediaPipe LLM Inference Android | https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference/android | MediaPipe deprecated, migrate to LiteRT-LM |
| **EpiCast** (competitor) | https://github.com/janeodum/Epicast | MedGemma 4B server-side, LoRA fine-tuned, React Native mobile shell |
| **Sunny** (competitor) | https://github.com/mrdbourke/sunny | MedGemma 1.5 4B on-device iOS via MLX, ultra-short prompts, SFT fine-tuned |
| Sunny Writeup | https://github.com/mrdbourke/sunny/blob/main/writeup.md | On-device VLM deployment lessons, quantization pitfalls |
| Gemma 4 Good Hackathon | https://www.kaggle.com/competitions/gemma-4-good-hackathon | Competition rules, $200K prize, deadline May 18 2026 |
