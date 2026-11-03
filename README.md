# BrushWatch

An iPhone prototype that notices when a Philips Sonicare (for Kids) toothbrush is switched on, over Bluetooth LE.

## How it works

- The brush sleeps when idle and **starts advertising over BLE when it wakes** (picked up or button pressed).
- The app scans continuously in the foreground. While the chosen brush has been seen in the last 4 seconds → **BRUSH ON**; when it goes quiet → **off**, with the awake duration logged.
- The **ⓘ Explore** sheet connects to a device, subscribes to every notify characteristic and shows raw hex values. Values that just changed turn orange. Use it to find which characteristic reports brushing state and the timer (Sonicare services start with `477EA600-A260-11E4-AE37-0002A5D5…`).

## Run it

```bash
brew install xcodegen   # if needed
xcodegen generate
open BrushWatch.xcodeproj
```

Pick your iPhone as the run destination and press ⌘R. Bluetooth does not work in the Simulator.

1. Turn the brush on. A device marked 🪥 should appear at the top of the list.
2. Tap it to select it. The card turns green while the brush is awake.
3. Close the official Philips app first, because the brush accepts only one connection at a time.

## Known limits

- Scanning only works fully in the **foreground**. In the background, iOS needs a service-UUID filter and slows the scan rate.
- While Explore is connected, the brush stops advertising. The app treats the open connection as "on".
