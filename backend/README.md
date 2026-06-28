# Recco Backend (Person B) — Convex

The Convex backend for the Recco camera-first networking demo. It stores the
demo roster, exposes a single reactive app state for iOS, matches face
embeddings against enrolled people, interprets voice commands into a structured
filter, and drafts short openers.

Everything is built to the frozen contract in [`../docs/API_CONTRACTS.md`](../docs/API_CONTRACTS.md)
and the Person B spec in [`../docs/planning/workstreams/02_PERSON_B_BACKEND_MATCHING_CONVEX.md`](../docs/planning/workstreams/02_PERSON_B_BACKEND_MATCHING_CONVEX.md).

> **Degrades gracefully with zero secrets.** With no API keys and no CV service,
> the whole backend runs in a deterministic mock mode that returns the exact
> same JSON shapes. Fill in keys to switch on the "real" paths (see
> [Environment variables](#environment-variables)).

---

## Table of contents

- [Quick start](#quick-start)
- [What's here](#whats-here)
- [Function reference (for Persons C & D)](#function-reference-for-persons-c--d)
- [HTTP bridge for iOS (Person A)](#http-bridge-for-ios-person-a)
- [Environment variables](#environment-variables)
- [Seeding & enrollment](#seeding--enrollment)
- [Verifying without the iOS app](#verifying-without-the-ios-app)
- [How the mock/real paths work](#how-the-mockreal-paths-work)
- [Design decisions & assumptions](#design-decisions--assumptions)

---

## Quick start

```bash
cd backend
npm install

# 1. Verify everything offline (typecheck + unit tests + smoke script). No
#    deployment, no secrets, no network required.
npm run verify

# 2. Run a real local Convex deployment (no Convex account needed).
#    This generates convex/_generated, watches files, and serves functions
#    on http://127.0.0.1:3210.
CONVEX_AGENT_MODE=anonymous npx convex dev      # macOS/Linux
#   PowerShell: $env:CONVEX_AGENT_MODE="anonymous"; npx convex dev

# 3. In another terminal, seed the roster and try the functions.
npx convex run seed:run
npx convex run people:list
npx convex run state:get
```

> The `CONVEX_AGENT_MODE=anonymous` flag spins up a **local** deployment with no
> login. To deploy to a cloud dev deployment instead, run `npx convex dev` and
> follow the login prompt, then `npx convex env set ...` for your secrets.

---

## What's here

```
backend/
├── convex/
│   ├── schema.ts            # tables: people, appState (singleton), faceMatches, drafts
│   ├── people.ts            # people:list (+ internal enrolled/by-id queries)
│   ├── state.ts             # state:get, state:setFilter (+ internal recordMatch)
│   ├── vision.ts            # vision:matchFace
│   ├── voice.ts             # voice:interpretCommand, voice:getDeepgramToken
│   ├── drafts.ts            # drafts:createOpener (+ internal record)
│   ├── seed.ts              # seed:run (load roster + init state)
│   ├── validators.ts        # shared Convex value validators (frozen shapes)
│   └── lib/                 # framework-free, unit-tested pure logic:
│       ├── types.ts         #   canonical TS types (mirror the contract)
│       ├── tags.ts          #   fixed tag vocabulary + NL→tag mapping
│       ├── similarity.ts    #   cosine, L2-normalize, threshold classification, matchBest
│       ├── filter.ts        #   visibility recompute + BrainState transitions
│       ├── voiceParser.ts   #   offline command parsing + LLM-output sanitizing
│       ├── opener.ts        #   templated opener generation
│       ├── mockEmbeddings.ts#   deterministic 512-d embeddings + demo-image markers
│       ├── cv.ts            #   CV /embed client with mock fallback
│       ├── openai.ts        #   minimal OpenAI JSON client
│       └── config.ts        #   env → thresholds / urls / keys
├── scripts/
│   ├── enroll.ts            # compute & write demo-data/embeddings.generated.json
│   └── smoke.ts             # exercise every function offline and print JSON
├── test/                    # vitest unit tests (cosine, thresholds, filter, voice, opener)
├── .env.local.example       # copy to .env.local and fill in to enable real paths
├── package.json             # scripts: dev, codegen, typecheck, test, smoke, enroll, verify
└── tsconfig.json
```

The `convex/lib/*` modules contain **all** the real logic and are pure
(no Convex imports), so they are fully unit-testable and runnable in Node
without a deployment. The Convex function files are thin wrappers that read the
database, call those helpers, and write state back.

---

## Function reference (for Persons C & D)

All names and shapes match `docs/API_CONTRACTS.md`. iOS calls these by their
`module:function` names. Types are in [`convex/lib/types.ts`](convex/lib/types.ts).

| Function | Kind | Input | Output |
|---|---|---|---|
| `people:list` | query | `{}` | `PublicPerson[]` (no embeddings) |
| `state:get` | query | `{}` | `BrainState` — **main iOS subscription** |
| `state:setFilter` | mutation | `{ command: FilterCommand }` | `BrainState` |
| `vision:matchFace` | action | `{ imageBase64, imageMimeType, trackId }` | `FaceMatchResult` |
| `voice:interpretCommand` | action | `{ transcript, visiblePersonIds? }` | `FilterCommand` |
| `drafts:createOpener` | action | `{ personId, userGoal? }` | `DraftResult` |
| `voice:getDeepgramToken` | action | `{}` | `{ temporaryToken, expiresAt }` |
| `seed:run` | mutation | `{ embeddings? }` | `{ peopleInserted, usedRealEmbeddings, embeddingSource }` |

### Sample calls (live, verified against a local deployment)

```bash
# people:list -> 5 people, each WITHOUT faceEmbedding
npx convex run people:list

# Apply a manual filter; recomputes visible/dimmed and returns the new state
npx convex run state:setFilter '{"command":{"action":"filter","includeTags":["AI"],"excludeTags":[],"rankBy":"relevance","rawText":"show me ai"}}'
# -> visiblePersonIds: [ava, nina, omar], dimmedPersonIds: [miles, sam]

# Interpret a spoken command into a FilterCommand
npx convex run voice:interpretCommand '{"transcript":"Who should I talk to about infra?"}'
# -> {"action":"rank","includeTags":["Infra"],"rankBy":"infra",...}

# Match a face. In mock mode, a "demo image" deterministically resolves to a
# person via an embedded marker (see "How the mock/real paths work").
#   imageBase64 below is base64("recco-match:person_ava_shah")
npx convex run vision:matchFace '{"imageBase64":"cmVjY28tbWF0Y2g6cGVyc29uX2F2YV9zaGFo","imageMimeType":"image/jpeg","trackId":"track_1"}'
# -> {"status":"matched","personId":"person_ava_shah","score":1,...}

# Draft an opener
npx convex run drafts:createOpener '{"personId":"person_ava_shah"}'

# Deepgram token (stub unless DEEPGRAM_API_KEY is set)
npx convex run voice:getDeepgramToken
```

> **Windows PowerShell note:** PS 5.1 mangles double quotes when calling native
> programs. Run the JSON-arg commands above from **Git Bash** / WSL, or write the
> args to a variable. Single-arg commands (`people:list`, `state:get`,
> `seed:run`) work everywhere.

### Recognition thresholds

`vision:matchFace` classifies the best cosine score (on L2-normalized 512-d
embeddings):

- `score ≥ 0.38` → `matched` (sets `highlightedPersonId`)
- `score ≥ 0.30` → `tentative`
- otherwise → `unknown` (**personId is dropped so iOS never shows a wrong name**)
- CV reports no face → `no_face`; any thrown error → `error`

Override with `FACE_STRONG_MATCH_SCORE` / `FACE_TENTATIVE_MATCH_SCORE`.

---

## HTTP bridge for iOS (Person A)

iOS talks to the backend over **plain HTTP/JSON** (`URLSession`), not the Convex
client. The bridge lives in [`convex/http.ts`](convex/http.ts) and wraps the
exact public functions above — no contract shapes change. Pure request
validation + response helpers are in [`convex/lib/http.ts`](convex/lib/http.ts)
(unit-tested in [`test/http.test.ts`](test/http.test.ts)).

### Base URL

Convex serves HTTP actions on a **different URL from the API/client URL**. After
`npx convex dev`, the deployment writes both to `backend/.env.local`:

```txt
CONVEX_URL=http://127.0.0.1:3210        # Convex client/API  (NOT the HTTP bridge)
CONVEX_SITE_URL=http://127.0.0.1:3211   # HTTP actions        <-- iOS base URL
```

- **Local (anonymous) dev:** base URL is `http://127.0.0.1:3211`.
- **Cloud deployment:** the HTTP base URL is your deployment's **`.convex.site`**
  host (e.g. `https://your-deployment-123.convex.site`), i.e. `CONVEX_SITE_URL`.
  It is `.convex.site`, **not** the `.convex.cloud` client URL.

iOS should set its base URL to `CONVEX_SITE_URL` and append the paths below.
For the iOS Simulator, `127.0.0.1` reaches the host; for a physical device on
the same network use the host machine's LAN IP and run a cloud deployment or a
tunnel.

### Endpoints

| Method | Path | Body | Returns |
|---|---|---|---|
| `GET`  | `/api/health` | — | `{ ok, service, time }` |
| `GET`  | `/api/people` | — | `PublicPerson[]` (never embeddings) |
| `GET`  | `/api/state` | — | `BrainState` |
| `POST` | `/api/state/filter` | `{ command: FilterCommand }` | `BrainState` |
| `POST` | `/api/voice/interpret` | `{ transcript, visiblePersonIds? }` | `FilterCommand` |
| `POST` | `/api/drafts/opener` | `{ personId, userGoal? }` | `DraftResult` |
| `POST` | `/api/vision/match-face` | `{ imageBase64, imageMimeType?, trackId? }` | `FaceMatchResult` |

Behavior:

- **CORS:** every route returns `Access-Control-Allow-Origin: *` and answers
  `OPTIONS` preflight (`204`) so browsers/local tools can call it directly.
- **JSON always**, including errors: `{ "ok": false, "error": "..." }`.
- **Status codes:** `200` success · `400` invalid input / malformed JSON ·
  `404` unknown route (Convex default) · `500` unexpected error.
- **match-face safety:** only `matched` / `tentative` carry a `personId`;
  `unknown` / `no_face` / `error` always return `personId: null`, so iOS can
  never show a name for a low-confidence face. iOS should show a name **only**
  for `status === "matched"`.
- **match-face defaults:** `imageMimeType` defaults to `image/jpeg` and a
  `trackId` is generated if omitted, so a minimal `{ imageBase64 }` payload works.

### Example curl requests

Base URL below is the local HTTP-actions URL (`CONVEX_SITE_URL`):

```bash
BASE=http://127.0.0.1:3211

# Health (diagnostics)
curl "$BASE/api/health"

# Roster (no embeddings)
curl "$BASE/api/people"

# Reactive state
curl "$BASE/api/state"

# Apply a filter
curl -X POST "$BASE/api/state/filter" \
  -H "Content-Type: application/json" \
  -d '{"command":{"action":"filter","includeTags":["AI"],"excludeTags":[],"rankBy":"relevance","rawText":"show me ai"}}'

# Interpret a spoken command -> FilterCommand
curl -X POST "$BASE/api/voice/interpret" \
  -H "Content-Type: application/json" \
  -d '{"transcript":"Who should I talk to about infra?","visiblePersonIds":["person_ava_shah"]}'

# Draft an opener -> DraftResult
curl -X POST "$BASE/api/drafts/opener" \
  -H "Content-Type: application/json" \
  -d '{"personId":"person_ava_shah","userGoal":null}'

# Match a face. imageBase64 here is base64("recco-match:person_ava_shah"),
# which the deterministic mock path resolves to a strong match.
curl -X POST "$BASE/api/vision/match-face" \
  -H "Content-Type: application/json" \
  -d '{"imageBase64":"cmVjY28tbWF0Y2g6cGVyc29uX2F2YV9zaGFo","imageMimeType":"image/jpeg","trackId":"trk_abc123"}'
```

> **Windows PowerShell note:** PS 5.1 mangles the double quotes inside the JSON
> `-d` payloads above when calling native `curl.exe`. Run these from **Git Bash**
> / WSL, or write the JSON to a file and use `curl -d "@body.json"`, or build the
> body with `ConvertTo-Json` and pass it via `Invoke-RestMethod`:
>
> ```powershell
> $body = @{ command = @{ action = "filter"; includeTags = @("AI"); excludeTags = @(); rankBy = "relevance"; rawText = "show me ai" } } | ConvertTo-Json -Depth 5
> Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:3211/api/state/filter" -ContentType "application/json" -Body $body
> ```

### Running the bridge

```bash
cd backend
# Local backend, no Convex account; serves API on :3210 and HTTP actions on :3211
CONVEX_AGENT_MODE=anonymous npx convex dev        # macOS/Linux / Git Bash
#   PowerShell: $env:CONVEX_AGENT_MODE="anonymous"; npx convex dev

# In another terminal: seed the roster, then hit the endpoints above.
npx convex run seed:run
curl http://127.0.0.1:3211/api/health
```

For a cloud deployment, run `npx convex deploy` (or a logged-in `npx convex dev`)
and use the printed `.convex.site` URL as the iOS base URL.

---

## Environment variables

Copy `.env.local.example` to `.env.local` and fill in what you want. **Every
variable is optional.** For a deployed Convex backend, set them on the
deployment instead with `npx convex env set NAME value` (Convex actions read
`process.env` from the deployment, not from `.env.local`).

| Variable | Default | Effect when set | Effect when empty |
|---|---|---|---|
| `CV_SERVICE_URL` | `http://127.0.0.1:8000` | `vision:matchFace` & `enroll` call Person A's `POST /embed` | deterministic **mock** embeddings |
| `OPENAI_API_KEY` | — | `voice:interpretCommand` & `drafts:createOpener` use OpenAI | deterministic **offline** parsing / templating |
| `OPENAI_MODEL` | `gpt-4o-mini` | model used for the above | n/a |
| `DEEPGRAM_API_KEY` | — | `voice:getDeepgramToken` mints a real short-lived token | clearly-marked **stub** token |
| `FACE_STRONG_MATCH_SCORE` | `0.38` | strong-match cosine threshold | default |
| `FACE_TENTATIVE_MATCH_SCORE` | `0.30` | tentative-match cosine threshold | default |
| `FIBER_API_KEY` | — | `identity:resolveTarget` calls Fiber AI person lookup | identity lane returns `not_found` |
| `FIBER_API_BASE_URL` | `https://api.fiber.ai` | Fiber base URL (no trailing slash) | default |
| `OPENAI_VISION_MODEL` | `gpt-4o` | vision model that reads the badge (reuses `OPENAI_API_KEY`) | identity lane returns `needs_clarification` |
| `IDENTITY_MIN_OCR_CONFIDENCE` | `0.45` | OCR confidence floor below which → `needs_clarification` | default |
| `IDENTITY_FACE_VERIFY_THRESHOLD` | `0.32` | cosine floor to mark a candidate face-`verified` (only when CV is real) | default |

### Exact commands to enable the "real" paths

```bash
# --- OpenAI (real voice parsing + opener writing) ---
echo 'OPENAI_API_KEY=sk-...'        >> backend/.env.local   # for local scripts
npx convex env set OPENAI_API_KEY sk-...                     # for the deployment

# --- Deepgram (real streaming token) ---
echo 'DEEPGRAM_API_KEY=...'         >> backend/.env.local
npx convex env set DEEPGRAM_API_KEY ...

# --- Person A's CV service (real face embeddings) ---
echo 'CV_SERVICE_URL=http://127.0.0.1:8000' >> backend/.env.local
npx convex env set CV_SERVICE_URL http://127.0.0.1:8000
```

No restart of `convex dev` is needed after `convex env set` — it redeploys.

---

## Seeding & enrollment

`seed:run` loads the 5-person demo roster (bundled in `convex/lib/demoRoster.ts`,
kept in sync with `../demo-data/people.sample.json`) and initializes the
singleton `BrainState`. It is **idempotent** — safe to re-run.

```bash
# Seed with deterministic mock embeddings (matching works fully offline):
npx convex run seed:run

# Seed with enrolled (real or per-person mock) embeddings:
cd backend && npm run enroll        # writes ../demo-data/embeddings.generated.json
# then load them (Git Bash / macOS / Linux):
npx convex run seed:run "{\"embeddings\": $(cat ../demo-data/embeddings.generated.json)}"
```

`npm run enroll` reads `demo-data/people.sample.json`, and for each person:

- if `CV_SERVICE_URL` is reachable **and** the enrollment image exists →
  calls `POST /embed` for a real 512-d embedding;
- otherwise → writes a deterministic mock embedding.

It then writes `demo-data/embeddings.generated.json` (a `personId → number[512]`
map; git-ignored). The demo enrollment images are not in the repo, so by default
enrollment produces mock embeddings — which still match end-to-end.

For the full enrollment workflow (capturing photos, running the CV service,
seeding, privacy checks, and troubleshooting) see
[`../docs/FACE_ENROLLMENT.md`](../docs/FACE_ENROLLMENT.md).

---

## Verifying without the iOS app

```bash
npm run typecheck   # tsc --noEmit over convex/, scripts/, test/  (0 errors)
npm run test        # vitest: cosine, thresholds, filter recompute, voice phrases, openers
npm run smoke       # runs every function's logic on sample input and prints JSON
npm run verify      # all three of the above
```

- **`npm run smoke`** is the fastest end-to-end sanity check. It mirrors each
  Convex function using the same pure helpers and prints contract-shaped JSON —
  no deployment, secrets, or network required.
- **Unit tests** (49) cover cosine similarity & scale-invariance, threshold
  classification at the 0.38/0.30 boundaries, `matchBest` (self-match ≈ 1.0,
  distinct identities below threshold), filter/visibility recompute, the five
  demo voice phrases, exclude phrasing, name resolution, LLM-output sanitizing,
  and opener generation.
- For a **live** check, run `npx convex dev` (anonymous) and use the
  `npx convex run ...` calls above.

---

## How the mock/real paths work

**Face matching.** `vision:matchFace` always returns a `FaceMatchResult`.

- If `CV_SERVICE_URL` is set and reachable, it sends the image to `POST /embed`
  and matches the returned embedding.
- If not, it generates a **deterministic** embedding from the image bytes.
  To make offline demos reproducible, a "demo image" can carry a marker:
  `base64("recco-match:<personId>")` resolves to exactly that person
  (cosine ≈ 1.0 → `matched`). Any other/real image hashes to a stable embedding
  that is near-orthogonal to all enrolled people → `unknown` (no false overlay).
  Build one in code with `makeMockImageBase64("person_ava_shah")`.

**Voice.** `voice:interpretCommand` tries OpenAI (JSON mode) when a key is
present, then **sanitizes** the result (clamps tags to the fixed vocabulary,
validates the action/rankBy, resolves the draft target against the roster). With
no key — or if the call fails — it uses a deterministic offline parser that
reliably handles the five demo phrases and degrades sensibly on anything else.
Both paths emit identical `FilterCommand` JSON.

**Openers.** `drafts:createOpener` tries OpenAI, then falls back to a templated
generator built from the person's real bio/tags/`openerSeed` (no invented
facts). Both return `DraftResult`.

**Deepgram.** `voice:getDeepgramToken` mints a 60s token via Deepgram's grant
endpoint when `DEEPGRAM_API_KEY` is set; otherwise it returns a stub token
clearly labeled `stub-deepgram-token-no-key-configured` so iOS can fall back to
typed/chip commands.

---

## Design decisions & assumptions

- **Filter semantics — `includeTags` are OR'd.** A person matches if they carry
  *any* requested tag, so "show me AI founders" brightens everyone AI-ish (Ava,
  Nina, Omar) rather than only people who are literally both AI *and* Founder.
  The contract left "match the current filter" open; this matches the demo
  script. `action: "rank"` keeps the same visible set but orders it by a
  relevance score (include-tag hits + a fractional tag-adjacency bonus, so an
  "infra" rank puts Miles above Ava).
- **`highlightedPersonId` is cleared only on `reset`** (per the contract). A
  `matched` face sets it; `tentative`/`unknown` leave it untouched.
- **`draft` does not tag-filter** — everyone stays visible and
  `selectedPersonId` is set to the target.
- **`state:get` returns a synthetic "everyone visible" default** (with
  `updatedAt: 0`) before the first seed/mutation, so the query stays
  deterministic (no `Date.now()` in a query).
- **The roster is bundled in code** (`convex/lib/demoRoster.ts`) because Convex
  functions can't read files at runtime. Keep it in sync with
  `demo-data/people.sample.json`. `enrollmentImagePath` and the null
  `faceEmbedding` from the sample file are intentionally not part of the stored
  contract shape.
- **`people:list` strips `faceEmbedding`** — embeddings are server-side only.
- **Convex requires a deployment for `codegen`.** The committed
  `convex/_generated/` lets the project typecheck out of the box. Regenerate
  with `CONVEX_AGENT_MODE=anonymous npx convex dev` (local, no account) or a
  normal logged-in `npx convex dev`.
- **The five demo voice phrases are the supported scope.** The offline parser
  also handles common variants (synonyms, `without X` excludes, name lookup),
  but per the spec we do not expand beyond the demo until integration is solid.
