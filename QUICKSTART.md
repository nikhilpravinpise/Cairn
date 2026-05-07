# Cairn — Quickstart

## 1. Flutter app

```bash
cd apps/cairn_mobile
flutter pub get
flutter analyze
flutter test
```

### Run on Android

Production/default runtime uses `flutter_gemma` with Gemma 4 LiteRT-LM
artifacts:

```bash
cd apps/cairn_mobile
flutter run -d <android-device-id>
```

Optional LiteRT-LM MTP bridge:

```bash
cd apps/cairn_mobile
flutter run -d <android-device-id> --dart-define=INFERENCE_RUNTIME=native_mtp
```

### Run on web

```bash
cd apps/cairn_mobile
flutter config --enable-web
flutter run -d chrome --web-browser-flag=--enable-unsafe-webgpu
```

## 2. Python tooling

```bash
cd scripts
python3 -m venv .venv
. .venv/bin/activate
pip install -e .
PYTHONPATH=. pytest -q
```

Optional extras:

```bash
pip install -e '.[ollama]'
pip install -e '.[gemini]'
pip install -e '.[audio]'
pip install -e '.[finetune]'
```

## 3. Gemma 4 model policy

The app strictly permits only Gemma 4 LiteRT-LM models:

- `litert-community/gemma-4-E2B-it-litert-lm`
- `litert-community/gemma-4-E4B-it-litert-lm`

The guard tests live in:

```bash
cd apps/cairn_mobile
flutter test test/model_registry_platform_test.dart
```

## 4. Locked artifacts

Do not edit without an intentional schema/prompt migration:

- `docs/prompts/system_prompt_v1.txt`
- `apps/cairn_mobile/assets/prompts/system_prompt_v1.txt`
- `docs/schema/evidence_packet_v1.schema.json`
- `apps/cairn_mobile/assets/schema/evidence_packet_v1.schema.json`
- `data/seeds/dialogues.seed.jsonl`
