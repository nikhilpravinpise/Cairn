# `cairn_mobile`

Flutter Android + Web app for offline FEMA P-154 building triage with Gemma 4.

## Model policy

The app is **Gemma 4 only**. Approved runtime artifacts are defined in
`lib/core/llm/model_registry.dart`:

- `litert-community/gemma-4-E2B-it-litert-lm`
- `litert-community/gemma-4-E4B-it-litert-lm`

`test/model_registry_platform_test.dart` fails if non-Gemma-4 repos, filenames,
or runtime model types are introduced.

## Runtime paths

- `flutter_gemma` is the production runtime.
- Android `.litertlm` files are used outside web.
- Web uses `.task` files.
- LiteRT-LM speculative decoding is requested by default through
  `flutter_gemma`.
- The legacy `INFERENCE_RUNTIME=native_mtp` bridge is diagnostic-only and is
  blocked on the current Android 16 test device.

## Core flow

1. Start a screening session.
2. Collect location and building metadata.
3. Capture required photos and optional audio.
4. Run Gemma 4 descriptions through `GemmaOrchestrator`.
5. Enforce output contracts before writing observations.
6. Compute deterministic triage in Dart.
7. Seal an `EvidencePacket` and generate a PDF report.

## Important source files

- `lib/core/llm/model_registry.dart` — approved model registry.
- `lib/core/llm/gemma_session.dart` — default `flutter_gemma` session.
- `lib/core/llm/native_mtp_session.dart` — Android MTP bridge.
- `lib/core/llm/orchestrator.dart` — prompt construction and JSON contract
  enforcement.
- `lib/core/state/session_controller.dart` — Riverpod session draft state.
- `lib/core/models/evidence_packet.dart` — packet model.
- `lib/core/models/evidence_packet_validator.dart` — packet validation.

## Setup

```bash
cd apps/cairn_mobile
flutter pub get
flutter analyze
flutter test
```

Run on Android:

```bash
flutter run -d <android-device-id>
```

Run on Android with MTP disabled for A/B debugging:

```bash
flutter run -d <android-device-id> --dart-define=BENCH_MTP=false
```

Run on web:

```bash
flutter config --enable-web
flutter run -d chrome --web-browser-flag=--enable-unsafe-webgpu
```

## Locked assets

The app bundles copies of locked docs assets:

- `assets/prompts/system_prompt_v1.txt`
- `assets/schema/evidence_packet_v1.schema.json`

When source docs change, sync and verify the asset copies before committing.
