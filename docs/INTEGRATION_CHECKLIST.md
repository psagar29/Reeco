# Recco — Integration / Merge Checklist

Use this when the four agent branches come back together. Goal: four good
branches become **one** clean, runnable `main` — not a confusing mess.

- **Base branch:** `main`
- **Owner of this doc:** Person D (integration QA)
- **Companion docs:** [QA_CHECKLIST](QA_CHECKLIST.md) ·
  [DEMO_RUNBOOK](DEMO_RUNBOOK.md) ·
  [HANDOFF_TEMPLATE](agent-handoffs/HANDOFF_TEMPLATE.md)

---

## Branches in flight

| Branch | Lane | Touches mostly |
|--------|------|----------------|
| `agent/person-c-backend-matching` | Backend HTTP bridge + matching | `backend/` (HTTP routes/actions), `docs/API_CONTRACTS.md` |
| `agent/person-b-cv-enrollment` | CV enrollment workflow | `cv-service/`, `backend/scripts/enroll.ts`, `demo-data/` |
| `agent/person-a-ios-live-overlay` | iOS live client + overlay | `app/ios/Recco/Recco/**` (esp. `ConvexBackend.swift`, camera/overlay) |
| `agent/person-d-integration-docs-qa` | Docs / QA / runbooks | `docs/`, root/sub `README.md`, `scripts/` |

---

## Recommended merge order

