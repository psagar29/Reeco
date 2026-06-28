# Recco — QA Checklist

Per-component verification before a merge or a demo. Boxes are the checks; the
**Last verified** notes record what Person D actually ran on this branch
(Windows, no Xcode), with evidence — claims here are not aspirational.

- **Companion docs:** [INTEGRATION_CHECKLIST](INTEGRATION_CHECKLIST.md) ·
  [DEMO_RUNBOOK](DEMO_RUNBOOK.md)
- **Convention:** *evidence before claims.* If a command wasn't run in this
  environment, it's marked **owner-verified** (whoever has the right machine).

---

## Backend (`backend/`, Convex + TypeScript)

```bash
cd backend
npm ci
npm run typecheck      # tsc --noEmit
npm run test           # vitest (49 cases)
npm run smoke          # exercises every function's logic, prints JSON
npm run verify         # all three above
npm audit              # advisory; see note
```

- [x] `npm ci` installs cleanly.
- [x] `npm run typecheck` → 0 errors.
- [x] `npm run test` → all tests pass.
- [x] `npm run smoke` → exits 0, prints contract-shaped JSON for every function.
- [x] `npm audit` reviewed (status below).

**Last verified (Person D, this branch):** `npm ci` ok · typecheck **exit 0** ·
tests **49/49 passed** (`filter` 11, `opener` 7, `similarity` 17, `voice` 14) ·
smoke **exit 0**.

> **`npm audit` known status:** reports **5 vulnerabilities (3 moderate, 1 high,
> 1 critical)**, all in the **dev-only** transitive chain of `vitest`
> (`vite` / `vite-node` / `esbuild`). These are **test tooling**, not shipped to
> the Convex deployment or the app. **Do not run `npm audit fix --force`** — it
> would force a breaking major bump of the test runner. Accepted for the demo;
> revisit by upgrading `vitest` to a patched major during normal maintenance.

> **`npm ci` note:** npm 11 prints `allow-scripts` advisories for esbuild's
> postinstall. They are informational; tests/smoke run, so esbuild is functional.

---

## CV service (`cv-service/`, FastAPI + InsightFace)

```bash
# Syntax check (works on any Python, no heavy deps):
python -m py_compile cv-service/main.py cv-service/test_embed.py

# Full run (needs Python 3.10–3.11 for InsightFace wheels):
cd cv-service && python -m venv .venv
. .venv/Scripts/Activate.ps1            # PowerShell  (mac/Linux: source .venv/bin/activate)
pip install -r requirements.txt
uvicorn main:app --port 8000
```

- [x] `py_compile` of `main.py` + `test_embed.py` → exit 0 (syntax OK).
- [ ] `GET /health` → `{"ok":true,"model":"buffalo_s","ready":true}` — **owner-verified** (needs deps).
- [ ] `POST /embed` with a real face → `faceDetected:true`, 512 finite floats, ‖v‖ ≈ 1.0 — **owner-verified**.
- [ ] No-face path: `python test_embed.py` (no image) → clean `faceDetected:false`, `embedding:null`, no crash — **owner-verified**.

**Last verified (Person D, this branch):** `py_compile` **exit 0** for both files.

> **Python version caveat:** `py_compile` passes on any modern Python, but
> InsightFace + onnxruntime wheels target **Python 3.10–3.11**. Install/run on a
> 3.10/3.11 venv; newer Pythons (e.g. 3.12+/3.14) may lack prebuilt wheels.

---

## iOS app (`app/ios/Recco/`, SwiftUI) — **owner-verified (Person A, needs Xcode)**

> Agents have no Xcode/iOS SDK and **cannot build or run the app.** These are
> Person A's checks on a Mac with full Xcode.

```bash
# Build for an iPhone simulator (must succeed):
xcodebuild -project app/ios/Recco/Recco.xcodeproj -scheme Recco \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Device-compile (code-signing-only failure without a profile is acceptable):
xcodebuild -project app/ios/Recco/Recco.xcodeproj -scheme Recco \
  -destination 'generic/platform=iOS' build
```

- [ ] Simulator build succeeds (no compile errors).
- [ ] Simulator run in **`mockAll`**: app opens to camera hero; synthetic faces
      produce overlay cards; chips/typed commands dim non-matches; tap → profile;
      "Scan" works; (DEBUG) self-check prints `19/19 passed`.
- [ ] Physical iPhone: real camera tracks 2–3 faces without wild flicker; front/back
      flip keeps boxes aligned; `live`/`mockCV` (with backend up) returns matches.

> Per `docs/planning/PROGRESS_LOG.md`, the camera lane's **pure logic** (19/19)
> and **non-UI type-check** were verified with the Swift compiler, but the full
> `xcodebuild`/Simulator run was **not** done in an agent environment.

---

## Product behavior (acceptance)

End-user behavior, observed on device/simulator (Person A) or approximated via
backend calls (agents). Mirrors `docs/API_CONTRACTS.md` → "Acceptance tests".

- [ ] **Recognized person shows overlay** — enrolled face → card with name + role.
- [ ] **LinkedIn/profile visible** — profile sheet shows links; tap opens LinkedIn.
- [ ] **Unknown does not show a wrong overlay** — below-threshold face → no named card.
      *Agent-verifiable proxy:* unrelated image → `vision:matchFace` returns
      `status:"unknown"`, `personId:null`.
- [ ] **Filters dim/brighten correctly** — "show me AI founders" / chips update
      visible/dimmed in camera + Brain graph.
      *Agent-verifiable proxy:* `npx convex run state:setFilter '{"command":{"action":"filter","includeTags":["AI"],"excludeTags":[]}}'`
      → visible `[ava, nina, omar]`, dimmed `[miles, sam]`.
- [ ] **Draft opener works** — selecting a person yields a short, specific opener.
      *Agent-verifiable proxy:* `npx convex run drafts:createOpener '{"personId":"person_ava_shah"}'`.

> **Windows:** run `npx convex run ...` commands that take JSON args from **Git
> Bash** (PowerShell 5.1 mangles embedded quotes).

---

## Docs / repo hygiene (Person D)

```bash
python scripts/check_markdown_links.py        # relative-link checker (stdlib only)
```

- [x] `check_markdown_links.py` → **OK** (all relative Markdown links resolve).
- [x] Stale `docs/workstreams` / `docs/OPEN_SOURCE_REPOS` references repointed to `docs/planning/...`.
- [x] No secrets in tracked files; `.env.local` git-ignored.

**Last verified (Person D, this branch):** link checker scanned **16** Markdown
files → **OK, exit 0**.

> **About the link checker:** `scripts/check_markdown_links.py` is **standard
> library only**, **ignores external URLs** and in-page `#anchors`, **skips
> fenced and inline code**, and flags any relative link whose target file is
> missing. It is **advisory** (run it before a docs PR); it is intentionally
> **not** a required CI gate yet. It does not validate bare inline-code paths
> (prose like `` `docs/foo.md` ``) or `#anchor` fragments.

---

## Quick "is the demo safe?" gate

Minimum green-light before walking on stage:

- [ ] `cd backend && npm run verify` passes.
- [ ] iOS app launches in `mockAll` (Person A).
- [ ] At least one chip/voice command visibly filters the room.
- [ ] One opener drafts successfully.
- [ ] You've rehearsed the [recovery plan](DEMO_RUNBOOK.md#recovery-plan) once.
