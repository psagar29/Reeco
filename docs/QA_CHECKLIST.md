# Recco QA Checklist

Use this before a demo, merge, or handoff. A box is only checked when the command
or device behavior has actually been verified.

Related docs: [Demo Runbook](DEMO_RUNBOOK.md) · [Architecture](ARCHITECTURE.md) ·
[API Contracts](API_CONTRACTS.md)

---

## Backend

```bash
cd backend
npm ci
npm run typecheck
npm test
```

- [x] Dependencies install.
- [x] TypeScript typecheck passes.
- [x] Vitest passes.
- [x] No backend secrets are committed.

Current verified result:

```txt
9 test files passed
167 tests passed
```

Focused live checks:

```bash
curl https://fabulous-hyena-861.convex.site/api/health
curl https://fabulous-hyena-861.convex.site/api/people
```

- [x] `/api/health` returns JSON with `ok: true`.
- [x] `/api/people` returns public people only, never `faceEmbedding`.
- [ ] `/api/voice/deepgram-token` returns a usable token with `DEEPGRAM_API_KEY`.
- [ ] `/api/identity/resolve` returns a candidate for a real badge/name photo.
- [ ] `/api/brain/memories` returns saved scan memories for the active client.
- [ ] `/api/gtm/run` creates a GTM run and prospects.

## CV Service

```bash
curl http://<cv-host>:8000/health
```

- [ ] Health returns `{ ok: true, ready: true }`.
- [ ] Model name matches the enrolled embeddings model.
- [ ] `POST /embed` on a face returns `faceDetected: true`.
- [ ] Embedding length is 512.
- [ ] Embedding values are finite and approximately L2-normalized.
- [ ] No-face images return `faceDetected: false` and `embedding: null`.

## iOS Build And Install

Build:

```bash
xcodebuild \
  -project app/ios/Recco/Recco.xcodeproj \
  -scheme Recco \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData-demo \
  build
```

Install:

```bash
xcrun devicectl list devices
xcrun devicectl device uninstall app --device <DEVICE_ID> com.recco.app || true
xcrun devicectl device install app --device <DEVICE_ID> build/DerivedData-demo/Build/Products/Debug-iphoneos/Recco.app
xcrun devicectl device process launch --device <DEVICE_ID> --terminate-existing com.recco.app
```

- [ ] Generic iOS build succeeds.
- [ ] Device appears as `available`.
- [ ] App installs on device.
- [ ] App launches from Xcode/devicectl.
- [ ] App launches from iPhone home screen after cable disconnect.
- [ ] Camera permission is granted.
- [ ] Microphone permission is granted.

## Camera And AR UI

- [ ] Camera opens immediately; no landing page.
- [ ] Face brackets align with faces.
- [ ] Center target becomes active target.
- [ ] Hologram/result panel stays near the face and remains on-screen.
- [ ] Bottom dock shows only scan, mic, keyboard.
- [ ] Buttons do not overlap brackets or text.
- [ ] UI remains readable on large accessibility text.
- [ ] App remains usable in portrait after relaunch.

## Voice

- [ ] Pressing mic starts listening.
- [ ] Deepgram partial transcript appears while speaking.
- [ ] Stopping mic submits the intended command when appropriate.
- [ ] `Find info on him` triggers identity resolution.
- [ ] Keyboard fallback runs the same command path.
- [ ] No API keys are present in the iOS app bundle or source.

## Identity Resolution

Test on a close badge/context crop.

- [ ] Result reaches `target locked`.
- [ ] Result reaches `reading badge/context`.
- [ ] Result reaches `searching profile`.
- [ ] Result reaches `verifying face` when a face crop is present.
- [ ] Result reaches `result ready`.
- [ ] Best candidate name is shown.
- [ ] LinkedIn button appears when a LinkedIn URL is returned.
- [ ] Confidence state is shown as Verified, Possible, or Needs confirmation.
- [ ] Unknown/low-confidence result does not show a wrong name.
- [ ] Result can be saved to Brain.

## Brain

- [ ] First-launch mission prompt appears over the blurred app.
- [ ] Mission can be created from a chip.
- [ ] Mission can be created from typed text.
- [ ] Brain graph opens.
- [ ] Saved scan appears as a node.
- [ ] Detail view shows profile fields and LinkedIn/email when present.
- [ ] Lead priority is computed from the mission.
- [ ] Lead reasons are displayed.
- [ ] Outreach variants are generated.
- [ ] User can choose LinkedIn DM, email, or in-person before marking sent.
- [ ] Fake send animation/status updates the node/detail state.

## Lazy GTM

- [ ] Lazy GTM panel opens from the camera.
- [ ] Voice input works.
- [ ] Typed fallback works.
- [ ] Request such as `Find 8 Swift engineers` creates a run.
- [ ] Prospects render in graph/list.
- [ ] Prospect detail shows match score, reasons, and missing info.
- [ ] Outreach draft can be generated.
- [ ] Fake send updates prospect status.

## Docs And Repo Hygiene

```bash
python3 scripts/check_markdown_links.py
git status --short
```

- [x] Markdown relative links resolve.
- [ ] Only intentional files are modified.
- [ ] No secrets in tracked files.
- [ ] README, runbook, architecture, API contracts, and QA checklist agree.

## Final Demo Gate

- [ ] Backend typecheck passes.
- [ ] Backend tests pass.
- [ ] Convex health endpoint is reachable.
- [ ] CV health endpoint is ready.
- [ ] iPhone app installed and launched.
- [ ] One real identity scan succeeds.
- [ ] One Brain memory appears.
- [ ] One Lazy GTM run succeeds.