Merge in **dependency order**, smallest blast radius first, and **run the
[per-branch pre-merge checks](#pre-merge-checks-per-branch) after each merge**
(not just at the end):

1. **Person C — backend HTTP bridge.** It defines the surface iOS will call
   (HTTP routes / Convex actions). Merge first so the contract the others target
   is fixed in `main`.
2. **Person B — CV / enrollment workflow.** Real embeddings depend on the CV
   service + `enroll`; verify it produces embeddings the backend can match.
3. **Person A — iOS live client / overlay.** Wires `ConvexBackend.swift` to the
   real backend from steps 1–2; the biggest surface, merged once its dependencies
   are stable.
4. **Person D — docs / QA.** Merge last so runbook/checklists/READMEs reflect the
   final merged reality (status lines, URLs, commands).

> If a later branch forces a contract change, **stop**, update
> `docs/API_CONTRACTS.md` + both DTO/type mirrors, and re-merge the affected
> branches. Don't paper over a shape mismatch.

---

## Pre-merge checks per branch

Run these on each branch **before** merging it into `main`.

### Every branch
- [ ] Branched from a recent `main`; rebased or merged latest `main` in.
- [ ] No secrets committed (`git log -p | grep -iE 'sk-|api[_-]?key|token'` is clean; `.env.local` not tracked).
- [ ] No stray generated/build artifacts (`node_modules/`, `.venv/`, `DerivedData/`, `*.generated.json`).
- [ ] `python scripts/check_markdown_links.py` → **OK** (no broken relative links).
- [ ] A filled-in [handoff](agent-handoffs/HANDOFF_TEMPLATE.md) under `docs/agent-handoffs/`.

### Person C (backend HTTP bridge)
- [ ] `cd backend && npm ci && npm run typecheck && npm run test && npm run smoke` all pass.
- [ ] New HTTP route(s) documented in `backend/README.md` with sample request/response.
- [ ] Response bodies match the frozen contract shapes (see [Contract checks](#contract-checks)).
- [ ] Auth/secret handling: the bridge issues short-lived tokens; **no keys leak to clients**.

### Person B (CV / enrollment)
- [ ] `python -m py_compile cv-service/main.py cv-service/test_embed.py` → exit 0.
- [ ] CV service starts; `GET /health` → `ready: true`.
- [ ] `POST /embed` returns a **512-d, L2-normalized** embedding for a real face; `faceDetected:false` for a no-face image.
- [ ] `cd backend && npm run enroll` produces `demo-data/embeddings.generated.json` with a 512-length vector per person.
- [ ] **Same `RECCO_CV_MODEL` for enrollment and matching** (embeddings from `buffalo_s` and `buffalo_l` are not comparable).

### Person A (iOS live client / overlay)
- [ ] Builds in **Xcode** for an iPhone simulator (agents can't verify this — **Person A must**):
      `xcodebuild -project app/ios/Recco/Recco.xcodeproj -scheme Recco -destination 'platform=iOS Simulator,name=iPhone 17' build`
- [ ] `mockAll` still launches and demos with no backend/network.
- [ ] `ConvexBackend.swift` `TODO(convex)` bodies replaced with real calls; falls back to `MockBackend` on error.
- [ ] DTOs unchanged or contract + both mirrors updated together.
- [ ] No API keys in the app; overlays show only for `status == matched`.

### Person D (docs / QA)
- [ ] Runbook, integration checklist, QA checklist, handoff template present.
- [ ] Root README status is **honest** (no claiming unmerged live work is done).
- [ ] Link checker passes.

---

## Conflict hotspots

These files are edited by multiple lanes — expect conflicts and resolve
deliberately (keep **both** sets of real content; don't blindly take one side):

| File | Why it conflicts | Resolution guidance |
|------|------------------|---------------------|
| `README.md` | Everyone edits status/quick-start | Keep one honest status section; merge each lane's quick-start row. |
| `backend/README.md` | C adds HTTP routes; B adds enroll notes | Append; keep the function/route reference complete. |
| `cv-service/README.md` | B tunes model/perf | Keep the model-consistency warning. |
| `app/ios/Recco/README.md` | A documents live wiring | Update demo-mode table + env vars (`CONVEX_URL` / `RECCO_API_BASE_URL`). |
| `docs/API_CONTRACTS.md` | Any shape change | **Single source of truth** — reconcile first, then update mirrors. |
| `backend/.env.local.example` | New env vars | Union of all keys; keep every key optional + commented. |

---

## Contract checks

The boundary types are mirrored on both sides — Swift DTOs in
`app/ios/Recco/Recco/Models/` and TS types in `backend/convex/lib/types.ts`,
frozen in [`API_CONTRACTS.md`](API_CONTRACTS.md). After merging, confirm each
pair still matches field-for-field:

| Contract | Swift DTO | TS type | Check |
|----------|-----------|---------|-------|
| `Person` | `PersonDTO` | `Person` / `PublicPerson` | id, name, role, company, avatarUrl?, bio, tags[], links{github,linkedin,x,site}, whyTalk, openerSeed? — **no `faceEmbedding` on the wire** |
| `BrainState` | `BrainStateDTO` | `BrainState` | activeFilter, highlightedPersonId?, selectedPersonId?, visiblePersonIds[], dimmedPersonIds[], lastTranscript?, lastMatch?, isThinking, updatedAt |
| `FilterCommand` | `FilterCommandDTO` | `FilterCommand` | action(filter\|rank\|reset\|draft), includeTags[], excludeTags[], rankBy?, targetPersonId?, rawText? |
| `FaceMatchResult` | `FaceMatchResultDTO` | `FaceMatchResult` | trackId, status(matched\|tentative\|unknown\|no_face\|error), personId?, score?, quality?, message?, latencyMs? |
| `DraftResult` | `DraftResultDTO` | `DraftResult` | personId, subject?, opener, email?, generatedAt |

- [ ] Field names + optionality match across Swift/TS for all five.
- [ ] Enum string values match exactly (e.g. `no_face`, not `noFace`).
- [ ] `tags` only use the fixed vocabulary (`backend/convex/lib/tags.ts` ↔ iOS `TagVocabulary.swift`).

---

## End-to-end checks (post-merge on `main`)

Run top-to-bottom after all four merges. Backend/CLI steps are agent-verifiable;
iOS steps need Person A on a Mac.

- [ ] **Seed people** — `npx convex run people:list` returns the 5-person roster (no embeddings).
- [ ] **Enroll embeddings** — `npm run enroll` writes a 512-length vector per person; `seed:run` loads them.
- [ ] **Match a demo image** — mock marker resolves to one person:
      `npx convex run vision:matchFace '{"imageBase64":"cmVjY28tbWF0Y2g6cGVyc29uX2F2YV9zaGFo","imageMimeType":"image/jpeg","trackId":"t1"}'`
      → `status: "matched"`, `personId: "person_ava_shah"`.
- [ ] **Unknown face stays unknown** — an unrelated image → `status: "unknown"`, `personId: null` (no wrong overlay).
- [ ] **iOS `mockAll`** — app launches, recognizes roster, filters via chips/voice, drafts an opener — no backend.
- [ ] **iOS live backend URL** — with `DEMO_MODE=live` + `CONVEX_URL`/`RECCO_API_BASE_URL` set, the app fetches `people:list`, subscribes to `state:get`, and a real match drives an overlay.
- [ ] **Voice command round-trip** — "show me AI founders" updates visible/dimmed in the app and the Brain graph.
- [ ] **Recovery** — toggling `live → mockCV → mockAll` keeps the app demoable at each step.

---

## Sign-off

- [ ] All four branches merged in the recommended order.
- [ ] All post-merge end-to-end checks pass (or open issues filed for any that don't).
- [ ] `main` README status reflects reality.
- [ ] Demo rehearsed once end-to-end from [DEMO_RUNBOOK](DEMO_RUNBOOK.md).
