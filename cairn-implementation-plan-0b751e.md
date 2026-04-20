# Cairn — Gemma 4 Good Hackathon Implementation Plan

Ship **Cairn**, an offline Flutter post-earthquake building triage app powered by Gemma 4 E2B (Android) + E4B (Web) following FEMA P-154 rapid visual screening, with structured evidence packets and a static engineer web console, in 31 days targeting Global Resilience + LiteRT + Unsloth prizes.

---
Review the latest docs for everything, and try to code optimised, dont add fallbacks for everything, when you fail, you fail loud. No heuristic approach allowed unless absolutely neceessary. No hardcoding stuff. Code should be modular 

## 0. Locked inputs

| Input | Value | Impact |
|---|---|---|
| Device | **Samsung S23 FE / A55 Exynos, 8 GB RAM** | Primary model = **E2B INT4** (not E4B). No Snapdragon NPU → Mali GPU + XNNPACK CPU. |
| Compute | **Colab Pro** (A100/L4) | Unlocks Phase B vision LoRA as stretch. |
| Video | **Solo + 1 collaborator** | Single-protagonist narrative + voiceover + archival B-roll. |
| Platform | **Android + Web (WebGPU)** | Web demo runs E4B for zero-install judge trial. |
| Runtime | **`flutter_gemma` 0.13.x** (MediaPipe LLM Inf API + LiteRT-LM 0.10) | One Dart codebase; fallback = Kotlin platform channels. |
| Protocol | **FEMA P-154 L1 Sidewalk Survey**, not ATC-20 | Legally defensible for non-experts. |
| Name | **Cairn** (verify `cairn.app` D1; fallback `Threshold`) | |
| Prizes | **Global Resilience $10K + LiteRT $10K + Unsloth $10K** | Realistic expected $10–30K. |

---

## 1. Product spec

### P0 (must ship)
1. Flutter Android app, offline, multimodal (image+voice+text), FEMA P-154 guided flow.
2. Camera + mic (mono 16kHz WAV) + text fallback.
3. Gemma 4 E2B inference via `flutter_gemma` with system-instruction-locked protocol + structured JSON output.
4. **EvidencePacket** (JSON + photos + audio) stored locally.
5. **PDF placard** with QR code to packet + disclaimer.
6. **Engineer web console** (Next.js static, zero-backend) — table + map.
7. **Web demo** (Flutter Web + E4B WebGPU).
8. **Phase A LoRA** (text-only, attention-layers only) via Unsloth.
9. Demo Kaggle Notebook (Ollama E4B).
10. GitHub repo, README, 3-min YouTube video, 1,500-word writeup, cover image, 4 gallery assets.

### P1 (stretch)
- Phase B vision-conditioned LoRA on IDEA/Φ-Net.
- USGS ShakeMap prefill.
- Multilingual UI (EN + ES + TR).
- Thinking mode toggle.

### Out of scope
- iOS. Cactus parallel build (only if `flutter_gemma` fails). Real backend/auth. Aftershock alerts. Bluetooth printer. ATC-45 (roadmap only). AICore (no custom LoRA).

### NFR
- TTFT < 15s on S23 FE with E2B+image.
- Decoding ≥ 4 tok/s.
- Peak RAM < 5.5 GB.
- APK < 200 MB; model downloaded on first run.

---

## 2. Architecture

### 2.1 Stack
```
Flutter app ─→ flutter_gemma ─→ MediaPipe LLM Inference API ─→ LiteRT-LM ─→ Gemma 4 E2B .task + LoRA flatbuffer
                                      ↑
                             Mali GPU / XNNPACK CPU delegate

Engineer console: Next.js static → reads EvidencePacket JSON client-side → MapLibre GL + table
Web demo: Flutter Web → flutter_gemma → WebGPU → Gemma 4 E4B gemma-4-E4B-it-web.task
```

