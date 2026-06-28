# Person A — iOS Live Backend + Face Overlay (Handoff)

Branch: `agent/person-a-ios-live-overlay`

## Summary of changes

Turned the placeholder `ConvexBackend` into a real `URLSession`/`Codable` HTTP
client, wired the demo modes and env config around it, aligned the iOS filter
semantics with the backend, and made the face overlay surface LinkedIn directly.
`mockAll` remains fully offline and stage-safe.

1. **Live HTTP client** (`ConvexBackend.swift`)
   - Plain `URLSession` + `JSONEncoder`/`JSONDecoder`, no third-party packages.
   - Generic `get(_:as:)` / `post(_:body:as:)` helpers; robust base-URL join so
     both `https://foo` and `https://foo/` work.
   - 12s request timeout (ephemeral session, `waitsForConnectivity = false`).
   - Non-2xx and transport/decoding failures throw `ConvexBackendError` with a
     readable message.
   - No base URL configured → transparently delegates to the offline
     `MockBackend`.
   - Endpoint map:
     - `GET  /api/people`        → `listPeople()`
     - `POST /api/voice/interpret` → `interpretCommand()`
     - `POST /api/drafts/opener` → `createOpener()`
     - `POST /api/vision/match-face` → `matchFace()`

2. **Env config + demo modes** (`ReccoApp.swift`, `AppModel.swift`)
   - Backend base URL now prefers `RECCO_API_BASE_URL`, falls back to
     `CONVEX_URL` (empty/whitespace treated as unset). Renamed the internal
     `convexURL` seam to `apiBaseURL`.
   - Backend mode with no URL surfaces a status line and runs on the local
     fallback (no silent confusion).
   - Safe fallbacks on backend failure: voice/typed commands re-interpret
     on-device (`CommandInterpreter`), openers regenerate on-device
     (`OpenerGenerator`), roster keeps the seeded data — each with a visible
     status. Face matching does **not** fall back to a fake card.
   - New `AppModel.setStatus(_:)` lets the camera lane explain degraded states.

3. **Filter semantics** (`FilterEngine.swift`)
   - Switched `includeTags` from AND to **OR** to match the backend
     `state:setFilter` rule. Excludes still remove people; empty include = all.
     Removed the now-unneeded AND→OR safety net. Updated the `toggleTag` comment.

4. **Face overlay LinkedIn affordance** (`CameraPlaceholderView.swift`,
   `CameraView.swift`)
   - `FaceOverlayCard` shows a compact **LinkedIn** pill (a `SwiftUI.Link`) when
     the person has a LinkedIn URL. The link consumes its own tap and opens
     directly; tapping elsewhere on the card still opens the full profile sheet.
   - Card stays compact (190pt wide); bumped the card placement half-height in
     `CameraView` so the taller card still anchors cleanly below/above the face.

5. **Unknown stays safe** (unchanged contract, verified)
   - Overlays render only for `status == .matched` (`shouldShowOverlay`).
     `tentative`/`unknown`/`no_face`/`error` show no named card. The debug HUD
     shows raw status only.

6. **Simulator live mode** (`CameraViewModel.swift`)
   - In `live` on the Simulator (no real pixels) the camera sets a clear status
     ("face matching is paused…") instead of silently showing nothing.

7. **Docs** — rewrote `app/ios/Recco/README.md` (env vars, endpoint table, run
   commands, degradation, filter semantics).

## Files touched

- `app/ios/Recco/Recco/State/Backend/ConvexBackend.swift` (rewritten)
- `app/ios/Recco/Recco/State/AppModel.swift`
- `app/ios/Recco/Recco/ReccoApp.swift`
- `app/ios/Recco/Recco/State/FilterEngine.swift`
- `app/ios/Recco/Recco/Views/CameraPlaceholderView.swift`
- `app/ios/Recco/Recco/Camera/CameraView.swift`
- `app/ios/Recco/Recco/Camera/CameraViewModel.swift`
- `app/ios/Recco/README.md`
- `docs/agent-handoffs/PERSON_A_IOS.md` (new)

No DTO shapes, backend, or CV service code changed.

## Build result

```bash
xcodebuild -project app/ios/Recco/Recco.xcodeproj \
  -scheme Recco \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

Result: **BUILD SUCCEEDED** (Xcode 26.5, iOS Simulator SDK 26.5).

## Manual run

- **Simulator: yes.** Installed and launched on a booted iPhone 17 simulator.
  - `mockAll`: launches to the camera; simulated face overlays appear with name,
    role/company, tags, why-talk, and a tappable **LinkedIn** pill on each card.
    Transcript ribbon shows "Showing everyone 5/5".
  - `live` (via `DEMO_MODE=live`): launches cleanly, shows the simulated-camera
    backdrop and the "Live mode: Simulator has no camera — face matching is
    paused" status, and shows **no** named overlays (no misidentification). No
    crash switching modes.
  - Tap-to-open-profile and tap-LinkedIn were **not** automated (no
    accessibility/UI-automation tooling available in this environment). The
    tap → `appModel.selectPerson` → profile-sheet seam is unchanged existing
    code; only a LinkedIn `Link` was added inside the card, which consumes its
    own tap.

- **Physical iPhone: not tested** (no device in this environment). Build does
  not depend on a device.

## Required env vars

- `RECCO_API_BASE_URL` — preferred backend base URL (Person C's HTTP bridge).
- `CONVEX_URL` — fallback base URL.
- `DEMO_MODE` — `mockAll` | `mockCV` | `live` (defaults to `mockAll`).

## Known blockers

- None blocking the iOS build. Live end-to-end is untested against a real
  backend because Person C's HTTP bridge is not deployed yet.

## Assumptions about Person C endpoints

- Base URL hosts the six `/api/...` routes from `AGENT_PROMPT.md`; this client
  uses the four it needs (`/api/people`, `/api/voice/interpret`,
  `/api/drafts/opener`, `/api/vision/match-face`).
- Responses are JSON matching the existing DTOs (`PersonDTO` without
  `faceEmbedding`, `FilterCommandDTO`, `DraftResultDTO`, `FaceMatchResultDTO`).
- `/api/people` returns a bare `[PersonDTO]` array (not wrapped).
- `match-face` returns `status: "matched"` only for confident matches; anything
  else yields no overlay on iOS.
- Non-2xx responses are acceptable to treat as failures (client falls back where
  safe and surfaces the status).
