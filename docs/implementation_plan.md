# Cairn Optimization + Production User Flow Overhaul

## Background

**Project:** Cairn — offline FEMA P-154 earthquake triage app  
**Competition:** Gemma 4 Good Hackathon (Kaggle × Google DeepMind), $200K prize, deadline **May 18, 2026**  
**Today:** May 5, 2026 — **13 days remain**  
**Device:** Samsung S23 FE (Exynos 2200, Mali-G710, 8 GB RAM)

### Current Status (repo audit)

| Area | Status |
|:---|:---|
| **Phases 0-9** | ✅ Complete; keep the current suite green before behavior changes |
| **Phase 10** (manual device test) | ⏳ PENDING |
| **flutter_gemma** | Pinned `^0.14.5` |
| **Screens** | 10/10 implemented (Bootstrap, Start, Location, Photos, Audio, Describe, Protocol, Humility, Synthesize, Report) |
| **Optimizations** | Sprint 3 (image preprocessing 768px, describeAll stream) ✅ implemented; Sprint 4 (history retention, CPU/GPU benchmark, batch feasibility probed) ✅ implemented — **all pending device benchmarks** |
| **User flow** | Functional but "beta" — raw Material widgets, no onboarding, no polished UX transitions |
| **Missing deliverables** | cairn_console (Next.js), CI, web demo, video, writeup, HF uploads, Kaggle notebook |

### Core Problem

5 photos × ~2 min each = ~10 min total pipeline. Competitors (EpiCast, Sunny) avoid this — server inference or ultra-short prompts respectively. We must close the speed gap while converting from "beta test harness" to "polished product demo."

---

## Decisions (Resolved)

| Decision | Resolution |
|:---|:---|
| **Model family** | ✅ **Gemma 4 only** — registry is guarded to `e2b` / `e4b` LiteRT-LM artifacts. |
| **flutter_gemma upgrade** | ✅ Complete — `^0.14.5` |
| **Timeline priority** | ✅ Model working properly first → optimization → UX → deliverables. Do it all once model works. |
| **Audio** | ✅ **Keep audio description** — fix BUG-4 so audio describe is reachable |
| **Demo device** | ✅ **Mobile (S23 FE)** — all optimizations target physical device |
| **Design direction** | ✅ **High-contrast disaster response theme** — semantic color, not dark mode |

---

## Proposed Changes

### Part A — Remaining Optimization (Speed + Resources)

These are the **unfired optimizations** that are already implemented but awaiting device benchmarks, plus new optimizations from research.

---

#### A1. Keep flutter_gemma on the Gemma 4-compatible line

#### [MODIFY] [pubspec.yaml](file:///Users/Hetansh/Github/kaggle_gemma/apps/cairn_mobile/pubspec.yaml)

- Current manifest: `flutter_gemma: ^0.14.5`
- Benefits:
  - iOS ITMS-90208 fix (App Store submission)
  - Android 16KB page-size rebuild (Play Store compliance)
  - Web WASM build pipeline fixes
  - Cumulative stability fixes since 0.14.2
- No API-breaking changes. `ModelType.gemma4`, `Message.withImage`, `Message.withAudio` all unchanged.

---

#### A2. Run Sprint 3 Device Benchmark (Image Preprocessing Gate)

Already implemented:
- `BoundedImagePreprocessor(maxLongEdgePx: 768)` — default
- `tool/benchmark_image_px.ps1` scripts for 768px, 512px, and raw variants

**Action:** Execute on S23 FE and select optimal image size. Expected result: **768px → 2-4× prefill speedup** over raw 1600px capture bytes.

From latest research:
- Google's Gemma 4 variable resolution uses token budgets: 70/140/280/560/1120 tokens
- 768px longest edge → ~280 visual tokens (good balance for building damage)
- 512px → ~140 tokens (aggressive but may lose fine cracks)
- **FEMA P-154 is about gross structural features** — 512px likely sufficient

---

#### A3. Run Sprint 4 Experiments (Device Gates Pending)

Three experiments already fully coded, just need device execution:

