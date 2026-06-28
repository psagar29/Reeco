<div align="center">

# Recco

**An iPhone AR networking assistant for hackathon and event floors.**

Point the camera at someone, say what you want, and Recco locks the target,
reads context from the scene, looks up identity data, saves the scan to a Brain
graph, and drafts the follow-up.

[Architecture](docs/ARCHITECTURE.md) · [API Contracts](docs/API_CONTRACTS.md) · [Demo Runbook](docs/DEMO_RUNBOOK.md) · [QA Checklist](docs/QA_CHECKLIST.md)

</div>

---

## Demo Story

Recco is built for the moment where you are holding your phone at a busy event
and want to know: "Who is this person, and are they worth talking to?"

The current demo flow:

1. **Set the mission** - first launch asks what you are here for today, such as
   "looking for investors", "hiring a Swift engineer", or "trying to get hired".
2. **Open the camera** - fullscreen iPhone camera with a clean AR intelligence
   layer, target reticle, face brackets, and a minimal scan / mic / keyboard dock.
3. **Lock a person** - the target closest to center becomes the active person.
4. **Ask by voice** - press the mic and say "find info on him" or type it.
5. **Resolve identity** - backend reads the badge/context with OpenAI Vision,
   searches profile data with Fiber, and verifies faces through the CV service
   when available.
6. **Save to Brain** - every resolved scan becomes a memory node with name,
   role, company, LinkedIn, confidence, lead score, and follow-up state.
7. **Draft outreach** - Recco generates a cold email / DM draft tailored to the
   mission and the person.
8. **Scout lazily** - Lazy GTM mode lets you say "find me 8 Swift engineers" or
   "find investors", then creates a prospect graph and outreach queue.

This is not a landing page or dashboard demo. The product is the AR lens.

## Current Live Demo Stack

| Layer | Status | Notes |
|---|---:|---|
| iOS app | Ready | SwiftUI app, fullscreen camera, AR overlay, Brain graph, mission setup, Lazy GTM, Deepgram voice client. |
| Convex backend | Ready | HTTP Actions power identity, voice tokens, Brain memories, mission scoring, GTM runs, outreach drafts. |
| CV service | Ready | FastAPI + InsightFace `/embed` service returns 512-d face embeddings. |
| OpenAI | Ready when env is set | Vision OCR for badges/context, mission parsing, outreach drafting. |
| Fiber | Ready when env is set | Profile / LinkedIn lookup for identity and GTM prospecting. |
| Deepgram | Ready when env is set | Streaming speech-to-text from the iPhone mic. |

The iOS app does **not** contain OpenAI, Fiber, or Deepgram secrets. Those live
in Convex environment variables. The app only talks to the public Convex HTTP
Actions URL.

Current public demo backend:

```txt
https://fabulous-hyena-861.convex.site
```

## Repository Layout

```txt
app/ios/Recco/             SwiftUI iPhone app
backend/                   Convex backend, TypeScript actions, tests
cv-service/                FastAPI InsightFace embedding service
tools/identity-debugger/   Browser test harness for identity resolution
demo-data/                 Demo roster seed data
docs/                      Architecture, API contracts, runbooks, QA
```

Main runtime flow:

```txt
iPhone camera
  -> face crop + context crop
  -> Convex HTTP Actions
  -> OpenAI Vision badge/context OCR
  -> Fiber profile lookup
  -> CV service face embedding / verification
  -> identity result + Brain memory + outreach draft
  -> iPhone AR overlay / Brain graph
```

## Run The iPhone App

Open the project:

```bash
open app/ios/Recco/Recco.xcodeproj
```

In Xcode:

1. Select the `Recco` scheme.
2. Select a connected iPhone.
3. Press `Cmd+R`.
4. Accept camera and microphone permissions on the phone.

The installed app falls back to the public Convex HTTP Actions URL in
`ReccoApp.swift`, so it can be launched from the iPhone home screen after the
cable is disconnected.

Command-line build:

```bash
xcodebuild \
  -project app/ios/Recco/Recco.xcodeproj \
  -scheme Recco \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData-demo \
  build
```

Install on a connected iPhone:

