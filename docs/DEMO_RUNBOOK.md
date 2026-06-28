# Recco — Demo Runbook

The document a human follows on demo day. Start at the top, run the commands,
and use the [Recovery plan](#recovery-plan) the moment anything wobbles.

> **Golden rule:** the demo is designed to survive any failure by dropping to a
> lower mode. `mockAll` needs **no backend, no network, no keys** and always
> tells the core story. When in doubt, drop a level and keep talking.

- **Roster (5 enrolled people):** Ava Shah (`person_ava_shah`), Miles Chen
  (`person_miles_chen`), Sam Rivera (`person_sam_rivera`), Nina Park
  (`person_nina_park`), Omar Wilson (`person_omar_wilson`).
- **Related docs:** [ARCHITECTURE](ARCHITECTURE.md) ·
  [API_CONTRACTS](API_CONTRACTS.md) · [QA_CHECKLIST](QA_CHECKLIST.md) ·
  [INTEGRATION_CHECKLIST](INTEGRATION_CHECKLIST.md)

> ⚠️ **Honest status (2026):** the iOS `live` path (real camera → backend → CV)
> is **not fully wired on `main` yet** — `ConvexBackend.swift` currently delegates
> to the offline `MockBackend`. Live wiring is being finished on the agent
> branches (see [INTEGRATION_CHECKLIST](INTEGRATION_CHECKLIST.md)). Until that
> merges, **demo in `mockAll`** and treat the live sections below as the target
> state. They are written so they're ready the moment live mode lands.

---

## 1. Demo objective

Show, in ~2 minutes, that Recco lets you walk into a room and instantly know who
to talk to:

1. Open the iPhone app to the camera.
2. It recognizes up to 5 enrolled people and overlays name + role + why-talk.
3. Unknown faces get **no** named overlay.
4. Voice/typed commands filter the room ("show me AI founders").
5. Tap a person → draft a short, specific opener.

The Brain graph is the secondary visual / fallback when the camera isn't ideal.

---

## 2. Hardware needed

| Role | Hardware | Notes |
|------|----------|-------|
| **iOS owner (Person A lane)** | MacBook **with full Xcode** | Required to build/run the app. Agents cannot build iOS. |
| Demo phone | iPhone (iOS 17+) | Best experience. Optional — the Simulator demos `mockAll` with a synthetic camera. |
| **Backend/CV laptop** | Any laptop with Node 18+ and Python 3.10–3.11 | Runs Convex + the CV service for `mockCV`/`live`. Can be the same MacBook. |
| Printed photos | 1 clear photo per roster person | Backup recognition targets if live faces are flaky. |

**Network assumptions:** put the phone and the backend/CV laptop on the **same
Wi-Fi/LAN** (or a phone hotspot). Avoid locked-down conference/guest Wi-Fi that
blocks device-to-laptop traffic — a personal hotspot is the safest bet. For a
cloud Convex deployment you also need outbound internet on the laptop.

---

## 3. Accounts / services needed

| Service | Needed for | Required? |
|---------|-----------|-----------|
| **GitHub** | cloning the repo | Yes |
| **Convex** | `mockCV` / `live` backend | Only for non-`mockAll` modes. A **local anonymous** deployment needs **no account** (`CONVEX_AGENT_MODE=anonymous`). A cloud deployment needs a free Convex login. |
| **OpenAI** | nicer voice parsing + openers | Optional — backend falls back to deterministic offline logic. |
| **Deepgram** | live streaming speech-to-text | Optional — without it, use the typed command bar / chips. |
| InsightFace model | real face embeddings | Auto-downloaded by the CV service on first run (no account). |

`mockAll` needs **none** of these.

---

## 4. Environment variables

Set on the **backend/CV laptop** (Convex reads them from the deployment via
`npx convex env set ...`; local scripts read `backend/.env.local`). Set the iOS
ones in the Xcode scheme (Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments ▸
Environment Variables).

### Backend / CV (`backend/.env.local`, copy from `.env.local.example`)

| Variable | Example | Effect |
|----------|---------|--------|
| `CV_SERVICE_URL` | `http://127.0.0.1:8000` | Where the backend calls `/embed`. Unset → deterministic **mock** embeddings. |
| `OPENAI_API_KEY` | `sk-...` | Real voice parsing + openers. Empty → offline fallback. |
| `OPENAI_MODEL` | `gpt-4o-mini` | Model for the above. |
| `DEEPGRAM_API_KEY` | `...` | Real streaming token. Empty → stub token (use typed/chips). |
| `FACE_STRONG_MATCH_SCORE` | `0.38` | Cosine threshold → `matched`. |
| `FACE_TENTATIVE_MATCH_SCORE` | `0.30` | Cosine threshold → `tentative`. |

### iOS (Xcode scheme env vars)

| Variable | Example | Effect |
|----------|---------|--------|
| `DEMO_MODE` | `mockAll` \| `mockCV` \| `live` | Launch mode. Default is `mockAll`. Can also switch in-app via the demo-mode badge. |
| `CONVEX_URL` | `https://<deployment>.convex.cloud` | Backend URL the app talks to (current iOS seam). |
| `RECCO_API_BASE_URL` | `http://<laptop-LAN-ip>:<port>` | **Planned** — base URL of the backend HTTP bridge once Person C's bridge lands. Until then the app uses `CONVEX_URL`. |

> **Never put `OPENAI_API_KEY` / `DEEPGRAM_API_KEY` in the iOS app.** Secrets live
> only on the backend; the app gets short-lived tokens from `voice:getDeepgramToken`.

---

## 5. Happy-path setup

Do this **before** the audience arrives. Three terminals on the backend/CV laptop
(CV service, Convex, and a scratch terminal), plus Xcode on the Mac.

### 5a. Install backend deps

```bash
cd backend
npm ci
npm run verify        # typecheck + 49 tests + smoke — confirms the backend is healthy
```

### 5b. Start / deploy Convex

**Local anonymous deployment (no Convex account — easiest):**

```bash
# Git Bash / macOS / Linux:
CONVEX_AGENT_MODE=anonymous npx convex dev
```

```powershell
# Windows PowerShell:
$env:CONVEX_AGENT_MODE="anonymous"; npx convex dev
```

This serves on `http://127.0.0.1:3210` and writes the deployment URL into
`backend/.env.local`. For a **cloud** deployment instead, run `npx convex dev`,
log in, then `npx convex env set CV_SERVICE_URL http://127.0.0.1:8000` (and any
other keys).

### 5c. Start the CV service (only for `live`)

```bash
cd cv-service
python -m venv .venv
# PowerShell:  . .venv/Scripts/Activate.ps1
# Git Bash:    source .venv/Scripts/activate    (macOS/Linux: source .venv/bin/activate)
pip install -r requirements.txt
uvicorn main:app --port 8000
```

> Requires **Python 3.10–3.11** (InsightFace wheels). First launch downloads the
> model pack (slow once). Confirm readiness:
> ```bash
> curl http://127.0.0.1:8000/health      # {"ok":true,"model":"buffalo_s","ready":true}
> ```

### 5d. Enroll faces (only for `live`)

```bash
# 1. Put one clear photo per person under demo-data/enrollment/
#    (ava.jpg, miles.jpg, sam.jpg, nina.jpg, omar.jpg)
# 2. With the CV service running and CV_SERVICE_URL set:
cd backend
npm run enroll        # writes demo-data/embeddings.generated.json
```

If photos are missing or the CV service is down, `enroll` writes **deterministic
mock** embeddings instead — matching still works for `mockCV`.

### 5e. Seed the backend

```bash
cd backend
# Seed with deterministic mock embeddings (works for mockCV with zero setup):
npx convex run seed:run

# OR seed with the enrolled embeddings from 5d (Git Bash / macOS / Linux):
npx convex run seed:run "{\"embeddings\": $(cat ../demo-data/embeddings.generated.json)}"
```

> **Windows quoting:** the JSON-argument form mangles double quotes in PowerShell
> 5.1. Run `npx convex run ...` commands with JSON args from **Git Bash**.
> Single-arg commands (`seed:run`, `people:list`, `state:get`) work in either.

Verify the seed:

```bash
npx convex run people:list        # 5 people, no embeddings
npx convex run state:get          # BrainState with everyone visible
```

### 5f. Run the iOS app (Person A, on the Mac)

```bash
open app/ios/Recco/Recco.xcodeproj
# Select scheme "Recco" + an iPhone simulator (or a connected iPhone), then ⌘R.
```

Default launch is `mockAll`. For `mockCV`/`live`, set `DEMO_MODE` and `CONVEX_URL`
in the scheme (see §4) — **only once live wiring has merged** (see status note).

---

## 6. Demo script (~2 min)

1. **Open the app.** It lands on the camera hero in `mockAll`. *"Recco helps you
   walk into a room and instantly know who to talk to."*
2. **Show mock mode.** Point at the (simulated or real) faces — overlay cards
   appear for recognized roster people with name, role, and a why-talk line.
   *"It only recognizes enrolled people, and gives me useful context."*
3. **(When live wiring has merged) switch to live mode** via the demo-mode badge.
   Re-scan a known person; the overlay now comes from the real CV → backend match.
4. **Scan a known person.** Tap an overlay → the **profile sheet** opens with
   role/company, tags, why-talk, and links (LinkedIn/GitHub).
5. **Open the profile / LinkedIn.** Show the profile detail; the LinkedIn link is
   visible on the card.
6. **Filter by voice or typed command.** Say or type one of:
   - "Show me AI founders." → Ava / Nina / Omar brighten.
   - "Who should I talk to about infra?" → Miles ranks first.
   - "Only growth people." → Sam.
   - "Reset." → everyone back.
   Non-matching overlays dim; the Brain graph reflects the same state.
7. **Draft an opener.** With a person selected, tap "Draft opener" (or say "draft
   an opener for Ava"). Read the one-line opener aloud.
8. **Brain view (optional close).** Switch to the Brain graph: *"This also works
   across the whole roster, not just who's in my camera."*

You can verify the command/draft behavior **without the phone** using the backend
directly (handy as a pre-demo smoke check, Git Bash):

```bash
npx convex run voice:interpretCommand '{"transcript":"show me AI founders"}'
npx convex run drafts:createOpener '{"personId":"person_ava_shah"}'
```

---

## 7. Recovery plan

| Symptom | Do this |
|---------|---------|
| **Backend down / flaky** | Switch the app to **`mockAll`** (demo-mode badge or relaunch). Everything runs on-device; the story is intact. |
| **CV service down / slow** | Switch to **`mockCV`** — Convex returns deterministic matches without the CV service. (Or `mockAll`.) |
| **Camera permission denied** | iOS Settings ▸ Recco ▸ Camera ▸ on, relaunch. On the Simulator, the app auto-uses a **synthetic** face source — no permission needed. |
| **Bad lighting / no detection** | Move closer, face the camera, increase light. Use the **printed photos**. Use the **"Scan"** button to capture one frame on demand. |
| **No face detected** | Backend returns `no_face` → app shows no card (correct). Re-scan closer; or demo via the **Brain graph** + voice instead of the camera. |
| **Wrong-match worry** | Thresholds are conservative (`matched ≥ 0.38`); below that → `unknown` with **no name shown**. If a wrong name ever appears, raise `FACE_STRONG_MATCH_SCORE` (e.g. `0.45`) and re-`seed:run`. |
| **Voice/Deepgram fails** | Use the **typed command bar** or the **chips** (AI / Founder / Infra / Growth / Design / Reset) — same command path, same result. |
| **PowerShell quoting errors on `convex run`** | Re-run the command in **Git Bash**. |

> **Stage parachute:** if all live services fail, `mockAll` + chips + the Brain
> graph still delivers the full narrative. Rehearse that path too.
