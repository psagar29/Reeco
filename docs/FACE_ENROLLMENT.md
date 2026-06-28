# Face Enrollment

How to turn private photos of the demo roster into the 512-d face embeddings the
backend matches against — locally, reproducibly, and without ever committing a
real photo.

> **TL;DR**
>
> ```bash
> # 1. Drop one clear photo per person here (NOT committed — git-ignored):
> #    demo-data/enrollment/{ava,miles,sam,nina,omar}.jpg
> # 2. Start the CV service (Python 3.10–3.11):
> cd cv-service && uv venv --python 3.11 .venv \
>   && uv pip install --python .venv/bin/python -r requirements.txt \
>   && .venv/bin/python -m uvicorn main:app --port 8000
> # 3. In another terminal, enroll:
> cd backend && cp .env.local.example .env.local   # CV_SERVICE_URL already set
> npm ci && npm run enroll
> # 4. Seed a running Convex deployment with the generated embeddings (below).
> ```

---

## Why Enrollment Is Needed

Recco's known-person face matcher recognizes the seeded roster. To recognize
someone, the backend needs a reference vector per person to compare a live
camera crop against.

The pipeline at match time:

1. iOS crops a face and sends it to the backend (`vision:matchFace`).
2. The backend forwards the crop to the CV service `POST /embed`, which returns a
   **512-dimensional, L2-normalized ArcFace embedding**.
3. The backend cosine-compares that embedding against every **enrolled** person's
   embedding and classifies the best score (`strong ≥ 0.38`, `tentative ≥ 0.30`).

Enrollment is step 0: it produces the per-person reference embeddings. Without
them there is nothing to compare against. `npm run enroll` builds those
reference embeddings — from a real photo when the CV service is up, or from a
deterministic per-person **mock** vector when it is not, so the demo still works
fully offline.

> **Model consistency (important):** enrollment and live matching must use the
> **same** CV model (`RECCO_CV_MODEL`, default `buffalo_s`). Embeddings from
> `buffalo_s` and `buffalo_l` are **not** comparable. Since both enrollment and
> matching call the one CV service, simply don't change the model between
> enrolling and demoing.

---

## How To Capture Good Photos

One photo per person is enough for the demo. Aim for the same conditions the
camera will see on stage.

- **One face, front-facing.** The detector picks the largest face; avoid group
  shots and steep angles.
- **Well lit, in focus.** Even, soft light on the face. No heavy backlight.
- **Reasonable resolution.** The face region should be at least ~160×160 px;
  bigger is fine. Tiny/blurry faces fall below the detector threshold.
- **Neutral, unobstructed.** No sunglasses or masks. Normal glasses are fine.
- **Format:** `.jpg`, `.jpeg`, or `.png`.
- **Match the demo look.** If you'll demo with lanyards/hats on, enroll a photo
  in roughly that state.

---

## Where To Place Files

The enrollment image path per person is defined in
[`demo-data/people.sample.json`](../demo-data/people.sample.json) as
`enrollmentImagePath`. By default:

```text
demo-data/enrollment/ava.jpg     -> person_ava_shah
demo-data/enrollment/miles.jpg   -> person_miles_chen
demo-data/enrollment/sam.jpg     -> person_sam_rivera
demo-data/enrollment/nina.jpg    -> person_nina_park
demo-data/enrollment/omar.jpg    -> person_omar_wilson
```

Create the folder and drop the files in:

```bash
mkdir -p demo-data/enrollment
cp ~/Downloads/ava.jpg   demo-data/enrollment/ava.jpg
# ...repeat per person
```

**`demo-data/enrollment/` is git-ignored** (see [`.gitignore`](../.gitignore)),
so these photos are never committed. If a person's photo is missing, enrollment
does not crash — it uses a mock embedding for that person and reports it.

---

## How To Start The CV Service

Requires **Python 3.10–3.11** (most reliable for InsightFace wheels). The
service downloads its model pack (~125 MB for the default `buffalo_s`) into
`~/.insightface/models/` on first launch.

