# Publish Cleanup Checklist

## Done in this cleanup pass

- Removed raw benchmark logcats and test-run text files from tracked files.
- Kept `apps/cairn_mobile/bench_out/RESULTS.md` as the publishable benchmark summary.
- Ignored future `bench_out/*.txt` raw logs.
- Updated README and Quickstart references away from the blocked `native_mtp` publish path.
- Aligned Python prompt-sync test with the locked `1 to 4 values` prompt constraint.

## Before recording

- Run `flutter analyze`.
- Run `flutter test`.
- Run `cd scripts && uv run pytest -q tests`.
- Build a profile or release APK with:

```bash
cd apps/cairn_mobile
flutter build apk --profile \
  --dart-define=BENCH_IMAGE_PX=640 \
  --dart-define=BENCH_NATIVE_IMAGE_PREPROCESS=true
```

MTP is requested by default through `flutter_gemma`. Use `--dart-define=BENCH_MTP=false` only for A/B debugging.

## Before Kaggle submission

- Replace placeholder links in `docs/submission/project_writeup.md`.
- Add final YouTube URL.
- Add GitHub Release URL.
- Add screenshots and thumbnail.
- Verify Kaggle writeup URL slug is under 50 chars.
- Verify title is under 80 chars.
- Verify subtitle is under 140 chars.

## Git history note

Do not rewrite public `main` history unless the whole team agrees. The safer cleanup is a normal commit that removes raw logs and updates publishing docs. If a completely clean history is required for public release, create a fresh release branch or squash-merge into a new public repository after preserving tags and attribution.
