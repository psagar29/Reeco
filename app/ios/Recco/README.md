# Recco iOS

SwiftUI iPhone app for the Recco AR networking lens.

The app opens into the product experience: mission setup, fullscreen camera,
target lock, voice/typed scan command, identity result, Brain graph, and Lazy
GTM prospecting.

Related docs: [API Contracts](../../../docs/API_CONTRACTS.md) ·
[Architecture](../../../docs/ARCHITECTURE.md) · [Demo Runbook](../../../docs/DEMO_RUNBOOK.md)

---

## Open In Xcode

```bash
open app/ios/Recco/Recco.xcodeproj
```

Then:

1. Select scheme `Recco`.
2. Select an iPhone or simulator.
3. Press `Cmd+R`.

## Command-Line Build And Install

```bash
xcodebuild \
  -project app/ios/Recco/Recco.xcodeproj \
  -scheme Recco \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData-demo \
  build

xcrun devicectl list devices

xcrun devicectl device uninstall app \
  --device <DEVICE_ID> com.recco.app || true

xcrun devicectl device install app \
  --device <DEVICE_ID> \
  build/DerivedData-demo/Build/Products/Debug-iphoneos/Recco.app

xcrun devicectl device process launch \
  --device <DEVICE_ID> \
  --terminate-existing com.recco.app
```

The installed app can run after the cable is disconnected. `ReccoApp.swift`
falls back to the public demo backend if no Xcode environment variable is
provided.

## Runtime Configuration

The app resolves its backend base URL in this order:

1. `RECCO_API_BASE_URL`
2. `CONVEX_URL`
3. installed fallback: `https://fabulous-hyena-861.convex.site`

Optional launch mode:

```txt
DEMO_MODE=live | mockCV | mockAll
```

The current installed-demo path should use `live`.

No OpenAI, Fiber, Deepgram, or CV secrets belong in iOS. Those live in Convex.

## App Structure

```txt
ReccoApp.swift                 app entry and backend URL fallback
Camera/                        AVFoundation camera, Vision tracking, crops
State/AppModel.swift           shared observable app state
State/Backend/ConvexBackend    HTTP client for Convex Actions
Models/                        DTOs matching docs/API_CONTRACTS.md
Views/AR/                      target reticle, face brackets, hologram panel
Views/MissionSetupView.swift   first-launch goal prompt
Views/Brain*.swift             Brain graph and scan memory detail
Views/GTM*.swift               Lazy GTM graph and prospect detail
Views/CommandDockView.swift    scan / mic / keyboard controls
```

## Main User Flows

### Mission

The first-launch prompt asks what the user is attending the event for. The
mission becomes scoring context for future scans and outreach.

### Camera Scan

The camera tracks faces, chooses the face closest to the center reticle, captures
a face crop and context crop, and calls:

```txt
POST /api/identity/resolve
```

### Voice

The mic requests a short-lived token from:

```txt
POST /api/voice/deepgram-token
```

Streaming speech updates the transcript and can trigger commands such as:

```txt
Find info on him
```

### Brain

Resolved identity results are saved through:

```txt
POST /api/brain/memories/upsert
```

The Brain graph shows saved people, lead priority, lead reasons, notes, and
outreach drafts.

### Lazy GTM

The Lazy GTM panel sends voice/text requests to:

```txt
POST /api/gtm/run
```

Prospects are displayed separately from real scan memories.

## Permissions

The iPhone app needs:

- Camera
- Microphone
- Network access

## Verification

- App builds in Xcode.
- App launches on physical iPhone.
- Camera permission prompt appears and is accepted.
- Mic permission prompt appears and is accepted.
- Mission prompt appears on first launch.
- Camera view appears immediately after mission.
- Bottom dock has scan, mic, keyboard.
- A real scan returns an identity result.
- Brain shows the saved memory.
- Lazy GTM creates a prospect run.
