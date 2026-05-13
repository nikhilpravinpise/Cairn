# Cairn Mac Developer Setup Guide

Test the app without a physical phone using the Android emulator or the Flutter
web target.  All commands assume the terminal is open at the repo root unless
stated otherwise.

---

## 1. Prerequisites

### 1a. Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 1b. Flutter SDK

```bash
brew install --cask flutter
flutter doctor
```

If `flutter doctor` reports Xcode issues, run:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

### 1c. Android Studio

1. Download from <https://developer.android.com/studio> and drag to
   `/Applications`.
2. Open Android Studio → **Settings → SDK Manager → SDK Tools** tab.
   Install:
   - Android SDK Build-Tools (latest)
   - Android SDK Command-line Tools (latest)
   - Android Emulator
   - Android Emulator hypervisor driver (for Apple Silicon, select the
     **HAXM** / **hypervisor** option that matches your chip)
3. Accept all licences:
   ```bash
   flutter doctor --android-licenses
   ```

### 1d. Java

Android Studio bundles a JDK.  Point Flutter at it:

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
echo 'export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"' >> ~/.zshrc
```

---

## 2. Create an Android Virtual Device (AVD)

1. Open Android Studio → **Device Manager** (right-side panel) → **+**.
2. Pick **Pixel 8** (or any `x86_64` phone category).
3. Select a system image — **API 35, x86_64, Google Play** is recommended.
   Download it if not present.
4. Finish — name it something recognisable (e.g. `Pixel8_API35`).
5. Start the AVD:
   ```bash
   emulator -avd Pixel8_API35
   ```
   Or use the green play button in Device Manager.

> **Apple Silicon note**: ARM images (arm64-v8a) run faster on M-series Macs
> but most Google Play images are still x86_64.  For pure Flutter UI testing
> either architecture works.

---

## 3. Verify Flutter sees the emulator

```bash
flutter devices
```

Expected output includes a line like:

```
sdk gphone64 x86 64 (mobile) • emulator-5554 • android-x64 • Android 15 (API 35)
```

---

## 4. Run on the emulator

```bash
cd apps/cairn_mobile
flutter pub get
flutter run -d emulator-5554
```

For the production-like profile build (no debug overhead):

```bash
flutter run --profile -d emulator-5554
```

> **Model file caveat**: The Gemma 4 `.litertlm` model is ~4 GB and must be
> downloaded by the app at first launch.  On an emulator this download goes to
> the virtual device's storage.  The first run will be slow; subsequent runs
> reuse the cached file.  If you only want UI/navigation testing without a
> model, skip the "Load model" step on the Start screen — the rest of the UX
> is fully exercisable.

---

## 5. Run on the Flutter web target (fastest iteration, no model)

The web build does not support LiteRT-LM inference (browser
`ArrayBuffer` limit is ~2 GB; the model is 4 GB).  It is useful for
navigation, theming, form UX, and photo/audio capture stub flows.

```bash
cd apps/cairn_mobile
flutter run -d chrome
```

The app boots to the Start screen.  The "Load model" button will spin and
never complete on web, but every other screen (photos, protocol, report,
saved screenings) is reachable.

---

## 6. Run the test suite

```bash
cd apps/cairn_mobile
flutter analyze lib test tool/api_probe.dart
flutter test --no-pub
```

Expected: `No issues found` from analyze, `All tests passed` (634 tests) from
the test runner.

---

## 7. Build a debug APK (without a connected device)

```bash
cd apps/cairn_mobile
flutter build apk --debug --no-pub
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.  You can
drag-install it onto an emulator:

```bash
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
```

---

## 8. Useful `adb` commands

```bash
# List connected devices (emulator + real)
adb devices

# Stream logcat filtered to Cairn tags
adb logcat -s flutter Cairn

# Push a model file to the emulator documents directory
adb -s emulator-5554 push /path/to/gemma-4-e2b-it.litertlm \
    /data/local/tmp/

# Pull benchmark output off device
adb pull /sdcard/Download/bench_out ./bench_out_local
```

---

## 9. Common issues

| Symptom | Fix |
|---|---|
| `HAXM not installed` on Intel Mac | Install HAXM from SDK Manager → SDK Tools |
| Emulator very slow on Apple Silicon | Use an ARM64 system image instead of x86_64 |
| `flutter doctor` shows Android toolchain ✗ | Run `flutter doctor --android-licenses` |
| `Gradle build failed` | Check `JAVA_HOME` points to Studio's bundled JDK |
| `MissingPluginException` on web | Expected — native plugins (camera, path_provider) are no-ops on web |
| App crashes on model load | Normal on emulator — LiteRT GPU/NPU delegate requires real hardware; the CPU fallback works but is very slow |

---

## 10. Benchmark note

Speed benchmarks **must** use a real Samsung S23 FE (or equivalent Exynos device)
in profile or release mode.  Emulator numbers are not representative — the
CPU-only LiteRT path on an x86 emulator can be 10–50× slower than GPU
inference on device.  See `docs/s23_fe_benchmark_guide.md` for the full
benchmark matrix.
