# Legal & licensing notes

## What Cairn is
A **preliminary screening aid** that helps a non-expert volunteer perform a
**FEMA P-154 Level 1 "Sidewalk Survey"** after an earthquake, and produces a
structured `EvidencePacket` for a licensed engineer to triage.

## What Cairn is not
- **Not** an ATC-20 placard. Cairn output never says "green", "yellow", or "red tag".
- **Not** a structural-engineering determination.
- **Not** a re-occupancy authorization.
- **Not** a life-safety instruction to occupants.

## Disclaimer (shipped in-app on every screen + on the PDF + on every packet)
> "I am not a licensed engineer. This is preliminary screening only."

## Licenses

### Code
Apache-2.0 (`LICENSE`).

### Synthetic dialogue dataset (produced by us)
CC-BY-4.0, released on HF Hub with attribution to FEMA P-154 for the protocol
vocabulary.

### LoRA adapters (Phase A / Phase B)
Gemma Terms of Use — we inherit the base model's license. Adapters shipped under
Gemma Terms with an additional README pointing at Google's license.

### Datasets we consume
| dataset | license | how we use it |
|---------|---------|---------------|
| IDEA (Zenodo 15120522) | CC variant not yet confirmed; redistribution withheld pending verification | fine-tune + eval only; we do not redistribute |
| PEER Φ-Net            | CC BY-NC-SA 4.0 | fine-tune + eval only (non-commercial); we do not redistribute |
| EERI LFE archive      | per-photo verified | video B-roll + qualitative eval only |
| FEMA P-154            | public domain (US Government work) | protocol vocabulary |
| USGS ShakeMap         | public domain | optional prefill |

## Data handling
- All capture stays **on device**. Packets are not uploaded anywhere by default.
- "Share packet" produces a local `.cairn.json` + attachments zip the user chooses to
  share.
- No telemetry, no crash reporting, no analytics in v1.
