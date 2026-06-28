# Person D - iOS Voice / Brain Graph / Profiles / Demo Flow

## One-line mission

Build the iOS app shell around the camera: shared state, voice commands, manual chips, Brain graph, profile sheets, opener drafting, and final demo flow.

## You own

- `app/ios/Recco/App/`
- Shared `AppModel`
- Convex connection or mock data source
- Voice transcript UI
- Manual filter chips
- Brain graph view
- Profile detail sheet
- Draft opener UI
- Demo mode/fallbacks

## Main reference repos

- `open-source/grape`
- `open-source/convex-swift`
- `open-source/deepgram-nextjs-live-transcription`
- `open-source/deepgram-live-transcripts-ios`
- Fallback: `open-source/directed-graph-fallback`

## Read first

1. `docs/API_CONTRACTS.md`
2. `demo-data/people.sample.json`
3. Person C brief: `docs/workstreams/03_PERSON_C_IOS_CAMERA_OVERLAY.md`

## Required deliverables

Build:

- App shell/navigation
- Shared models matching API contracts
- Local mock mode using `people.sample.json`
- Convex people/state subscription
- Manual chips: AI, Founder, Infra, Growth, Design, Reset
- Transcript ribbon
- Voice or typed command path
- Brain graph view with people nodes
- Profile detail sheet
- Draft opener panel
- Demo mode switch: `mockAll`, `mockCV`, `live`

## App flow

Default launch:

1. Camera opens first.
2. Bottom/side control strip shows chips and voice button.
3. Tapping matched overlay opens profile.
4. Profile has "Draft opener."
5. Brain view is available as a secondary tab/sheet.

## Shared state

Define Swift models for:

- `PersonDTO`
- `BrainStateDTO`
- `FilterCommandDTO`
- `FaceMatchResultDTO`
- `DraftResultDTO`

Expose a shared app model so Person C can do:

```swift
appModel.selectPerson(personId)
appModel.peopleById[personId]
appModel.state.visiblePersonIds
```

## Voice behavior

Minimum viable path:

- Typed/fixed command bar works first.
- Manual chips work first.
- Deepgram live speech is a bonus once the demo is stable.

Supported commands:

- "Show me AI founders."
- "Who should I talk to about infra?"
- "Only growth people."
- "Draft an opener for Ava."
- "Reset."

User experience:

1. Show partial transcript immediately.
2. Show thinking state after final transcript.
3. Call `voice:interpretCommand`.
4. Apply returned filter through `state:setFilter`.
5. Animate camera overlays and Brain nodes.

## Brain graph

Use Grape if it builds quickly.

Brain behavior:

- Shows all demo people as nodes.
- Current filter brightens matching nodes.
- Non-matches dim.
- Tap node opens the same profile sheet.
- Optional: cluster by tags/background.

If Grape takes too long:

- Use a radial/grid layout.
- Keep dimming/filtering.
- Do not block the camera demo.

## Opener drafting

Profile sheet button:

```txt
Draft opener
```

Calls:

```ts
drafts:createOpener({ personId, userGoal })
```

Displays:

- One opener sentence
- Optional short email
- "Sent" button is a stub only

## Step-by-step plan

1. Create SwiftUI app shell.
2. Add local mock people from `people.sample.json`.
3. Define shared app models.
4. Add manual filter chips.
5. Add profile sheet.
6. Add draft opener UI with mock text.
7. Add Brain view with fake data.
8. Connect to Person B's people/state functions.
9. Add typed command path.
10. Add Deepgram or iOS speech path if time allows.
11. Rehearse full demo with Person C's camera overlay.

## Done when

- App runs in `mockAll` mode without backend.
- Manual chips filter both Brain and camera overlays.
- Profile opens from Person C's overlay.
- Draft opener works with mock or live backend.
- Voice/typed command "show me AI founders" updates state.
- Demo mode can recover if CV or voice breaks.

## Fallback

If Deepgram fails:

- Use typed commands.
- Use manual chips.
- Keep the transcript ribbon as a staged/fixed command if needed.

If Grape fails:

- Use radial/grid view.
- Keep node tap/filter behavior.

If Convex Swift is slow:

- Use HTTP action calls or local JSON.
- Keep the app demoable.

## What not to do

- Do not build the CV service.
- Do not tune face embeddings.
- Do not add extra features after demo lock.
- Do not let graph polish delay the camera-first flow.

