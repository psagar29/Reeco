# Recco API Contracts

This file is the shared agreement between the computer vision team, backend team, and iOS team.

Freeze these shapes early. If one field changes, all four people need to know.

## Shared types

### Person

```ts
type Person = {
  id: string;
  name: string;
  role: string;
  company: string;
  avatarUrl?: string;
  bio: string;
  tags: string[];
  links: {
    github?: string;
    linkedin?: string;
    x?: string;
    site?: string;
  };
  whyTalk: string;
  openerSeed?: string;
  faceEmbedding?: number[] | null;
};
```

Rules:

- `id` is stable and used everywhere.
- `tags` must come from the fixed vocabulary.
- `faceEmbedding` is server-side data. iOS does not need it.

### BrainState

```ts
type BrainState = {
  activeFilter: FilterCommand;
  highlightedPersonId?: string | null;
  selectedPersonId?: string | null;
  visiblePersonIds: string[];
  dimmedPersonIds: string[];
  lastTranscript?: string | null;
  lastMatch?: FaceMatchResult | null;
  isThinking: boolean;
  updatedAt: number;
};
```

Rules:

- `visiblePersonIds` are the people that match the current filter.
- `dimmedPersonIds` can still be shown, just visually quieter.
- Camera overlays and Brain graph use the same state.

### FilterCommand

```ts
type FilterCommand = {
  action: "filter" | "rank" | "reset" | "draft";
  includeTags: string[];
  excludeTags: string[];
  rankBy?: "relevance" | "infra" | "growth" | "ai" | "founder" | null;
  targetPersonId?: string | null;
  rawText?: string | null;
};
```

Examples:

```json
{
  "action": "filter",
  "includeTags": ["AI", "Founder"],
  "excludeTags": [],
  "rankBy": "relevance",
  "targetPersonId": null,
  "rawText": "show me AI founders"
}
```

```json
{
  "action": "reset",
  "includeTags": [],
  "excludeTags": [],
  "rankBy": null,
  "targetPersonId": null,
  "rawText": "reset"
}
```

### FaceMatchResult

```ts
type FaceMatchResult = {
  trackId: string;
  status: "matched" | "tentative" | "unknown" | "no_face" | "error";
  personId?: string | null;
  score?: number | null;
  quality?: FaceQuality | null;
  message?: string | null;
  latencyMs?: number | null;
};
```

Rules:

- Show overlay only for `status === "matched"`.
- In demo mode, `tentative` may be shown only if debug is enabled.
- `unknown` should not create a distracting card.

### FaceQuality

```ts
type FaceQuality = {
  faceDetected: boolean;
  detectionScore?: number | null;
  cropWidth?: number | null;
  cropHeight?: number | null;
  model?: string | null;
};
```

### DraftResult

```ts
type DraftResult = {
  personId: string;
  subject?: string | null;
  opener: string;
  email?: string | null;
  generatedAt: number;
};
```

## Fixed tag vocabulary

Use this set unless the team explicitly changes it:

```txt
AI
Founder
Infra
Rust
Python
Design
Growth
DevTools
ML
Search
Seed
Backend
Frontend
Product
GoToMarket
Evaluation
```

## Computer Vision Service

Base URL local default:

```txt
http://127.0.0.1:8000
```

### GET /health

Response:

```json
{
  "ok": true,
  "model": "buffalo_l",
  "ready": true
}
```

### POST /embed

Request option A, JSON:

```json
{
  "imageBase64": "/9j/4AAQSkZJRgABAQ...",
  "imageMimeType": "image/jpeg",
  "requestId": "track_123"
}
```

Request option B, multipart:

```txt
file=<jpeg/png>
requestId=track_123
```

Pick one request style at Checkpoint 0. JSON base64 is easiest through Convex actions; multipart is better for direct HTTP.

Success response:

```json
{
  "requestId": "track_123",
  "faceDetected": true,
  "embedding": [0.0123, -0.0456],
  "quality": {
    "faceDetected": true,
    "detectionScore": 0.97,
    "cropWidth": 180,
    "cropHeight": 180,
    "model": "buffalo_l"
  },
  "latencyMs": 421
}
```

Failure response:

```json
{
  "requestId": "track_123",
  "faceDetected": false,
  "embedding": null,
  "quality": {
    "faceDetected": false,
    "cropWidth": 52,
    "cropHeight": 48,
    "model": "buffalo_l"
  },
  "error": "No usable face detected"
}
```

Embedding rules:

- Length must be 512.
- Values must be finite numbers.
- Embedding should be L2-normalized before return.
- Never return a partial-length embedding.

## Convex functions

Names can be adjusted to match Convex file structure, but the behavior must stay the same.

### people:list query

Input:

```ts
{}
```

Output:

```ts
Person[]
```

### state:get query

Input:

```ts
{}
```

Output:

```ts
BrainState
```

