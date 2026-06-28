# Person B Handoff — CV Service + Face Enrollment

Branch: `agent/person-b-cv-enrollment`

## Summary of changes

Hardened the face-enrollment workflow and made the CV-service docs consistent
with the code's actual defaults. No API contracts changed; no iOS or Convex
matching logic touched.

- **`backend/scripts/enroll.ts` — rewritten to be clear and reliable:**
  - Pre-flight `GET /health` probe when `CV_SERVICE_URL` is set; reports
    reachable/ready/model (+ `detSize`/`minDetScore`) before enrolling.
  - Per-person source is explicit: `cv`, `mock (image missing)`,
    `mock (CV found no face)`, or `mock (CV unavailable)`. A missing image (or an
    unavailable/not-ready CV service) never crashes the run.
  - Added validation helpers `isFiniteEmbedding`, `embeddingNorm`,
    `validateEmbedding`. Every final embedding is validated (array, length 512,
    finite) before writing; real CV embeddings warn if L2 norm isn't ~1.0
    (tolerance 0.02).
  - Final summary: people enrolled, real-CV count, mock-fallback count, output
    path, and the exact next commands to seed Convex (bash + PowerShell).
- **`cv-service/main.py`:**
  - Fixed a stale comment that contradicted itself ("buffalo_l is the default" vs
    "Default is buffalo_s"). Default is `buffalo_s`.
  - `GET /health` now also returns `detSize` and `minDetScore` (additive,
    contract-compatible).
  - Clearer low-confidence `/embed` error: now reports the best detection score
    and the minimum threshold.
- **Docs made honest + consistent:**
  - `cv-service/README.md`: first-launch download is the **default `buffalo_s`**
    (~125 MB), not `buffalo_l`; all example `model` values now show `buffalo_s`;
    `/health` example shows the new `detSize`/`minDetScore` fields.
  - Root `README.md` and `docs/ARCHITECTURE.md`: CV warm latency corrected from
    `~90 ms` to `~380 ms` (matches the code comment + CV README perf table).
  - New `docs/FACE_ENROLLMENT.md`: end-to-end enrollment guide (why, photo tips,
    file placement, CV start, `npm run enroll`, Convex seeding, privacy checks,
    troubleshooting).
  - `backend/README.md` + `backend/.env.local.example`: cross-link to the new
    enrollment doc; note that `enroll` also uses `CV_SERVICE_URL`.

## Files touched

```
backend/scripts/enroll.ts          (rewritten)
backend/README.md                  (+cross-link to FACE_ENROLLMENT.md)
backend/.env.local.example         (CV_SERVICE_URL comment: enroll uses it too)
cv-service/main.py                 (comment fix; /health +detSize/minDetScore; clearer error)
cv-service/README.md               (buffalo_s consistency; /health fields; download size)
docs/ARCHITECTURE.md               (~90ms -> ~380ms; model-consistency note)
README.md                          (~90ms -> ~380ms warm, default buffalo_s)
docs/FACE_ENROLLMENT.md            (new)
docs/agent-handoffs/PERSON_B_CV_ENROLLMENT.md  (new, this file)
```

Not touched (per ownership rules): `app/ios/**`, Convex function contracts,
backend matching logic, `docs/API_CONTRACTS.md`.

## Commands run and results

All on macOS (Apple Silicon), Node v25, npm 11, Python 3.11 via `uv`.

| Command | Result |
|---|---|
| `python -m py_compile cv-service/main.py cv-service/test_embed.py` | ✅ OK |
| `cd backend && npm ci` | ✅ installed from lockfile |
| `npm run typecheck` (`tsc --noEmit`) | ✅ 0 errors |
| `npm run test` (vitest) | ✅ **49 passed** (4 files) |
| `uv venv --python 3.11 .venv && uv pip install -r requirements.txt` | ✅ deps installed |
| `uvicorn main:app --port 8000` | ✅ `buffalo_s` downloaded (~125 MB), model ready |
| `curl /health` | ✅ `{"ok":true,"model":"buffalo_s","ready":true,"detSize":320,"minDetScore":0.3}` |
| `python test_embed.py` (no-face path) | ✅ clean failure, all assertions passed |
| `CV_SERVICE_URL=… npm run enroll` (no photos) | ✅ all 5 → `mock (image missing)`, dim=512 norm=1.000 |
| `npm run enroll` with one real face (transient) | ✅ 1 → `cv` norm=1.000, 4 → mock; file git-ignored |

## Was the real CV service run?

**Yes.** Python 3.11 was provisioned with `uv`, the default `buffalo_s` pack
downloaded and loaded, `/health` returned `ready: true`, and the enrollment
script's health probe + real `/embed` path were both exercised live.

## Real images or mock fallback?

**No real roster photos exist in the repo** (they're private + git-ignored), so a
normal `npm run enroll` produces 5 deterministic **mock** embeddings — which
still match end-to-end. The real `cv` path was verified once by transiently
copying InsightFace's bundled `Tom_Hanks_54745.png` into the git-ignored
`demo-data/enrollment/` (→ `person_ava_shah` got a real `cv` embedding,
norm=1.000), then deleting it. No face image was committed; the regenerated
`demo-data/embeddings.generated.json` on disk is all-mock and git-ignored.

## Exact steps for teammates

```bash
# 1. Private photos (git-ignored), one per person:
#    demo-data/enrollment/{ava,miles,sam,nina,omar}.jpg

# 2. CV service (Python 3.10–3.11):
cd cv-service
uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -r requirements.txt
.venv/bin/python -m uvicorn main:app --port 8000
curl http://127.0.0.1:8000/health        # wait for "ready": true

# 3. Enroll (second terminal):
cd backend
cp .env.local.example .env.local          # CV_SERVICE_URL preset
npm ci
npm run enroll                            # -> demo-data/embeddings.generated.json

# 4. Seed a running Convex deployment:
CONVEX_AGENT_MODE=anonymous npx convex dev   # terminal A
npx convex run seed:run "{\"embeddings\": $(cat ../demo-data/embeddings.generated.json)}"  # terminal B
```

Full guide with photo tips + troubleshooting: `docs/FACE_ENROLLMENT.md`.

## Known blockers / notes

- **None blocking.** Enrollment, the CV service, and all backend checks run
  cleanly on this machine.
- `npm ci` prints `allow-scripts` warnings (esbuild/fsevents postinstall not
  pre-approved). Harmless — install and all scripts still succeed.
- Direct system Python here is 3.13; InsightFace is happiest on 3.10–3.11, so
  `uv venv --python 3.11` (or any 3.11 interpreter) is the recommended path. This
  is documented in `cv-service/README.md` and `docs/FACE_ENROLLMENT.md`.
- `docs/API_CONTRACTS.md` example JSON still shows `"model": "buffalo_l"`. Left
  unchanged on purpose — it's the frozen cross-team contract and the `model`
  field is illustrative, not a guarantee. Flag for coordination if the team wants
  the example value updated to `buffalo_s`.
- Threshold tuning (`strong 0.38` / `tentative 0.30`) still wants real demo
  photos once they exist — unchanged from Person A/B defaults.
```
