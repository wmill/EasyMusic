# EasyMusic

A SwiftUI iOS app (deployment target **17.6**) for learning/jamming music without the physicality of a
traditional instrument. The user picks an **instrument**, then a **musical key**, and is presented with the
7 notes of that key across 3 octaves as large colored buttons — so every button is "in key" and chords are
visually obvious. See `README.md` for the product vision.

## Build & run

Single Xcode project, one app scheme:

```sh
xcodebuild -scheme EasyMusic -destination 'platform=iOS Simulator,name=iPhone 17' build
```

(Use whatever simulator is installed — `iPhone 17` is current here; `iPhone 16` is not available.)

Targets: `EasyMusic` (app), `EasyMusicTests` (unit), `EasyMusicUITests` (UI). The test files are still the
Xcode boilerplate — no meaningful coverage yet.

## Architecture — it's (almost) all one file

Essentially the entire app lives in **`EasyMusic/ContentView.swift`**. There is no `JamView.swift` etc.;
models, audio, and every view are in that one file. `EasyMusicApp.swift` is just the `@main` entry point.

Navigation is a 3-step `NavigationStack` driven by `AppModel` (`@Published selectedInstrument`, `selectedKey`):

`InstrumentSelectionView` → `KeySelectionView` → `JamView`

Key pieces in `ContentView.swift`:

- **Musical model** — `MusicalKey` (enharmonic spelling via `semitoneOffsetFromC`), `Scale.majorIntervals`,
  `PlayableNote`, `PianoKey`. MIDI note math lives in `JamView.midiNote(for:degree:octave:)`.
- **Audio** — `SamplerAudioEngine` wraps `AVAudioEngine` + `AVAudioUnitSampler`, loading `.sf2` SoundFonts.
  A single engine instance is created in `ContentView` and passed down; `play`/`stop` take MIDI notes.
- **Instruments** — `InstrumentCatalog` loads `EasyMusic/instruments.json` (list of `{program, name}`
  General MIDI presets) into the instrument list.
- **`JamView`** — the main play surface: 3 rows × 7 `PressableKey`s, plus an optional `PianoKeyboardView`
  and a width-resize feature (see below).

## Assets

- `EasyMusic/instruments.json` — General MIDI preset names shown in `InstrumentSelectionView`.
- Two bundled SoundFonts: `GeneralUser-GS.sf2` (default at startup) and
  `SGM-v2.01-NicePianosGuitarsBass-V1.2.sf2` (loaded when a preset is chosen). The SGM file is ~325 MB, so
  the repo is large; be mindful with clones/commits.

## JamView width-resize feature (recent work)

`JamView` lets the user narrow the colored key grid by increasing horizontal padding, persisted via
`@AppStorage("jamHorizontalPadding")` (clamped so the grid never gets narrower than `minimumJamWidthRatio`
= 0.5 of available width).

- **`JamResizeButton`** (bottom-right corner, `arrow.left.and.right.square.fill` icon) toggles resize mode
  with a single tap; turns green while active. The settings gear sits at the bottom-left corner.
- While unlocked, two **`JamResizeHandle`** bars are overlaid on the key grid (leading/trailing) and dragged
  via `resizeGesture(edge:availableWidth:)`. Handles are sized to `jamGridHeight` and overlaid on the grid
  container so they stay vertically aligned with the keys regardless of the piano keyboard's presence.
- While dragging (`isDraggingJamWidth`, derived from `draggingPadding != nil`), the real key grid is swapped
  for **`JamKeyPlaceholderGrid`** (cheap translucent `Color.primary` boxes — must stay visible in both light
  and dark mode) to keep resizing smooth. Placeholder boxes and real keys share the `jamKeyMinHeight`
  (= 80) constant and matching corner radius / spacing so the placeholder matches the final shape.
- The drag gesture measures translation in `.global` coordinate space (the handles move with the grid edge,
  so `.local` would feed back into itself and oscillate), holds the in-flight value in `@State draggingPadding`,
  and writes `@AppStorage jamHorizontalPadding` once on drag end. `EasyMusicUITests/JamResizeDriverTests.swift`
  covers this flow end-to-end.

Shared layout constants live at file scope (`jamKeyMinHeight`) or as `JamView` computed props
(`jamGridHeight`). Key visual constants: key `cornerRadius` 16, row/column spacing 16.
