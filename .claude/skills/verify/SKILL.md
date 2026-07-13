---
name: verify
description: Build, run, and drive EasyMusic in the iOS Simulator to verify changes end-to-end.
---

# Verifying EasyMusic changes

## Build
```sh
xcodebuild -scheme EasyMusic -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Drive the UI
The surface is the iOS Simulator. `simctl` has no tap/drag primitives, so drive flows
with an XCUITest in `EasyMusicUITests/` (the project uses synchronized folder groups —
just drop a `.swift` file in that directory, no pbxproj edit needed).

```sh
xcodebuild test -scheme EasyMusic \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO \
  -only-testing:EasyMusicUITests/<Class>/<test>
```

- **`-parallel-testing-enabled NO` is required** — otherwise the test runs on a *cloned*
  simulator with its own data container, and external `simctl` screenshots/defaults
  target the wrong device.
- Pre-boot the target device (`xcrun simctl boot <UDID>; xcrun simctl bootstatus <UDID> -b`).

## Capturing mid-gesture evidence
XCUITest can't screenshot during its own drag. Run a background loop before the test:
```sh
for i in $(seq -w 1 300); do xcrun simctl io <UDID> screenshot frames/f$i.png; sleep 0.4; done
```
and give the gesture a hold window: `coordinate.press(forDuration: 0.3, thenDragTo: end,
withVelocity: XCUIGestureVelocity(rawValue: 60), thenHoldForDuration: 2.0)`. Match frames
to the test's NSLog timestamps via file mtimes.

## Gotchas
- Existing flow driver: `EasyMusicUITests/JamResizeDriverTests.swift` (navigate to JamView,
  resize-mode drags, geometry assertions). Reuse its helpers.
- The simulator may be in **landscape**: `app.frame.width` is the full screen, but JamView's
  `GeometryReader` width excludes safe-area insets (~62pt/side on iPhone 17). Derive the
  inset from a known layout state instead of assuming 0.
- `@AppStorage("jamHorizontalPadding")` **persists between test runs** — normalize state
  (e.g. drag to a clamp) before measuring, or reset the app container.
- Jam key labels collide with the navigation title (both show the key's root note);
  filter static texts by `frame.minY > 150`.
- Navigating Instrument → Key loads a ~325 MB SoundFont; use generous `waitForExistence`
  timeouts (15s).
