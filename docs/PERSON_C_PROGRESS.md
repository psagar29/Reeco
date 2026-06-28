# Person C — Progress Log (iOS Camera / Face Tracking / Overlay)

Branch: `person-c-ios-camera`. This log records decisions, what was built, what
was verified (with evidence), and what still requires a machine with full Xcode /
a physical device. Evidence-before-claims: nothing below is marked "verified"
unless a command was actually run.

---

## 0. Environment reality (read this first)

This run happened on a machine with **Command Line Tools only — full Xcode is NOT
installed**:

- `xcodebuild -version` → error: "requires Xcode" (CommandLineTools active).
- `xcrun simctl` → "unable to find utility 'simctl'": **no iOS Simulator**.
- No `/Applications/Xcode*.app` anywhere (checked `/Applications`, `~/Applications`,
  Spotlight).
- `swift`/`swiftc` **are** available (Apple Swift 6.1.2) but only the **macOS**
  SDK — no iOS SDK, so SwiftUI/AVFoundation/Vision/UIKit code cannot be compiled
  here.

**Consequence:** the full app build (`xcodebuild`) and Simulator run **could not
be performed in this environment.** They are not claimed as done. Everything that
*could* be verified with the available toolchain was verified (see §4). The exact
commands to finish on a Mac with Xcode are in §6.

---

## 1. Integration setup

- Merged Person D's complete app shell into this branch:
  `git merge --no-ff origin/person-d-ios-voice-brain` → commit
  `7aa2c39 Merge Person D iOS app shell into camera branch`.
  Only conflict was `AGENT_BRIEF.md` (add/add) — resolved by keeping Person C's
  brief (`--ours`), since this is the camera branch.
- Confirmed the Xcode project is `app/ios/Recco/Recco.xcodeproj`, scheme `Recco`,
  iOS 17 deployment target, Swift 5 language mode, **file-system synchronized
  group** rooted at `app/ios/Recco/Recco/`.
- **Decision (important):** placed all camera code under
  `app/ios/Recco/Recco/Camera/` (inside the synchronized group) — NOT the old
  brief path `app/ios/Recco/Camera/` (a sibling, outside the group, which would
  not compile). Inside the synced group, files auto-join the `Recco` target with
  **no `.pbxproj` editing**. Verified all 12 files land there.
- **Info.plist:** no work needed — `GENERATE_INFOPLIST_FILE = YES` and
  `INFOPLIST_KEY_NSCameraUsageDescription` / `…NSMicrophoneUsageDescription` are
  already set in Person D's build settings.

---

## 2. What was built (lane: `app/ios/Recco/Recco/Camera/`)

| File | Responsibility |
|------|----------------|
| `FaceGeometry.swift` | **Pure** geometry: Vision bottom-left → SwiftUI top-left, front-camera mirroring, normalized→view scaling, EMA smoothing, IoU + center-distance for track association, crop-rect padding/clamp, 96/160 crop-size guards. |
| `RecognitionPolicy.swift` | **Pure** per-track throttle + cache: ≤1 request/track/1.0s, cache strong match ≥10s, retry on significant move / track reset / non-match. Injected clock → deterministic. |
| `RecognitionClient.swift` | `RecognitionClient` protocol; `MockRecognitionClient` (deterministic, no backend, force-match support); `BackendRecognitionClient` (routes through `AppModel.recognizeFace` → demo-mode-aware backend → `vision:matchFace`). |
| `FaceTracking.swift` | `FaceTracker`: per-frame `VNImageRequestHandler` + `VNDetectFaceRectanglesRequest`, IoU association → **stable `trackId`s**, EMA-smoothed boxes, largest-first `faceRank`, stale-track pruning. |
| `FaceCropper.swift` | Crop face from `CVPixelBuffer`, reject <96×96, upscale toward ≥160, JPEG q≈0.75, base64. |
| `CameraSession.swift` | `AVCaptureSession` wrapper: permission, front/back input, `AVCaptureVideoDataOutput` frames, upright portrait rotation (iOS 17 `videoRotationAngle`), Simulator-safe (`isCameraAvailable`). |
| `CameraPreviewView.swift` | `UIViewRepresentable` over `AVCaptureVideoPreviewLayer` (`.resizeAspectFill`). |
| `SimulatedFaceSource.swift` | Deterministic synthetic tracks so the Simulator (no camera) still demos overlays/filter/tap/scan/debug. |
| `CameraViewModel.swift` | `@Observable @MainActor` orchestrator: capture → track → policy → crop → client → `appModel.applyMatch`; debug/scan/flip; auto-fallback to simulated source. |
| `CameraView.swift` | The hero screen: preview/backdrop + face boxes + anchored `FaceOverlayCard` (reused from Person D) + scan/flip controls + permission state + long-press debug. |
| `CameraDebugOverlay.swift` | Debug HUD: demo mode, request count, latency, all-boxes toggle, simulated face count, **force-match picker**. |
| `CameraSelfCheck.swift` | `#if DEBUG` runtime assertions of the contract invariants (logged at launch). |

