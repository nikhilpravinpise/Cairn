# Cairn: Offline Building Triage with Gemma 4

## One-sentence summary

Cairn is an offline-first Android app that helps trained volunteers collect post-earthquake building evidence, run Gemma 4 on-device, and produce an auditable FEMA P-154-style triage packet without sending photos or notes to the cloud.

## Project description

After a major earthquake, the first shortage is not always concrete, steel, or trucks. It is trusted information. Streets fill with people asking the same urgent question: is this building safe enough to approach, avoid, or escalate?

Professional engineers and official inspectors are limited. Volunteers, neighborhood responders, and local organizations often arrive first, but they need a workflow that is structured, private, and honest about its limits. Cairn is built for that gap.

Cairn turns a phone into a field screening companion for FEMA P-154 Level 1 sidewalk-style observations. The app guides a volunteer through a fixed collection flow: location, building context, required exterior photos, optional audio notes, protocol answers, AI-assisted observations, deterministic triage, and a sealed evidence packet. It is not an ATC-20 placard, not an engineering determination, and not a replacement for a licensed structural assessment. Its job is narrower and more useful during the first hours of response: collect consistent evidence, summarize visible risk indicators, and produce a packet that can be reviewed, shared, and escalated.

The system uses Gemma 4 locally through LiteRT-LM via `flutter_gemma`. Photos are resized for bounded on-device inference, then Gemma 4 describes visible structural cues such as diagonal cracks, soft-story indicators, spalling, foundation damage, or no visible damage. Every model response must pass a strict JSON contract before it can enter app state. Unknown tags, malformed bounding boxes, unsupported media references, and attempts by the model to assign final priority are rejected.

That last point is central to Cairn's safety design. Gemma does not get to make the final call. Gemma describes evidence. Dart computes the final priority score and priority band deterministically from the structured packet. This separation keeps the model useful while preventing it from becoming an unbounded authority in a high-stakes situation.

## Why Global Resilience

Global resilience is about systems that work when infrastructure is degraded. Cairn is designed for exactly that environment:

- It works from a mobile device, not a command center.
- It preserves privacy by keeping building photos and field notes local.
- It supports low-connectivity response by generating local evidence packets and PDFs.
- It turns scattered volunteer observations into structured, auditable records.
- It uses AI where it is strongest: visual description, protocol assistance, and evidence summarization.
- It keeps risk scoring deterministic, reviewable, and bounded.

The target user is not "everyone." It is a trained volunteer or local responder doing rapid exterior screening after an earthquake, flood, landslide, blast, or other structural hazard event. The target output is not a chatbot answer. It is a portable evidence packet that can be reviewed by response coordinators or engineers.

## How Gemma 4 is used

Cairn uses Gemma 4 for multimodal understanding and structured language generation:

- `describe_photo`: image + task prompt to produce a concise observation JSON object.
- `describe_audio`: optional volunteer audio notes can be converted into structured observations.
- `ask_followup`: protocol-aware follow-up questions when the packet is incomplete.
- `protocol_answer`: maps plain-language responder notes into supported protocol fields.
- `synthesize`: creates rationale bullets and uncertainty notes for the final report.

Gemma 4 is constrained by a locked system prompt, schema validation, and tests that mirror the production schema. The permitted `model_tags` vocabulary is closed. The app validates confidence ranges, media references, bounding boxes, task shape, and priority ownership before observations can persist.

## Architecture

The production path is:

1. Flutter Android app collects location, photos, notes, and protocol answers.
2. Required photos are cached locally and resized before inference.
3. Gemma 4 E2B or E4B LiteRT-LM runs on-device through `flutter_gemma`.
4. `GemmaOrchestrator` builds task prompts and parses model output.
5. Contract validators reject malformed or unsafe responses.
6. Dart computes deterministic priority score and band.
7. Cairn seals an `EvidencePacket` with observations, assets, triage, and metadata.
8. The app generates a PDF report for handoff.

The repo includes guard tests to keep the app Gemma 4-only and to prevent accidental drift in model registry, prompt, schema, and scoring behavior.

## Optimization work

The app was optimized around the bottlenecks that matter on a real phone:

- Bounded image preprocessing at the production 640 px longest-edge target.
- Native Android JPEG sidecar preprocessing to avoid expensive Dart PNG paths.
- LiteRT-LM speculative decoding requested through `flutter_gemma`.
- Concise output rules: maximum 3 sentences, maximum 60 words, and 1 to 4 model tags.
- Sequential per-photo inference to avoid cross-photo contamination.
- Deterministic removal of contradictory `no_visible_damage` tags when concrete damage tags are present.

Recent device gates on a Samsung S23 FE-class Android device confirmed the three structural test scenarios pass with zero schema failures and correct priority bands. Four-photo critical scenario inference remains measured in minutes rather than seconds, but the result is stable, local, private, and auditable. For a disaster screening workflow, correctness and trust boundaries matter more than pretending a cloud-only demo is field-ready.

## What makes it different

Many AI demos answer questions. Cairn produces evidence.

It is opinionated about workflow: collect the right photos, keep observations tied to specific media, reject unsupported model output, compute triage outside the model, and package everything for handoff. The product is designed around a response coordinator asking, "What did the volunteer see, where, with which photo, and why was this building escalated?"

The app also does not oversell itself. Every report frames the output as preliminary screening only. The model is an assistant for consistency and speed, not a structural engineer.

## Current limitations

Cairn is a prototype. It should not be used for official placarding or life-safety decisions without trained review. Model performance varies with photo quality, building type, lighting, and local construction practices. The current implementation focuses on Android and English-first protocol flow. More field testing, language support, and engineering review are required before operational deployment.

Fine-tuning is prepared as a future path, but the submitted app favors a stable on-device base model plus strict contract validation. A domain fine-tune could later reduce prompt length, improve tag accuracy, and lower latency, but only after it passes the same on-device validation gates.

## Impact

Cairn is built for the moment when a city has more damaged buildings than inspectors, more photos than context, and more fear than verified information. It gives volunteers a careful way to collect what they see, gives coordinators a structured packet instead of a chat transcript, and shows how Gemma 4 can support resilience where connectivity, privacy, and trust all matter.

## Suggested links

- Source code: `https://github.com/N1KH1LT0X1N/cairn`
- Demo video: `[Demo video — to be added]`
- Android build: `[Release — to be added]`
- Optional notebook: `[Kaggle notebook — to be added]`
