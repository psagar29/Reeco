# Person C - iOS Camera / Face Tracking / Overlay

## One-line mission

Build the camera-first iOS experience: live camera, face boxes, stable tracking, face crops, and profile overlays.

## You own

- `app/ios/Recco/Camera/`
- AVFoundation camera preview
- Vision face detection/tracking
- Face crop extraction
- Recognition throttling
- Overlay cards anchored to face boxes
- Camera debug mode

## Main APIs

- AVFoundation
- Vision
- SwiftUI
- Convex client or backend HTTP fallback

## Read first

1. `docs/API_CONTRACTS.md`
2. Person B brief: `docs/workstreams/02_PERSON_B_BACKEND_MATCHING_CONVEX.md`
3. Person D brief: `docs/workstreams/04_PERSON_D_IOS_VOICE_BRAIN_DEMO.md`

## Required deliverables

Build:

- Full-screen camera view on app launch
- Face rectangle overlay
- Stable temporary `trackId` per visible face
- Cropped face JPEG generation
- Backend call to `vision:matchFace`
- Profile overlay for matched people
- Visual dimming/hiding based on active filter
- Debug toggle for boxes, timing, and confidence

## Camera UX

The camera is the hero screen.

Overlay card minimum:

- Name
- Role/company
- 2-4 tags
- Why-talk one-liner

Do not show a distracting card for unknown people.

## Recognition rules

- Do not send every frame.
- Minimum crop size: 96 x 96 px.
- Preferred crop size: 160 x 160 px or bigger.
- JPEG quality around 0.75.
- Max one recognition request per face track every 0.8-1.5 seconds.
- Cache a strong match for at least 10 seconds while the track stays stable.
- Retry if the face moves significantly, tracking resets, or match confidence is low.

## Backend call

Call Person B's `vision:matchFace` with:

```json
{
  "imageBase64": "/9j/4AAQSkZJRgABAQ...",
  "imageMimeType": "image/jpeg",
  "trackId": "track_123"
}
```

Receive:

```json
{
  "trackId": "track_123",
  "status": "matched",
  "personId": "person_ava_shah",
  "score": 0.44,
  "latencyMs": 420
}
```

Show overlay only for `status: "matched"`.

## Integration with Person D

Person D owns the shared app model, profile card, filters, and Brain view.

You need access to:

- `peopleById`
- `BrainState.activeFilter`
- `BrainState.visiblePersonIds`
- `BrainState.dimmedPersonIds`
- `selectedPersonId`

When user taps an overlay, call the shared selection route:

```swift
appModel.selectPerson(personId)
```

## Step-by-step plan

1. Create a SwiftUI camera screen with AVFoundation preview.
2. Add Vision face detection rectangles.
3. Normalize face boxes to screen coordinates.
4. Generate stable-ish `trackId`s.
5. Add fake match responses to prove overlays.
6. Add face crop generation.
7. Call backend `vision:matchFace`.
8. Map returned `personId` to profile data.
9. Add filter dimming.
10. Tune in real lighting with real demo people.

## Done when

- App opens to camera.
- Face boxes show over live camera.
- One enrolled person produces a stable overlay.
- Two or three visible people do not cause wild flicker.
- Manual filter state can dim non-matches.
- Tap overlay opens Person D's profile card.

## Fallback

If live camera recognition is flaky:

- Add a "Scan" button that captures one still frame.
- Recognize one person at a time.
- Use printed enrollment photos for stage backup.
- Keep fake recognition mode available.

## What not to do

- Do not build OpenAI/voice.
- Do not implement face embeddings locally.
- Do not build Convex schema.
- Do not polish the Brain graph before camera overlays work.