Integration edits (the one sanctioned shared seam + the swap):
- `AppModel.swift`: added a 4-line public `recognizeFace(imageBase64:trackId:)`
  passthrough to the (private) demo-mode-aware backend. This is the wiring Person
  D's `Camera/README.md` intended; reuses `MockBackend`/`ConvexBackend` and
  demo-mode switching for free. Purely additive.
- `RootView.swift`: replaced `CameraPlaceholderView()` with `CameraView(appModel:)`.
  Nothing else in Person D's code changed. (`CameraPlaceholderView` is left in
  place, now unused, still compiling — its `FaceOverlayCard` is reused.)

---

## 3. How the frozen contract rules are satisfied (`docs/API_CONTRACTS.md`)

- **Crop min 96 / preferred 160 / JPEG ~0.75** → `FaceGeometry.meetsMinimumCropSize`
  (reject <96), upscale toward 160 in `FaceCropper`, `jpegQuality = 0.75`.
- **≤1 request/track/0.8–1.5s** → `RecognitionPolicy.minRequestInterval = 1.0`
  (rate limit always wins).
- **Cache strong match ≥10s** → `cacheTTL = 10.0`; only `.matched` populates cache.
- **Retry on move/reset/low-confidence** → `moveThreshold`, cache cleared on
  non-match, track pruning forgets dropped tracks.
- **Overlay only for `status == matched`** → `matchedPerson(for:)` gates on
  `shouldShowOverlay`; unknown/tentative/no-face show no card (debug shows boxes).
- **No secrets / no direct CV-OpenAI-Deepgram** → camera only ever calls Convex
  `vision:matchFace` via `AppModel.recognizeFace`; no keys in the app.
- **No contract shapes changed.**

---

## 4. Verification performed (with evidence)

### 4.1 Pure-logic contract tests — PASS (actually run)
Compiled `FaceGeometry.swift` + `RecognitionPolicy.swift` with a standalone test
main using the real Swift compiler and ran it:

```
swiftc -O FaceGeometry.swift RecognitionPolicy.swift main.swift -o run && ./run
== FaceGeometry ==
  ✅ y-flip bottom-left->top-left
  ✅ front-camera mirror x
  ✅ normalized->view scale
  ✅ crop <96 rejected / 96 accepted / 160 preferred / 159 not preferred
  ✅ crop padded size 300x300
  ✅ iou identical == 1 / disjoint == 0
== RecognitionPolicy ==
  ✅ first send
  ✅ rate-limited <1.0s
  ✅ cache holds <10s
  ✅ cache expires >10s
  ✅ retry on significant move
  ✅ default min interval in 0.8-1.5s / cache TTL >= 10s
  ✅ cachedMatch within/after TTL
RESULT: 19 passed, 0 failed   (exit 0)
```

These cover the contract-critical numeric invariants (coordinate conversion,
mirroring, 96/160 crop guards, throttle timing, ≥10s cache, retry-on-move). The
same invariants are asserted at launch in DEBUG by `CameraSelfCheck`.

### 4.2 Non-UI layer type-check — PASS (actually run)
Type-checked the whole Foundation-only layer against the macOS SDK, including the
`AppModel.recognizeFace` edit, both recognition clients, and DTO usage:

```
swiftc -typecheck Models/*.swift State/AppModel.swift State/Backend/*.swift \
  State/{CommandInterpreter,FilterEngine,OpenerGenerator,RosterStore,TagVocabulary}.swift \
  Camera/{FaceGeometry,RecognitionPolicy,RecognitionClient,CameraSelfCheck}.swift
→ exit 0 (no errors)
```

