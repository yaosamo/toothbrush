# BrushWatch

A kids' brushing game for iPhone. A panda in a 3D Chinese temple courtyard reacts to a real Philips Sonicare toothbrush over Bluetooth LE and earns achievements for good brushing.

<img src="docs/temple.png" width="300">

## How it works

- **Brush detection.** The app stays connected to the selected brush and reads its handle state (`…4010`), brushing state (`…4082`) and brushing time (`…4090`). It counts as brushing when the handle state is *run* or the brushing state is *on*. The Sonicare map comes from community reverse engineering ([mtheli/philips_sonicare_ble](https://github.com/mtheli/philips_sonicare_ble)). The newer "Condor" protocol brushes (Kids HX6600, Series 7100) aren't supported yet, and the app says so.
- **3D scene.** Built with RealityKit + SwiftUI (`RealityView`, virtual camera). The panda is rigged. `PandaDirector` cuts these clips from its single USDZ timeline: Idle, Wave, Yes, Jump, Chop_Loop (played while brushing) and Punch (on tap).
- **Achievements.** `Achievements.swift` defines first brush, 2 minutes, morning + evening, 3- and 7-day streaks, 10 sessions and 30 sessions. Sessions under 10 s are ignored. Progress is saved in UserDefaults.

## Run it

```bash
xcodegen generate
open BrushWatch.xcodeproj     # pick your iPhone, ⌘R
```

Tap the status pill (top left) to pick your brush, and close the Philips app first. The **Simulate brushing** switch in that sheet drives the panda without a brush. Launching with the `-simulateBrushing` argument starts a fake session automatically.

## Models

| Model | Author | License |
|---|---|---|
| Panda (rigged, ~30 animations) | Quaternius | CC0 |
| Pavilion, Pagoda | Poly by Google | CC-BY 3.0 |
| Red Lantern | Sophie Kim | CC-BY 3.0 |

All were downloaded from poly.pizza as GLB and converted to USDZ with `tools/convert.py`. The script also scales each model to real-world metres and lays out the chosen animations end to end:

```bash
blender -b --python tools/convert.py -- panda.glb BrushWatch/Models/Panda.usdz 1.0 Idle Wave Yes Jump Chop_Loop Punch
```

If you change the panda's clip list, copy the printed frame ranges into `PandaDirector.ranges`.
