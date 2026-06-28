# Recco Architecture

Recco is a camera-first iPhone app backed by Convex, a small CV embedding
service, and sponsor/API integrations for identity, voice, and outreach.

The product surface is the iPhone AR lens. The backend owns secrets, scoring,
lookup, memory, and outreach generation.

---

## System Overview

```txt
                 ┌─────────────────────────────────────────────┐
                 │ iPhone app                                  │
                 │ SwiftUI + AVFoundation + Vision             │
                 │                                             │
                 │ camera / face boxes / reticle / hologram    │
                 │ mission setup / Brain graph / Lazy GTM      │
                 └──────────────────┬──────────────────────────┘
                                    │ HTTPS JSON
                                    ▼
                 ┌─────────────────────────────────────────────┐
                 │ Convex backend                              │
                 │ HTTP Actions + queries/mutations/actions     │
                 │                                             │
                 │ identity, voice tokens, Brain memories,     │
                 │ mission scoring, GTM runs, outreach drafts  │
                 └───────┬──────────────┬──────────────┬───────┘
                         │              │              │
                         ▼              ▼              ▼
              ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
              │ CV service   │ │ OpenAI       │ │ Fiber        │
              │ InsightFace  │ │ Vision/text  │ │ profiles/GTM │
              └──────────────┘ └──────────────┘ └──────────────┘
                         │
                         ▼
                 ┌──────────────┐
                 │ Deepgram     │
                 │ STT tokens   │
                 └──────────────┘
```

## iOS App

Path: `app/ios/Recco/`

The iOS app is pure SwiftUI with system frameworks. It has no third-party
package dependency and no backend secrets.

Key areas:

| Area | Files | Role |
|---|---|---|
| App shell | `ReccoApp.swift`, `Views/RootView.swift` | launches live app and injects `AppModel`. |
| Camera | `Camera/*` | AVFoundation camera session, Vision face tracking, crops, recognition client. |
| AR UI | `Views/AR/*`, `CommandDockView.swift` | face brackets, target reticle, scan timeline, hologram panel, minimal controls. |
| State | `State/AppModel.swift` | single app model for camera, mission, voice, identity, Brain, GTM. |
| Backend client | `State/Backend/ConvexBackend.swift` | `URLSession` client for Convex HTTP Actions. |
| Brain | `Views/Brain*.swift`, `Models/BrainGraphModel.swift` | saved scan graph, details, outreach state. |
| Mission | `Views/MissionSetupView.swift`, `Models/MissionProfileDTO.swift` | first-launch goal and scoring context. |
| Lazy GTM | `Views/LazyGTMVoicePanelView.swift`, `Views/GTMScout*.swift`, `Models/GTMModels.swift` | voice/text prospect search graph. |

Launch behavior:

- Default mode is live unless `DEMO_MODE` overrides it.
- The app prefers `RECCO_API_BASE_URL`, then `CONVEX_URL`, then the public demo
  backend baked into `ReccoApp.swift`.
- Secrets are never stored in iOS.

## Backend

Path: `backend/`

Convex owns the API, persistent state, external API calls, and all secrets.
The iPhone calls ordinary HTTP JSON routes served by Convex HTTP Actions.

Main modules:

| Module | Role |
|---|---|
| `convex/http.ts` | public HTTP bridge used by iOS and browser tools. |
| `convex/identity.ts` | `find info on him`: OCR, Fiber lookup, CV face verification. |
| `convex/vision.ts` | known-person face matching against enrolled embeddings. |
| `convex/voice.ts` | command interpretation and Deepgram token minting. |
| `convex/mission.ts` | parses and stores today's goal. |
| `convex/scanMemories.ts` | durable Brain memories and outreach generation. |
| `convex/gtm.ts` | Lazy GTM prospect search, scoring, and outreach. |
| `convex/people.ts` | public roster and private enrollment embeddings. |
| `convex/schema.ts` | Convex tables and indexes. |

Important tables:

| Table | Purpose |
|---|---|
| `people` | demo/enrolled roster plus private face embeddings. |
| `appState` | singleton `BrainState` for filter/highlight state. |
| `faceMatches` | debug log of known-person match attempts. |
| `identityLookups` | text/scores-only log of identity resolution. |
| `scanMemories` | durable people the user scanned at an event. |
| `missionProfiles` | one mission per anonymous client id. |
| `gtmRuns` | Lazy GTM search requests. |
| `gtmProspects` | prospects found for GTM runs. |

