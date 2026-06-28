# Recco Integration Checklist

Use this when preparing a demo branch, release build, or final `main` handoff.
It checks that iOS, Convex, CV, docs, and secrets agree.

Related docs: [Demo Runbook](DEMO_RUNBOOK.md) · [QA Checklist](QA_CHECKLIST.md) ·
[API Contracts](API_CONTRACTS.md) · [Architecture](ARCHITECTURE.md)

---

## Code Health

- [ ] `cd backend && npm ci`
- [ ] `cd backend && npm run typecheck`
- [ ] `cd backend && npm test`
- [ ] `python3 scripts/check_markdown_links.py`
- [ ] `git status --short` shows only intentional files.
- [ ] No `.env.local`, keys, generated embeddings, enrollment photos, or build
      artifacts are tracked.

## Backend

- [ ] Convex functions deploy with `npx convex dev --once --typecheck=disable`.
- [ ] `GET /api/health` returns OK from the deployed `.convex.site` URL.
- [ ] `GET /api/people` returns public roster entries only.
- [ ] `POST /api/voice/deepgram-token` works with the deployment env.
- [ ] `POST /api/identity/resolve` works for a real name/badge test.
- [ ] `GET /api/brain/memories` returns the expected client memories.
- [ ] `POST /api/gtm/run` creates a run and prospects.

## CV Service

- [ ] `GET /health` returns `ready: true`.
- [ ] The service model matches the enrolled embeddings model.
- [ ] `POST /embed` returns a 512-d vector for a clear face.
- [ ] `POST /embed` returns `faceDetected: false` for no-face input.
- [ ] `CV_SERVICE_URL` in Convex points to the deployed service.

## iOS

- [ ] Xcode build succeeds for generic iOS or the target iPhone.
- [ ] App installs on the connected iPhone.
- [ ] App launches from the home screen after disconnecting cable.
- [ ] Camera permission granted.
- [ ] Microphone permission granted.
- [ ] `ReccoApp.swift` fallback URL points to the intended `.convex.site` backend.
- [ ] No secret keys are present in the app source or scheme.

## Product Flow

- [ ] Mission setup appears and saves a goal.
- [ ] Camera opens immediately after mission.
- [ ] Face brackets and target reticle align.
- [ ] Mic command `find info on him` triggers the identity pipeline.
- [ ] Keyboard fallback triggers the same pipeline.
- [ ] Identity result shows name and LinkedIn when available.
- [ ] Result saves to Brain.
- [ ] Brain memory shows lead priority, reasons, and outreach.
- [ ] Channel selection works before fake send.
- [ ] Lazy GTM voice/text request creates a prospect graph.
- [ ] GTM prospect outreach and fake send status work.

## Docs

- [ ] Root README describes the current product and setup.
- [ ] Demo runbook matches the current on-stage flow.
- [ ] QA checklist reflects the current tests and device checks.
- [ ] API contracts include identity, Brain memories, mission, and GTM.
- [ ] Architecture reflects iOS + Convex + CV + OpenAI + Fiber + Deepgram.
- [ ] License section points to MIT and mentions third-party service terms.

## Sign-Off

- [ ] One real scan tested on iPhone.
- [ ] One Brain memory created.
- [ ] One Lazy GTM run created.
- [ ] One outreach draft generated.
- [ ] Team has verified no secrets or private photos are committed.
