<div align="center">

# Recco

**Camera-first AI networking assistant.** Point your phone at the room, see who
people are and why they're worth talking to, filter the crowd by voice, and
draft a warm opener in one tap.

[Architecture](docs/ARCHITECTURE.md) · [API Contracts](docs/API_CONTRACTS.md) · [Demo Runbook](docs/DEMO_RUNBOOK.md) · [Contributing](CONTRIBUTING.md)

</div>

---

## What it does

1. **Recognize** — the iOS camera detects and recognizes enrolled people in frame.
2. **Surface** — a profile overlay shows each person's role, what they build, tags, and a one-line *why-talk*.
3. **Filter by voice or chips** — "show me AI founders", "who should I talk to about infra?", "only growth people" narrow the room (and a Brain graph) in real time.
4. **Draft** — generate a short, specific opener or email for anyone, grounded in their actual work.

It's designed to be **demo-reliable**: the whole iOS app runs fully offline in a
mock mode, and every external dependency (camera, backend, CV, voice) degrades
gracefully.

## Repository layout

This is a monorepo with four independently-runnable components:

| Path | Component | Stack | What it is |
|------|-----------|-------|------------|
| [`app/`](app/ios/Recco) | iOS app | SwiftUI | Camera, overlays, Brain graph, voice/typed commands, profiles, opener drafting |
| [`backend/`](backend) | Backend | Convex + TypeScript | Reactive app state, face matching, voice-command interpretation, opener generation |
| [`cv-service/`](cv-service) | CV service | FastAPI + InsightFace | Turns a face image into a 512-d ArcFace embedding |
| [`docs/`](docs) | Docs | Markdown | API contracts, architecture, planning history |

```
┌──────────┐   face crop    ┌───────────┐   /embed    ┌──────────────┐
│  iOS app │ ─────────────► │  backend  │ ──────────► │  cv-service  │
│ (SwiftUI)│ ◄───────────── │ (Convex)  │ ◄────────── │ (InsightFace)│
└──────────┘  reactive state└───────────┘  512-d emb  └──────────────┘
      ▲  voice / chips / draft    │
      └───────────────────────────┘
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full data flow and the
frozen type contracts in [`docs/API_CONTRACTS.md`](docs/API_CONTRACTS.md).

## Quick start

The fastest path to seeing it work is the **iOS app in mock mode** — no backend,
no network, no API keys.

### iOS app (mock mode)

```bash
open app/ios/Recco/Recco.xcodeproj
# Select the "Recco" scheme + an iPhone simulator, then ⌘R.
```

It launches in `mockAll`: local roster, on-device command parsing, on-device
opener generation, and a simulated camera source on the Simulator. See
[`app/ios/Recco/README.md`](app/ios/Recco/README.md).

### Backend (Convex)

```bash
cd backend
npm install
npm run test         # 49 unit tests, no deployment needed
npm run dev          # starts `convex dev` (requires a Convex project + env keys)
```

Env keys live in `backend/.env.local` (see `backend/.env.local.example`). See
[`backend/README.md`](backend/README.md).

> **Windows note:** to run a **local** Convex deployment without an account, set
> `CONVEX_AGENT_MODE=anonymous` first —
> PowerShell: `$env:CONVEX_AGENT_MODE="anonymous"; npx convex dev` ·
> Git Bash: `CONVEX_AGENT_MODE=anonymous npx convex dev`. Run any
> `npx convex run ...` command that takes a **JSON argument** from **Git Bash**
> (PowerShell 5.1 mangles embedded double quotes).

### CV service (face embeddings)

Requires **Python 3.10–3.11** (InsightFace wheels). [`uv`](https://docs.astral.sh/uv/) makes this painless:

```bash
cd cv-service
uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -r requirements.txt
.venv/bin/python -m uvicorn main:app --port 8000
curl localhost:8000/health     # {"ok":true,"model":"buffalo_s","ready":true}
```

> **Windows note:** the venv interpreter is `.venv/Scripts/python` (not
> `.venv/bin/python`). Activate with `. .venv/Scripts/Activate.ps1` (PowerShell)
> or `source .venv/Scripts/activate` (Git Bash), then `uvicorn main:app --port 8000`.

See [`cv-service/README.md`](cv-service/README.md).

## Demo modes

The iOS app supports three fallback levels so a demo can always recover:

| Mode | Backend | Recognition | Use when |
|------|---------|-------------|----------|
| `mockAll` | none (local JSON) | fake | default / stage-safe recovery |
| `mockCV` | Convex | deterministic | backend up, CV/cameras flaky |
| `live` | Convex + CV | real | everything works |

## Status

Each component is built and individually checked; the live path is wired in code
but still needs real enrollment, deployed service URLs, and physical-device
threshold tuning before a public demo.

- ✅ **Backend** — typecheck clean, **49 unit tests passing**, smoke script green; Convex functions and the iOS HTTP bridge are implemented.
- ✅ **iOS** — builds/runs in `mockAll`; `mockCV` / `live` can call the backend HTTP bridge when `RECCO_API_BASE_URL` is configured.
- ✅ **CV service** — FastAPI + InsightFace service is present and `py_compile`-clean; default `buffalo_s` produces 512-d L2-normalized embeddings when installed on Python 3.10-3.11.
- 🔌 **Remaining live-demo work** — collect real enrollment photos, generate/load embeddings, deploy or run Convex + CV service, set iOS backend URL, and tune thresholds on a real iPhone.

Run a demo with [`docs/DEMO_RUNBOOK.md`](docs/DEMO_RUNBOOK.md); verify components
with [`docs/QA_CHECKLIST.md`](docs/QA_CHECKLIST.md).

## Credits

Built at a hackathon by a four-person team:

- **CV service** — [@Cheemasukh962](https://github.com/Cheemasukh962)
- **Backend** — Bryan Pham
- **iOS camera** — Dat Nguyen
- **iOS app shell / voice / Brain** — [@psagar29](https://github.com/psagar29)

## License

[MIT](LICENSE) © 2026 psagar29
