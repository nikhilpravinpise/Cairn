# Demo Video Script

Target length: 2:45 to 3:00.

Tone: cinematic but grounded. Show a real workflow, not a feature tour. The story is "trusted information when the network is gone."

## Title

Cairn: The first packet after the quake

## Shot list and narration

### 0:00-0:12 — Cold open

Visual:

- Black screen.
- Phone vibration sound.
- Quick cuts: cracked wall, blocked street, volunteer putting phone into airplane mode, hand opening Cairn.

Voiceover:

> After an earthquake, the first question is simple: which buildings need help first?
> But the network may be down, inspectors are overwhelmed, and every minute creates more uncertainty.

On-screen text:

> Offline. Private. Structured.

### 0:12-0:28 — The human problem

Visual:

- Volunteer outside a damaged building.
- Phone camera frames exterior, ground floor, foundation, visible cracks.
- No dramatic rescue footage. Keep it practical and field-real.

Voiceover:

> Cairn is built for trained volunteers doing rapid exterior screening. It does not replace an engineer. It turns field observations into evidence that can be reviewed.

On-screen text:

> Preliminary screening only

### 0:28-0:48 — Start the app

Visual:

- Cairn onboarding / scope screen.
- Start screening.
- Location and building metadata.

Voiceover:

> The workflow follows a FEMA P-154-style Level 1 sidewalk screening flow: location, building context, required photos, optional notes, protocol answers, and a final handoff packet.

On-screen text:

> Guided collection

### 0:48-1:15 — Capture evidence

Visual:

- Required photo grid: front, ground floor, foundation, cracks.
- Show thumbnails filling in.
- Brief airplane mode indicator or no-network state.

Voiceover:

> The app asks for the evidence that response teams actually need. Every photo is tied to a specific observation, so the final packet is not just a summary. It is traceable.

On-screen text:

> Each observation stays linked to its photo

### 1:15-1:45 — Gemma 4 on device

Visual:

- Tap "Describe photos."
- Loading/progress state.
- Results appear with tags and confidence.
- Show "diagonal crack", "soft story indicator", "concrete spalling", or similar.

Voiceover:

> Gemma 4 runs on the device through LiteRT-LM. It reads the photos and produces structured observations. The model can describe evidence, but it is not allowed to assign final priority.

On-screen text:

> Gemma describes. Cairn verifies.

### 1:45-2:08 — Trust boundary

Visual:

- Simple architecture animation or static diagram.
- Gemma output passes through contract validation.
- Invalid output rejected.
- Dart scoring computes priority.

Voiceover:

> Cairn treats AI output as untrusted until it passes a strict contract: known tags only, valid media references, bounded boxes, confidence ranges, and no model-owned triage score. The final priority band is computed deterministically in Dart.

On-screen text:

> Contract validation + deterministic triage

### 2:08-2:32 — Final report

Visual:

- Triage screen with colored band.
- Rationale bullets.
- Uncertainty notes.
- PDF export / evidence packet.

Voiceover:

> The result is a sealed evidence packet: photos, observations, protocol answers, model metadata, uncertainty notes, and a PDF that can be handed to a coordinator or engineer.

On-screen text:

> From scattered photos to an auditable packet

### 2:32-2:52 — Why it matters

Visual:

- Volunteer walks to next building.
- Map/list of saved screenings.
- Calm closing shot of phone in hand.

Voiceover:

> Resilience is not only prediction. It is the ability to keep making careful decisions when infrastructure is damaged. Cairn brings local Gemma 4 intelligence to that moment.

On-screen text:

> Built for Global Resilience

### 2:52-3:00 — Close

Visual:

- Logo/title card.
- GitHub / Kaggle links.

Voiceover:

> Cairn: offline building triage with Gemma 4.

On-screen text:

> Cairn
> Offline building triage with Gemma 4

## Recording notes

- Record a real phone screen, not only simulator footage.
- Show airplane mode or no-network state for at least one clear second.
- Show the final PDF/report in the same take if possible.
- Keep all claims careful: "preliminary screening", "evidence packet", "trained volunteer", "review by coordinator or engineer".
- Avoid saying "safe", "unsafe", "red tag", "official inspection", or "life-safety decision".
- Use captions. Judges often skim videos muted.

## Music and pacing

- Low, urgent pulse for first 20 seconds.
- Quiet, confident rhythm during workflow.
- No triumphant disaster-movie tone.
- Use natural field sounds: footsteps, shutter click, phone tap, subtle radio static.
