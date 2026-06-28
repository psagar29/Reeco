# Person B - Backend / Convex / Face Matching

## One-line mission

Build the Convex backend that stores people, calls the CV service, matches embeddings, interprets voice commands, and returns shared app state.

## You own

- `backend/convex/`
- Convex schema
- Demo roster seed
- Face embedding enrollment
- Face match action
- Voice command action
- Opener draft action
- Reactive app state

## Main reference repos

- `open-source/convex-templates`
- `open-source/convex-helpers`
- `open-source/convex-swift`

## Read first

1. `docs/API_CONTRACTS.md`
2. `demo-data/people.sample.json`
3. Person A brief: `docs/planning/workstreams/01_PERSON_A_CV_SERVICE_INSIGHTFACE.md`

## Required deliverables

Create:

- `backend/convex/schema.ts`
- `backend/convex/people.ts`
- `backend/convex/state.ts`
- `backend/convex/vision.ts`
- `backend/convex/voice.ts`
- `backend/convex/drafts.ts`
- Seed/enrollment script for demo people

Functions:

- `people:list`
- `state:get`
- `state:setFilter`
- `vision:matchFace`
- `voice:interpretCommand`
- `drafts:createOpener`
- Optional: `voice:getDeepgramToken`

## Data model

Store people shaped like:

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

App state:

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

## Face matching flow

`vision:matchFace` must:

1. Receive `imageBase64`, `imageMimeType`, and `trackId` from iOS.
2. Call Person A's CV service at `CV_SERVICE_URL`.
3. Receive a 512-d embedding.
4. Compare against stored person embeddings using cosine similarity.
5. Return `matched`, `tentative`, `unknown`, `no_face`, or `error`.
6. Update `BrainState.lastMatch`.
7. Set `BrainState.highlightedPersonId` for strong matches.

Default thresholds:

```ts
const strongMatchScore = 0.38;
const tentativeMatchScore = 0.30;
```

Tune these with the actual demo people.

## Voice flow

`voice:interpretCommand` turns transcripts into `FilterCommand`.

Support these commands first:

- "Show me AI founders."
- "Who should I talk to about infra?"
- "Only growth people."
- "Draft an opener for Ava."
- "Reset."

Fixed tag vocabulary:

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

## Opener flow

`drafts:createOpener` receives a `personId` and returns:

```ts
type DraftResult = {
  personId: string;
  subject?: string | null;
  opener: string;
  email?: string | null;
  generatedAt: number;
};
```

Keep it short and specific.

## Environment variables

```txt
CV_SERVICE_URL=http://127.0.0.1:8000
OPENAI_API_KEY=...
DEEPGRAM_API_KEY=...
FACE_STRONG_MATCH_SCORE=0.38
FACE_TENTATIVE_MATCH_SCORE=0.30
```

## Step-by-step plan

1. Scaffold Convex project under `backend/convex/`.
2. Define schema.
3. Seed `demo-data/people.sample.json`.
4. Implement `people:list`.
5. Implement `state:get` and `state:setFilter`.
6. Implement cosine similarity helper.
7. Implement `vision:matchFace` using mock embeddings first.
8. Connect `vision:matchFace` to Person A's real `/embed`.
9. Implement `voice:interpretCommand`.
10. Implement `drafts:createOpener`.
11. Share function names and sample calls with Persons C and D.

## Done when

- iOS can fetch people.
- iOS can subscribe to state.
- Manual filters update visible/dimmed people.
- One image can match one demo person.
- Voice command returns valid JSON.
- Draft opener returns a usable sentence.

## Fallback

If Convex Swift integration gets slow:

- Add simple HTTP actions.
- Let iOS poll state once per second.
- Preserve the same JSON shapes.

If OpenAI is slow:

- Hardcode command parsing for the 5 demo phrases.
- Keep the same `FilterCommand` output.

## What not to do

- Do not build UI.
- Do not render camera overlays.
- Do not put API keys in iOS.
- Do not expand beyond the 5-person demo until integration works.

