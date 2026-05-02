# Re-pivot to Android (S23 FE) — Plan & Next Steps

_Decided: Apr 30, 2026. Supersedes `docs/week1_pivot.md`. The locked plan
`cairn-implementation-plan-0b751e.md` is once again the **primary** spec; this
doc records the explicit reversal of the Week-1 web-first delta and the
concrete next-step checklist from today (~D14)._

---

## 1. TL;DR

- **Primary target reverts to Samsung S23 FE / A55 Exynos, 8 GB RAM** running
  **Gemma E2B INT4** via `flutter_gemma` 0.13.x (MediaPipe LLM Inf API +
  LiteRT-LM 0.10), Mali GPU + XNNPACK CPU fallback. Plan §0 + §2.4 are back in
  force.
- **Web (E4B) demotes to the zero-install judge demo only** (one URL, served
  from the same Dart codebase). It is no longer the primary feasibility target.
- The `docs/week1_pivot.md` deltas are **reversed**. S1 becomes adb-based
  device feasibility again; S2 LoRA-on-device load is back in scope.
- Today ≈ **D14** of the 31-day plan. We have to land Android parity + W1
  decision doc + the W2 E2E in compressed time. See §6.

---

## 2. What actually changes vs `docs/week1_pivot.md`

| Spike / artifact            | Web pivot (now reversed)                            | Re-pivoted (Android primary)                                       |
|----------------------------|------------------------------------------------------|--------------------------------------------------------------------|
| **S1 — feasibility**        | `s1_web_feasibility.md` on Mac Chrome WebGPU         | `s1_device_feasibility.md` + `scripts/spikes/s1_adb_harness.py`    |
| Pass criteria (S1)          | TTFT<20s, decode>4 tok/s, warm reload<10s            | TTFT<15s, decode>4 tok/s, peak RAM<5.5 GB, no OOM (plan §1 NFR)    |
| **S2 — `flutter_gemma`**    | Chrome / Edge target, `loraPath:` no-ops cleanly     | Android target, `loraPath:` actually loads MediaPipe `.fb`         |
| **S5 — LoRA round-trip**    | Colab-only, on-device load deferred                  | Colab + on-device adb sideload + 5-prompt diff                     |
| Primary model              | E4B (web)                                            | **E2B INT4** (device); E4B web demo is secondary artefact          |
| Audio modality (Screen 4)  | Web fallback = text area                             | Native `record` mono 16 kHz WAV → Gemma audio modality             |
| Screen 5 (protocol)        | Tap-only on web                                      | `protocol_answer` LLM round-trip on free-text replies (plan §5)    |
| App platforms              | `apps/cairn_mobile/` only generated `web/`           | Generate `android/` and keep `web/` as the demo target             |
| CI                          | Removed in commit `180301a`                          | Restore APK CI workflow (Linux Flutter build + APK artefact upload)|

The web-first pivot is **archived**, not deleted: `docs/week1_pivot.md` stays
in-tree as a record of the temporary deviation. New PRs reference *this* doc.

---

## 3. Immediate Day-0 tasks (today)

These unblock everything else. Order matters.

### 3.1 Hardware bring-up (S23 FE)
1. Enable Developer options + USB debugging on the device.
2. Verify `adb devices` lists the device. Verify Mali GPU on `adb shell getprop ro.hardware.egl`.
3. Pre-clear ~6 GB free space (E2B `.task` ≈ 1.5 GB; we want a safety margin
   for the OPFS-equivalent app-support dir + screen recording + LoRA fb).

### 3.2 Flutter platform restore
Run from `apps/cairn_mobile/`:
```bash
flutter create --platforms=android,web --project-name cairn_mobile .
flutter pub get
flutter analyze
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
flutter run -d <device-id>     # smoke test on S23 FE
```
The Dart code is platform-neutral by design (`lib/main.dart` already passes
`WebStorageMode.streaming`, which `flutter_gemma` documents as ignored on
mobile — see the comment at `@c:\Dev\gemma_project\apps\cairn_mobile\lib\main.dart:16-22`).
No code change required just to run on Android, but verify on first launch
and tighten if `getActiveModel(supportImage: true, maxNumImages: 5)` reports
delegate fallback to XNNPACK on the S23 FE.

