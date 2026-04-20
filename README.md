# Cairn

Offline Flutter post-earthquake building triage app powered by Gemma E4B on Web (Week-1 primary)
and Gemma E2B on Android (Week-2+), following **FEMA P-154 Rapid Visual Screening (Level 1,
Sidewalk Survey)**. Outputs a structured `EvidencePacket` (JSON + photos + audio) and a PDF
placard. A static Next.js console lets engineers triage reports.

> Preliminary screening tool only. Not an ATC-20 placard. Not a structural-engineering
> determination. See `docs/LEGAL.md`.

---

## Repository layout

```
apps/
  cairn_mobile/        # Flutter Android + Web (WebGPU) app
  cairn_console/       # Next.js static engineer console (queue + map)
finetune/              # Unsloth Phase A / Phase B LoRA scripts
scripts/
  spikes/              # Week-1 de-risk spike harnesses (S1..S5)
  eval/                # metrics, baseline + tuned evaluation
  data/                # synthetic dialogue pipeline, dataset prep
  finetune/            # MediaPipe LoRA conversion + round-trip
docs/
  prompts/             # system prompt v1 (locked)
  schema/              # EvidencePacket JSON Schema v1
  LEGAL.md             # protocol framing, liability, licenses
data/                  # gitignored — licensed datasets live here
  seeds/               # 30 hand-authored seed dialogues (ShareGPT JSONL)
.github/workflows/     # APK CI
```

## Week-1 status

The repo is currently at the **Week-1 de-risk** stage of the plan
(`cairn-implementation-plan-0b751e.md`), **pivoted to web-first** because no
Android device is on hand yet — see `docs/week1_pivot.md`.

- `docs/prompts/system_prompt_v1.md` — locked system prompt
- `docs/schema/evidence_packet_v1.schema.json` — locked schema
- `data/seeds/dialogues.seed.jsonl` — 30 hand-authored seed dialogues
- `scripts/spikes/` — S1..S5 spike harnesses (S1 = web feasibility; adb track deferred)
- `scripts/eval/` — baseline vision + audio eval harness
- `scripts/data/generate_dialogues.py` — synthetic dialogue pipeline
- `docs/week1_decision.md` — W1 decision-doc template
- `QUICKSTART.md` — setup + run instructions

## Prizes targeted

Global Resilience + LiteRT + Unsloth.

## License

Apache-2.0 (see `LICENSE`). Datasets retain their upstream licenses (see `docs/LEGAL.md`).