### 4.3 NOT verified here (requires full Xcode — see §6)
- `xcodebuild` Simulator build of the full app (SwiftUI/AVFoundation/Vision files).
- Running in the Simulator and observing overlays/filter/tap/scan/debug.
- Anything needing a physical device (live camera).

The SwiftUI/AVFoundation/Vision files were written carefully against the iOS 17
APIs and Person D's real types, but **cannot be compiled in this environment**, so
they are not claimed to build. Likely Swift 6 *concurrency warnings* (e.g.
sending `CVPixelBuffer`/`CameraFrame` into a `@MainActor` Task) may appear; the
project is Swift 5 language mode, so these should be warnings, not errors.

---

## 5. Acceptance-test mapping (`docs/API_CONTRACTS.md` "Acceptance tests")

| # | Test | Status |
|---|------|--------|
| 1 | App launches to camera | Implemented (`RootView` → `CameraView`); **needs Xcode run to confirm** |
| 3 | A person is recognized | Mock path deterministic (verified by logic); live path wired; **needs device/backend** |
| 4 | Unknown face → no wrong overlay | **Verified by logic** (`shouldShowOverlay` gate) + Simulator-confirmable |
| 6 | Tap matched overlay → profile | Implemented (`selectPerson` → Person D sheet); **needs Xcode run** |
| 8 | Demo runs with no network | Implemented (`mockAll` default + simulated source); **needs Xcode run** |

Workstream "Done when": camera-hero, boxes, stable overlay, no flicker (EMA),
filter dimming, tap→profile — all implemented; UI behaviors require an Xcode run /
device to observe.

---

## 6. Finish-it checklist (run on a Mac with full Xcode)

**A. Build for Simulator (must succeed):**
```sh
cd app/ios/Recco
xcodebuild -project Recco.xcodeproj -scheme Recco \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
```
If the first compile surfaces Swift 6 concurrency *errors* (only if someone bumps
the language mode), the fixes are localized to `CameraViewModel`/`CameraSession`
frame plumbing — wrap frame hand-off in a `Sendable` box or annotate accordingly.

**B. Run in Simulator (`mockAll`, the default) and confirm:**
1. App opens to the camera hero (simulated backdrop: "Simulated camera").
2. 3 synthetic face boxes appear; the largest faces get overlay cards
   (Ava/Miles/Sam from the roster).
3. Long-press the camera → debug HUD; check request count climbs but is throttled
   (~1/sec/track), latency shows, "Show all boxes" works, force-match pins a
   person, simulated-face stepper changes count.
4. Toggle a chip in Person D's control strip → non-matching overlays dim.
5. Tap an overlay card → Person D's profile sheet opens.
6. Tap "Scan" → recognizes the largest face on demand.
7. Console prints `🧪 CameraSelfCheck: 19/19 passed` at launch.

**C. Device build compiles:**
```sh
xcodebuild -project Recco.xcodeproj -scheme Recco -destination 'generic/platform=iOS' build
```
(A code-signing-only failure without a provisioning profile is expected/acceptable.)

**D. Physical device (requires hardware — NOT verifiable by agent):**
1. Run on a real iPhone in `mockAll`; point the back camera at people.
2. Confirm face boxes track 2–3 faces without wild flicker (EMA smoothing).
3. Confirm front/back flip works and boxes stay aligned (front mirroring).
4. If backend is up: switch to `mockCV` then `live` (set `CONVEX_URL`); confirm
   `vision:matchFace` returns matches and overlays appear for enrolled people,
   and unknown faces show **no** named card.
5. Tune orientation/mirroring if boxes are offset (note in `CameraSession` rotation
   + `FaceGeometry` mirroring are the two knobs).

---

## 7. Commits

See `git log`. Work was committed in logical chunks:
merge → pure logic → clients → Vision/crop/session/preview → view + debug + sim
source → AppModel seam + RootView swap → self-check + progress log. Pushed to
`origin/person-c-ios-camera`.

---

## 8. Honest status summary

**Done:** all camera lane code written against the real contracts + Person D API,
placed so it auto-compiles into the target; integration seam + camera swap done;
contract-critical pure logic compiled and tested (19/19) and the non-UI layer
type-checks. **Not done (environment blocker, not a code gap):** full `xcodebuild`
compile and Simulator/device runs — this machine has no Xcode. Those steps are in
§6 and should be quick on a Mac with Xcode installed.
