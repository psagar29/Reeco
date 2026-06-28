# Camera (Person C)

This directory is **Person C's** lane: the real AVFoundation camera preview,
Vision face detection/tracking, face-crop extraction, recognition throttling,
and overlay anchoring.

Person D has left a working **placeholder** at
`app/ios/Recco/Recco/Views/CameraPlaceholderView.swift` so the demo shell is
fully usable today. When you build the real camera, you only need to talk to the
shared `AppModel` through this small, stable surface:

## Integration contract

```swift
// Read the roster (id -> person)
let person = appModel.peopleById[personId]

// Read the current filter partition (drive dimming/hiding of overlays)
appModel.state.visiblePersonIds   // [String]
appModel.state.dimmedPersonIds    // [String]
appModel.state.highlightedPersonId

// Feed a recognition result back in (highlights the person everywhere)
appModel.applyMatch(
    FaceMatchResultDTO(trackId: track.id, status: .matched, personId: id, score: 0.44)
)

// When the user taps a matched overlay, open the shared profile sheet:
appModel.selectPerson(personId)
```

`appModel` is provided via the SwiftUI environment:

```swift
@Environment(AppModel.self) private var appModel
```

## Reusable pieces

- `FaceOverlayCard` (in `CameraPlaceholderView.swift`) is a drop-in overlay card
  (name, role/company, tags, why-talk) that already honors `dimmed` /
  `highlighted`. Anchor it to your real face boxes.
- Show an overlay **only** for `FaceMatchResultDTO.status == .matched`
  (`result.shouldShowOverlay`). Unknown/low-confidence faces should not produce
  a card.

## Backend call

In `mockAll` / `mockCV`, `appModel`'s backend already returns deterministic
matches via `backend.matchFace(...)`. In `live`, wire your crop into Person B's
`vision:matchFace` Convex action and pass the result to `appModel.applyMatch`.

Replace `CameraPlaceholderView` in `RootView` with your real camera view when
ready — nothing else in Person D's code needs to change.
