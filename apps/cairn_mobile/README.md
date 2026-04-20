# `cairn_mobile` — Flutter app (Week-1 S2 scaffold)

Directory name is historical — **Week 1 targets web** (see
`docs/week1_pivot.md`). Android/iOS targets are enabled when hardware arrives.

This is a **`flutter_gemma` stability spike** scaffold, not the real Cairn app.
The real app ships in Week 2–3 (see `cairn-implementation-plan-0b751e.md` §5).

## What this app does today
- Loads Gemma **E4B** (or E2B) via `flutter_gemma` with vision.
- Runs **10 consecutive vision prompts** on a bundled test image.
- Logs TTFT, wallclock, JSON-parse success per run.
- Shows the report JSON on-page with **Copy** + **Download** buttons.

## Pass criteria (web-pivoted — see `docs/week1_pivot.md`)
- No tab crash during the 10-prompt run.
- Cached reload (warm) < 10 s on M-series Mac.
- Image TTFT < 20 s on first prompt, decode > 4 tok/s.

## Setup
```bash
cd apps/cairn_mobile
flutter config --enable-web
# Generate platform folders (web, later android/ios):
flutter create --platforms=web --project-name cairn_mobile .
./tool/sync_assets.sh               # copy the locked system prompt into assets
flutter pub get
flutter run -d chrome --web-browser-flag=--enable-unsafe-webgpu
```

Put an IDEA-dataset photo at `assets/images/s2_probe.jpg` by hand before running.

## Model hosting
The first click of **Load** downloads the `.task` file from the HuggingFace
repo defined in `lib/core/llm/model_registry.dart`. MediaPipe caches it to OPFS
automatically; subsequent loads come from cache. If the HuggingFace slug is
stale, the download fails loud — update `model_registry.dart` + the Python
mirror at `scripts/cairn/constants.py` together (CI enforces parity).

If HuggingFace doesn't serve CORS headers for the direct file, mirror the
model to Cloudflare R2 / our own bucket and point `hfRepo`/`taskFilename` at
the mirror.

## What this spike does NOT include
- Camera, mic, GPS, maps, PDF, screens 1–9 — all Week 2+.
- LoRA on-device load — MediaPipe Web doesn't support `setLoraPath`. Deferred
  to the Android build when the Pixel/S23 FE arrives. S5 still validates the
  LoRA in Colab.
- Real UI polish.

See `scripts/spikes/s1_web_feasibility.md` for the full measurement protocol.
