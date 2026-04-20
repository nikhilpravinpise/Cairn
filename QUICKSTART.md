# Cairn — Quickstart (Week-1 state)

## 1. Python (`scripts/`) — shared for spikes, eval, data, fine-tune

```bash
cd scripts
python3 -m venv .venv && . .venv/bin/activate
pip install -e .                 # core deps
# optional extras, per-workflow:
pip install -e '.[ollama]'       # S3/S4 Ollama E4B runner
pip install -e '.[gemini]'       # D5 synthetic dialogue expansion
pip install -e '.[audio]'        # S4
pip install -e '.[finetune]'     # S5 / Phase A (Linux/CUDA only)

# tests
PYTHONPATH=. pytest -q

# validate the 30 hand-authored seeds
PYTHONPATH=. python -m data.validate_seeds
```

## 2. Flutter (`apps/cairn_mobile/`) — S2 `flutter_gemma` spike (web-first)

Week-1 target is **web**. Android is restored when hardware arrives — see
`docs/week1_pivot.md`.

```bash
cd apps/cairn_mobile
flutter config --enable-web
flutter create --platforms=web --project-name cairn_mobile .
./tool/sync_assets.sh           # copies docs/prompts/system_prompt_v1.txt into assets/
flutter pub get
flutter analyze
# Launch in Chrome with WebGPU enabled
flutter run -d chrome \
    --web-browser-flag=--enable-unsafe-webgpu \
    --web-browser-flag=--enable-features=Vulkan
```

Drop a test image at `assets/images/s2_probe.jpg` (IDEA-dataset photo).

The spike UI exposes **[model dropdown] / Load / Run 10 prompts / Unload** and
shows the report JSON inline with **Copy** + **Download** buttons. Save the
downloaded file under `scripts/spikes/out/`.

## 3. Week-1 spike quick-refs

Pivot: `docs/week1_pivot.md`. S1 is **web** in Week 1; adb-based S1 stays
in-tree for when Android hardware arrives.

| # | Entrypoint | Doc (Week-1 web) | Doc (Android, later) |
|---|------------|------------------|----------------------|
| S1 | `apps/cairn_mobile/` (Chrome) | `scripts/spikes/s1_web_feasibility.md` | `scripts/spikes/s1_device_feasibility.md` + `s1_adb_harness.py` |
| S2 | `apps/cairn_mobile/` | same page as S1; see `docs/s2_checklist.md` for the 10-prompt protocol | — |
| S3 | `scripts/eval/eval_baseline.py` | `scripts/eval/README.md` | — |
| S3 bbox | `scripts/spikes/s3_bbox_probe.py` | inline docstring | — |
| S4 | `scripts/spikes/s4_audio_multilingual.py` | inline docstring | — |
| S5 | `finetune/phase_a_text_lora.py` + `finetune/convert_mediapipe_lora.py` | `scripts/spikes/s5_lora_round_trip.md` (Colab-only in Week 1) | Device-load in Week 2 |

## 4. Locked artifacts (D4)

Do not edit without bumping schema version:

- `docs/prompts/system_prompt_v1.txt`
- `docs/schema/evidence_packet_v1.schema.json`
- `data/seeds/dialogues.seed.jsonl`

The `scripts/cairn/` package and `apps/cairn_mobile/lib/core/` both load these
as the single source of truth; CI (`.github/workflows/ci.yml`) enforces
cross-language parity (`test_constants_parity.py`).

## 5. Week-1 decision doc

Fill in `docs/week1_decision.md` by end of D7 (Apr 24). The doc's PASS/FAIL
rows come from the spike output artifacts above.
