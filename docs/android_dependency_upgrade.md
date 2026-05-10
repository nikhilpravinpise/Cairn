# Android Dependency Upgrade Process

Use this process for inference/runtime dependency bumps.

1. Change exactly one version at a time, for example
   `com.google.ai.edge.litertlm:litertlm-android`.
2. Run:

   ```bash
   cd apps/cairn_mobile
   flutter pub get
   flutter analyze lib test tool/api_probe.dart
   flutter test
   flutter build apk --debug --no-pub
   ```

3. Run the Android profile benchmark on the same device and curated scenarios:

   ```powershell
   .\tool\benchmark_android_speed.ps1 -DeviceId <DEVICE_ID> -OutDir <OUT_DIR>
   ```

4. Commit only when the benchmark output records:
   - `phase=engine_create`
   - `phase=image_preprocess`
   - `phase=generate`
   - `phase=parse_contract`
   - zero schema failures in the dev scenario export

Do not use dynamic Gradle versions such as `latest.release`; they make build
times and runtime behavior non-reproducible.
