# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Public repository preparation: community health files, CI workflows, issue templates, and documentation overhaul.

## [0.1.0] - 2026-06-14

### Added
- Initial public release of Cairn.
- **Model enforcement**: Gemma 4 only. Approved models are `gemma-4-E2B-it` and `gemma-4-E4B-it` LiteRT-LM artifacts from `litert-community`.
- **MTP (Multi-Turn Prompting / speculative decoding)**: enabled by default via `flutter_gemma` for ~33% faster decode speed.
- **Model registry**: `litert-community/gemma-4-E2B-it-litert-lm` and `litert-community/gemma-4-E4B-it-litert-lm` with E2B/E4B size class support.
- **EvidencePacket v1 schema**: structured JSON schema for photos, audio observations, deterministic triage, and PDF report generation.
- **Locked system prompt**: `system_prompt_v1.txt` with strict contract rules (max 3 sentences, max 60 words, 1–4 model tags).
- **Contract validation**: `GemmaOrchestrator` validates tags, media refs, bounding boxes, confidence, tool shape, and triage ownership before persisting model output.
- **Deterministic scoring**: Dart computes final priority score and band; the model describes evidence but does not assign priority.
- **657 Flutter tests** covering model registry, session configs, orchestrator, validators, and UI flows.
- **Python test suite** for mirrored constants, schema, prompts, and data tooling.
- **On-device optimization**: bounded 640 px image preprocessing, native Android JPEG sidecar preprocessing, sequential per-photo inference to avoid cross-photo contamination.
- **FEMA P-154 Level 1** sidewalk screening workflow with location, building context, required exterior photos, optional audio notes, and protocol answers.
- **PDF report generation** for handoff and escalation.
- **Privacy-first design**: no telemetry, no crash reporting, no analytics; all capture stays on device.
