# Recco Demo Runbook

This is the operator guide for showing Recco on an iPhone. It assumes the
Convex deployment, CV service, and iPhone app are already built from this repo.

Related docs: [Architecture](ARCHITECTURE.md) · [API Contracts](API_CONTRACTS.md) ·
[QA Checklist](QA_CHECKLIST.md) · [Face Enrollment](FACE_ENROLLMENT.md)

---

## Demo Goal

Show that Recco lets someone walk through an event, point their iPhone at a
person, understand who they are, save the encounter to a Brain graph, and draft
the next follow-up.

The intended live path is:

```txt
mission setup -> camera target lock -> voice/typed command
  -> identity resolve -> Brain memory -> outreach draft
  -> Lazy GTM prospect graph
```

## Pre-Demo Requirements

| Area | Requirement |
|---|---|
| iPhone | iOS 17+, camera and microphone permissions enabled. |
| Mac | Xcode installed, signing profile available, iPhone trusted by the Mac. |
| Backend | Convex HTTP Actions deployed and reachable on `.convex.site`. |
| CV | FastAPI service reachable from Convex through `CV_SERVICE_URL`. |
| Keys | OpenAI, Fiber, and Deepgram keys set in Convex env. |
| Network | iPhone has internet; CV service public URL is reachable from Convex. |

Current demo backend:

```txt
https://fabulous-hyena-861.convex.site
```

## Environment

Set backend secrets on the Convex deployment:

```bash
cd backend
npx convex env set OPENAI_API_KEY sk-...
npx convex env set OPENAI_MODEL gpt-4o-mini
npx convex env set OPENAI_VISION_MODEL gpt-4o
npx convex env set FIBER_API_KEY ...
npx convex env set FIBER_API_BASE_URL https://api.fiber.ai
npx convex env set DEEPGRAM_API_KEY ...
npx convex env set CV_SERVICE_URL http://<cv-host>:8000
```

Useful thresholds:

```bash
npx convex env set FACE_STRONG_MATCH_SCORE 0.38
npx convex env set FACE_TENTATIVE_MATCH_SCORE 0.30
npx convex env set IDENTITY_MIN_OCR_CONFIDENCE 0.45
npx convex env set IDENTITY_FACE_VERIFY_THRESHOLD 0.32
```

The iOS app must not contain these secret values. It only needs the public
backend origin, currently baked into `ReccoApp.swift` as an installed-app
fallback.

## Backend Check

```bash
cd backend
npm ci
npm run typecheck
npm test
npx convex dev --once --typecheck=disable
curl https://fabulous-hyena-861.convex.site/api/health
curl https://fabulous-hyena-861.convex.site/api/people
```

Expected:

- TypeScript typecheck passes.
- Vitest suite passes.
- `/api/health` returns `{ "ok": true, "service": "recco-backend", ... }`.
- `/api/people` returns public roster entries with no face embeddings.

## CV Check

```bash
curl http://<cv-host>:8000/health
```

Expected shape:

```json
{
  "ok": true,
  "model": "buffalo_s",
  "ready": true
}
```

Enrollment and live matching should use the same model.

## iPhone Install

```bash
open app/ios/Recco/Recco.xcodeproj
```

In Xcode:

1. Select the `Recco` scheme.
2. Select the connected iPhone.
3. Press `Cmd+R`.
4. Accept camera and microphone permissions.

Command-line install:

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

After install, the app can be launched from the iPhone home screen without the
cable.

## On-Stage Flow

### 1. Set Mission

Launch the app. The first screen is a glass mission prompt over the blurred app.
Choose or type a goal:

- `Looking for investors`
- `Hiring a Swift engineer`
- `Trying to get hired`
- `Looking for customers`

Explain that this mission controls lead priority, outreach tone, and Brain
ranking.

### 2. Show Camera Lens

Move to the fullscreen camera. Keep the person near the center reticle. The UI
should show restrained face brackets, a minimal bottom dock, and the live
intelligence panel.

### 3. Resolve A Person

Use either:

- mic: `Find info on him`
- keyboard: `Find info on him`
- scan button: run the current target scan

Expected scan phases:

```txt
target locked
reading badge/context
searching profile
verifying face
result ready
```

Expected result card:

- name
- role/company/headline when available
- LinkedIn button
- confidence state
- generated opener

### 4. Save To Brain

Open Brain. The scan should appear as a memory node. The detail view should show:

- profile summary
- LinkedIn/email if available
- mission-based priority (`hot`, `warm`, `cold`, or `needs_info`)
- lead reasons
- cold email / LinkedIn DM / in-person opener variants
- channel selector before marking a fake send

### 5. Lazy GTM

Tap the Lazy GTM control. Say or type:

```txt
Find 8 Swift engineers
```

Expected:

- voice/text request parses into a GTM run
- prospects appear as a separate graph/list
- prospect detail shows match reasons and missing info
- outreach can be drafted
- fake send updates status

## What To Say

Short script:

> Recco is an AR networking assistant. I tell it my goal for the event, then
> point my phone at someone. It locks the target, reads the badge/context,
> searches for the right profile, verifies when it can, and saves the encounter
> into a Brain graph. From there it drafts the follow-up and helps me prioritize
> who is actually worth talking to.

For Lazy GTM:

> If I do not want to manually scan the room, I can ask Scout Mode for the kind
> of people I want, and it builds a prospect graph with outreach ready to edit.

## Final Pre-Show Checklist

- [ ] `curl https://fabulous-hyena-861.convex.site/api/health` returns OK.
- [ ] `curl http://<cv-host>:8000/health` returns ready.
- [ ] iPhone app launches from the home screen.
- [ ] Camera permission granted.
- [ ] Microphone permission granted.
- [ ] One real scan has been tested.
- [ ] Brain shows the saved scan.
- [ ] Lazy GTM creates a prospect run.
- [ ] No secrets are present in iOS source or committed files.
