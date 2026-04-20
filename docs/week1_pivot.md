# Week-1 Pivot — Web-first

_Status: decided Apr 20, 2026 after discovering the target device (Samsung S23 FE) is unavailable and only an iPhone 14 is on hand._

The implementation plan (`cairn-implementation-plan-0b751e.md`) is **not rewritten**.
Every decision below is an explicit delta against that doc.

## TL;DR
- Primary Week-1 target: **`flutter_gemma` Web (WebGPU)** running Gemma **E4B** on the developer's Mac via Chrome/Edge.
- Android (S23 FE / Pixel) path remains in the plan; deferred until hardware arrives.
- iPhone 14 via `flutter_gemma` iOS is **not** a Week-1 target (kept as a fallback recording device in Week 3).

## Why

| factor                        | Web-first                         | iPhone-first                              |
|------------------------------|-----------------------------------|-------------------------------------------|
| hardware available today     | ✅ Mac + any judge's laptop       | ✅ iPhone 14 only                         |
| distribution for Kaggle demo | 1 URL                             | TestFlight ($99) or 7-day dev profile     |
| CI testability               | `flutter build web` in GH Actions | requires macOS runner + Xcode             |
| model size budget            | ~E4B (3 GB) fits in browser OPFS  | E2B (1.5 GB), E4B tight on 6 GB RAM       |
| engineering risk             | well-documented MediaPipe path    | less-documented `flutter_gemma` iOS path  |

Android on S23 FE when it arrives: still the best "disaster responder in the field" story, but not Week-1 blocking.

## Deltas vs the locked plan

### S1 — device feasibility (plan §7.1 S1) → **web feasibility**
- Replaces `scripts/spikes/s1_device_feasibility.md` with `scripts/spikes/s1_web_feasibility.md`.
- New pass criteria (M-series Mac, WebGPU Chrome):
  - E4B first-load (download + compile) < 4 min on Wi-Fi
  - Warm reload (cached in OPFS) < 10 s
  - Image TTFT **< 20 s** (relaxed from 15 s — web adds MediaPipe WebGPU init)
  - Decode **> 4 tok/s** on a 2023+ integrated GPU
  - No tab crash across 10 consecutive vision prompts
- Measurement tools: Chrome DevTools **Performance** + **Memory** tabs; the spike page itself records `ttftMs` + `wallclockMs` per run.

### S2 — `flutter_gemma` stability (plan §7.1 S2)
- Same spike page, now target `chrome` / `edge` device instead of `android`.
- LoRA attach-on-web is unsupported by MediaPipe Web today — S2's LoRA step is **deferred** to Android Week 2. S5 still happens (LoRA training + conversion), we just don't prove device-load until the Pixel arrives.

### S3 — vision eval (plan §7.1 S3)
- **Unchanged.** Runs server-side via Ollama on the Mac. Both E4B Ollama and E4B Web are compared in `scripts/eval/reports/` (two rows in the same table).

### S4 — audio multilingual (plan §7.1 S4)
- **Unchanged.** ASR-through-text mode against Ollama E4B.

### S5 — LoRA round-trip (plan §7.1 S5)
- Training + MediaPipe conversion still runs in Colab.
- **On-device load** portion is parked until Pixel arrives. We keep a Colab notebook that runs base-vs-LoRA on the same 20-prompt holdout so we can claim "measurable behavior delta" without a phone.

### §5.2 app architecture
- `apps/cairn_mobile/` stays — Flutter builds from the same source to `web` AND `android`. We just don't build for android in CI yet.
- Camera/mic/GPS Flutter plugins will still work on web via the browser APIs when we enable them in Week 2; we gain nothing mobile-specific that we lose on web.
- Offline story for web: OPFS model cache + service worker for app shell.

### §5.3 Next.js console
- **Unchanged.** Same plan.

## What this buys us
1. A **working one-URL demo** by end of Week 1 (deployed to Cloudflare Pages / Netlify).
2. Faster iteration — no USB cable, no phone reflash, `flutter run -d chrome` hot-reloads.
3. Broader judge reach — any reviewer with a WebGPU browser can try the app.
4. Android isn't lost; it comes back in Week 2 when the phone arrives, using the identical Dart codebase.

## What this costs us
1. **Narrative**: "volunteer in the field offline on their own phone" becomes "volunteer in the field offline on any browser-enabled device (laptop now, phone when Android ships)". Still defensible but slightly weaker.
2. **Power/thermals**: we don't get real mobile-SoC numbers in Week 1; those must be collected in Week 2.
3. **S2 LoRA device-load** is unverified until Pixel arrives. Plan B if LoRA-on-mobile turns out to be broken: ship LoRA in the Colab notebook as "the recipe", base model on device.

## Go/no-go gates (pivoted)

| # | Spike | Pass criteria (web-pivoted)                            | Deferred-to-Android |
|---|-------|---------------------------------------------------------|---------------------|
| S1| web feasibility     | warm reload < 10 s; TTFT < 20 s; decode > 4 tok/s; 10/10 prompts OK | on-device RAM cap |
| S2| `flutter_gemma` web | no tab crash on 10 prompts; `loraPath:` no-ops cleanly on web | LoRA device-load |
| S3| vision quality      | unchanged | — |
| S4| audio multilingual  | unchanged | — |
| S5| LoRA round-trip     | base-vs-LoRA delta on 20 holdout in **Colab** | Device-load behavior delta |
