# Week 1 Decision Doc (fill in by end of D7 = Apr 24)

Plan: `cairn-implementation-plan-0b751e.md` §7.1 + §12
**as pivoted by `docs/week1_pivot.md` — Week 1 is web-first (no Android hardware).**

## Scoreboard (web-pivoted)

| # | Spike | Pass criteria (Week-1 / web) | Measured | Verdict | Plan-B taken? |
|---|-------|-------------------------------|----------|---------|---------------|
| S1 | Web feasibility (E4B in Chrome WebGPU) | warm reload<10s, TTFT<20s, decode>4 tok/s, no tab crash on 10 prompts | **TBD** | ☐ PASS ☐ FAIL | ☐ fallback to Ollama E4B for live demo; ☐ switch to E2B |
| S2 | `flutter_gemma` web stability | no tab crash on 10 prompts; `loraPath:` no-op cleanly on web | **TBD** | ☐ PASS ☐ FAIL | ☐ rewrite on raw MediaPipe JS (+2–3 days) |
| S3 | Vision quality | E2B F1≥0.7 top3≥0.5; E4B F1≥0.8 top3≥0.6 on 200 IDEA held-out | **TBD** | ☐ PASS ☐ FAIL | ☐ reframe as "AI-guided checklist + evidence packet" |
| S4 | Audio multilingual | ≥16/20 clips correctly identify stated damage | **TBD** | ☐ PASS ☐ FAIL | ☐ on-device ASR → text pipe (Whisper-tiny) |
| S5 | LoRA round-trip (Colab) | measurable behavior diff vs base on 20-prompt holdout in Colab | **TBD** | ☐ PASS ☐ FAIL | ☐ LoRA as recipe only (no device load in Week 1) |

### Deferred to Android week (not gating Week-1 decision)
- On-device RAM probe (S1 original adb criteria: TTFT<15s, decode>4 tok/s, RSS<5.5GB).
- LoRA on-device load via `flutter_gemma`'s `loraPath:` (MediaPipe Web doesn't support it today).

## Assumptions resolved (plan §11)
| # | assumption | resolution |
|---|------------|------------|
| 1 | E2B multimodal RAM on S23 FE Exynos 8 GB | TBD (S1) |
| 2 | `cairn.app` domain available | TBD (Namecheap lookup D1) |
| 3 | IDEA exact CC license variant | TBD (Zenodo page D1) |
| 4 | Gemma bbox format on MediaPipe path | TBD (`scripts/spikes/s3_bbox_probe.py` D4) |
| 5 | MediaPipe LoRA conversion for Unsloth Gemma | TBD (S5 D5–D6) |
| 6 | `flutter_gemma` LoRA path API for E2B `.task` | TBD (D9; verify `loraPath:` round-trips) |
| 7 | Kaggle rules on web demos | TBD (Kaggle competition page D1) |
| 8 | EERI photo licensing | TBD (per-photo D22) |

## Go / No-Go decision

**Go criteria:** S1, S2, S3, S5 PASS. S4 can fall back to ASR without killing
the video narrative.

**Partial-Go criteria:** any single spike FAILed but Plan B listed above is
feasible within slip-kill budget (plan §8 "slip-kill order"). Document here
which Plan B we're committing to.

**No-Go triggers:**
- S1 FAIL with **no** Plan B path (e.g. device can't run even text + image).
- S2 FAIL **and** Kotlin MethodChannel fallback estimated > 7 days.
- S3 FAIL below F1 0.5 AND checklist reframe deemed unviable by the team.

## Decision (fill in D7)

> _signed_ ______  _date_ ______

Decision:  ☐ GO  ☐ PARTIAL-GO  ☐ NO-GO
If PARTIAL-GO, which Plan Bs are taken: ______________________
Risks accepted:  _____________________________________________
Start Phase A LoRA overnight D7?  ☐ YES  ☐ NO  (reason: __________)