## CV Service

Path: `cv-service/`

The CV service is a stateless FastAPI app around InsightFace. It exposes:

- `GET /health`
- `POST /embed`

`/embed` accepts a base64 or multipart image and returns:

- `faceDetected`
- `embedding: number[512] | null`
- `quality`
- `latencyMs`

Enrollment and live matching must use the same model. The current demo service
uses `buffalo_s`.

## Identity Flow

```txt
iPhone captures:
  faceImageBase64        tight face crop
  contextImageBase64     wider person/badge crop
  transcript             "find info on him" or typed equivalent

POST /api/identity/resolve
  -> OpenAI Vision reads badge/context
  -> spoken/provided name is merged as a clue
  -> Fiber searches candidate profiles
  -> CV embeds live face
  -> CV embeds candidate profile photos when available
  -> backend scores candidates
  -> iOS receives IdentityResolveResult
```

Identity statuses:

- `verified` - face verification confirmed the selected profile.
- `possible` - profile/name found but face verification did not confirm.
- `needs_clarification` - badge/name clue was too weak.
- `not_found` - no usable profile candidate.
- `error` - structured backend error.

The app should never show a low-confidence face as a named person.

## Brain Flow

```txt
IdentityResolveResult
  -> /api/brain/memories/upsert
  -> dedupe by LinkedIn, then name+company
  -> score against MissionProfile
  -> generate / update OutreachDraft
  -> render in Brain graph
```

Brain memories store extracted profile text, links, confidence, notes, lead
scores, and outreach state. They do not store raw face or badge images.

## Mission Flow

```txt
first launch prompt
  -> /api/mission/parse
  -> MissionProfile
  -> UserDefaults + backend missionProfiles
  -> lead scoring for future scans
```

Examples:

- `Looking for investors`
- `Hiring a Swift engineer`
- `Trying to get hired`
- `Looking for customers`

Mission fields influence:

- lead priority
- lead reasons
- next action
- outreach channel and tone
- Brain graph grouping

## Lazy GTM Flow

```txt
voice/text request
  -> /api/gtm/run
  -> parse GTM intent
  -> Fiber/OpenAI-backed prospect generation
  -> score prospects
  -> render GTM graph/list
  -> /api/gtm/prospects/outreach
  -> /api/gtm/prospects/status
```

Lazy GTM prospects are separate from Brain scan memories. Scan memories are
people the user actually encountered; GTM prospects are AI-found outbound leads.

## HTTP Surface

The iOS app uses the Convex `.convex.site` HTTP Actions URL, not the
`.convex.cloud` client URL.

Current primary routes:

| Route | Purpose |
|---|---|
| `GET /api/health` | backend health. |
| `GET /api/people` | public roster. |
| `GET /api/state` | current `BrainState`. |
| `POST /api/vision/match-face` | known-person face matching. |
| `POST /api/identity/resolve` | live identity lookup. |
| `POST /api/voice/deepgram-token` | short-lived Deepgram token. |
| `POST /api/mission/parse` | parse/store mission. |
| `GET /api/brain/memories` | list scan memories. |
| `POST /api/brain/memories/upsert` | save identity result. |
| `POST /api/brain/memories/outreach` | generate memory outreach. |
| `POST /api/brain/memories/follow-up-status` | update fake send/follow-up state. |
| `POST /api/gtm/run` | create Lazy GTM run. |
| `GET /api/gtm/runs` | list GTM runs. |
| `GET /api/gtm/prospects` | list GTM prospects. |
| `POST /api/gtm/prospects/outreach` | generate prospect outreach. |
| `POST /api/gtm/prospects/status` | update prospect status. |

Full shapes are in [API Contracts](API_CONTRACTS.md).

## Privacy Boundaries

- iOS sends images only for immediate resolution.
- Persistent Brain data stores text, links, scores, notes, and outreach state.
- Raw face/badge images are not persisted by the app contract.
- OpenAI, Fiber, and Deepgram keys live only in Convex env.
- Unknown/low-confidence results should stay unnamed.

## Verification

Use [QA Checklist](QA_CHECKLIST.md) before demo:

```bash
cd backend
npm run typecheck
npm test
curl https://fabulous-hyena-861.convex.site/api/health
curl http://<cv-host>:8000/health
```
