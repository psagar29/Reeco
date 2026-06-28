# Architecture

Recco is a monorepo of three runnable services plus shared contracts. They
communicate through a small set of frozen types defined in
[`API_CONTRACTS.md`](API_CONTRACTS.md).

## Components

### 1. iOS app — `app/ios/Recco` (SwiftUI)

The product surface. Camera-first, with a control strip (chips + voice/typed
command bar + transcript ribbon), a Brain graph, profile sheets, and opener
drafting.

Internally organized around a single observable **`AppModel`** that owns the
shared `BrainState` (active filter, visible/dimmed person ids, selection,
transcript, thinking). Every input path — manual chips, typed commands, and
voice — funnels through one `apply(FilterCommandDTO)` method, so the camera
overlays and the Brain graph always reflect the same state.

The app talks only to a `ReccoBackend` protocol. Two implementations:

- `MockBackend` — fully offline (local roster, on-device command parsing and
  opener generation). Powers `mockAll`.
- `ConvexBackend` — the seam to the real backend. Powers `mockCV` / `live`.

The camera pipeline (capture → Vision tracking → throttle/cache → crop →
recognize) feeds results back via `AppModel.applyMatch` and opens profiles via
`AppModel.selectPerson`.

### 2. Backend — `backend/` (Convex + TypeScript)

The reactive brain. A single `appState` singleton holds the `BrainState` that
iOS subscribes to. Pure, framework-free logic libs (`filter`, `similarity`,
`voiceParser`, `opener`) are unit-tested without a live deployment.

Functions (see contracts):

| Function | Kind | Purpose |
|----------|------|---------|
| `people:list` | query | roster (no embeddings) |
| `state:get` | query | the reactive `BrainState` (main iOS subscription) |
| `state:setFilter` | mutation | recompute visible/dimmed for a `FilterCommand` |
| `vision:matchFace` | action | CV `/embed` → cosine match → classify → record |
| `voice:interpretCommand` | action | NL → `FilterCommand` (OpenAI + offline fallback) |
| `drafts:createOpener` | action | opener/email (OpenAI + templated fallback) |
| `voice:getDeepgramToken` | action | short-lived Deepgram token |

Every action degrades gracefully: no API key → deterministic offline path.

### 3. CV service — `cv-service/` (FastAPI + InsightFace)

Stateless face → embedding. `POST /embed` accepts a JPEG/PNG (base64 or
multipart) and returns a **512-dimensional, L2-normalized ArcFace embedding** for
the largest face, plus quality metadata. `GET /health` reports model readiness.

Default model is `buffalo_s` (MobileFaceNet recognition) for ~90 ms warm CPU
latency; set `RECCO_CV_MODEL=buffalo_l` for the higher-accuracy ResNet50 net.

> **Important:** enrollment and live matching must use the **same** model —
> embeddings from `buffalo_s` and `buffalo_l` are not comparable.

## Data flow

```
                         ┌──────────────────────────────────────────────┐
                         │                  iOS app                     │
                         │                                              │
   voice / chips ───────►│  AppModel.apply(FilterCommand)               │
                         │       │                                      │
   camera frame ─► crop ─┼───────┼──► ConvexBackend.matchFace ──┐       │
                         │       ▼                              │       │
                         │   BrainState  ◄── state:get (reactive)│       │
                         └───────┼──────────────────────────────┼───────┘
                                 │                              │
                                 ▼                              ▼
                         ┌───────────────┐  vision:matchFace ┌──────────────┐
                         │    backend    │ ────────────────► │  cv-service  │
                         │   (Convex)    │   POST /embed     │ (InsightFace)│
                         │               │ ◄──────────────── │  512-d emb   │
                         │ cosine match  │                   └──────────────┘
                         │ vs enrolled   │
                         └───────────────┘
```

## Enrollment

Face matching needs enrolled embeddings stored in Convex:

1. Collect 1+ photo per roster person under `demo-data/enrollment/`.
2. Run `cd backend && npm run enroll` — sends each photo to the CV service
   `/embed` and writes the embedding onto that person in Convex.
3. At match time, `vision:matchFace` cosine-compares a live crop against all
   enrolled embeddings and classifies against thresholds
   (`strong = 0.38`, `tentative = 0.30` — re-tune per model).

## Contracts

The boundary types (`Person`, `BrainState`, `FilterCommand`, `FaceMatchResult`,
`DraftResult`, `FaceQuality`) are frozen in [`API_CONTRACTS.md`](API_CONTRACTS.md)
and mirrored on both sides: Swift DTOs in `app/ios/Recco/Recco/Models/` and
TypeScript types in `backend/convex/lib/types.ts`. Changing a shape means
updating both plus the contract doc.

## Demo modes

| Mode | Backend | CV | Notes |
|------|---------|----|-------|
| `mockAll` | local JSON | fake | fully offline; stage-safe default |
| `mockCV` | Convex | deterministic | backend real, recognition faked |
| `live` | Convex | real | full pipeline |
