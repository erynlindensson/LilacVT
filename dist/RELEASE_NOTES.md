# OpenVT v0.1.3 — Linux x86_64

- Artifact: `open-vt-0.1.3-linux-x86_64.tar.gz`

## Changes

- **VRM face tracking** via OpenSeeFace (Start/Stop Tracking; no auto-start).
- **VRM Expressions** — standard blendshapes in Set Expression (exclusive apply).
- **VRM Poses** — Set Pose next to Expressions (Neutral, Wave, HandsOnHips, ArmsCrossed, Thinking, Point).
- **Lighting** controls in the Items panel (color HSV wheel + intensity).
- **Opaque background by default**; toggle under Camera → Transparent Background.
- VRM import/discovery, stage lighting, look-axis fix, and related UI polish.

## Smoke

- [ ] Rest OK
- [ ] Start Tracking → head/mouth follow; Stop Tracking kills process
- [ ] Set Expression clears previous morphs
- [ ] Set Pose → HandsOnHips looks correct; head tracking still works
- [ ] Transparent Background toggle works both ways
