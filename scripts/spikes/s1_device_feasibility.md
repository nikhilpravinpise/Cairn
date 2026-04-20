# S1 — Device feasibility (D1–D2)

Verify Gemma E2B can actually run multimodal on the target device.

## Target device
Samsung S23 FE / A55 Exynos, 8 GB RAM, Android 14.

## Prereqs (on the laptop)
```bash
brew install android-platform-tools            # for adb
pipx install scrcpy                            # optional, for screen rec
# or: brew install --cask android-platform-tools scrcpy
```

## Prereqs (on the phone)
1. Enable Developer Options + USB debugging.
2. Install **Google AI Edge Gallery** APK (sideload) — that ships Gemma E2B/E4B with
   MediaPipe LLM Inf and gives us a trusted baseline before `flutter_gemma`.
3. Plug in USB and accept the RSA fingerprint.

## Measurements
Run the harness while the AI Edge Gallery is doing inference on a canonical IDEA
test image (see `scripts/spikes/assets/s1_probe.jpg` — placed there by hand from
the IDEA dataset):

```bash
python scripts/spikes/s1_adb_harness.py \
    --device <serial> \
    --pkg  com.google.ai.edge.gallery \
    --out  scripts/spikes/out/s1_$(date -u +%Y%m%dT%H%M%SZ).json \
    --duration 120
```

The harness samples `adb shell dumpsys meminfo <pkg>` and `adb shell top -n 1 -p
<pid>` at 1 Hz for the duration window. You start one vision prompt per minute
in AI Edge Gallery and label the start/end in the harness CLI (`Enter` to mark).

## Pass criteria (plan §7.1 S1)
- E2B vision **TTFT < 15 s**
- E2B vision **decode ≥ 4 tok/s**
- E2B vision **peak RSS < 5.5 GB**
- No OOM / no reboot across 10 consecutive vision prompts

## Plan B on fail
Drop audio modality, text+photo only. Swap live audio for Whisper-tiny
(`whisper_ggml_flutter`) → text pipe.

## Deliverable
- `scripts/spikes/out/s1_*.json` — raw samples + labeled prompt windows.
- A row filled in `docs/week1_decision.md`.