### 3.3 Required `pubspec.yaml` audit
Already present and Android-compatible: `flutter_gemma`, `geolocator`,
`geocoding`, `permission_handler`, `image_picker`, `record`, `printing`,
`pdf`, `qr_flutter`, `flutter_map`, `share_plus`. **No changes needed**, but
add Android `INTERNET`, `RECORD_AUDIO`, `ACCESS_FINE_LOCATION`, `CAMERA`,
`READ_EXTERNAL_STORAGE` permissions to
`android/app/src/main/AndroidManifest.xml` once `flutter create` regenerates
it.

### 3.4 Run S1 adb harness
```bash
PYTHONPATH=scripts python -m spikes.s1_adb_harness \
    --device <serial> --model e2b \
    --out scripts/spikes/out/s1_e2b_$(date -u +%Y%m%dT%H%M%SZ).json
```
Acceptance per plan §7.1: TTFT < 15 s, decode > 4 tok/s, peak RSS < 5.5 GB,
10 consecutive vision prompts without OOM/SIGSEGV.

---

## 4. Code changes the re-pivot forces

Concrete, file-level. Each item is a self-contained PR.

1. **Audio capture in Screen 4** — `apps/cairn_mobile/lib/features/describe/describe_screen.dart`
   currently records a text note (web fallback, `@c:\Dev\gemma_project\apps\cairn_mobile\lib\features\describe\describe_screen.dart:1-12`).
   Add a `record`-package mono 16 kHz WAV capture path gated on
   `defaultTargetPlatform == TargetPlatform.android`, push the bytes through
   `SessionController.addAudio`, then send via
   `_session.generate(audio: bytes)` once the orchestrator gains an audio
   parameter. Web path stays as the text fallback.
2. **Orchestrator audio support** — extend
   `@c:\Dev\gemma_project\apps\cairn_mobile\lib\core\llm\orchestrator.dart:110-160`
   `describePhoto` (rename or add `describeMultimodal`) to accept optional
   `Uint8List? audio` and pass through `Message.withAudio` (or
   `Message.withImageAndAudio`) on the `flutter_gemma` 0.13 API. Mirror the
   change in `gemma_session.dart`.
3. **Screen 5 protocol LLM round-trip** —
   `@c:\Dev\gemma_project\apps\cairn_mobile\lib\features\protocol\protocol_screen.dart:1-60`
   currently uses tap chips and calls `applyProtocolDelta` directly. Add a
   "Speak / type your answer" mode that fires
   `orchestrator.protocolAnswer(...)` (already implemented at
   `@c:\Dev\gemma_project\apps\cairn_mobile\lib\core\llm\orchestrator.dart:202-231`)
   and applies the resulting single-key delta. Tap chips remain as the
   fast-path / fallback.
4. **LoRA path wiring** — `GemmaSession.open` already forwards `loraPath` to
   `createChat` (`@c:\Dev\gemma_project\apps\cairn_mobile\lib\core\llm\gemma_session.dart:108-127`).
   Add a Start-screen UI affordance to pick a sideloaded `.fb` from
   `/sdcard/Android/data/app.cairn.cairn_mobile/files/` so S5 can run end-to-end.
5. **OPFS → app-support vault swap** — replace `InMemoryEvidenceVault`
   (`@c:\Dev\gemma_project\apps\cairn_mobile\lib\core\providers.dart:78-81`)
   with a `path_provider` + `dart:io` File-backed implementation under
   `getApplicationSupportDirectory()`. Web build keeps an OPFS path via
   conditional imports.
6. **Synthesize + Report screens** (still stubs from `_pending.dart`). Now
   that audio is real, the synthesize task can include the audio observation
   set; ship the deterministic `priorityScore` call + the report layout.
7. **CI restore** — re-add `.github/workflows/ci.yml` running:
   - `pip install -e scripts && PYTHONPATH=scripts pytest -q`
   - `flutter analyze && flutter test` in `apps/cairn_mobile/`
   - `flutter build apk --debug` (Linux runner; uploads APK as artefact)
   - `flutter build web --release`
   The parity test `scripts/tests/test_constants_parity.py` must run green —
   it is the only thing keeping `cairn/constants.py::MODELS` in sync with
   `apps/cairn_mobile/lib/core/llm/model_registry.dart::models`.

---

## 5. Spikes — re-scored against the locked plan