This is the main reactive subscription for iOS.

### state:setFilter mutation

Input:

```ts
{
  command: FilterCommand
}
```

Output:

```ts
BrainState
```

Rules:

- Recompute `visiblePersonIds` and `dimmedPersonIds`.
- Clear `highlightedPersonId` only on reset.
- Write `updatedAt`.

### vision:matchFace action

Input:

```ts
{
  imageBase64: string;
  imageMimeType: "image/jpeg" | "image/png";
  trackId: string;
}
```

Output:

```ts
FaceMatchResult
```

Behavior:

1. Call CV service `/embed`.
2. If no face, return `status: "no_face"`.
3. Compare embedding to enrolled people.
4. Return best match if above threshold.
5. Optionally write `lastMatch` and `highlightedPersonId` into `BrainState`.

Cosine similarity:

```ts
function cosine(a: number[], b: number[]): number {
  let dot = 0;
  let aa = 0;
  let bb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    aa += a[i] * a[i];
    bb += b[i] * b[i];
  }
  return dot / (Math.sqrt(aa) * Math.sqrt(bb));
}
```

Thresholds:

```ts
{
  strongMatchScore: 0.38,
  tentativeMatchScore: 0.30
}
```

Tune with real demo photos.

### voice:interpretCommand action

Input:

```ts
{
  transcript: string;
  visiblePersonIds?: string[];
}
```

Output:

```ts
FilterCommand
```

Rules:

- Only output JSON.
- Map user language into the fixed tag vocabulary.
- If user asks "who should I talk to", use `action: "rank"`.
- If user asks to reset, use `action: "reset"`.
- If user asks to draft, use `action: "draft"` and set `targetPersonId` when possible.

### drafts:createOpener action

Input:

```ts
{
  personId: string;
  userGoal?: string | null;
}
```

Output:

```ts
DraftResult
```

Style:

- Short.
- Human.
- Specific to that person's tags/bio.
- No fake claims.

Example:

```json
{
  "personId": "person_ava_shah",
  "subject": "Quick question on agent infra",
  "opener": "Hey Ava, I saw you are building multimodal agent infra. I am curious what latency issue has been hardest to tame so far.",
  "email": "Hey Ava,\n\nI saw you are building multimodal agent infra. I am curious what latency issue has been hardest to tame so far.\n\nWould love to compare notes for a minute at the hackathon.",
  "generatedAt": 1782522000000
}
```

### voice:getDeepgramToken action

Input:

```ts
{}
```

Output:

```ts
{
  "temporaryToken": "string",
  "expiresAt": 1782522000000
}
```

Fallback:

If temporary token setup is slow, Person 4 can use manual chips or a typed command bar for demo.

## HTTP bridge (iOS ↔ backend)

iOS calls the backend over plain HTTP/JSON (`URLSession`) via a thin bridge in
`backend/convex/http.ts`. These routes are **1:1 wrappers** over the Convex
functions above — **the DTO shapes are unchanged**; this section only documents
the transport. See `backend/README.md` for base-URL details and curl examples.

Base URL = the Convex **HTTP actions** URL (`CONVEX_SITE_URL`), i.e. the
`.convex.site` host (locally `http://127.0.0.1:3211`) — **not** the `.convex.cloud`
client URL.

| Method & path | Wraps | Request body | Response |
|---|---|---|---|
| `GET /api/health` | — | — | `{ ok: true, service: "recco-backend", time: number }` |
| `GET /api/people` | `people:list` | — | `Person[]` without `faceEmbedding` |
| `GET /api/state` | `state:get` | — | `BrainState` |
| `POST /api/state/filter` | `state:setFilter` | `{ command: FilterCommand }` | `BrainState` |
| `POST /api/voice/interpret` | `voice:interpretCommand` | `{ transcript, visiblePersonIds? }` | `FilterCommand` |
| `POST /api/drafts/opener` | `drafts:createOpener` | `{ personId, userGoal? }` | `DraftResult` |
| `POST /api/vision/match-face` | `vision:matchFace` | `{ imageBase64, imageMimeType?, trackId? }` | `FaceMatchResult` |
| `POST /api/identity/resolve` | `identity:resolveTarget` | `{ trackId, transcript?, faceImageBase64?, contextImageBase64?, imageMimeType? }` | `IdentityResolveResult` |
| `POST /api/voice/deepgram-token` | `voice:getDeepgramToken` | — | `{ temporaryToken, expiresAt }` |

Transport rules:

- All responses are JSON with `Access-Control-Allow-Origin: *`; every route
  answers `OPTIONS` preflight (`204`).
- Errors are JSON: `{ "ok": false, "error": string }`. Status: `200` ok,
  `400` invalid input, `404` unknown route, `500` unexpected error.
