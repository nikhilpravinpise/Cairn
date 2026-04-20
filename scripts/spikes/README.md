# Week-1 spike harnesses

Run order and pass criteria come from `cairn-implementation-plan-0b751e.md` §7.1,
**as pivoted by `docs/week1_pivot.md`** (web-first, no Android hardware in Week 1).

| # | Spike                   | Days  | Entrypoint (web)                                    | Pass criteria (web-pivoted) |
|---|-------------------------|-------|-----------------------------------------------------|-----------------------------|
| S1| Web feasibility         | D1–D2 | `s1_web_feasibility.md` + `apps/cairn_mobile/`      | E4B TTFT<20s, decode>4 tok/s, warm reload<10s |
| S2| `flutter_gemma` stability | D2–D3 | same page as S1 + `apps/cairn_mobile/docs/s2_checklist.md` | No tab crash on 10 vision prompts |
| S3| Vision quality          | D3–D4 | `scripts/eval/eval_baseline.py`                     | E2B F1≥0.7 top3≥0.5; E4B F1≥0.8 top3≥0.6 |
| S4| Audio multilingual      | D3    | `s4_audio_multilingual.py`                          | ≥16/20 clips correctly identify damage |
| S5| LoRA round-trip (Colab) | D5–D6 | `s5_lora_round_trip.md`                             | Measurable behavior diff from base on 20 held-out (Colab notebook) |

**Deferred until Android device arrives** (Week 2+):
- `s1_device_feasibility.md` + `s1_adb_harness.py` (adb-based RAM/CPU probe).
- LoRA on-device load (MediaPipe Web can't `setLoraPath`).

Outputs of every spike are written as JSON/MD under `scripts/spikes/out/` (gitignored).
A go/no-go row in `docs/week1_decision.md` must be filled in before the end of D7.
