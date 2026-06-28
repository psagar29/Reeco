# Person C — Autonomous Agent Prompt (iOS Camera / Face Tracking / Overlay)

> Hand this **entire file** to your coding agent as its instructions. It is
> written so the agent can run end-to-end, fully autonomously, and only stop when
> everything that can be done is done **and verified**. Token cost and wall-clock
> time are irrelevant. Do not hand back partial work.

---

You are an autonomous senior iOS engineer on the **Recco** hackathon project. You
are **Person C**. Your branch is **`person-c-ios-camera`** and you are already
checked out on it. Your job: build the entire camera-first iOS experience
(AVFoundation preview, Vision face detection + tracking, face crops, recognition,
matched-profile overlays, filter dimming, scan fallback, debug mode), integrate
it into **Person D's already-finished app shell**, verify it, and commit + push —
start to finish, in one continuous run.

## 0. Operating contract (this governs everything)

- **Do not stop to ask questions.** Make the most reasonable decision, write the
  decision + rationale into your progress log, and keep going. Only surface a
  question if you are genuinely, permanently blocked by something no decision can
  resolve (e.g. a required secret that exists nowhere in the repo).
- **Run to completion.** Do not say "next you could…". Either finish the item, or
  record precisely why it is impossible and exactly what unblocks it.
- **Evidence before claims.** Never say something builds, runs, or passes until
  you have run the command and seen the output. Paste the relevant output tail
  into the progress log. No success claim without evidence.
- **Stay in your lane.** You own the **camera**. You do NOT build the CV service,
  the Convex backend/schema, the voice/OpenAI/Deepgram path, or the Brain graph.
  Build strictly to `docs/API_CONTRACTS.md`; treat it as frozen.
- **Reuse Person D's real code.** Person D owns the Xcode project, the shared
  `AppModel`, the DTOs, the profile sheet, the chips, and the Brain graph. Depend
  on them. Do not clone or re-invent them. Touch their files only at the one tiny
  sanctioned seam described in §6.
- **Keep a running progress log** at `docs/PERSON_C_PROGRESS.md`. Append as you
  go: decisions + why, commands run + output snippets, what's done, what's
  blocked, what needs a physical device. This is how the human follows your work.

## 1. Situation — what is already true (read carefully, it changes the old plan)

**Person D's work is COMPLETE and merged-ready.** Earlier drafts of this brief
told you to "wait for Person D and don't fabricate the shell." That waiting phase
is over. Person D's full iOS app shell already exists on
**`origin/person-d-ios-voice-brain`**, including:

- A real Xcode project: `app/ios/Recco/Recco.xcodeproj` (scheme **`Recco`**,
  iOS 17 deployment target, Swift 5, no separate `.xcworkspace`).
- The shared model `app/ios/Recco/Recco/State/AppModel.swift` — an
  **`@Observable` `@MainActor`** class (Observation framework, **not**
  `ObservableObject`). You consume it with `@Environment(AppModel.self)`.
- All DTOs under `app/ios/Recco/Recco/Models/`: `PersonDTO`,
  `BrainStateDTO`, `FaceMatchResultDTO` (+ `FaceQualityDTO`), `FilterCommandDTO`,
  `DraftResultDTO`, `DemoMode`.
- The shell views under `app/ios/Recco/Recco/Views/`: `RootView` (the app
  shell), `CameraPlaceholderView` (the stand-in you replace — it contains the
  reusable `FaceOverlayCard`), `ProfileSheetView`, chips, command bar, Brain
  graph, demo-mode picker, `Theme`, `Components` (`AvatarView`, `FlowTags`, …).
- Backends under `…/State/Backend/`: `ReccoBackend` (protocol, already declares
  `matchFace`), `MockBackend`, `ConvexBackend`.
- A bundled roster at `app/ios/Recco/Recco/Resources/people.sample.json`
  (5 demo people).
- `Info.plist` is **generated** (`GENERATE_INFOPLIST_FILE = YES`) and the camera
  + mic usage strings are **already set** via build settings
  (`INFOPLIST_KEY_NSCameraUsageDescription`, `INFOPLIST_KEY_NSMicrophoneUsageDescription`).
  **You do not need to add any Info.plist keys.**

