# Contributing to Cairn

Thank you for your interest in contributing. This document covers setup, workflow, and the policies that keep Cairn safe for disaster-response use.

## Development environment

1. **Flutter** ≥3.22 (stable channel)
2. **Android SDK** with command-line tools and `adb`
3. **Python** ≥3.11
4. **Git** with a GitHub account
5. **Model file** — download a Gemma 4 LiteRT-LM `.task` file and push it to your test device (see `README.md` → Model download)

### Quick validation

```bash
# Flutter
cd apps/cairn_mobile
flutter pub get
flutter analyze
flutter test

# Python
cd scripts
pip install -e .
PYTHONPATH=. pytest -q
```

## Branching and pull requests

- Create feature branches from `main`.
- Open a pull request against `main`.
- All PRs must pass the checklist in the PR template.
- Force-push to `main` is not allowed.

## PR checklist (enforced by maintainer review)

- `flutter analyze` passes
- `flutter test` passes (all 657+ tests)
- `cd scripts && pytest -q` passes
- No raw bench logs or model files are committed
- Locked artifacts (see below) are not changed without a migration note
- `CHANGELOG.md` is updated if the change is user-facing

## Locked artifacts policy

The following files are considered locked. Do not edit them without an explicit migration plan and maintainer approval:

- `docs/prompts/system_prompt_v1.txt`
- `docs/schema/evidence_packet_v1.schema.json`
- `docs/prompts/system_prompt_v1.md`

These artifacts directly affect model behavior and packet compatibility. Changes require:
1. A version bump in the schema or prompt filename
2. Corresponding test updates
3. A record in `CHANGELOG.md`

## Commit message style

Use imperative mood, lowercase subject, and match the existing history style:

```
feat: add priority band validation for soft-story tags
fix: reject bounding boxes with negative width
chore: update flutter_gemma to 0.15.0
docs: clarify model download steps in README
```

## Attribution and licensing

Cairn is released under the Apache-2.0 License. By contributing, you agree that your contributions will be licensed under the Apache-2.0 License. No separate DCO or CLA is required; standard Git commit attribution is sufficient.

## Questions?

Open a discussion on GitHub or reach out via the issue tracker.