| # | Spike                          | Status today | Pass criteria (Android-primary) | Owner action |
|---|--------------------------------|--------------|---------------------------------|--------------|
| S1 | Device feasibility (E2B+image) | Untested     | TTFT<15s, decode>4 tok/s, RSS<5.5GB, 10/10 prompts OK | run `s1_adb_harness.py` |
| S2 | `flutter_gemma` 10-prompt burst | S2 page exists at `/spike` | No SIGSEGV; load<25s; LoRA flatbuffer loads | run on device, follow `apps/cairn_mobile/docs/s2_checklist.md` |
| S3 | Vision quality on 200 IDEA     | Eval harness done; gold file missing | E2B F1≥0.7, top3≥0.5; E4B (Ollama) F1≥0.8, top3≥0.6 | assemble `data/eval/gold.jsonl`, run `eval_baseline.py` |
| S4 | Audio multilingual ≥16/20      | Harness done; manifest missing | ≥16/20 clips correctly identify damage | record 20 clips, write manifest |
| S5 | LoRA round-trip                | Scripts done, never executed | base-vs-LoRA tag/confidence delta on ≥3/5 prompts on device | run Colab notebook → `convert_mediapipe_lora.py` → `adb push` → S2 page |

The W1 decision-doc rows in
`@c:\Dev\gemma_project\docs\week1_decision.md:6-14` are still the right
template — just measure under Android thresholds instead of the web ones.

---

## 6. Compressed timeline (D14 → D30)

We've burned 14 days; submit on **D30 = May 17**. The plan §8 sequence still
holds, but the slack is gone. Recommended re-baseline:

| Day(s)        | Deliverable                                                                                       | Plan §            |
|---------------|---------------------------------------------------------------------------------------------------|-------------------|
| **D14 (today)** | Re-pivot doc (this file). `flutter create --platforms=android,web`. APK on S23 FE smoke-test.    | §8 W1 + §12       |
| D15           | S1 + S2 measured on device. Fill in `week1_decision.md`. **GO/NO-GO signed.**                     | §7.1 + §11        |
| D16           | S3 gold file (200 IDEA) assembled; S3 baseline run for E2B (device adb runner) + E4B (Ollama).    | §7.1 S3           |
| D17           | S4 audio manifest + run. S5 LoRA round-trip on device. Audio capture wired into Screen 4.        | §7.1 S4 + S5      |
| D18           | Synthesize + Report screens, deterministic `priorityScore`, PDF placard via `printing`+`qr_flutter`. | §5 screens 7–9    |
| D19           | OPFS / app-support `EvidenceVault`. Share/export `.cairn.json`.                                   | §5 + §2.2         |
| D20           | Phase A LoRA training overnight on Colab Pro (3 epochs E2B, attention-only).                     | §4.1              |
| D21           | Phase A → MediaPipe `.fb` → device load. Held-out 100-dialogue eval; gate vs base.               | §4.1 + §3.4       |
| D22           | `apps/cairn_console/` Next.js scaffold + table + JSON drop. Deploy Vercel.                       | §6                |
| D23           | Console map (MapLibre + OSM). Detail panel. CSV export.                                           | §6                |
| D24           | E2E airplane-mode test on S23 FE. Record raw screen capture (`scrcpy --record`).                 | §7.2 W2 / W3      |
| D25–D26       | Web demo (Flutter Web + E4B) deployed to HF Spaces / Vercel. Multilingual UI EN+ES (TR if time). | §1 P0 + §1 P1     |
| D27           | Video shoot (S23 FE in-hand + scrcpy). Storyboard + voiceover.                                   | §8 W4 D23–D24     |
| D28           | Video edit + writeup draft (1500 w). Cover image + 4 gallery assets. Kaggle Notebook (Ollama E4B).| §8 W4 D25–D28     |
| D29           | HF Hub uploads (LoRA card + synthetic dataset card). Signed APK in GitHub Releases.              | §9                |
| D30           | **Submit Kaggle.** Verify every link. YouTube unlisted public.                                    | §8 W5             |

Phase B vision LoRA stays in **slip-kill #1** — only attempt if the Phase A
gate (§3.3) is unambiguously met by D26.

---

## 7. Risk register deltas

The plan §10 risks are mostly unchanged; the re-pivot sharpens these:

- **R1 — E2B can't do real-time multimodal on S23 FE Exynos**: now LIVE risk;
  resolved by running S1 today/tomorrow. Plan B (drop audio, text+photo only)
  is still on the shelf.
- **R2 — `flutter_gemma` Android crashes**: LIVE; resolved by S2 with the new
  `/spike` page on the actual phone.
