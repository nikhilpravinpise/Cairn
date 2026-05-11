# S23 FE Benchmark Results — Session 1 (2026-05-11)

Device: Samsung Galaxy S23 FE (RZCX920ARVA, Exynos 2200, Android 14)  
Model: `gemma-4-E2B-it.litertlm` — GPU backend, maxTokens=4096  
Flutter SDK: 3.41.8 stable  
Profile APK, `DEV_MODEL_TEST=true`

---

## §2 Build sanity

- `flutter pub get` ✅
- `flutter analyze` ✅ (0 issues)
- `flutter test` ✅ 634/634 pass
- Debug APK built ✅

**Bug fixed:** `pubspec.yaml` was missing explicit declarations for the three
`dev_scenarios/` subdirectories. Flutter does not recurse into asset directories.
Added `low_no_visible_damage/`, `medium_cracks_spalling/`, `high_column_soft_story/`.

---

## §3 Structural understanding gate

Engine cold-start: **14,718 ms** (`litert_lm_engine_create` native: 11,601 ms)

| Scenario | vision_score | Priority band | schema=0 | all 4 imgs | damage correct | severity ≤1 | PASS |
|---|---|---|---|---|---|---|---|
| low_no_visible_damage | **1.00** | LOW 1/10 ✅ | ✅ | ✅ | ✅ | ✅ (all Δ=0) | ✅ |
| medium_cracks_spalling | **0.40** ❌ | MEDIUM 4/10 ✅ | ✅ | ✅ | ❌ | ❌ (front Δ=2) | ❌ |
| high_column_soft_story | **0.54** | CRITICAL 10/10 ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**Gate verdict: FAIL** — scenario 2 fails 3/7 checks.  
Root cause: front photo tagged `horizontal_crack + vertical_crack + no_visible_damage`
simultaneously. Model hedges with contradictory tag. Priority band is still correct.

Wall times (768px, GPU, default temp=0.10):
- S1 low: **333,149 ms** (cold — GPU throttled photos 2-3, TTFT reached 69 s)
- S2 medium: **340,926 ms**
- S3 high: **181,336 ms** (GPU warm after 2 prior runs)

---

## §13 Temperature remedy (vision_temp01, temp=0.05)

| Scenario | default vision_score | temp01 vision_score | default wall | temp01 wall |
|---|---|---|---|---|
| S1 low | 1.00 ✅ | 1.00 ✅ | 333,149 ms | 279,598 ms |
| S2 medium | 0.40 ❌ | 0.44 ❌ | 340,926 ms | 248,875 ms |
| S3 high | **0.54** ✅ | **0.48** ❌ | 181,336 ms | 197,129 ms |

**Verdict: temp01 does NOT fix scenario 2. It slightly regresses scenario 3 (0.54→0.48).**  
The `no_visible_damage` tag contradiction is systematic, not stochastic.  
All further benchmarks use default temperature (production config).

---

## §4/§5 Image size speed matrix (Scenario 1, cold start, GPU)

All three image sizes produce **identical patch counts** (2,376 / 2,394 / 2,394 / 2,340).
The native `stb_image_preprocessor` always upscales input to fill the ≤2,520 patch budget.
Speed gain is from **JPEG I/O reduction**, not from fewer visual tokens.

| Variant | Photo bytes total | Photo 1 TTFT | total_wallclock | vs 768px | vision_score S1 |
|---|---|---|---|---|---|
| **768px** (prod) | 491,385 B | 32,512 ms | 333,149 ms | baseline | 1.00 ✅ |
| **512px** | 168,152 B (3.0×↓) | 18,654 ms | **168,195 ms** | **-49%** 🚀 | 1.00 ✅ |
| **256px** | 46,406 B (10.6×↓) | 23,393 ms | 145,698 ms | -56% | 1.00 ✅ |

**Recommendation: promote 512px.** Diminishing returns past 512px (-13% additional vs -49%
for first step). Scenarios 2 and 3 at 512px not yet tested.

---

## Pending benchmark sections

| Section | Status | Notes |
|---|---|---|
| §6 CPU vs GPU backend | ❌ not run | Build started, cancelled |
| §7 Session config variants | ❌ not run | |
| §8 History retention A/B | ❌ not run | |
| §9 Manual field UX flow (21 steps) | ❌ not run | |
| §10 Regression checks | ❌ not run | |
| §11-13 Log analysis / promotion decisions | partial | Speed matrix analysis done |
| §15 Production candidate config | ❌ pending §6-10 | |

**Blocked:** Cannot promote any config until scenario 2 structural gate is resolved.

---

## Production promotion checklist (current status)

- [x] Zero schema failures across all runs
- [x] Dart scorer priority bands correct (LOW/MEDIUM/CRITICAL all match)
- [ ] Scenario 2 structural gate pass (vision_score ≥ 0.50, severityDelta ≤ 1)
- [ ] §6 CPU vs GPU decision
- [ ] §7 Session config gate
- [ ] §8 History contamination hard gate
- [ ] §9 Manual UX flow 21-step pass
- [ ] §10 Regression checks