| Experiment | What | Dart-Define | Expected Impact |
|:---|:---|:---|:---|
| **OPT-5: History Retention** | Skip `clearHistory()` between same-profile photo turns | `BENCH_CONFIG=vision_history_retained` | 15-25% if safe |
| **OPT-6: CPU vs GPU** | Compare Mali GPU vs XNNPACK CPU on Exynos | `BENCH_BACKEND=cpu` | Pick more consistent backend |
| **Image 512px** | Aggressive downscale | `BENCH_IMAGE_PX=512` | More prefill savings |

---

#### A4. New Optimization: Prompt Output Constraints (OPT-2)

#### [MODIFY] [system_prompt_v1.txt](file:///Users/Hetansh/Github/kaggle_gemma/docs/prompts/system_prompt_v1.txt)
#### [MODIFY] [system_prompt_v1.txt](file:///Users/Hetansh/Github/kaggle_gemma/apps/cairn_mobile/assets/prompts/system_prompt_v1.txt)

Add explicit length constraints to reduce decode time:
```
For task = "describe_photo":
- model_description: maximum 3 sentences and maximum 60 words.
- model_tags: 1 to 5 values from the permitted enum.
- bbox_annotations: at most 1 box per visible finding.
```

**Expected impact:** 20-40% reduction in decode time (from ~30-40s to ~15-25s per photo).

Competitor insight: Sunny uses 2-word prompts ("skin extract") via SFT. We won't go that far, but constraining output is the fastest non-model-swap speed win.

---

#### A5. New Optimization: SessionConfig Max Tokens Reduction (OPT-3)

#### [MODIFY] [session_config.dart](file:///Users/Hetansh/Github/kaggle_gemma/apps/cairn_mobile/lib/core/llm/session_config.dart)

Benchmark `maxTokens` from 4096 → 2048 for vision sessions.

Rationale from research:
- MediaPipe/LiteRT-LM defines `maxTokens` as input+output
- System prompt ~2K tokens + image ~280 tokens + output ~200 tokens = ~2.5K max
- Both competitor projects (EpiCast, Sunny) use 1024-2048
- Lower `maxTokens` reduces KV cache allocation and engine creation time
- **Gate required:** no truncation, no contract failures

---

#### A6. New Optimization: Temperature Reduction for Structured Output

#### [MODIFY] [session_config.dart](file:///Users/Hetansh/Github/kaggle_gemma/apps/cairn_mobile/lib/core/llm/session_config.dart)

Benchmark temperature 0.2 → 0.1 for `describe_photo` and `protocol_answer` sessions.

Rationale:
- EpiCast uses temperature 0.1 for structured JSON extraction
- Lower temperature = more deterministic = fewer wasted decoding cycles on rejected tokens
- Synthesis should stay at 0.2+ (needs creative reasoning for rationale bullets)

---

#### A7. Gemma 4-only performance path

Do not add a third model family. The current architecture intentionally keeps
the registry restricted to Gemma 4 E2B/E4B LiteRT-LM artifacts and uses tests to
guard that constraint.

**Combined speed estimate with approved optimizations:**

| Optimization Stack | Per-Photo Time |
|:---|:---|
| Current (raw 1600px, 4096 tokens, temp 0.2, Gemma 4) | ~120s |
| + Image preprocessing (768px) | ~50-60s |
| + maxTokens 2048 + output constraints | ~35-45s |
| + History retention (if safe) | ~30-40s |
| + LiteRT-LM MTP on supported Android runtime | device-gated |
| **5 photos total** | device-gated target, no model-family swap |

---

#### A8. Advanced LiteRT-LM Optimization Techniques (From Research)

These are documented for awareness; some are actionable now, some are future:

| Technique | Actionable? | Impact |
|:---|:---|:---|
| **KV cache quantization** (FP16 → q4_0) | ❌ Not exposed by flutter_gemma | 3× decode speed |
| **AOT compilation** | ❌ LiteRT-LM handles internally | Faster model init |
| **Zero-copy memory** | ❌ Handled by FFI path | Already optimized in 0.14.0+ |
| **Model warm-up** | ✅ **Implement** — preload engine during capture phase | Eliminates reload stall |
| **Selective routing** (small model for simple tasks) | ✅ Protocol/followup could use lighter session | Save ~5s per reload |
| **NPU acceleration** | ❌ S23 FE Exynos has no viable NPU for LLMs | Only Snapdragon 8 Gen 2+ |