- **R5 — MediaPipe LoRA conversion**: LIVE again; we have the conversion
  script (`finetune/convert_mediapipe_lora.py`) but have never executed
  end-to-end on Unsloth Gemma 4 output.
- **R8 — 31 days insufficient**: was M-prob; now **H-prob** because we burned
  14 days on a non-Android path. Slip-kill order applies aggressively (§8):
  drop Phase B → drop TR → drop ShakeMap → console table-only → solo video.

---

## 8. Concrete next-steps checklist (copy into your tracker)

```
[ ] D14  Hardware: S23 FE booted, USB-debug on, `adb devices` green
[ ] D14  cd apps/cairn_mobile && flutter create --platforms=android,web .
[ ] D14  android/app/src/main/AndroidManifest.xml: add INTERNET, RECORD_AUDIO,
         CAMERA, ACCESS_FINE_LOCATION, READ_EXTERNAL_STORAGE
[ ] D14  flutter build apk --debug && adb install -r → smoke-test on device
[ ] D15  Run scripts/spikes/s1_adb_harness.py → fill S1 row in week1_decision.md
[ ] D15  Run /spike page on device 10 prompts → fill S2 row
[ ] D15  Sign D7 GO/NO-GO decision (late but mandatory)
[ ] D16  Assemble data/eval/gold.jsonl from IDEA (200 items)
[ ] D16  Run eval_baseline.py for E2B (device) and E4B (Ollama Mac)
[ ] D17  Record 20 audio clips (10 EN / 5 ES / 5 TR) + transcripts + manifest
[ ] D17  Wire `record` mono-16k-WAV capture into describe_screen.dart
[ ] D17  Extend orchestrator.dart to forward audio via flutter_gemma
[ ] D18  Implement synthesize_screen.dart (thinking-mode stream + priorityScore)
[ ] D18  Implement report_screen.dart (badge, bullets, bbox photos, share, PDF)
[ ] D19  Replace InMemoryEvidenceVault with path_provider-backed FileVault
[ ] D19  Share-packet flow → .cairn.json + assets zip via share_plus
[ ] D20  Kick Phase A LoRA on Colab Pro (overnight)
[ ] D21  convert_mediapipe_lora.py → adb push e2b_lora.fb → S2 base-vs-LoRA diff
[ ] D22  Scaffold apps/cairn_console/ (Next.js + ajv + MapLibre)
[ ] D23  Console: map + detail panel + CSV export → deploy to Vercel
[ ] D24  Airplane-mode E2E on S23 FE; scrcpy --record raw video
[ ] D25  Flutter Web demo (E4B + WebGPU) deployed
[ ] D26  ES locale strings (TR if time)
[ ] D27  Video shoot day
[ ] D28  Video v1 edit + 1500-word writeup draft + cover/gallery assets
[ ] D29  HF Hub uploads (LoRA card, dataset card); signed APK in Releases
[ ] D30  Submit Kaggle, verify every link, publish unlisted YouTube
[ ] D31  Buffer
```

---

## 9. What is not changing

For the avoidance of doubt:

- The locked artifacts stay locked: `docs/prompts/system_prompt_v1.txt`,
  `docs/schema/evidence_packet_v1.schema.json`, `data/seeds/dialogues.seed.jsonl`.
- The four LLM task contracts (`describe_photo`, `ask_followup`,
  `protocol_answer`, `synthesize`) are unchanged.
- The deterministic Dart/Python `priorityScore` is unchanged (and still must
  match byte-for-byte across both languages — see
  `scripts/tests/test_constants_parity.py`).
- The 9-screen FEMA P-154 user flow is unchanged.
- The legal framing in `docs/LEGAL.md` is unchanged: this is a preliminary
  screening aid, not an ATC-20 placard.

---

## 10. Decision log

| Date         | Decision                                       | Doc                          |
|--------------|------------------------------------------------|------------------------------|
| Apr 17 (D0)  | Lock plan, S23 FE primary, E2B INT4            | `cairn-implementation-plan-0b751e.md` |
| Apr 20 (D4)  | Lock system prompt + schema + seeds            | `docs/prompts/`, `docs/schema/`, `data/seeds/` |
| Apr 20 (D4)  | Web-first pivot (no Android hardware)          | `docs/week1_pivot.md` (now superseded) |
| **Apr 30 (D14)** | **Re-pivot to Android (S23 FE) primary**   | **this doc**                 |