- `vision/match-face` enforces the matching safety rule: only `matched` and
  `tentative` carry a `personId`; `unknown` / `no_face` / `error` always have
  `personId: null`. Show an overlay name **only** for `status === "matched"`.
- `vision/match-face` request convenience: `imageMimeType` defaults to
  `image/jpeg`; `trackId` is generated when omitted.
- `identity/resolve` ("find info on him"): `trackId` is required; both crops are
  optional (a missing badge crop degrades to `needs_clarification`). The result
  `status` is only ever `"verified"` when the text match is strong AND the
  candidate's profile photo face-verified against the live face **using real CV
  embeddings** (never with mock embeddings / CV unavailable). iOS must not
  relabel a non-`verified` result. All external keys (OpenAI / Fiber / Deepgram)
  stay server-side.

### IdentityResolveResult (response of `POST /api/identity/resolve`)

```ts
type IdentityClue = {
  rawText: string;
  fullName?: string | null;     // OpenAI Vision returns this as `personName`
  company?: string | null;      // ...`companyName`
  role?: string | null;
  school?: string | null;       // ...`schoolName`
  confidence: number;           // 0..1
  evidence?: string | null;
};

type IdentityCandidate = {
  candidateId: string;
  fullName: string;
  headline?: string | null;
  role?: string | null;
  company?: string | null;
  school?: string | null;
  location?: string | null;
  linkedinUrl?: string | null;
  email?: string | null;
  profilePhotoUrl?: string | null;
  source: string;               // e.g. "fiber:kitchen-sink"
  matchScore: number;           // ranking score; verified candidates rank highest
};

type FaceVerification = {
  candidateId: string;
  verified: boolean;            // true only with REAL CV on both sides AND score >= threshold
  score?: number | null;        // cosine 0..1
  threshold: number;
  faceDetected: boolean;
  message?: string | null;
};

type IdentityResolveResult = {
  trackId: string;
  status: "verified" | "possible" | "not_found" | "needs_clarification" | "error";
  clue?: IdentityClue | null;
  candidates: IdentityCandidate[];
  bestCandidate?: IdentityCandidate | null;
  verification?: FaceVerification | null;
  message?: string | null;
  latencyMs?: number | null;
};
```

## iOS internal interfaces

iOS should define Swift models matching the shared types:

```swift
struct PersonDTO: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let role: String
    let company: String
    let avatarUrl: String?
    let bio: String
    let tags: [String]
    let links: PersonLinksDTO
    let whyTalk: String
    let openerSeed: String?
}
```

```swift
struct FaceMatchResultDTO: Codable, Equatable {
    let trackId: String
    let status: String
    let personId: String?
    let score: Double?
    let quality: FaceQualityDTO?
    let message: String?
    let latencyMs: Double?
}
```

## Camera recognition rules

- Do not send every video frame.
- Minimum crop size: 96 x 96 pixels.
- Preferred crop size: 160 x 160 or bigger.
- Send JPEG quality around 0.75.
- Max one request per track per 0.8-1.5 seconds.
- Cache a strong match for at least 10 seconds while the track remains stable.
- Hide overlays for unknown people by default.

## Demo fallback modes

The app should support three levels:

1. `mockAll`: no backend, local JSON, fake recognition.
2. `mockCV`: Convex works, CV action returns deterministic demo matches.
3. `live`: Convex + CV service + voice actions.

Use a hidden debug switch or compile flag.

## Environment variables

Backend:

```txt
CV_SERVICE_URL=http://127.0.0.1:8000
OPENAI_API_KEY=...
OPENAI_MODEL=gpt-4o-mini
DEEPGRAM_API_KEY=...
FACE_STRONG_MATCH_SCORE=0.38
FACE_TENTATIVE_MATCH_SCORE=0.30
# Identity lane ("find info on him"):
FIBER_API_KEY=...
FIBER_API_BASE_URL=https://api.fiber.ai
OPENAI_VISION_MODEL=gpt-4o
IDENTITY_MIN_OCR_CONFIDENCE=0.45
IDENTITY_FACE_VERIFY_THRESHOLD=0.32
```

iOS:

```txt
RECCO_API_BASE_URL=https://<deployment>.convex.site
CONVEX_URL=https://<deployment>.convex.site
DEMO_MODE=mockAll|mockCV|live
```

## Acceptance tests

Before demo lock, these must pass:

1. App launches to camera.
2. Manual chip "AI" changes overlay/Brain state.
3. One enrolled person is recognized from live camera or printed photo.
4. Low-confidence/unknown face does not show a wrong named overlay.
5. Voice or typed command "show me AI founders" updates filter.
6. Tapping a matched overlay opens profile.
7. Draft opener returns a useful sentence.
8. Demo can run without network using mock mode.
9. Typed/voice "find info on him" returns an identity result; in `mockAll` it is
   a plausible `possible` mock; "Verified" appears only when CV face-verifies a
   candidate against the live face (never with mock embeddings).

