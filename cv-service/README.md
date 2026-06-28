# Recco CV Service (Person A)

A small stateless **FastAPI** service that turns a face image into a
**normalized 512-dimensional InsightFace (ArcFace) embedding**.

Person B's Convex backend (`vision:matchFace`) calls this service, then
compares the returned embedding against the enrolled roster with cosine
similarity. This service **never stores roster data** — matching is not its job.

- Default model pack: `buffalo_s` (RetinaFace detector + ArcFace MobileFaceNet)
  — ~380ms warm on CPU. Set `RECCO_CV_MODEL=buffalo_l` for the higher-accuracy
  ResNet50 net (~1.7s warm).
- Embedding: 512 floats, **L2-normalized**, finite values only
- Endpoints: `GET /health`, `POST /embed`, `POST /debug/detect` (optional)

> **Model consistency (important for Person B):** enrollment and live matching
> must use the **same** `RECCO_CV_MODEL`. Embeddings from `buffalo_s` and
> `buffalo_l` are not comparable. Since both enrollment and matching call this
> one service, just don't change the model between enrolling and demoing.

---

## Quick start

```bash
cd cv-service

# 1. Create an isolated environment (Python 3.10–3.11 recommended)
python -m venv .venv
# Windows PowerShell:
. .venv/Scripts/Activate.ps1
# macOS/Linux:
# source .venv/bin/activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Run the service
uvicorn main:app --reload --port 8000
```

The service binds to `http://127.0.0.1:8000`.

On first startup InsightFace downloads the configured model pack into
`~/.insightface/models/` — the default `buffalo_s` (~125 MB download) or the
larger, higher-accuracy `buffalo_l` (~300 MB) if you set
`RECCO_CV_MODEL=buffalo_l`. The first launch is slow (download + warmup); later
launches are fast. `/health` reports `ready: true` once the model is loaded.

---

## Configuration (environment variables)

| Variable                  | Default      | Meaning                                                  |
|---------------------------|--------------|----------------------------------------------------------|
| `RECCO_CV_MODEL`          | `buffalo_s`  | InsightFace model pack. `buffalo_l` = higher accuracy.   |
| `RECCO_CV_DET_SIZE`       | `320`        | Detector input size (square). Larger = slower.           |
| `RECCO_CV_MIN_DET_SCORE`  | `0.30`       | Min detector confidence to treat a face as usable.       |
| `RECCO_CV_WARMUP`         | `1`          | Run dummy inferences at startup so call #1 is fast.      |

Example (highest accuracy, slower):

```bash
RECCO_CV_MODEL=buffalo_l RECCO_CV_DET_SIZE=640 uvicorn main:app --port 8000
```

### Performance (16-core CPU, single face crop, warm)

| Config                     | Warm median | First call |
|----------------------------|-------------|------------|
| `buffalo_s` @ det 320 (default) | **~380ms** | ~1.1s   |
| `buffalo_l` @ det 320      | ~1.1s       | ~1.5s      |
| `buffalo_l` @ det 640      | ~1.7s       | ~1.9s      |

Startup runs a looped warmup so the first request doesn't pay onnxruntime's
one-time arena/thread-pool cost. iOS should still cache a strong match per face
track (per the camera rules) rather than re-embedding every frame.

---

## API

Base URL (local default): `http://127.0.0.1:8000`

### `GET /health`

```json
{ "ok": true, "model": "buffalo_s", "ready": true, "detSize": 320, "minDetScore": 0.3 }
```

`ok` is true while the process is up. `ready` is true only once the model has
loaded. `detSize` and `minDetScore` echo the active detector configuration. If
loading failed, an `error` field explains why.

### `POST /embed`

Two request styles are accepted.

**Option A — JSON (easiest from Convex actions):**

```json
{
  "imageBase64": "/9j/4AAQSkZJRgABAQ...",
  "imageMimeType": "image/jpeg",
  "requestId": "track_123"
}
```

`imageBase64` may include a `data:image/jpeg;base64,` prefix; it is stripped
automatically.

**Option B — multipart (better for direct HTTP):**

```
file=<jpeg/png bytes>
requestId=track_123
```

**Success response:**

```json
{
  "requestId": "track_123",
  "faceDetected": true,
  "embedding": [0.0123, -0.0456, "... 512 floats ..."],
  "quality": {
    "faceDetected": true,
    "detectionScore": 0.97,
    "cropWidth": 180,
    "cropHeight": 180,
    "model": "buffalo_s"
  },
  "latencyMs": 421
}
```

**Failure response** (no face / unusable face — HTTP 200, clean shape):

```json
{
  "requestId": "track_123",
  "faceDetected": false,
  "embedding": null,
  "quality": { "faceDetected": false, "cropWidth": 52, "cropHeight": 48, "model": "buffalo_s" },
  "error": "No usable face detected"
}
```

Embedding guarantees:

- length is exactly **512**
- values are **finite** floats
- vector is **L2-normalized** (‖v‖ ≈ 1.0)
- a partial-length embedding is **never** returned

Status codes: `200` success or clean no-face; `400` bad/undecodable input;
`503` model not ready yet; `500` unexpected embedding problem. The body always
follows the contract shape above.

### `POST /debug/detect` (optional)

Returns detected face boxes + scores for tuning. Accepts the same JSON or
multipart input.

```json
{ "faceCount": 1, "faces": [{ "bbox": [x1,y1,x2,y2], "width": 180, "height": 180, "detScore": 0.97 }], "model": "buffalo_s" }
```

---

## Testing

With the service running:

```bash
# Real face image — validates 512-d, L2 norm, echoed requestId
python test_embed.py path/to/face.jpg

# Multipart path
python test_embed.py path/to/face.jpg --multipart

# No image -> exercises the clean no-face error path with synthetic noise
python test_embed.py
```

Quick manual check:

```bash
curl http://127.0.0.1:8000/health
```

---

## Notes for Person B (backend integration)

- Set `CV_SERVICE_URL=http://127.0.0.1:8000` in the Convex environment.
- Call `POST /embed` with the JSON base64 body; read `embedding` (512 floats).
- The embedding is already L2-normalized, so cosine similarity reduces to a dot
  product, but the contract's `cosine()` still works unchanged.
- On `faceDetected: false`, map to `FaceMatchResult.status = "no_face"`.
- Suggested thresholds from the contract: strong `0.38`, tentative `0.30`.
- This service is stateless; restart-safe; holds no roster data.

## Fallback

If InsightFace cannot be installed in time, the same `/embed` contract can be
served with deterministic mock embeddings (e.g. a seeded hash of the image
bytes mapped to a unit 512-vector). Tell Person B immediately so matching can
proceed against mock vectors with an identical response shape.