### 2.2 EvidencePacket schema v1
```jsonc
{
  "schema": "cairn.evidence.v1",
  "packet_id": "uuid-v7",
  "created_at_utc": "2026-05-02T14:23:11Z",
  "app_version": "0.1.0",
  "protocol": "FEMA-P-154-L1",
  "model": {"name": "gemma-4-e2b-it", "quant": "int4", "lora": "cairn-protocol-v1"},
  "location": {"lat": 0, "lng": 0, "accuracy_m": 0, "address_text": ""},
  "building": {"type": "concrete_moment_frame|unreinforced_masonry|wood_light_frame|steel|mixed|unknown",
               "stories_above_grade": 0, "occupancy_hint": "", "year_built_est": null},
  "observations": [{
    "observation_id": "obs-1",
    "prompt_id": "fema_p154_q03_visible_collapse",
    "asked_in": "es",
    "image_refs": ["img-1"], "audio_refs": ["aud-1"], "user_text": null,
    "model_description": "…",
    "model_tags": ["diagonal_crack","column_base"],
    "model_confidence": 0.71,
    "bbox_annotations": [{"image_ref":"img-1","box_2d":[112,34,340,280],"label":"diagonal_shear_crack"}]
  }],
  "hazards_flagged": [{"code":"H01_soft_story","severity":"high","evidence_refs":["obs-2"]}],
  "protocol_answers": {
    "visible_collapse": false, "building_off_foundation": false, "leaning": "slight",
    "ground_failure_adjacent": true, "falling_hazards": true, "adjacent_leaning": false
  },
  "triage": {
    "priority_score": 7, "priority_band": "HIGH",
    "rationale_bullets": ["…","…","…"],
    "uncertainty_notes": ["…"],
    "recommend_engineer_followup": true
  },
  "volunteer": {"attestation":"I am not a licensed engineer. This is preliminary screening only.",
                "signature_hash":"sha256:…","locale":"es-MX"},
  "assets": {"images":[], "audio":[]}
}
```

### 2.3 Deterministic scoring (Dart, not LLM)
The LLM **describes**; a pure Dart function **computes priority** from `protocol_answers` + `hazards_flagged`. Anti-hallucination design. Unit-tested.

```dart
int priorityScore(EvidencePacket p) {
  if (p.protocol_answers.visible_collapse) return 10;
  if (p.protocol_answers.building_off_foundation) return 10;
  if (p.protocol_answers.leaning == "severe") return 9;
  int s = 0;
  for (final h in p.hazards_flagged) {
    s += {"high":3,"moderate":2,"low":1}[h.severity] ?? 0;
  }
  if (p.protocol_answers.ground_failure_adjacent) s += 2;
  if (p.protocol_answers.falling_hazards) s += 2;
  if (p.building.type == "unreinforced_masonry") s += 2;
  if (p.hazards_flagged.any((h) => h.code == "H01_soft_story")) s += 2;
  return s.clamp(1, 10);
}
```

### 2.4 Runtime / file decisions

| Concern | Decision |
|---|---|
| Model format | `.task` (MediaPipe LLM Inference bundle) |
| Source | HF `litert-community/gemma-4-E2B-it-litert-lm` (Android), `gemma-4-E4B-it-web.task` (Web) |
| Download | On-first-run via `FlutterGemma.installModel().fromNetwork(url)` + progress UI |
| LoRA | MediaPipe flatbuffer, attention-layers only (`q_proj,k_proj,v_proj,o_proj`) |
| System prompt | ~2k tokens via `createChat(systemInstruction:…)` |
| Context | 8k per session |
| Audio | Mono WAV 16kHz, ≤30s |
| Image | ≤5 per session (MediaPipe cap 10) |
| Thinking mode | `isThinking: true` for final triage synthesis only |
| Delegate | `preferredBackend: LlmPreferredBackend.gpu` (Mali); XNNPACK CPU fallback |

### 2.5 System prompt (locked)
Short, deterministic, schema-locked. Rules:
1. If image unclear, say so, confidence ≤ 0.5, flag for human.
2. Concrete vocabulary only ("diagonal crack", "concrete spalling", "soft-story condition").
3. Uncertain structural/cosmetic → `uncertain_structural`, confidence ≤ 0.5.
4. STRICT JSON matching schema, no markdown.
5. Rationale in user locale; schema keys in English.
6. User voice observations override model inferences.

---

## 3. Data plan

### 3.1 Datasets

