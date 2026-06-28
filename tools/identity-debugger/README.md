# Recco · Identity Debugger

A zero-dependency, single-file browser tool for debugging the **"find info on him"**
identity flow end to end:

```
face image + badge/context image
  → POST {convexBase}/api/identity/resolve   (Convex HTTP bridge)
    → OpenAI Vision   reads the name off the badge/context crop
    → Fiber AI        finds LinkedIn / profile candidates
    → EC2 CV service  embeds live face + candidate profile photo, compares
  → status: verified | possible | needs_clarification | not_found | error
```

Use it to find out **exactly where the chain breaks** when the iPhone app reads a
name but does not verify the face.

No build step, no framework. Just static HTML/CSS/JS.

## Run it

```bash
cd tools/identity-debugger
python3 -m http.server 5174
```

Then open: <http://localhost:5174>

> Serve over `http://localhost` (not `file://`) so `fetch` and image processing
> behave consistently. Port `5174` matches the CORS allow-list added to the CV
> service (see below).

## What it does

### 1. Configuration
- **Convex base URL** — default `https://fabulous-hyena-861.convex.site`
- **CV service base URL** — default `http://18.118.12.102:8000`
- **Track ID** — auto-filled `dbg_<timestamp>_<rand>`, regenerated after each resolve
- **Transcript / name hint** — default `find info on him`
- **Image MIME**, **max dimension**, **JPEG quality** — control client-side compression

### 2. Quick endpoint checks
- `GET /api/health` (Convex)
- `GET /api/people` (Convex; shows count)
- `GET /health` (CV service)

### 3. Images
- Upload (or drag-drop) a **face** image and a **context/badge** image.
- Or tick **"Use one image for both"** to send the same image as face + context.
- Each image is previewed, **resized + recompressed to JPEG base64 in the browser**,
  and the tool shows original→final dimensions and the final payload size.
- The `data:` URL prefix is stripped before sending — the backend receives raw base64.

### 4. Resolve + auto-diagnosis
`POST /api/identity/resolve` with:

```json
{
  "trackId": "...",
  "transcript": "find info on him",
  "faceImageBase64": "...",
  "contextImageBase64": "...",
  "imageMimeType": "image/jpeg"
}
```

The result panel shows **status, message, latency**, the **clue** (fullName, company,
role, school, confidence, evidence, rawText), the **candidates table** (name, company,
role, school, LinkedIn, email, profile photo, matchScore, source), the **verification**
block (candidateId, verified, score, threshold, faceDetected, message), and the **raw
JSON**.

Below the status it prints an automatic **diagnosis** that maps the result to the
likely failure point, e.g.:

| Symptom | Diagnosis |
| --- | --- |
| `needs_clarification` | OpenAI Vision didn't read a reliable name — clearer badge crop / say the name. |
| `clue.fullName` set, `candidates` empty | OCR worked, Fiber returned no candidates. |
| candidates exist, none has `profilePhotoUrl` | Fiber gave candidates but no photos — face verify can't run. |
| `verification` is `null` | No verification ran — check live-face embedding / photo fetch / CV path. |
| `verification.faceDetected = false` | CV found no usable face in the live crop or profile photo. |
| `score` below `threshold` | Faces compared but score too low — better crop or tune threshold. |
| `verification.message` mentions *mock* | CV unreachable from Convex — fell back to mock; nothing truly verified. |
| `possible` | Identity found but not face-verified. |
| `verified` | End-to-end verification passed. |

### 5. Direct CV test (`POST /embed`)
Upload one image and send it straight to the EC2 CV service to see whether **the crop
itself** is usable: `faceDetected`, `detectionScore`, `cropWidth/Height`, `model`,
embedding length, latency, and any `error`. This isolates "is my face crop good?" from
the rest of the pipeline.

## CORS note (important)

- **Convex** (`/api/*`) already returns `Access-Control-Allow-Origin: *`, so the
  health/people/resolve calls work from the browser with no changes.
- **The CV service has no CORS headers**, so the browser's **Direct CV test** call to
  `http://18.118.12.102:8000/embed` is blocked by a CORS preflight until the service is
  updated. This does **not** affect the main resolve flow — Convex calls the CV service
  **server-side**, where CORS is irrelevant.

To enable the in-browser Direct CV test, this repo adds a **scoped** CORS allow-list to
`cv-service/main.py` for local debugging only:

```python
from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5174", "http://127.0.0.1:5174"],
    allow_methods=["*"],
    allow_headers=["*"],
)
```

Redeploy the EC2 CV service for that to take effect. If you can't redeploy, just test
`/embed` with `curl` instead:

```bash
B64=$(base64 -i face.jpg | tr -d '\n')
curl -s http://18.118.12.102:8000/embed \
  -H 'Content-Type: application/json' \
  -d "{\"imageBase64\":\"$B64\",\"imageMimeType\":\"image/jpeg\",\"requestId\":\"t1\"}" | jq '.faceDetected, .quality, (.embedding|length)'
```

## Privacy / safety

- **Do not commit teammate photos.** This folder's `.gitignore` ignores common image
  types under `tools/identity-debugger/`. Keep test photos local.
- The tool never stores images server-side; the backend logs text + scores only, never
  raw images.
- Keys (OpenAI / Fiber / Deepgram) live in Convex env and are **never** in this tool.