**Actionable new optimization: Background model warm-up**

Instead of loading model → then capturing photos → then describing, do:
1. User starts session → navigate to location
2. **Background: begin model download/install check** (idempotent)
3. User does GPS + building info
4. User captures photos (model NOT loaded — saves RAM for camera)
5. User taps "Describe photos" → **model engine creation starts** (or was already warm)

This is partially implemented (PhotosScreen already unloads model for camera), but the warm-up can be moved earlier.

---

### Part B — Production User Flow & UX Overhaul

Transform from beta test harness to polished product demo.

---

#### B1. Design System Foundation

#### [NEW] [cairn_theme.dart](file:///Users/Hetansh/Github/kaggle_gemma/apps/cairn_mobile/lib/core/theme/cairn_theme.dart)

Create a proper Material 3 theme with disaster-response-optimized design tokens:

```dart
// Design principles:
// 1. "Stress-first" — high contrast, large touch targets (48dp+), clear hierarchy
// 2. Semantic color — red/orange/amber/green for triage bands
// 3. Professional authority — not flashy, conveys reliability
// 4. Offline-ready — no network-dependent assets

class CairnTheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: _lightColorScheme,
    textTheme: _textTheme,
    // Custom component themes...
  );
  
  static const _lightColorScheme = ColorScheme(
    // Primary: Deep blue (authority, trust)
    primary: Color(0xFF1565C0),
    // Error/Critical: Vivid red
    error: Color(0xFFD32F2F),
    // Custom semantic colors via extensions
    // ...
  );
}
```

Key design tokens:
- **Triage colors:** Critical (red `#D32F2F`), High (deep orange `#E65100`), Medium (amber `#F9A825`), Low (green `#2E7D32`)
- **Typography:** Inter or Roboto (already available via Material)
- **Touch targets:** Minimum 48×48dp for all interactive elements
- **Spacing:** 8dp grid system
- **Elevation:** Minimal — flat cards with subtle borders (disaster conditions = bright sun glare)

---

#### B2. Onboarding Flow Redesign

Replace current Bootstrap screen (blanket permission request) with a proper progressive onboarding:

#### [DELETE] [bootstrap_screen.dart](file:///Users/Hetansh/Github/kaggle_gemma/apps/cairn_mobile/lib/features/bootstrap/bootstrap_screen.dart)

#### [NEW] [onboarding_screen.dart](file:///Users/Hetansh/Github/kaggle_gemma/apps/cairn_mobile/lib/features/onboarding/onboarding_screen.dart)

New onboarding flow (3 screens max, 60-second rule):

**Screen 1: Welcome + Model Setup**
- Cairn logo + tagline ("Post-earthquake building triage — offline, on your device")
- Single prominent CTA: "Set Up" or "Get Started"
- Model auto-download begins immediately (background)
- Progress indicator shows download state
- Key message: "Works completely offline. No data leaves your device."

**Screen 2: How It Works (Interactive)**
- 3-step visual walkthrough (not carousel — single scrollable view):
  1. 📸 "Photograph the building (4 angles)"
  2. 🤖 "AI analyzes damage patterns"
  3. 📋 "Get a triage report in minutes"
- Skip button always visible
- "Begin First Screening" CTA

**Permissions: Contextual, not upfront**
- Camera permission → requested when user taps capture button
- Location permission → requested on Location screen with "Why we need this" context
- Microphone permission → requested only if user enters Audio screen

This matches the optimization plan (BUG-8: Bootstrap Permission Gate Contradicts The Flow).

---

#### B3. Start Screen Redesign

#### [MODIFY] [start_screen.dart](file:///Users/Hetansh/Github/kaggle_gemma/apps/cairn_mobile/lib/features/start/start_screen.dart)

Transform from developer-facing model picker to production-ready dashboard:

**New layout:**
```
┌─────────────────────────────┐
│  Cairn                  ⚙️  │  ← Settings gear (model selection hidden here)
├─────────────────────────────┤
│                             │
│  ┌─────────────────────┐    │
│  │   🏢                │    │
│  │   Ready to screen   │    │
│  │   a building?       │    │
│  │                     │    │
│  │  [Start Screening]  │    │  ← Giant, primary FAB-style button
│  └─────────────────────┘    │
│                             │
│  ── Model Status ──         │  ← Minimal status line ("Gemma E2B ✓ ready")
│                             │
│  ── Resume Draft ──         │  ← Draft banner IF available (prominent)
│                             │
│  ── Recent Reports ──       │  ← Card list with triage color bands
│    ┌──────────────────┐     │
│    │ 🔴 8 HIGH  Front │     │
│    │ May 4 · 3 photos │     │
│    └──────────────────┘     │
│                             │
└─────────────────────────────┘
```

Key changes:
- Model picker moved to settings/hidden — default is E2B, no user decision needed
- No "Load model" button — model is auto-managed (install on first run, warm-up before inference)
- "Start building screening" is the ONE primary action — giant button, impossible to miss
- Recent reports as cards with triage color bands, not raw list tiles
- Draft resume banner is prominent and visually distinct

---

#### B4. Linear Flow Step Indicator

#### [NEW] [flow_stepper.dart](file:///Users/Hetansh/Github/kaggle_gemma/apps/cairn_mobile/lib/core/widgets/flow_stepper.dart)

Add a persistent step indicator across all screening screens:

```
  📍 → 📸 → 🎤 → 📝 → ✓ → 🧠 → 📋
 Location Photos Audio Describe Protocol Humility Synthesize Report
   ●     ●     ○      ○       ○       ○        ○        ○
```

- Shows which step the user is on
- Tap-to-navigate disabled (linear flow only, for data integrity)
- Animates progress with subtle color fill
- Collapses to compact mode on small screens

---

#### B5. Screen-by-Screen UX Polish

For each of the 10 screens, apply:

1. **Consistent AppBar** with step indicator, back navigation, and screen title
2. **Proper loading states** — skeleton screens, not spinners
3. **Error states** — branded error cards with retry buttons, not raw exception text
4. **Transitions** — smooth slide animations between screens (GoRouter custom transitions)
5. **Haptic feedback** — on triage result, on photo capture confirmation
6. **Empty states** — meaningful illustrations/messages, never blank screens

Specific screen enhancements:

| Screen | Enhancement |
|:---|:---|
| **Location** | Map preview after GPS fix, cleaner building type chips |
| **Photos** | Camera preview overlay with slot indicator ("Front · 1/4"), progress ring during describe |
| **Audio** | Waveform visualization (already exists), cleaner record button |
| **Describe** | Show AI observations as collapsible cards with confidence bars |
| **Protocol** | Single-question-per-page with large Yes/No buttons, progress bar |
| **Humility** | Photo context card + clear follow-up question styling |
| **Synthesize** | Animated "thinking" visualization (pulsing brain icon), show rationale bullets as they stream |
| **Report** | Premium triage card with large colored badge, photo grid, share/PDF buttons with icons |

---

#### B6. Model Lifecycle UX (Background Management)

#### [MODIFY] [providers.dart](file:///Users/Hetansh/Github/kaggle_gemma/apps/cairn_mobile/lib/core/providers.dart)
#### [MODIFY] [gemma_session.dart](file:///Users/Hetansh/Github/kaggle_gemma/apps/cairn_mobile/lib/core/llm/gemma_session.dart)

Remove the "Load model" / "Unload model" buttons from user-facing UI. Instead:

1. **First launch:** Auto-download model during onboarding (with progress bar)
2. **Subsequent launches:** Model is cached, install check is ~instant
3. **Before inference:** Session auto-loads the right profile (vision/synthesis/standard)
4. **After inference:** Auto-unload after idle timeout (120s, matching Sunny's pattern)
5. **During capture:** Model NOT loaded (RAM preserved for camera)
6. **User-facing state:** Just "Ready" / "Preparing AI..." / "Analyzing..."

The model is an implementation detail, not a user decision.

---

#### B7. Fix Remaining Correctness Bugs

From `docs/optimization-plan.md` Section 0:

| Bug | Status | Action |
|:---|:---|:---|
| BUG-0: Skip GPS schema-invalid | ✅ FIXED | `kSkippedGeoLocation` uses `accuracyMeters: 0.0` (schema-valid) |
| BUG-3: Start loads then Photos unloads | ✅ FIXED | StartScreen no longer pre-loads model; defers to PhotosScreen |
| BUG-4: Audio describe unreachable | ✅ RESOLVED | Record-only path; audio capture works, no LLM describe |
| BUG-5: turns.jsonl incomplete | ✅ FIXED | All task types (describe, protocol, synthesis) emit TurnRecord |
| BUG-6: Hand-written JSON encoder | ✅ FIXED | Report screen uses `JsonEncoder.withIndent` from dart:convert |
| BUG-7: Contract validation holes | ✅ FIXED | bbox `[y1,x1,y2,x2]` ordering + protocol key validation in place |
| BUG-8: Bootstrap permission gate | ✅ FIXED | Replaced with OnboardingScreen; contextual permissions only |
| COMPILE ERRORS: bracket mismatches | ✅ FIXED | audio_screen, photos_screen, location_screen, report_screen |
| IMPORT MISSING: FlowStepper in report | ✅ FIXED | Added missing import |
| UX: S2 spike button exposed in prod | ✅ FIXED | Removed from StartScreen AppBar |
| UX: Jarring default transitions | ✅ FIXED | Slide-left transitions for flow, fade for entry/exit screens |

---

### Part C — Submission Deliverables (Final Sprint)

#### C1. Demo Video Recording

After Parts A+B are complete:
- Record 3-min walkthrough on S23 FE
- Show: onboarding → capture 4 photos → AI analysis → protocol → triage report → PDF share
- Highlight: offline capability, speed, triage color coding

#### C2. Technical Writeup (1500 words)

Cover: problem statement, architecture, Gemma 4 on-device, optimization journey, competitive positioning, results

#### C3. Kaggle Notebook

Demonstrate: system prompt design, eval metrics, LoRA training config

#### C4. Repository Cleanup

- Re-add CI workflow (`.github/workflows/ci.yml`)
- Update README with screenshots
- HuggingFace model card upload

---

## Verification Plan

### Automated Tests
```bash
# After all changes:
cd apps/cairn_mobile
flutter pub get
dart analyze lib test
flutter test

# Python side:
cd ../../scripts
python -m pytest -q tests/
```

### Device Benchmarks (S23 FE)
```bash
# Sprint 3 image size gate:
./tool/benchmark_image_px.ps1 -Variant 768px
./tool/benchmark_image_px.ps1 -Variant 512px
./tool/benchmark_image_px.ps1 -Variant raw

# Sprint 4 experiments:
./tool/benchmark_session_config.ps1 -Variant vision_history_retained
./tool/benchmark_backend.ps1 -Variant vision_gpu
./tool/benchmark_backend.ps1 -Variant vision_cpu
```

### Manual Verification
- Full screening flow on S23 FE (start → report)
- PDF opens correctly
- JSON validates against schema
- Model downloads and loads without user intervention
- All triage bands display correctly
- Draft resume works after app kill

### Browser Testing
- Verify web build still compiles (`flutter build web`)
- Web fallback mode (no audio, no file persistence) functional

---

## Implementation Priority (13 days)

| Day | Focus | Deliverables |
|:---|:---|:---|
| **D1-2** (May 5-6) | ✅ Optimization + correctness | Upgrade to 0.14.5 ✅, prompt constraints ✅, all compilation errors fixed ✅, BUG-0/3/4/5/6/7/8 resolved ✅, route transitions ✅, start screen cleaned ✅ |
| **D3-4** (May 7-8) | UX overhaul foundation | Theme system, onboarding, start screen redesign |
| **D5-6** (May 9-10) | Screen polish | Step indicator, screen-by-screen enhancements |
| **D7-8** (May 11-12) | Model lifecycle + bugs | Auto-management, BUG fixes, flow testing |
| **D9** (May 13) | Gemma 4 runtime gate | Benchmark default runtime vs native MTP and keep registry guard green |
| **D10-11** (May 14-15) | Integration + testing | Full-flow device test, edge cases, CI |
| **D12** (May 16) | Submission artifacts | Video, writeup, Kaggle notebook |
| **D13** (May 17) | Submit | Final checks, submit |
