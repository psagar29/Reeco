# Recco iOS (Person D)

The camera-first Voice Brain demo shell. Pure SwiftUI, **no external package
dependencies**, so it always builds and runs offline for the demo.

## Run

```bash
open app/ios/Recco/Recco.xcodeproj
# Select the "Recco" scheme + an iPhone simulator, then ⌘R.
```

Or from the command line:

```bash
xcodebuild -project app/ios/Recco/Recco.xcodeproj \
  -scheme Recco \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

The app launches into the **stage-safe `mockAll` mode**: local roster from the
bundled `people.sample.json`, on-device command parsing, and on-device opener
generation. No backend or network required.

## What's here (Person D scope)

- **`Recco/Models/`** — DTOs matching `docs/API_CONTRACTS.md`: `PersonDTO`,
  `BrainStateDTO`, `FilterCommandDTO`, `FaceMatchResultDTO`, `DraftResultDTO`,
  plus `DemoMode`.
- **`Recco/State/AppModel.swift`** — the single shared, observable app model
  (roster, `BrainState`, demo mode, draft, command pipeline).
- **`Recco/State/`** — pure engines: `CommandInterpreter` (NL → command),
  `FilterEngine` (command → visible/dimmed), `OpenerGenerator`, `RosterStore`,
  `TagVocabulary`, and the `ReccoBackend` protocol with `MockBackend` /
  `ConvexBackend` (live placeholder).
- **`Recco/Views/`** — camera placeholder, control strip (transcript ribbon +
  chips + typed/voice command bar), Brain radial graph, profile sheet, draft
  opener panel, demo-mode picker.

## Demo modes

| Mode      | Backend          | CV match        | Use when            |
|-----------|------------------|-----------------|---------------------|
| `mockAll` | none (local)     | fake            | default / recovery  |
| `mockCV`  | Convex           | deterministic   | backend up, CV down |
| `live`    | Convex + CV      | real            | everything works    |

Switch live from the **demo-mode badge** in the top bar. Override the launch
default with the `DEMO_MODE` env var (`mockAll|mockCV|live`) and set `CONVEX_URL`
for the backend modes.

## Single command path

Manual chips, the typed command bar, and the voice quick-pick all produce a
`FilterCommandDTO` and funnel through `AppModel.apply(_:)`, which recomputes the
shared `BrainState`. Camera overlays and the Brain graph both read that one
state, so they always agree.

## Person C integration (camera)

`CameraPlaceholderView` is a stand-in for Person C's real camera. The stable
seam is documented in `app/ios/Recco/Camera/README.md`:

```swift
appModel.peopleById[personId]
appModel.state.visiblePersonIds      // drive overlay dimming
appModel.state.dimmedPersonIds
appModel.selectPerson(personId)      // open profile on overlay tap
appModel.applyMatch(faceMatchResult) // feed recognition results in
```

Swapping the placeholder for the real camera requires no changes elsewhere.
