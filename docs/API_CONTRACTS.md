# Recco API Contracts

This is the shared contract between the iOS app, Convex backend, CV service, and
demo/debug tooling.

The iOS app talks to Convex over HTTP JSON through the `.convex.site` HTTP
Actions origin. It does not use the Convex client SDK and does not hold secret
API keys.

Current demo backend:

```txt
https://fabulous-hyena-861.convex.site
```

---

## General Rules

- All timestamps are Unix epoch milliseconds.
- Image payloads are base64 strings without a `data:` prefix.
- All HTTP responses are JSON.
- Backend errors use `{ "ok": false, "error": "..." }`.
- Public people and memories must never include `faceEmbedding`.
- Raw face/badge images are not persisted in Brain memory payloads.
- iOS should show a named face overlay only for `FaceMatchResult.status === "matched"`.

## Shared Types

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
  faceEmbedding?: number[] | null; // server-side only
};
```

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

## Identity Types

### IdentityClue

```ts
type IdentityClue = {
  rawText: string;
  fullName?: string | null;
  company?: string | null;
  role?: string | null;
  school?: string | null;
  confidence: number;
  evidence?: string | null;
};
```

### IdentityCandidate

```ts
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
  source: string;
  matchScore: number;
};
```

### FaceVerification

```ts
type FaceVerification = {
  candidateId: string;
  verified: boolean;
  score?: number | null;
  threshold: number;
  faceDetected: boolean;
  message?: string | null;
};
```

### IdentityResolveResult

```ts
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

## Mission And Lead Types

```ts
type MissionProfile = {
  id?: string | null;
  clientId?: string | null;
  rawText: string;
  goalType:
    | "fundraising"
    | "hiring"
    | "get_hired"
    | "customers"
    | "sponsors"
    | "cofounder"
    | "founders"
    | "networking"
    | "other";
  targetRoles: string[];
  targetKeywords: string[];
  targetCompanies: string[];
  targetIndustries: string[];
  preferredAction: "linkedin_dm" | "cold_email" | "in_person" | "reminder";
  userContext?: string | null;
  tone: string;
  createdAt: number;
  updatedAt: number;
};

type LeadPriority = "hot" | "warm" | "cold" | "needs_info";
type FollowUpStatus = "new" | "drafted" | "edited" | "sent" | "archived";
type FollowUpChannel = "linkedin_dm" | "cold_email" | "in_person";
```

### OutreachDraft

```ts
type OutreachDraft = {
  linkedinDm: string;
  coldEmailSubject: string;
  coldEmail: string;
  inPersonOpener: string;
  generatedAt: number;
};
```

### ScanMemory

```ts
type ScanMemory = {
  id: string;
  scanId: string;
  personId?: string | null;
  name?: string | null;
  headline?: string | null;
  role?: string | null;
  company?: string | null;
  school?: string | null;
  linkedinUrl?: string | null;
  email?: string | null;
  confidence: "verified" | "possible" | "needs_confirmation" | "unknown";
  confidenceScore?: number | null;
  sources: string[];
  notes?: string | null;
  badgeText?: string | null;
  outreach?: OutreachDraft | null;
  firstScannedAt: number;
  lastScannedAt: number;
  scanCount: number;
  clientId?: string | null;
  leadPriority?: LeadPriority | null;
  leadScore?: number | null;
  leadReasons: string[];
  nextAction?: string | null;
  followUpStatus: FollowUpStatus;
  followUpChannel?: FollowUpChannel | null;
  sentAt?: number | null;
  editedOutreach?: OutreachDraft | null;
  missionSnapshot?: MissionProfile | null;
};
```

### ScanMemoryInput

```ts
type ScanMemoryInput = {
  scanId: string;
  status: string;
  clientId?: string | null;
  mission?: MissionProfile | null;
  name?: string | null;
  headline?: string | null;
  role?: string | null;
  company?: string | null;
  school?: string | null;
  linkedinUrl?: string | null;
  email?: string | null;
  confidenceScore?: number | null;
  personId?: string | null;
  transcript?: string | null;
  badgeText?: string | null;
  hadFaceVerification: boolean;
  candidateCount: number;
};
```

## Lazy GTM Types

```ts
type GTMIntent = {
  rawText: string;
  goalType: string;
  searchQuery: string;
  targetRoles: string[];
  targetKeywords: string[];
  targetCompanies: string[];
  targetIndustries: string[];
  count: number;
  preferredAction: "linkedin_dm" | "cold_email" | "in_person" | "reminder";
};

type GTMRun = {
  id: string;
  clientId: string;
  rawText: string;
  parsedIntent?: GTMIntent | null;
  goalType: string;
  query: string;
  count: number;
  status: string;
  errorMessage?: string | null;
  createdAt: number;
  updatedAt: number;
};

type GTMProspect = {
  id: string;
  runId: string;
  clientId: string;
  prospectId: string;
  name: string;
  headline?: string | null;
  role?: string | null;
  company?: string | null;
  location?: string | null;
  linkedinUrl?: string | null;
  email?: string | null;
  profilePhotoUrl?: string | null;
  source: string;
  matchScore: number;
  priority: LeadPriority;
  reasons: string[];
  missingInfo: string[];
  outreach?: OutreachDraft | null;
  selectedChannel?: FollowUpChannel | null;
  status: "new" | "drafted" | "sent" | "archived";
  sentAt?: number | null;
  createdAt: number;
  updatedAt: number;
};

type GTMRunResult = {
  run: GTMRun;
  prospects: GTMProspect[];
};
```

