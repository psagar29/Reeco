# Person A - Computer Vision Service / InsightFace

## One-line mission

Build the Python face-embedding service that receives a face image and returns a normalized 512-dimensional embedding.

## You own

- `cv-service/`
- Local FastAPI server
- InsightFace setup
- Face embedding extraction
- Health/test endpoints
- Clear failure responses when no usable face is found

## Main reference repo

- `open-source/insightface`

## Read first

1. `docs/API_CONTRACTS.md`
2. `docs/OPEN_SOURCE_REPOS.md`

## Required deliverables

Create:

- `cv-service/main.py`
- `cv-service/requirements.txt`
- `cv-service/README.md`
- `cv-service/test_embed.py`

Endpoints:

- `GET /health`
- `POST /embed`

## API contract

Local service URL:

```txt
http://127.0.0.1:8000
```

`GET /health` returns:

```json
{
  "ok": true,
  "model": "buffalo_l",
  "ready": true
}
```

`POST /embed` accepts:

```json
{
  "imageBase64": "/9j/4AAQSkZJRgABAQ...",
  "imageMimeType": "image/jpeg",
  "requestId": "track_123"
}
```

Successful response:

```json
{
  "requestId": "track_123",
  "faceDetected": true,
  "embedding": [0.0123, -0.0456],
  "quality": {
    "faceDetected": true,
    "detectionScore": 0.97,
    "cropWidth": 180,
    "cropHeight": 180,
    "model": "buffalo_l"
  },
  "latencyMs": 421
}
```

Failure response:

```json
{
  "requestId": "track_123",
  "faceDetected": false,
  "embedding": null,
  "quality": {
    "faceDetected": false,
    "cropWidth": 52,
    "cropHeight": 48,
    "model": "buffalo_l"
  },
  "error": "No usable face detected"
}
```

## Implementation notes

- Use FastAPI.
- Use `insightface.app.FaceAnalysis`.
- Start with `buffalo_l`.
- If setup is too slow, use `buffalo_s`.
- Return L2-normalized embeddings.
- Never return partial embeddings.
- Do not store roster data in this service. Matching belongs to Person B.

## Step-by-step plan

1. Create a FastAPI app with `/health`.
2. Add image-base64 decoding.
3. Load InsightFace once at startup.
4. Run face detection on the image.
5. Pick the largest/best detected face.
6. Extract embedding.
7. Normalize embedding.
8. Return JSON matching the contract.
9. Add `test_embed.py` that calls `/embed` with a local image.
10. Share local run command with Person B.

## Done when

- `uvicorn main:app --reload --port 8000` starts.
- `/health` returns ready.
- `/embed` returns exactly 512 floats for a real face image.
- A no-face image returns a clean error.
- Person B can call your service from Convex or a local script.

## Fallback

If InsightFace setup is painful:

- Return deterministic mock embeddings for the 5 demo enrollment images.
- Keep the same `/embed` contract.
- Tell Person B immediately so matching can proceed.

## What not to do

- Do not build the iOS camera.
- Do not build Convex matching.
- Do not call OpenAI.
- Do not change response shapes without telling the team.

