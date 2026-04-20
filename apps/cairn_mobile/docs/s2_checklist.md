# S2 — `flutter_gemma` stability checklist (D2–D3)

Goal: prove `flutter_gemma` can load Gemma E2B with vision + LoRA on the target
S23 FE / A55 without crashing, and measure load/inference timing.

## Protocol
1. Fresh install (`adb uninstall app.cairn.cairn_mobile && flutter run`).
2. First-run model download completes < 3 min on Wi-Fi.
3. Warm start: kill app, relaunch. Model load **< 25 s**.
4. Press **Run 10 prompts**. Each prompt = bundled IDEA image + the
   `describe_photo` user turn. Expected: 10/10 parse as JSON with no
   SIGSEGV, no OOM, no ANR.
5. Press **Toggle LoRA** to attach `e2b_lora.fb` (dummy flatbuffer from S5).
   Re-run 5 prompts. Behavior delta ≠ 0 confirms LoRA loaded.
6. Press **Reboot & resume**. App should kill the engine, recreate it from
   cold, and succeed on the 11th prompt.

## Exit artifact
`/sdcard/Android/data/app.cairn.cairn_mobile/files/s2_report.json`

Pull with:
```bash
adb pull /sdcard/Android/data/app.cairn.cairn_mobile/files/s2_report.json \
    scripts/spikes/out/s2_$(date -u +%Y%m%dT%H%M%SZ).json
```

## Fail → Plan B
SIGSEGV or reboot → abandon `flutter_gemma`, build Kotlin `MethodChannel` against
MediaPipe LLM Inf API directly. Budget +3–4 days — tracked in `docs/week1_decision.md`.