```bash
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

If the device is `unavailable`, unlock the iPhone, keep it awake, tap
`Trust This Computer`, and reconnect the cable.

## Backend Setup

```bash
cd backend
npm ci
npm run typecheck
npm test
```

Deploy/update the Convex dev deployment:

```bash
npx convex dev --once --typecheck=disable
```

Health check:

```bash
curl https://fabulous-hyena-861.convex.site/api/health
```

Seed the roster:

```bash
cd backend
npx convex run seed:run
```

Seed with real face embeddings:

```bash
cd backend
npm run enroll
npx convex run seed:run "{\"embeddings\": $(cat ../demo-data/embeddings.generated.json)}"
```

Use Git Bash or macOS/Linux shells for JSON arguments. Windows PowerShell often
mangles nested quotes.

## Required Backend Env

Set these on the Convex deployment with `npx convex env set KEY value`.

| Variable | Purpose |
|---|---|
| `OPENAI_API_KEY` | Badge/context OCR, mission parsing, outreach generation. |
| `OPENAI_MODEL` | Text model for parsing/drafting. |
| `OPENAI_VISION_MODEL` | Vision model for badge/context OCR. |
| `FIBER_API_KEY` | Profile, LinkedIn, and prospect lookup. |
| `FIBER_API_BASE_URL` | Fiber base URL, usually `https://api.fiber.ai`. |
| `DEEPGRAM_API_KEY` | Streaming voice token minting. |
| `CV_SERVICE_URL` | Face embedding service URL, for example `http://host:8000`. |
| `IDENTITY_MIN_OCR_CONFIDENCE` | Confidence floor before lookup. |
| `IDENTITY_FACE_VERIFY_THRESHOLD` | Face verification threshold. |
| `FACE_STRONG_MATCH_SCORE` | Known-person face match threshold. |
| `FACE_TENTATIVE_MATCH_SCORE` | Tentative face match threshold. |

Do not put secret keys into the iOS app.

## CV Service

```bash
cd cv-service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

Health check:

```bash
curl http://127.0.0.1:8000/health
```

Expected shape:

```json
{"ok":true,"model":"buffalo_s","ready":true}
```

For iPhone demos, host this somewhere the Convex deployment can reach. EC2 works
well for the hackathon path. Set `CV_SERVICE_URL` in Convex to that public URL.

## Demo Script

Use this as the live walkthrough.

1. Launch Recco on iPhone.
2. In the first mission prompt, type or choose a goal:
   - `Looking for investors`
   - `Hiring a Swift engineer`
   - `Trying to get hired`
3. Point the camera at the person.
4. Keep them near the center reticle.
5. Press the mic and say:
   - `Find info on him`
   - or type the same command with the keyboard button.
6. Show the scan phases:
   - target locked
   - reading badge/context
   - searching profile
   - verifying face
   - result ready
7. Open the result:
   - name
   - role/company
   - LinkedIn
   - confidence
   - generated opener
8. Open Brain:
   - scanned person appears as a memory node
   - priority is based on the mission
   - follow-up draft is available
9. Open Lazy GTM:
   - say `Find 8 Swift engineers`
   - show generated prospect graph
   - open a prospect
   - generate outreach

## Verify Before Demo

Backend:

```bash
cd backend
npm run typecheck
npm test
curl https://fabulous-hyena-861.convex.site/api/health
curl https://fabulous-hyena-861.convex.site/api/people
```

CV:

```bash
curl http://<CV_HOST>:8000/health
```

iPhone:

```bash
xcrun devicectl list devices
```

Then run one real scan on the phone before going on stage.

## Safety And Privacy Notes

- The app should only scan people in a context where demo participants consent.
- Raw face and badge images are used for resolution, but the persistent Brain
  stores text, links, scores, notes, and outreach state, not raw images.
- Unknown or low-confidence faces should not be shown as named people.
- Secrets stay on the backend. The phone receives only public results and
  short-lived voice tokens.

## Useful Docs

- [Demo runbook](docs/DEMO_RUNBOOK.md) - exact on-stage flow and setup checks.
- [Architecture](docs/ARCHITECTURE.md) - current system design and data flow.
- [API contracts](docs/API_CONTRACTS.md) - HTTP routes and DTO shapes.
- [QA checklist](docs/QA_CHECKLIST.md) - demo readiness and verification commands.
- [Backend README](backend/README.md) - Convex setup, env, seed, and smoke checks.
- [iOS README](app/ios/Recco/README.md) - Xcode/device install and app structure.
- [CV service README](cv-service/README.md) - FastAPI/InsightFace service.
- [Identity debugger](tools/identity-debugger/README.md) - browser harness for profile lookup testing.
- [Face enrollment](docs/FACE_ENROLLMENT.md) - enrollment photos and embedding workflow.

## License

Recco is released under the [MIT License](LICENSE).

The license covers this repository's source code and documentation. It does not
grant rights to third-party services, SDKs, model weights, event data, LinkedIn
profiles, generated demo images, or user-provided photos. Use OpenAI, Convex,
Deepgram, Fiber, InsightFace/ONNXRuntime, Apple SDKs, and any public profile data
under their own terms and applicable privacy rules.