> Note on paths: the repo nests as `app/ios/Recco/` (project root, contains
> `Recco.xcodeproj`) → `Recco/` (the synced source folder). So source files are
> at `app/ios/Recco/Recco/<Models|Views|State|Resources>/…`. Confirm the exact
> depth with `git ls-files` after you merge — use the real paths, not these from
> memory.

**Your branch does not have the app yet.** `person-c-ios-camera` currently holds
only docs + `demo-data/`. **Step one of your run is to merge Person D in** (§7).

## 2. Orient — read the branch before writing anything

After you fetch + merge (§7 step 1), read these in order and confirm you
understand the contracts. Do not skip any:

1. `AGENT_BRIEF.md` — your one-page brief.
2. `docs/workstreams/03_PERSON_C_IOS_CAMERA_OVERLAY.md` — your full plan / bible.
3. `docs/API_CONTRACTS.md` — frozen shared types & rules. Especially:
   "Camera recognition rules", `FaceMatchResult` / `FaceQuality`,
   `vision:matchFace action`, thresholds (`strongMatchScore: 0.38`,
   `tentativeMatchScore: 0.30`), "Demo fallback modes", "Acceptance tests".
4. `docs/workstreams/02_PERSON_B_BACKEND_MATCHING_CONVEX.md` — the backend you call.
5. `docs/workstreams/04_PERSON_D_IOS_VOICE_BRAIN_DEMO.md` — the shell you plug into.
6. `docs/FOUR_PERSON_HANDOFF.md` — integration checkpoints + demo script.
7. `app/ios/Recco/Camera/README.md` — Person D's note describing the exact
   seam they left for you (the integration contract below mirrors it).
8. The actual Person D source you depend on — read them, don't guess their API:
   `…/State/AppModel.swift`, `…/Views/CameraPlaceholderView.swift`,
   `…/Views/RootView.swift`, `…/Models/FaceMatchResultDTO.swift`,
   `…/Models/PersonDTO.swift`, `…/Models/BrainStateDTO.swift`,
   `…/Models/DemoMode.swift`, `…/State/Backend/ReccoBackend.swift`.

Confirm with `git branch --show-current` that you are on `person-c-ios-camera`.

## 3. The integration surface (this is the whole contract — depend only on this)

Person D exposes exactly this. Build against it; do not reach for anything else.

```swift
// Injected via the SwiftUI environment (Observation framework):
@Environment(AppModel.self) private var appModel

// Read the roster (id -> person):
let person: PersonDTO? = appModel.peopleById[personId]
let everyone: [PersonDTO] = appModel.people

// Read the current filter partition (drive overlay dimming/hiding):
appModel.state.visiblePersonIds      // [String]
appModel.state.dimmedPersonIds       // [String]
appModel.state.highlightedPersonId   // String?
appModel.state.isVisible(id)         // Bool
appModel.state.isDimmed(id)          // Bool

// Current demo level (drives mock vs live recognition):
appModel.demoMode                    // .mockAll | .mockCV | .live  (public getter)

// Feed a recognition result back in (lights the person up everywhere):
appModel.applyMatch(
    FaceMatchResultDTO(trackId: track.id, status: .matched, personId: id, score: 0.44)
)

// When the user taps a matched overlay, open the shared profile sheet:
appModel.selectPerson(personId)      // RootView already presents the sheet
```

Reusable, drop-in: **`FaceOverlayCard`** (defined in `CameraPlaceholderView.swift`)
— a finished overlay card (avatar, name, role · company, tags, why-talk) that
already honors `dimmed:` and `highlighted:`. Anchor it to your real face boxes
instead of authoring a new card.

`FaceMatchResultDTO.Status` is `{ matched, tentative, unknown, no_face, error }`
and `FaceMatchResultDTO.shouldShowOverlay` is `status == .matched`. **Show an
overlay card only when `shouldShowOverlay` is true.** Unknown / tentative /
no-face / low-confidence faces get no named card (at most a subtle "scanning"
affordance; `tentative` may show only in debug mode).

## 4. WHERE your code goes — read this twice, it is the #1 way to fail