## CV Service

Base URL example:

```txt
http://<cv-host>:8000
```

### GET /health

```json
{
  "ok": true,
  "model": "buffalo_s",
  "ready": true,
  "detSize": 320,
  "minDetScore": 0.3
}
```

### POST /embed

Request:

```json
{
  "imageBase64": "/9j/4AAQSkZJRgABAQ...",
  "imageMimeType": "image/jpeg",
  "requestId": "track_123"
}
```

Response:

```ts
type EmbedResponse = {
  requestId?: string;
  faceDetected: boolean;
  embedding: number[] | null; // length 512 when present
  quality?: FaceQuality | null;
  latencyMs?: number | null;
  error?: string | null;
};
```

Embedding rules:

- length must be 512
- all values finite
- vector should be L2-normalized
- return `faceDetected: false` and `embedding: null` when no usable face exists

## Convex HTTP Routes

Base URL is `CONVEX_SITE_URL`, the `.convex.site` HTTP Actions origin.

| Method | Path | Request | Response |
|---|---|---|---|
| `GET` | `/api/health` | none | `{ ok, service, time }` |
| `GET` | `/api/people` | none | `Omit<Person, "faceEmbedding">[]` |
| `GET` | `/api/state` | none | `BrainState` |
| `POST` | `/api/state/filter` | `{ command: FilterCommand }` | `BrainState` |
| `POST` | `/api/voice/interpret` | `{ transcript: string, visiblePersonIds?: string[] }` | `FilterCommand` |
| `POST` | `/api/voice/deepgram-token` | none | `{ temporaryToken: string, expiresAt: number }` |
| `POST` | `/api/drafts/opener` | `{ personId: string, userGoal?: string | null }` | `DraftResult` |
| `POST` | `/api/vision/match-face` | `{ imageBase64: string, imageMimeType?: "image/jpeg" \| "image/png", trackId?: string }` | `FaceMatchResult` |
| `POST` | `/api/identity/resolve` | `{ trackId: string, transcript?: string \| null, faceImageBase64?: string, contextImageBase64?: string, imageMimeType?: "image/jpeg" \| "image/png" }` | `IdentityResolveResult` |
| `POST` | `/api/mission/parse` | `{ clientId?: string \| null, rawText: string }` | `MissionProfile` |
| `POST` | `/api/mission/current` | `{ clientId?: string \| null }` | `MissionProfile \| null` |
| `GET` | `/api/brain/memories?clientId=...` | query string | `ScanMemory[]` |
| `POST` | `/api/brain/memories/upsert` | `ScanMemoryInput` | `ScanMemory` |
| `POST` | `/api/brain/memories/notes` | `{ id: string, notes?: string \| null }` | `ScanMemory \| null` |
| `POST` | `/api/brain/memories/score` | `{ id: string, mission?: MissionProfile \| null }` | `ScanMemory \| null` |
| `POST` | `/api/brain/memories/outreach` | `{ id: string, mission?: MissionProfile \| null }` | `OutreachDraft` |
| `POST` | `/api/brain/memories/follow-up-status` | `{ id: string, status: FollowUpStatus, channel?: FollowUpChannel \| null, editedOutreach?: OutreachDraft \| null, sentAt?: number \| null }` | `ScanMemory \| null` |
| `POST` | `/api/gtm/run` | `{ clientId: string, rawText: string, mission?: MissionProfile \| null }` | `GTMRunResult` |
| `GET` | `/api/gtm/runs?clientId=...` | query string | `GTMRun[]` |
| `GET` | `/api/gtm/prospects?clientId=...&runId=...` | query string | `GTMProspect[]` |
| `POST` | `/api/gtm/prospects/outreach` | `{ prospectId: string, mission?: MissionProfile \| null }` | `OutreachDraft` |
| `POST` | `/api/gtm/prospects/status` | `{ id: string, status: "new" \| "drafted" \| "sent" \| "archived", channel?: FollowUpChannel \| null, outreach?: OutreachDraft \| null, sentAt?: number \| null }` | `GTMProspect \| null` |

## Tag Vocabulary

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

## Threshold Defaults

```ts
{
  FACE_STRONG_MATCH_SCORE: 0.38,
  FACE_TENTATIVE_MATCH_SCORE: 0.30,
  IDENTITY_MIN_OCR_CONFIDENCE: 0.45,
  IDENTITY_FACE_VERIFY_THRESHOLD: 0.32
}
```

Tune with real demo photos and the same CV model used for enrollment.
