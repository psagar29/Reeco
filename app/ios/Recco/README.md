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
  `TagVocabulary`, and the `ReccoBackend` protocol with `MockBackend` (offline)
  and `ConvexBackend` (live `URLSession` HTTP client — see below).
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
default with the `DEMO_MODE` env var (`mockAll|mockCV|live`) and set the backend
base URL for the backend modes (see below).

## Backend configuration (live / mockCV)

The live HTTP client lives in `Recco/State/Backend/ConvexBackend.swift`. It uses
plain `URLSession` + `Codable` (no third-party networking) and calls Person C's
HTTP bridge:

| Method                  | Endpoint                  |
|-------------------------|---------------------------|
| `listPeople()`          | `GET  /api/people`        |
| `interpretCommand()`    | `POST /api/voice/interpret` |
| `createOpener()`        | `POST /api/drafts/opener` |
| `matchFace()`           | `POST /api/vision/match-face` |

### Environment variables

| Var                  | Purpose                                                        |
|----------------------|---------------------------------------------------------------|
| `RECCO_API_BASE_URL` | **Preferred** backend base URL (Person C's HTTP bridge).      |
| `CONVEX_URL`         | Fallback base URL if `RECCO_API_BASE_URL` is unset.           |
| `DEMO_MODE`          | Launch mode override: `mockAll` \| `mockCV` \| `live`.         |

Set these in the scheme's **Run → Arguments → Environment Variables**, or from
the command line:

```bash
# mockAll (default — no backend, fully offline)
xcrun simctl launch booted com.recco.app

# live, pointed at Person C's deployed bridge
SIMCTL_CHILD_DEMO_MODE=live \
SIMCTL_CHILD_RECCO_API_BASE_URL=https://your-bridge.example.com \
  xcrun simctl launch booted com.recco.app
```

The base URL is joined robustly, so both `https://foo` and `https://foo/` work.
A request timeout (~12s) keeps the demo responsive on flaky Wi-Fi.

### What URL to use

Once Person C deploys the backend bridge, set `RECCO_API_BASE_URL` to its origin
(e.g. `https://recco-bridge.fly.dev`). Until then, leave it unset: the app shows
a status line and runs entirely on the local fallback.

### Graceful degradation

- **No backend URL** in `live`/`mockCV` → transparently uses the offline
  `MockBackend`, with a status line in the transcript ribbon.
- **Backend call fails** → people keep the seeded roster; voice/typed commands
  and openers fall back to the on-device engines (safe, non-destructive) with a
  visible status. Face matching never falls back to a fake card — unknown stays
  unknown rather than risk a wrong name.

### Filter semantics

`FilterEngine.partition` uses **OR** semantics for `includeTags` (matching the
backend `state:setFilter` rule): a person is visible if they have *any* included
tag; excluded tags always remove people; empty include means everyone.

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
