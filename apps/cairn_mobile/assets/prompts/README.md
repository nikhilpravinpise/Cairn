# Asset bundle for the app

- `system_prompt_v1.txt` — symlink / build-copy of
  `/docs/prompts/system_prompt_v1.txt`. Do **not** edit in place here; the
  build script `tool/sync_assets.sh` copies the canonical file before
  `flutter run`.
- `assets/images/s2_probe.jpg` — one IDEA sample image used by the S2 spike.
  Place it by hand (dataset license).
