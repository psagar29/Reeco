# Recco Backend

Convex backend for the Recco iPhone demo. It powers the public HTTP API used by
the app, stores Brain memories, owns all API keys, and integrates with OpenAI,
Fiber, Deepgram, and the CV service.

Related docs: [API Contracts](../docs/API_CONTRACTS.md) ·
[Architecture](../docs/ARCHITECTURE.md) · [Demo Runbook](../docs/DEMO_RUNBOOK.md)

---

## Quick Start

```bash
cd backend
npm ci
npm run typecheck
npm test
```

Run/update Convex:

```bash
npx convex dev --once --typecheck=disable
```

Health:

```bash
curl https://fabulous-hyena-861.convex.site/api/health
```

## What Lives Here

```txt
convex/
  http.ts              public HTTP Actions used by iOS
  identity.ts          OpenAI Vision + Fiber + CV identity resolution
  vision.ts            known-person face matching
  voice.ts             Deepgram token + command interpretation
  mission.ts           today's goal parsing/storage
  scanMemories.ts      Brain memories, scoring, outreach, follow-up status
  gtm.ts               Lazy GTM runs, prospects, outreach
  people.ts            public roster + private enrolled embeddings
  schema.ts            Convex tables and indexes
  lib/                 pure helpers and shared types
scripts/
  enroll.ts            generate face embeddings from enrollment photos
  smoke.ts             local contract smoke checks
test/
  *.test.ts            Vitest suite
```

## Environment

Set secrets on the Convex deployment:

```bash
npx convex env set OPENAI_API_KEY sk-...
npx convex env set OPENAI_MODEL gpt-4o-mini
npx convex env set OPENAI_VISION_MODEL gpt-4o
npx convex env set FIBER_API_KEY ...
npx convex env set FIBER_API_BASE_URL https://api.fiber.ai
npx convex env set DEEPGRAM_API_KEY ...
npx convex env set CV_SERVICE_URL http://<cv-host>:8000
```

Optional thresholds:

```bash
npx convex env set FACE_STRONG_MATCH_SCORE 0.38
npx convex env set FACE_TENTATIVE_MATCH_SCORE 0.30
npx convex env set IDENTITY_MIN_OCR_CONFIDENCE 0.45
npx convex env set IDENTITY_FACE_VERIFY_THRESHOLD 0.32
```

Local scripts may also read `backend/.env.local`. Do not commit `.env.local`.

## HTTP API

Base URL is the Convex HTTP Actions URL, ending in `.convex.site`.

Important routes:

| Route | Purpose |
|---|---|
| `GET /api/health` | backend health. |
| `GET /api/people` | public people, no embeddings. |
| `GET /api/state` | current `BrainState`. |
| `POST /api/vision/match-face` | known-person face match. |
| `POST /api/identity/resolve` | badge/name/profile identity lookup. |
| `POST /api/voice/deepgram-token` | short-lived Deepgram token. |
| `POST /api/mission/parse` | parse today's goal. |
| `GET /api/brain/memories` | list saved scan memories. |
| `POST /api/brain/memories/upsert` | save an identity result to Brain. |
| `POST /api/brain/memories/outreach` | generate memory outreach. |
| `POST /api/gtm/run` | create Lazy GTM prospect run. |
| `GET /api/gtm/prospects` | list GTM prospects. |

Full request and response shapes are in
[API Contracts](../docs/API_CONTRACTS.md).

## Seeding And Enrollment

Seed the demo roster:

```bash
npx convex run seed:run
```

Generate face embeddings from enrollment photos:

```bash
cd backend
npm run enroll
npx convex run seed:run "{\"embeddings\": $(cat ../demo-data/embeddings.generated.json)}"
```

Use macOS/Linux shells or Git Bash for JSON arguments. PowerShell may mangle
nested quotes.

Enrollment notes:

- `npm run enroll` calls `CV_SERVICE_URL /embed` when available.
- Missing photos or unavailable CV service fall back to deterministic mock
  embeddings.
- Enrollment and live matching must use the same CV model.
- Generated embeddings are git-ignored.

## Verification

```bash
cd backend
npm run typecheck
npm test
python3 ../scripts/check_markdown_links.py
```

Current suite:

```txt
9 test files
167 tests
```

Live smoke:

```bash
BASE=https://fabulous-hyena-861.convex.site
curl "$BASE/api/health"
curl "$BASE/api/people"
```

Identity smoke with a transcript-only fallback:

```bash
curl -X POST "$BASE/api/identity/resolve" \
  -H "Content-Type: application/json" \
  -d '{"trackId":"smoke","transcript":"find info on Jordan Lee","faceImageBase64":"","contextImageBase64":"","imageMimeType":"image/jpeg"}'
```

## Data Safety

- iOS sends face/context images for immediate resolution only.
- Persistent tables store text, links, scores, notes, and outreach state.
- `people.faceEmbedding` is server-side only.
- API keys live in Convex env only.
- Low-confidence face matches must not return a named overlay.
