# Play Store Plan

## Is Play Store publishing required?

No. For the Kaggle writeup, a public code repo, working demo evidence, video, and accessible build/demo link are the important deliverables. A Play Store listing can improve credibility, but it should not block submission.

## Recommendation for this deadline

Use this order:

1. Submit a GitHub Release APK or Android App Bundle link.
2. Record the demo on the real target device.
3. If the Play Console account is already ready, publish to internal testing.
4. Do not wait for public Play Store review before submitting Kaggle.

## Why not block on Play Store

- New Play Console accounts and review flows can take longer than the remaining schedule.
- A public listing requires store graphics, privacy policy, data safety declarations, content rating, app signing, release notes, and possible review back-and-forth.
- The model artifact path and offline setup may need clear reviewer instructions.
- Kaggle judges need to understand and test the project, not install from the public store specifically.

## Best practical demo link

Preferred:

- GitHub Release containing:
  - signed APK or AAB
  - build instructions
  - model artifact setup note
  - known device requirements

Nice to have:

- Play Store internal testing link, if already available.

Do not publish a broad public Play listing unless the app has passed the manual UX flow and legal wording review.

## Store listing draft

**App name**  
Cairn

**Short description**  
Offline post-earthquake building screening packets with Gemma 4.

**Full description**  
Cairn helps trained volunteers collect structured exterior building observations after an earthquake or similar structural hazard. It guides photo capture, runs Gemma 4 on-device to describe visible evidence, validates model output against a strict schema, computes deterministic preliminary priority, and exports an evidence packet for review.

Cairn is a prototype screening aid. It is not an official inspection tool, not an ATC-20 placard, and not a substitute for a licensed structural engineer or local authority.

**Data safety summary**  
Photos, notes, and generated packets are stored locally by default. The prototype is designed for offline operation. Do not enter sensitive personal information.

## Release checklist

- App name and icon verified.
- Package ID stable: `app.cairn.cairn_mobile`.
- Legal disclaimer visible in onboarding and report.
- Signed release build created.
- Model setup instructions documented.
- Demo scenario verified on the target Android device.
- Privacy policy URL available if using Play Console.
- Screenshots prepared from real device.