Using [`uv`](https://docs.astral.sh/uv/) (handles the Python version for you):

```bash
cd cv-service
uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -r requirements.txt
.venv/bin/python -m uvicorn main:app --port 8000
```

Or with a system Python 3.10/3.11:

```bash
cd cv-service
python -m venv .venv
source .venv/bin/activate          # Windows: . .venv/Scripts/Activate.ps1
pip install -r requirements.txt
uvicorn main:app --port 8000
```

Confirm it's ready before enrolling:

```bash
curl http://127.0.0.1:8000/health
# {"ok":true,"model":"buffalo_s","ready":true,"detSize":320,"minDetScore":0.3}
```

`ready: true` means the model is loaded. See
[`cv-service/README.md`](../cv-service/README.md) for full config and the API.

---

## How To Run `npm run enroll`

In a second terminal:

```bash
cd backend
cp .env.local.example .env.local     # CV_SERVICE_URL=http://127.0.0.1:8000 is preset
npm ci
npm run enroll
```

What the script does, per person in `demo-data/people.sample.json`:

1. Loads `backend/.env.local` (without overwriting existing env vars) and reads
   `CV_SERVICE_URL`.
2. If `CV_SERVICE_URL` is set, probes `GET /health` once and prints whether the
   service is reachable, ready, and which model it's serving.
3. For each person:
   - **image present + CV ready** → calls `POST /embed` for a **real** embedding;
   - **image missing** → deterministic mock, reported `mock (image missing)`;
   - **CV found no face** → mock, reported `mock (CV found no face)`;
   - **CV unreachable / not ready / errored** → mock, reported `mock (CV unavailable)`.
4. Validates every final embedding (array, length 512, all finite; real CV
   vectors warned if not ~L2-unit) and writes
   `demo-data/embeddings.generated.json`.

Example output (CV up, photos not present → clean mock fallback):

```text
Enrolling 5 people.
CV_SERVICE_URL = http://127.0.0.1:8000
  /health: ready  model=buffalo_s  detSize=320 minDetScore=0.3
  (enrollment and live matching must use the SAME model: buffalo_s)

  person_ava_shah      mock (image missing)     dim=512 norm=1.000
  person_miles_chen    mock (image missing)     dim=512 norm=1.000
  ...
────────────────────────────────────────────────────────────
People enrolled : 5
Real CV embeds  : 0
Mock fallbacks  : 5
Output written  : demo-data/embeddings.generated.json
────────────────────────────────────────────────────────────
```

With real photos in place and the CV service ready, the per-person source reads
`cv` and `Real CV embeds` counts them.

> **`demo-data/embeddings.generated.json` is git-ignored** — it can carry vectors
> derived from real photos, so it is never committed.

---

## How To Seed Convex With The Generated Embeddings

Run a local Convex deployment (no account needed) and seed it:

```bash
cd backend
CONVEX_AGENT_MODE=anonymous npx convex dev    # terminal A: serves functions

# terminal B — load the enrolled embeddings:
npx convex run seed:run "{\"embeddings\": $(cat ../demo-data/embeddings.generated.json)}"
```

PowerShell:

```powershell
npx convex run seed:run ("{\"embeddings\": $(Get-Content ../demo-data/embeddings.generated.json -Raw)}")
```

To seed with deterministic mock embeddings only (no enrollment file needed):

```bash
npx convex run seed:run
```

`seed:run` is idempotent — safe to re-run. Verify with `npx convex run
people:list` and `npx convex run state:get`. See
[`backend/README.md`](../backend/README.md) for the full function reference.

---

## How To Verify No Secrets Or Images Were Committed

Privacy-sensitive files must stay out of git. Quick checks:

```bash
# 1. Nothing under enrollment/ or the generated file is tracked or staged:
git status --porcelain demo-data/

# 2. Confirm the ignore rules are active (these should print a match):
git check-ignore demo-data/enrollment/ava.jpg demo-data/embeddings.generated.json

# 3. No image files anywhere in the index:
git ls-files | grep -Ei '\.(jpg|jpeg|png|heic)$' || echo "no tracked images — good"

# 4. No real .env.local tracked (only the .example):
git ls-files | grep -E 'backend/\.env\.local$' && echo "LEAK" || echo "ok"
```

`.gitignore` protects `demo-data/enrollment/`, `demo-data/embeddings.generated.json`,
and `backend/.env.local`. Never `git add -f` any of them.

---

## Troubleshooting

**`/health` shows `ready: false` (model not ready).**
The model is still downloading or loading on first launch (~125 MB for
`buffalo_s`). Wait, then re-`curl` `/health`. If it stays false, the `error`
field explains why (usually a failed download or a bad InsightFace install).
Enrolling against a not-ready service is safe — every person falls back to mock.

**`mock (CV found no face)` for a person.**
The detector didn't find a usable face in that photo. Use a clearer, larger,
front-facing, well-lit shot (face ≥ ~160 px). Debug a specific image with:

```bash
curl -s -X POST http://127.0.0.1:8000/debug/detect \
  -H 'content-type: application/json' \
  -d "{\"imageBase64\":\"$(base64 < demo-data/enrollment/ava.jpg)\"}"
```

A `faceCount` of 0, or a `detScore` below `minDetScore` (0.3), means retake the
photo. You can temporarily lower the bar with `RECCO_CV_MIN_DET_SCORE=0.2`.

**Wrong Python version / InsightFace install issues.**
InsightFace wheels are most reliable on **Python 3.10–3.11**. On 3.12/3.13 the
install may try to build from source and need a C/C++ toolchain. Easiest fix is
to let `uv` pin the version: `uv venv --python 3.11 .venv`. If `pip install`
fails to build `insightface`, install build tools (macOS: `xcode-select
--install`) or switch to a 3.11 interpreter.

**`mock (CV unavailable)` even though I started the service.**
The script couldn't reach a *ready* CV service:
- Is it actually listening on the URL in `backend/.env.local`
  (`CV_SERVICE_URL`, default `http://127.0.0.1:8000`)? Re-check `curl .../health`.
- Did `/health` report `ready: true`? A reachable-but-loading service still
  falls back to mock.
- Port mismatch (started on a different `--port`)? Align the env var.

**Mock fallback happened and I expected real embeddings.**
Check the per-person source column in the output and the `/health` line at the
top. Mock fallback is **not a failure** — the demo matches end-to-end on mock
vectors. To force real embeddings: ensure the photo exists at the person's
`enrollmentImagePath`, the CV service is `ready: true`, and `CV_SERVICE_URL`
points at it; then re-run `npm run enroll`.
