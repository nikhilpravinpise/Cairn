# S1 (web pivot) — WebGPU feasibility (replaces adb-based device feasibility)

_See `docs/week1_pivot.md` for context. This doc replaces `s1_device_feasibility.md`
for Week 1. The original adb harness and its checklist stay in-tree for when
the Android device arrives._

## Goal
Prove Gemma **E4B** runs in a developer's browser through `flutter_gemma`
WebGPU at usable latency, and that the 10-prompt burst doesn't crash the tab.

## Target environment
- Hardware: Mac (M-series) or any laptop with WebGPU support.
- Browser: Chrome stable ≥ 121 **or** Edge ≥ 121.
- Backends: WebGPU preferred; if unavailable, MediaPipe falls back to WASM+SIMD
  (massively slower — treat as FAIL).

### Chrome setup (one-time)
```bash
# macOS
open -a "Google Chrome" --args --enable-unsafe-webgpu --enable-features=Vulkan
```
Verify on `chrome://gpu` that "WebGPU" is listed as hardware-accelerated.

## Protocol
1. **Cold start**: `flutter run -d chrome`, click **Load**. Model downloads
   from HuggingFace (one-time).
2. **Warm reload**: reload the tab, click **Load** again. Should resolve from
   OPFS cache.
3. **Run 10 prompts**: click **Run 10 prompts**. Each prompt = bundled IDEA
   image + the `describe_photo` user turn.
4. Inspect the on-page report. Click **Download** to save `s2_report_*.json`
   into Downloads; move it to `scripts/spikes/out/`.
5. Open Chrome DevTools → **Performance Monitor** → watch
   `JS heap size` and `GPU process memory`.

## Pass criteria
| metric                         | threshold                     |
|-------------------------------|-------------------------------|
| First-load wallclock           | < 4 min on Wi-Fi              |
| Warm reload wallclock          | < 10 s                        |
| Image TTFT (first prompt)      | < 20 s                        |
| Decode rate                    | > 4 tok/s                     |
| 10/10 prompts succeed          | no tab crash, no GPU hang     |
| JS-parseable JSON responses    | ≥ 8/10                        |
| Peak JS heap                   | < 2 GB                        |
| Peak GPU process memory        | < 4 GB (reported by Chrome)   |

## Fail → Plan B
- **WebGPU unavailable on judge's machine** → fall back to Ollama E4B on
  Mac for the live demo video (no browser claim), plus Colab notebook.
- **OOM or TTFT > 30 s** → switch primary model to E2B (`--model e2b`);
  document tradeoff in `docs/week1_decision.md`.
- **JSON parse rate < 50 %** → log as S3 prompt-strategy failure, not a
  device failure.

## Deliverables
- `scripts/spikes/out/s2_<timestamp>.json` (downloaded from the app).
- A row filled in `docs/week1_decision.md` — same row name (`S1`) just with
  "(web)" appended.

## When the Android device arrives
`scripts/spikes/s1_device_feasibility.md` + `s1_adb_harness.py` are unchanged;
resume that track in Week 2. Numbers from both tracks end up in the final
Kaggle writeup as two rows of the feasibility table.