| Dataset | Size | Access | License | Use | Priority |
|---|---|---|---|---|---|
| **IDEA** ([Zenodo 15120522](https://zenodo.org/records/15120522)) | 5,400+ images, Pascal VOC XML | Direct DL | **Verify CC variant D1** | Primary fine-tune + eval | P0 |
| **PEER Φ-Net** | 8 task subsets | Gated form | CC BY-NC-SA 4.0 | Phase B fine-tune | P1 |
| **EERI LFE archive** | Türkiye/Morocco 2023 photos | Public browse | Per-photo verify | Video B-roll + qualitative eval | P0 (video) |
| **Synthetic FEMA P-154 dialogues** | 2,000 | Generated by us | Ours | Phase A LoRA | P0 |
| xBD (satellite) | — | — | — | Cite only, not used | Skip |

### 3.2 Phase A data (P0)
- **2,000 synthetic dialogues**, 6 typologies × 4 damage scenarios × 3 locales.
- D4: 30 hand-authored seeds.
- D5: expand via Gemini 2.5 Pro / Claude 3.7 API to 2,000.
- Hand-verify 200 randomly sampled; re-seed if <90% acceptable.
- 100 held-out eval dialogues.
- Format: Unsloth ShareGPT JSONL.

### 3.3 Phase B data (P1)
- IDEA (5,400) + 500 EERI (hand-captioned) + 1,000 Φ-Net (if form approved).
- ~3,000 image-caption-JSON triples.
- Captions drafted via Gemini Pro Vision, 300 hand-reviewed.
- **Ship gate:** Phase B must beat Phase A by ≥10pt damage-type top-3 OR ≥5pt severity MAE on held-out.

### 3.4 Eval harness
```
scripts/eval/
  eval_baseline.py    # zero-shot E2B (device) + E4B (Ollama Mac)
  eval_tuned.py       # with Phase A or Phase B LoRA
  metrics.py          # damage-presence F1, severity Spearman, damage-type top-1/3, tag-Jaccard
  report.md           # auto comparison table
```

---

## 4. Fine-tuning

### 4.1 Phase A (P0) — Text-only LoRA on E2B + E4B
- Framework: **Unsloth FastLanguageModel** in Colab Pro.
- Base: `unsloth/gemma-4-E2B-it`, `unsloth/gemma-4-E4B-it`.
- **LoRA config** (MediaPipe-compatible):
  - `r=16, alpha=32, dropout=0.05`
  - `target_modules=["q_proj","k_proj","v_proj","o_proj"]` **only**
  - `finetune_vision_layers=False, finetune_mlp_modules=False`
- 3 epochs, batch 2 (E4B) / 4 (E2B), grad accum 4, lr 2e-4 cosine, max_seq 4096.
- Est. 3–5h A100 for E4B; 1–2h for E2B.
- **Export:** save adapters → `mediapipe.tasks.python.genai.converter.convert_checkpoint(backend='gpu', lora_ckpt=…, lora_rank=16, lora_output_tflite_file=…)` → load in app via `LlmInference.LlmInferenceOptions.setLoraPath()`.
- **Verify** parity between Colab inference and on-device inference on 20 examples before shipping.

### 4.2 Phase B (P1) — Vision-conditioned LoRA on E4B
- Same config, `FastVisionModel`, images included.
- Vision tower frozen (per MediaPipe constraint); only language-side attention adapts.
- 8–12h A100. Ship only if §3.3 gate passes.

### 4.3 Honest framing (for writeup)
- Not training a damage CNN.
- Not improving vision encoder.
- Shaping LM output toward FEMA P-154 vocabulary, confidence calibration, EvidencePacket schema.

---

## 5. User flow (9 screens)

1. **Start** — "Start building screening" big button; recent reports list. Auto GPS + permissions.
2. **Location** — auto-filled address (offline tile cache), correctable; building typology chips.
3. **Walk around** — 4 required photos with visual reference cards (front, ground floor, cracks, foundation). Optional 5th. After each capture, one-liner from model for instant feedback.
4. **Describe** — single mic button, 30s mono 16kHz WAV. Transcribe + summarize in user locale.
5. **Quick questions** — FEMA P-154 L1 simplified (collapse, leaning, off-foundation, ground failure, falling hazards, adjacent leaning). Voice + tap.
6. **Humility check** — model re-queries its lowest-confidence observations. *"I wasn't sure about the column at the front-left. Describe its base."* ← **the differentiator beat**.
7. **Synthesizing** — thinking mode rolls bullets ("Applying soft-story weighting…"). <10s on E2B.
8. **Report** — priority 1–10 badge, 3 rationale bullets, 1–2 uncertainty notes, photos w/ bboxes. Buttons: **Generate PDF** / **Share packet** / **Start another**.
9. **PDF placard** — A6/A5 printable, priority color bar, QR to packet, GPS, timestamp, disclaimer.

**Timing target:** user 3–4 min + model 30–60s + PDF 15s.

---

## 6. Engineer web console

- Next.js static export → Vercel.
- Client-only: drop `.cairn.json` files OR paste URL.
- **Table view**: priority-sorted, filterable by typology/score/date.
- **Map view**: MapLibre GL + OSM, color-coded markers, side panel with photos + packet.
- **CSV export** of queue for field use.
- Offline-capable after first load.

---

## 7. Testing plan (user explicitly asked)

### 7.1 Week-1 spikes (each has go/no-go)

| # | Spike | Days | Pass criteria | Plan B on fail |
|---|---|---|---|---|
| **S1** | **Device feasibility** — Install Google AI Edge Gallery APK on S23 FE, load E2B + E4B, measure TTFT/tok-s/RAM via `adb dumpsys meminfo`, test image + audio prompts with IDEA photo | D1–D2 | E2B vision TTFT<15s, decode>4 tok/s, peak RAM<5.5GB, no OOM | Drop audio modality; text+photo only; Whisper-tiny via `whisper_ggml_flutter` |
| **S2** | **flutter_gemma stability** — Minimal Flutter scaffold, load E2B, 10 consecutive vision prompts, dummy LoRA load, reboot test | D2–D3 | No SIGSEGV/reboot; load<25s; LoRA loads | Kotlin MethodChannel → MediaPipe LLM Inf API direct (+3-4 days) |
| **S3** | **Vision quality** — Zero-shot E2B (device) + E4B (Ollama M4) on 200 IDEA held-out, 3 prompt strategies | D3–D4 | E2B damage-presence F1≥0.7, damage-type top-3≥0.5; E4B F1≥0.8, top-3≥0.6 | Reframe as "AI-guided checklist + evidence package" (writeup variant pre-written) |
| **S4** | **Audio multilingual** — 20 clips (10 EN, 5 ES, 5 TR) with technical vocab → E2B + E4B | D3 | ≥16/20 correctly identify stated damage | On-device ASR → text pipe; drop "native audio" claim in video |
| **S5** | **LoRA round-trip** — Tiny 5-min LoRA on 50 dialogues; MediaPipe convert; Flutter harness test | D5–D6 | Measurable behavior diff from base | Ship unmodified base; LoRA in Colab demo only (lose Unsloth prize angle) |

### 7.2 Weekly E2E tests
- **W2 end (D14):** full airplane-mode run, video it, log every defect.
- **W3 end (D21):** + PDF + share + console round-trip (10 packets).
- **W4 end (D28):** 2 language locales, verify all strings translated.

### 7.3 Regression & unit tests
- `priorityScore` Dart: 30 hand-crafted packets → expected scores.
- EvidencePacket schema validator (Dart): every field, types, enums.
- MediaPipe session lifecycle (integration test): create → image → run → dispose × 50, no native leak.
- Web console parser: 15 real + 5 corrupt packets → never crash.

### 7.4 Usability test (D21)
One non-dev friend, their language, full flow, no coaching. Note every confusion. Fix top 3 before video.

### 7.5 Not tested
- Real volunteers in real disasters (ethical impossibility).
- Accuracy claims vs real ATC-20 placards (our output is not a placard).

---

## 8. 31-day timeline

Start D0 = Apr 17. Submit D30 = May 17. Buffer D31 = May 18.

### Week 1 (D1–D7) — De-risk

| D | Deliverable | Gate |
|---|---|---|
| D1 | **S1 device spike**. Verify `cairn.app`. IDEA download + license check. Φ-Net form. Read FEMA P-154. Read competition rules. | E2B usable? |
| D2 | **S2 flutter_gemma spike**. E2B text prompt on phone. | Stable? |
| D3 | **S3 vision + S4 audio spikes**. | **GO/NO-GO on autonomous description framing** |
| D4 | Lock system prompt + EvidencePacket schema v1. 30 seed dialogues. Verify Gemma 4 bbox format. | Schema locked |
| D5 | Synthetic dialogue pipeline (Gemini API). 500 dialogues + 100 hand-review. **S5 LoRA round-trip spike**. | LoRA works? |
| D6 | Outreach: Mosalam (PEER), Dyke (Purdue), EERI coord, CalOES SAP, Türkiye NGO. Kaggle discussion recon. | |
| D7 | W1 decision doc. Start Phase A E4B LoRA overnight on Colab Pro. | Everything green → proceed |

### Week 2 (D8–D14) — Core app
| D | Deliverable |
|---|---|
| D8 | Flutter scaffold (Riverpod). Screens 1–2. Encrypted local vault. |
| D9 | Screen 3 (photo capture). `flutter_gemma` session lifecycle. First E2E: photo → E2B → text. |
| D10 | Screen 4 (voice mono 16kHz WAV). E2B audio + ASR fallback. |
| D11 | Screen 5 (questionnaire). State machine per FEMA P-154. |
| D12 | Screen 6 (humility check) — re-query low-confidence observations. |
| D13 | Screen 7–8 (thinking mode synthesis + report). `priorityScore` + unit tests. |
| D14 | **E2E airplane-mode test. Record raw video. Log defects.** |

### Week 3 (D15–D21) — Polish + fine-tune + console
| D | Deliverable |
|---|---|
| D15 | PDF placard (`printing` + `qr_flutter`). |
| D16 | Screen 9 + share flow. |
| D17 | Phase A LoRA done → MediaPipe flatbuffer → load in app → eval on held-out 100. |
| D18 | Console scaffold + table + JSON upload. |
| D19 | Console map (MapLibre) + detail panel. Deploy Vercel. |
| D20 | Multilingual UI (EN+ES+TR). USGS ShakeMap prefill (P1). |
| D21 | **Usability test with 1 friend.** Fix top 3. Start Phase B vision LoRA overnight. |

### Week 4 (D22–D28) — Video + writeup + web demo
| D | Deliverable |
|---|---|
| D22 | Phase B eval → ship-or-skip. Web demo (Flutter Web) on HF Spaces. |
| D23 | Video storyboard + shot list. Location scouting. |
| D24 | **Video shoot day.** Self + 1 collaborator. Hero scenes + `scrcpy` screen rec. Backup SD. |
| D25 | Video edit v1 → trim to 2:45. Kevin MacLeod or Artlist music. |
| D26 | Writeup draft 1,500w. Cover image + 4 gallery assets. |
| D27 | Video v2 w/ captions, color, audio ducking. Show 2 non-tech friends, cut what confuses. |
| D28 | Writeup revision. README polish. Kaggle demo Notebook (Ollama E4B). |

### Week 5 (D29–D31) — Submit
| D | Deliverable |
|---|---|
| D29 | HF Hub uploads (LoRA, dataset card, synthetic data). Signed APK in Releases. |
| D30 | **Submit Kaggle.** Verify every link. YouTube unlisted public. |
| D31 | Buffer. Fix whatever broke. |

### Slip-kill order (if behind)
1. Phase B vision LoRA  
2. TR locale + USGS ShakeMap  
3. Web demo (Android is enough)  
4. Console map (table only)  
5. 1-collaborator shot (go solo voiceover)

**Defend:** Phase A LoRA, PDF placard, offline demo, writeup, video.

---

## 9. Submission artifacts checklist

- [ ] GitHub repo, Apache 2.0, `CITATION.cff`
- [ ] `README.md`: problem, 30s demo GIF, install, run, fine-tune, FEMA attribution, disclaimer, datasets, model card
- [ ] Signed APK in GitHub Releases (<200 MB)
- [ ] HF Hub: `cairn-protocol-v1` LoRA card
- [ ] HF Hub: synthetic dialogue dataset card (license-compatible)
- [ ] Kaggle writeup ≤1,500 w
- [ ] YouTube unlisted ≤3:00 w/ burned-in captions
- [ ] Kaggle Notebook (Ollama E4B reproduction)
- [ ] Web demo URL (HF Spaces or Vercel)
- [ ] Engineer console URL (Vercel)
- [ ] Cover image 1280×640
- [ ] 4 media gallery assets (hero, bbox screen, PDF, console map)
- [ ] `LEGAL.md`: protocol framing, liability, licenses

---

## 10. Risk register

| ID | Risk | P | I | Mitigation | Kill→Plan B |
|---|---|---|---|---|---|
| R1 | E2B can't do real-time multimodal on S23 FE | M | H | S1 | TTFT>15s or OOM → drop audio, text+photo only |
| R2 | `flutter_gemma` crashes with Gemma 4 | M | H | S2 | SIGSEGV → Kotlin MethodChannel + MediaPipe direct |
| R3 | Vision poor on damage photos | M-H | H | S3 | F1<0.7 → reframe "AI-guided checklist + evidence packet" |
| R4 | Audio multilingual poor | M | M | S4 | <80%/20 → Whisper-tiny ASR → text |
| R5 | MediaPipe LoRA conversion fails | L-M | M | S5 | Ship base in app; LoRA in Colab only |
| R6 | IDEA license forbids redistribution | L | L | D1 verify | Don't republish; fine-tune only; release only our synthetic data |
| R7 | Competitor submits same idea | L-M | M | D6 + weekly recon | Lean on differentiators (humility check, FEMA framing, console) |
| R8 | 31 days insufficient | M | H | Slip-kill order | Cut P1s, defend P0s |
| R9 | Judge legal concern | L | H | FEMA P-154 framing + `LEGAL.md` + in-app copy | Pre-empt in writeup |
| R10 | Amateur video | M | H | Storyboard D23 + 2 feedback passes | Fall back to voiceover+archival+screen-only |

---

## 11. Open assumptions (W1 resolves each)

1. E2B multimodal RAM profile on S23 FE Exynos 8GB — S1.
2. `cairn.app` domain — D1.
3. IDEA exact CC license variant — D1 Zenodo page.
4. Gemma 4 bbox format `[y1,x1,y2,x2]` in MediaPipe path — D4 test prompt.
5. MediaPipe LoRA conversion for Unsloth Gemma 4 E2B — S5.
6. `flutter_gemma` LoRA path API for Gemma 4 E2B + `.task` — D9.
7. Kaggle rules on web demos — D1.
8. EERI per-photo B-roll licensing — D22 verified one-by-one.

---

## 12. First actions on "go"

Scaffold:
- `/Users/Hetansh/Github/kaggle_gemma/apps/cairn_mobile/` (Flutter)
- `/Users/Hetansh/Github/kaggle_gemma/apps/cairn_console/` (Next.js)
- `/Users/Hetansh/Github/kaggle_gemma/finetune/` (Unsloth Python)
- `/Users/Hetansh/Github/kaggle_gemma/data/` (gitignored for licensed data)
- `/Users/Hetansh/Github/kaggle_gemma/scripts/eval/` (eval harness)
- `/Users/Hetansh/Github/kaggle_gemma/docs/prompts/` (system prompt, schema)
- `/Users/Hetansh/Github/kaggle_gemma/.github/workflows/` (APK CI)

Then immediately execute Spike 1 (device feasibility) and Spike 2 (`flutter_gemma` scaffold) in parallel on D1–D2.

---

## Key source links

- Gemma 4 model card: https://ai.google.dev/gemma/docs/core/model_card_4
- LiteRT-LM E4B on HF: https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm
- LiteRT-LM E2B on HF: https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm
- `flutter_gemma`: https://pub.dev/packages/flutter_gemma
- MediaPipe Android LLM Inference (vision + audio + LoRA): https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference/android
- Unsloth Gemma 4 fine-tune: https://unsloth.ai/docs/models/gemma-4/train
- FEMA P-154 3rd ed.: https://www.fema.gov/sites/default/files/2020-07/fema_earthquakes_rapid-visual-screening-of-buildings-for-potential-seismic-hazards-a-handbook-third-edition-fema-p-154.pdf
- IDEA dataset (Zenodo): https://zenodo.org/records/15120522
- PEER Φ-Net: https://apps.peer.berkeley.edu/phi-net/
- EERI LFE archive: https://learningfromearthquakes.org/archive/
- Cactus open Gemma 4 bug (evidence for avoiding Cactus): https://github.com/cactus-compute/cactus/issues/584
