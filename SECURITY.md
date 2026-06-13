# Security Policy

## Supported versions

Only the latest commit on `main` is supported for security updates. Cairn does not maintain versioned release branches at this stage.

## Reporting a vulnerability

Please report security vulnerabilities **privately** via [GitHub Security Advisories](https://github.com/N1KH1LT0X1N/cairn/security/advisories/new).

Do not open public issues for security bugs. We will respond within 5 business days and work with you to validate, fix, and disclose the issue responsibly.

## Scope

Cairn's production security surface is intentionally small:

- **On-device only**: All inference, photo storage, and packet generation happen locally on the Android device. There is no server-side component, no cloud API, and no telemetry in the production path.
- **Network surface**: The app does not open listening ports or make outbound network requests during triage workflows. Optional map tiles and share actions use standard Android intents (user-initiated, outbound only).

## Out of scope

The following are considered out of scope for security advisories:

- **Model quality issues**: Incorrect triage tags, hallucinated observations, or low-confidence outputs are safety/accuracy concerns, not security vulnerabilities. Please open a standard issue instead.
- **Upstream LiteRT or flutter_gemma bugs**: Vulnerabilities in the underlying inference engine or Flutter plugin should be reported to their respective maintainers (Google / LiteRT team, flutter_gemma publisher).
- **Device compromise**: We assume the Android OS and user data partition are reasonably secured by the device vendor. Physical-access or rooted-device attacks are out of scope.
- **Third-party dependencies**: Vulnerabilities in Flutter, Dart, or Android SDK packages should follow the upstream disclosure process.

## What we commit to

- We will acknowledge receipt of a valid report within 5 business days.
- We will validate the issue and provide a timeline for a fix or mitigation.
- We will publicly credit reporters who wish to be named (with their consent) in the release notes or `CHANGELOG.md`.
- We will not take legal action against good-faith security research.

## History

No security advisories have been issued to date.
