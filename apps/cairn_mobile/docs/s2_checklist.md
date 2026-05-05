# S2 — `flutter_gemma` stability checklist (Phase 10, Android only)

**Scope:** Android-only. Web S2 is frozen in maintenance mode per
`docs/android_repivot_v5.md §1.3`.

**Pre-condition:** `s2_probe.jpg` is **operator-provided** — it must be placed
at `apps/cairn_mobile/assets/images/s2_probe.jpg` before building.
The app shows a clean error card at `/spike` if the asset is absent; there
is no crash. The asset is excluded from version control (`.gitignore`).

## Protocol

1. Fresh install:
   ```powershell
   adb -s RZCX920ARVA uninstall app.cairn.cairn_mobile
   flutter run -d RZCX920ARVA
   ```
2. First-run model download completes within 3 min on Wi-Fi.
3. Warm start: kill app via recents, relaunch. Model load **< 25 s**
   (GPU kernel cache warm after first boot).
4. Navigate to `/spike` (tap the S2 entry on the debug menu or use
   `adb shell am start -n app.cairn.cairn_mobile/.MainActivity`
   then navigate via the in-app route).
5. Select model, press **Load**, wait for model ready.
6. Press **Run 10 prompts**. Each prompt uses `s2_probe.jpg` +
   the `describe_photo` user turn. Expected: 10/10 parse as JSON
   with no SIGSEGV, no OOM, no ANR.
7. Press the copy icon and paste the JSON report into:
   ```
   scripts/spikes/out/s2_<date>.json
   ```

## Exit artifact

The report JSON is displayed in the app and can be copied to clipboard.
Archived at: `scripts/spikes/out/s2_<yyyyMMddTHHmmssZ>.json`

## Fail → Plan B

SIGSEGV or ANR with no recovery → review `docs/week1_decision.md`.
`flutter_gemma` LiteRT-LM path on Exynos 2200 was confirmed working in
Phase 5 (`docs/android_repivot_v5_runlog.md`); a regression here should
be investigated via logcat before abandoning the integration.