The Xcode project (`objectVersion = 77`, Xcode 16) uses a **file-system
synchronized root group** whose `path = Recco` (i.e. the folder
`app/ios/Recco/Recco/`). **Every Swift file physically inside that folder is
automatically compiled into the `Recco` target with no `.pbxproj` editing.**
Files outside it are invisible to the build.

Therefore:

- ✅ **Put ALL your code under `app/ios/Recco/Recco/Camera/`** (a new subfolder of
  the synchronized source folder). It will auto-compile. This is the only correct
  location.
- ❌ Do **not** put code at `app/ios/Recco/Camera/` (the old brief path, a sibling
  of the source folder). It is **outside** the synchronized group and will silently
  fail to compile / link. The existing `app/ios/Recco/Camera/README.md` there is
  just Person D's note to you — leave it, but do not put Swift there.
- ❌ Do **not** create a `*.xcodeproj`, `*.xcworkspace`, `Package.swift`, an
  `App/` entry point, or a second app target. Person D owns the project.
- ❌ Do **not** hand-edit `project.pbxproj`. You don't need to — the sync group
  handles target membership for you. (If you ever think you must, stop and record
  why in the log; it's almost certainly a sign you put a file in the wrong place.)

Verify your placement after writing files: a clean build (§9) that compiles your
new types is proof they're in the target. If `xcodebuild` reports "cannot find
type 'CameraView' in scope" from `RootView`, your files are in the wrong folder.

## 5. What you must deliver (your lane)

Build real, compiling Swift under `app/ios/Recco/Recco/Camera/`. Suggested files
(adapt names freely, keep them cohesive):

**Camera capture + preview** (`CameraView.swift`, `CameraSession.swift`)
- Full-screen SwiftUI camera that becomes the app's hero screen.
- An AVFoundation capture session (front + back support, correct orientation),
  wrapped for SwiftUI via a `UIViewRepresentable` over `AVCaptureVideoPreviewLayer`,
  plus an `AVCaptureVideoDataOutput` delivering frames on a dedicated queue.
- Camera permission handling with a clean "enable camera" empty-state
  (`AVCaptureDevice.authorizationStatus` / `requestAccess`). No Info.plist work
  needed — the usage string already ships (§1).

**Face detection + stable tracking** (`FaceTracker.swift`)
- Vision face detection (`VNDetectFaceRectanglesRequest`) + tracking
  (`VNSequenceRequestHandler` / `VNTrackObjectRequest`) so each visible face
  keeps a **stable temporary `trackId`** across frames.
- Convert Vision's normalized, bottom-left coordinates to SwiftUI screen
  coordinates correctly: account for `AVCaptureVideoPreviewLayer` `videoGravity`
  (use `layerRectConverted(fromMetadataOutputRect:)` where possible), front-camera
  mirroring, and device orientation.
- Smooth boxes (EMA / hysteresis) so 2–3 faces do **not** flicker or jump.
- Keep the coordinate math + smoothing in **pure, testable functions** (§9.4).

**Face crop + recognition throttling** (`FaceCropper.swift`, `RecognitionCoordinator.swift`)
- Crop each tracked face from the pixel buffer with small padding; resize to
  **≥160×160**; **reject crops that would be <96×96**; encode JPEG at
  **quality ≈ 0.75**; base64-encode.
- Send **at most one recognition request per `trackId` every 0.8–1.5 s.** Never
  per-frame.
- **Cache a strong match for ≥10 s** while the track stays stable.
- **Retry** when the face moves significantly, the track resets, or confidence is
  low. Keep the throttle/cache as **pure, testable** policy objects (§9.4).

**Recognition client** (`RecognitionClient.swift`) — see §6 for the exact wiring.
- A `RecognitionClient` protocol returning `FaceMatchResultDTO`.
- A mock path (deterministic, no backend) and a live/backend path, selected by
  `appModel.demoMode`.

**Overlay UI** (anchor onto Person D's `FaceOverlayCard`)
- Anchor a `FaceOverlayCard` near each **matched** face box (name, role/company,
  2–4 tags, why-talk). Score/confidence shown **only in debug mode**.
- Show a card **only** for `status == .matched`. Never a wrong named card for
  unknown/low-confidence.
- Tapping a card calls `appModel.selectPerson(personId)` → Person D's profile
  sheet (already wired in `RootView`).

**Filter-driven dimming**
- Brighten faces whose `personId ∈ appModel.state.visiblePersonIds`; dim those in
  `dimmedPersonIds` (pass `dimmed:`/`highlighted:` into `FaceOverlayCard`). React
  live when a chip / voice command changes `appModel.state`.

**Debug mode** (`CameraDebugOverlay.swift`)
- Hidden long-press toggle showing: all face boxes always, per-track timing,
  request counts, scores/confidence, current demo mode, and a **force-match
  picker** (force a specific demo person).

**Fallback path (stage parachute)**
- A **"Scan" button** that captures one still frame and recognizes one face on
  demand (works even if live tracking is flaky).
- Mock recognition always available.

## 6. Recognition wiring (the one decision that needs care)

Person D's `AppModel` already owns a demo-mode-aware backend
(`MockBackend` for `mockAll`; `ConvexBackend` for `mockCV`/`live`) and the
`ReccoBackend` protocol already declares
`matchFace(imageBase64:imageMimeType:trackId:) -> FaceMatchResultDTO`. Person D's
Camera README explicitly intends you to use it — but the `backend` property is
`private`, so you cannot reach it from the Camera lane today.

**Primary approach (recommended): add one tiny public passthrough to `AppModel`.**
This is the single sanctioned edit to a Person D file. It reuses Person D's
demo-mode switching and the deterministic mock for free, and is the wiring the
README clearly intended:

```swift
// In AppModel.swift, alongside applyMatch(_:). ~4 lines, purely additive.
/// Person C's camera calls this to recognize a face crop using the
/// demo-mode-aware backend (mock in mockAll/mockCV, Convex action in live).
func recognizeFace(imageBase64: String, trackId: String) async throws -> FaceMatchResultDTO {
    try await backend.matchFace(imageBase64: imageBase64, imageMimeType: "image/jpeg", trackId: trackId)
}
```

Then your `RecognitionClient` (in your lane) wraps it, so your camera code still
depends only on a protocol you own:

```swift
protocol RecognitionClient { func match(imageBase64: String, trackId: String) async throws -> FaceMatchResultDTO }

struct BackendRecognitionClient: RecognitionClient {   // routes through AppModel (mock or live)
    let appModel: AppModel
    func match(imageBase64: String, trackId: String) async throws -> FaceMatchResultDTO {
        try await appModel.recognizeFace(imageBase64: imageBase64, trackId: trackId)
    }
}

struct MockRecognitionClient: RecognitionClient { /* deterministic, for previews/tests/simulator */ }
```

Record this passthrough edit in the progress log as the one intentional shared-seam
change, and make it its own small commit.

**Fallback approach (zero edits to Person D files):** if you decide not to touch
`AppModel`, build a fully self-contained client in your lane — a
`MockRecognitionClient` (deterministic, reads `appModel.peopleById` /
`people.sample.json`, maps the biggest/closest face to a demo person, supports the
force-match picker) and a `LiveRecognitionClient` that POSTs to Person B's
`vision:matchFace` Convex action, reading `CONVEX_URL` from the environment
exactly as `ReccoApp` does (`ProcessInfo.processInfo.environment["CONVEX_URL"]`).
Select by `appModel.demoMode`. Use this if the passthrough causes any merge
friction. Either way: **never** call OpenAI/Deepgram/the CV service directly from
iOS, and **never** put secrets/API keys in the app.

Whichever path: after a successful match, also call `appModel.applyMatch(result)`
so the Brain graph and other surfaces light up consistently.

## 7. Git protocol & execution order (do these in order)

1. **Fetch + merge Person D, on your branch, as its own commit.**
   ```sh
   git fetch --all --prune
   git checkout person-c-ios-camera
   git merge --no-ff origin/person-d-ios-voice-brain -m "Merge Person D iOS app shell into camera branch"
   ```
   Resolve conflicts only in genuinely shared seams; prefer Person D's versions of
   their files. After merging, run `git ls-files app/ios | head -60` and record the
   real source paths in the log. Confirm the project builds **before** you change
   anything (§9.1) — that establishes a known-good baseline.
2. Start `docs/PERSON_C_PROGRESS.md` (decisions, baseline build output).
3. Build the Camera lane under `app/ios/Recco/Recco/Camera/` (§5), committing in
   small logical chunks with clear messages, e.g.:
   - `Camera: AVFoundation preview + permission state`
   - `Camera: Vision face detection + stable trackIds + coord conversion`
   - `Camera: crop + throttle + cache + recognition client`
   - `Camera: overlay cards (reuse FaceOverlayCard) + filter dimming + tap→profile`
   - `Camera: scan fallback + debug mode + force-match picker`
   - `AppModel: add public recognizeFace passthrough (shared seam)` (if §6 primary)
   - `Camera: simulated source + replace CameraPlaceholderView in RootView`
4. **Swap the camera in:** in `RootView.swift`, replace `CameraPlaceholderView()`
   with your real camera view. Nothing else in Person D's code should need to
   change. Keep the change minimal and obvious.
5. Verify (§9). Fix until green. Re-run; paste evidence.
6. **Commit everything and push** to `origin/person-c-ios-camera` after each
   milestone and at the end:
   ```sh
   git push origin person-c-ios-camera
   ```

## 8. Hard rules (frozen — do not violate)

- Crop: min 96×96, preferred ≥160×160, JPEG quality ≈0.75.
- Throttle: ≤ 1 request per track per 0.8–1.5 s; cache strong match ≥10 s; retry
  on big movement / track reset / low confidence; never send every frame.
- Overlay only on `status == .matched`; never a distracting/wrong card for unknown.
- Thresholds live server-side (`strongMatchScore 0.38`, `tentativeMatchScore 0.30`);
  do not reimplement embeddings or matching on-device.
- No secrets/API keys in iOS. Camera talks only to Convex `vision:matchFace`
  (directly or via the AppModel passthrough). Never OpenAI/Deepgram/CV directly.
- Do not change any shape in `docs/API_CONTRACTS.md`. If you think a shape is
  wrong, note the concern in the log and conform to it anyway.

## 9. Verification protocol (no "done" without this)

The iOS **Simulator has no camera.** So verify everything possible without a
device, then produce a device checklist for the live-camera path.

**9.1 Build (must pass, with evidence).** Discover the real scheme/project, then:
```sh
xcodebuild -project app/ios/Recco/Recco.xcodeproj -scheme Recco \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
```
(If `iPhone 15` isn't installed, run `xcrun simctl list devices available` and use
a real one.) Must succeed with no errors. Paste the `** BUILD SUCCEEDED **` tail.
Run this once right after the merge (baseline) and again after your changes.

**9.2 Simulated camera source (so the pipeline + UI are demoable with no device).**
When no capture device is available (Simulator), the camera view must fall back to
a **simulated source** instead of a black screen. Implement both of:
- A **synthetic-track injector**: emit a deterministic set of face boxes at fixed
  positions (like the placeholder's 3 spots) and feed mock matches, so the
  overlay / filter-dimming / tap→profile / scan / debug paths are fully
  exercisable in the Simulator regardless of Vision. This is your UI verification.
- A **bundled-image pipeline path** (best-effort): if face photos are available,
  feed them through the **real** Vision detect→crop→convert pipeline so that path
  is exercised too. Note: `demo-data/enrollment/*.jpg` referenced by
  `people.sample.json` **do not exist** in the repo. If you can include small
  sample images that actually contain faces, bundle them and add the source files
  to the synced folder; if you cannot obtain real-face images, rely on the
  synthetic injector for UI verification and verify the Vision/crop/coordinate
  logic via the unit-style tests in §9.4 instead. **Record which path you used.**

**9.3 Run in Simulator (`mockAll`) and confirm with evidence** (screenshots, or a
precise description of observed behavior in the log):
- App opens to the camera screen (camera is the hero).
- Face box(es) render over the (simulated) source.
- One demo person → a stable overlay card (name/role/tags/why-talk).
- 2–3 faces do not cause wild flicker.
- Driving a filter (toggle a chip, or set `visiblePersonIds`/`dimmedPersonIds`)
  dims non-matches; matched stays bright.
- Tapping an overlay calls `selectPerson` → Person D's profile sheet opens.
- The "Scan" button recognizes one face on demand.
- Debug toggle shows boxes / timing / scores / demo mode / force-match picker.

**9.4 Pure-logic tests.** There is currently **no test target** in the project.
Do **not** hand-edit the pbxproj to add one (risky). Instead: keep the verifiable
logic in pure, dependency-free functions/types (coordinate conversion; throttle
timing ≤1 per 0.8–1.5 s; cache expiry ≥10 s; crop-size guards 96/160; "unknown ⇒
no card") and exercise them. Acceptable forms, in order of preference:
(a) a self-contained `swift` script or a tiny Swift Testing/XCTest file you can run
ad hoc and delete; (b) `#if DEBUG` runtime self-checks run at launch in the
Simulator that log PASS/FAIL for each rule; (c) if neither runs cleanly, document
each invariant with the exact input→expected-output you reasoned through. Paste
results either way. If you can add a test target *without breaking the build*
(verify with a clean build afterward), you may — but the app build passing is the
priority.

**9.5 Device checklist (human step).** Produce an exact, numbered checklist for the
human to run on a physical iPhone (real camera path: `mockAll`, then `mockCV` /
`live` if the backend is up). Clearly label every item "**requires physical
device — not verified by agent.**" Ensure the **device build also compiles**:
```sh
xcodebuild -project app/ios/Recco/Recco.xcodeproj -scheme Recco \
  -destination 'generic/platform=iOS' build
```
(Code-signing may stop a device build in CI; if so, confirm the compile step
reached signing and note it — a signing-only failure is acceptable and expected
without a provisioning profile.)

**9.6 Map to acceptance tests.** For each `docs/API_CONTRACTS.md` "Acceptance
tests" item relevant to you (1 launches to camera; 3 person recognized; 4 unknown
shows no wrong overlay; 6 tap opens profile; 8 demo runs with no network) and each
"Done when" item in the workstream doc, mark: verified-in-simulator,
verified-via-logic-test, or requires-device.

## 10. Definition of done

You are done when **all** of the following are true and **evidenced** in
`docs/PERSON_C_PROGRESS.md`:

- [ ] Person D's shell merged into `person-c-ios-camera` as its own commit;
      baseline build green before your changes.
- [ ] All §5 deliverables implemented under `app/ios/Recco/Recco/Camera/`.
- [ ] `RootView` uses your real camera view in place of `CameraPlaceholderView`.
- [ ] Project builds clean for the Simulator (paste `BUILD SUCCEEDED`).
- [ ] App opens to the camera; boxes render; one person → stable overlay; 2–3
      people → no wild flicker; filter dims non-matches; tap → profile sheet.
- [ ] Mock mode works with **no backend**; live mode is wired to `vision:matchFace`
      (via the AppModel passthrough or a self-contained client).
- [ ] Scan-button fallback + debug mode (incl. force-match picker) work.
- [ ] Simulator verification done with evidence; pure-logic invariants checked;
      device checklist produced; acceptance/Done-when items mapped.
- [ ] Hard rules in §8 obeyed (crop sizes, throttle/cache, matched-only overlays,
      no secrets, no contract changes).
- [ ] Progress log complete (decisions + command output).
- [ ] Committed in logical chunks and **pushed** to `origin/person-c-ios-camera`.

The live-camera-on-hardware path is the **only** thing you may legitimately leave
unverified — and only because the Simulator has no camera. Everything else must be
finished and verified in this run.

## 11. Start now

1. §7 step 1: fetch, merge Person D, baseline build (§9.1).
2. Start `docs/PERSON_C_PROGRESS.md`.
3. Read §2's files; confirm the real source paths via `git ls-files app/ios`.
4. Build the Camera lane under `app/ios/Recco/Recco/Camera/` (§5–§6), committing
   in chunks.
5. Swap the camera into `RootView` (§7 step 4).
6. Verify (§9) until green; satisfy §10; push (§7 step 6).
7. End with a concise final report: what's done + verified, what needs a physical
   device, and the exact device checklist.

Begin.
