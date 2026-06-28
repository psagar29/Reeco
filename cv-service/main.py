"""Recco Computer Vision Service (Person A).

A small FastAPI service that turns a face image into a normalized
512-dimensional InsightFace (ArcFace) embedding.

Contract: see docs/API_CONTRACTS.md

Endpoints:
  GET  /health         -> readiness + model info
  POST /embed          -> 512-d L2-normalized embedding for the best face
  POST /debug/detect   -> (optional) detected face boxes for debugging

The service is stateless. It never stores roster data; matching belongs to
Person B's Convex backend.
"""

from __future__ import annotations

import base64
import binascii
import io
import os
import time
from typing import Any, Optional

import numpy as np
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

# Pillow is used to decode arbitrary image bytes (jpeg/png/...) reliably,
# then we hand a BGR numpy array to InsightFace.
from PIL import Image

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Model pack. Default is buffalo_s: it emits the same 512-d ArcFace embedding as
# buffalo_l but uses a MobileFaceNet recognition net that is ~4x faster on CPU
# (~380ms warm vs ~1.7s for buffalo_l on a 16-core machine), which is what
# keeps us under the 800ms demo target. Set RECCO_CV_MODEL=buffalo_l for the
# highest-accuracy ResNet50 recognition net. IMPORTANT: enrollment and live
# matching MUST use the same model — embeddings from buffalo_s and buffalo_l
# are not comparable.
MODEL_NAME = os.environ.get("RECCO_CV_MODEL", "buffalo_s")

# Detector input size. Larger -> better at finding small/distant faces, slower.
# 320 is plenty for the pre-cropped faces iOS sends and roughly halves detector
# cost vs 640. Raise to 640 if you feed full frames with small faces.
DET_SIZE = int(os.environ.get("RECCO_CV_DET_SIZE", "320"))

# Minimum detection confidence to treat a face as usable.
MIN_DET_SCORE = float(os.environ.get("RECCO_CV_MIN_DET_SCORE", "0.30"))

# Run one dummy inference at startup so the first real request is warm
# (avoids paying onnxruntime graph-optimization/allocation cost on request 1).
WARMUP = os.environ.get("RECCO_CV_WARMUP", "1") not in ("0", "false", "False")

# Embedding dimensionality guaranteed by the contract.
EMBED_DIM = 512

# ---------------------------------------------------------------------------
# App + lazily-loaded model state
# ---------------------------------------------------------------------------

app = FastAPI(title="Recco CV Service", version="1.0.0")

# Holds the loaded insightface.app.FaceAnalysis instance once ready.
_face_app: Optional[Any] = None
_model_ready: bool = False
_load_error: Optional[str] = None


def _load_model() -> None:
    """Load InsightFace once. Records any failure rather than crashing."""
    global _face_app, _model_ready, _load_error

    try:
        # Imported lazily so the module can be inspected/tested even if the
        # heavy native deps are not installed yet.
        from insightface.app import FaceAnalysis

        # Pin to the CPU execution provider explicitly. onnxruntime's CPU EP
        # uses all physical cores for intra-op parallelism by default, which is
        # what we want for low single-request latency.
        face_app = FaceAnalysis(
            name=MODEL_NAME, providers=["CPUExecutionProvider"]
        )
        # ctx_id < 0 forces CPU; the demo machine has no guaranteed GPU.
        face_app.prepare(ctx_id=-1, det_size=(DET_SIZE, DET_SIZE))

        _face_app = face_app
        _model_ready = True
        _load_error = None

        if WARMUP:
            _warmup(face_app)
    except Exception as exc:  # pragma: no cover - environment dependent
        _face_app = None
        _model_ready = False
        _load_error = f"{type(exc).__name__}: {exc}"


def _warmup(face_app: Any) -> None:
    """Run several dummy inferences so the first real request doesn't pay the
    one-time onnxruntime cost (graph optimization + memory-arena growth +
    thread-pool spin-up). The CPU arena stabilizes after a few passes, so a
    single warmup pass is not enough — we loop. Best-effort: never fatal."""
    try:
        rec = None
        for model in getattr(face_app, "models", {}).values():
            if hasattr(model, "get_feat"):
                rec = model
                break

        det = np.zeros((DET_SIZE, DET_SIZE, 3), dtype=np.uint8)
        face112 = np.zeros((112, 112, 3), dtype=np.uint8)

        # Loop so the onnxruntime CPU arena/thread pool fully warms.
        for _ in range(4):
            face_app.get(det)              # warm the detection graph
            if rec is not None:
                rec.get_feat(face112)      # warm the ArcFace recognition graph
    except Exception:
        # Warmup is an optimization, not a correctness requirement.
        pass


@app.on_event("startup")
def _on_startup() -> None:
    _load_model()


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------


class EmbedRequest(BaseModel):
    """JSON body for POST /embed (request option A)."""

    imageBase64: str = Field(..., description="Base64-encoded image bytes")
    imageMimeType: Optional[str] = Field(
        default=None, description="e.g. image/jpeg or image/png"
    )
    requestId: Optional[str] = Field(
        default=None, description="Caller-supplied id, echoed back"
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _decode_base64_image(image_b64: str) -> bytes:
    """Decode base64 (with or without a data-URL prefix) to raw bytes."""
    data = image_b64.strip()
    if data.startswith("data:"):
        # data:image/jpeg;base64,XXXX  ->  XXXX
        _, _, data = data.partition(",")
    return base64.b64decode(data, validate=False)


def _bytes_to_bgr(image_bytes: bytes) -> np.ndarray:
    """Decode image bytes to a BGR uint8 numpy array (OpenCV/InsightFace order)."""
    pil = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    rgb = np.asarray(pil)  # HxWx3, RGB
    bgr = rgb[:, :, ::-1].copy()  # InsightFace expects BGR
    return bgr


def _l2_normalize(vec: np.ndarray) -> np.ndarray:
    norm = float(np.linalg.norm(vec))
    if norm == 0.0 or not np.isfinite(norm):
        raise ValueError("embedding has zero or non-finite norm")
    return vec / norm


def _pick_best_face(faces: list) -> Any:
    """Pick the largest face by bounding-box area (closest/most prominent)."""

    def area(face: Any) -> float:
        x1, y1, x2, y2 = face.bbox
        return float(max(0.0, x2 - x1) * max(0.0, y2 - y1))

    return max(faces, key=area)


def _quality(
    face_detected: bool,
    crop_width: Optional[int],
    crop_height: Optional[int],
    detection_score: Optional[float] = None,
) -> dict:
    q: dict = {
        "faceDetected": face_detected,
        "cropWidth": crop_width,
        "cropHeight": crop_height,
        "model": MODEL_NAME,
    }
    if detection_score is not None:
        q["detectionScore"] = round(float(detection_score), 4)
    return q


def _failure(
    request_id: Optional[str],
    error: str,
    crop_width: Optional[int] = None,
    crop_height: Optional[int] = None,
    status_code: int = 200,
) -> JSONResponse:
    """A clean, contract-shaped failure (never a server crash)."""
    body = {
        "requestId": request_id,
        "faceDetected": False,
        "embedding": None,
        "quality": _quality(False, crop_width, crop_height),
        "error": error,
    }
    return JSONResponse(status_code=status_code, content=body)


def _embed_from_bytes(image_bytes: bytes, request_id: Optional[str]):
    """Core pipeline shared by JSON and multipart entrypoints.

    Returns a dict (success or failure) plus an HTTP status code.
    """
    started = time.perf_counter()

    if not _model_ready or _face_app is None:
        return (
            {
                "requestId": request_id,
                "faceDetected": False,
                "embedding": None,
                "quality": _quality(False, None, None),
                "error": f"Model not ready: {_load_error or 'still loading'}",
            },
            503,
        )

    # Decode image bytes.
    try:
        bgr = _bytes_to_bgr(image_bytes)
    except Exception as exc:
        return (
            {
                "requestId": request_id,
                "faceDetected": False,
                "embedding": None,
                "quality": _quality(False, None, None),
                "error": f"Could not decode image: {exc}",
            },
            400,
        )

    img_h, img_w = bgr.shape[:2]

    # Detect faces.
    faces = _face_app.get(bgr)
    if not faces:
        return (
            {
                "requestId": request_id,
                "faceDetected": False,
                "embedding": None,
                "quality": _quality(False, img_w, img_h),
                "error": "No usable face detected",
            },
            200,
        )

    face = _pick_best_face(faces)
    det_score = float(getattr(face, "det_score", 0.0) or 0.0)

    x1, y1, x2, y2 = (int(v) for v in face.bbox)
    crop_w = max(0, x2 - x1)
    crop_h = max(0, y2 - y1)

    if det_score < MIN_DET_SCORE:
        return (
            {
                "requestId": request_id,
                "faceDetected": False,
                "embedding": None,
                "quality": _quality(False, crop_w, crop_h, det_score),
                "error": (
                    f"No usable face detected: best detection score "
                    f"{det_score:.2f} is below the minimum {MIN_DET_SCORE:.2f}"
                ),
            },
            200,
        )

    # Extract + normalize embedding.
    raw = getattr(face, "normed_embedding", None)
    if raw is None:
        raw = getattr(face, "embedding", None)
    if raw is None:
        return (
            {
                "requestId": request_id,
                "faceDetected": False,
                "embedding": None,
                "quality": _quality(False, crop_w, crop_h, det_score),
                "error": "Face found but embedding extraction failed",
            },
            200,
        )

    vec = np.asarray(raw, dtype=np.float64).flatten()

    if vec.shape[0] != EMBED_DIM:
        # Never return a partial-length embedding.
        return (
            {
                "requestId": request_id,
                "faceDetected": False,
                "embedding": None,
                "quality": _quality(False, crop_w, crop_h, det_score),
                "error": f"Unexpected embedding length {vec.shape[0]}, expected {EMBED_DIM}",
            },
            500,
        )

    try:
        vec = _l2_normalize(vec)
    except ValueError as exc:
        return (
            {
                "requestId": request_id,
                "faceDetected": False,
                "embedding": None,
                "quality": _quality(False, crop_w, crop_h, det_score),
                "error": f"Invalid embedding: {exc}",
            },
            500,
        )

    if not np.all(np.isfinite(vec)):
        return (
            {
                "requestId": request_id,
                "faceDetected": False,
                "embedding": None,
                "quality": _quality(False, crop_w, crop_h, det_score),
                "error": "Embedding contained non-finite values",
            },
            500,
        )

    latency_ms = int(round((time.perf_counter() - started) * 1000))

    return (
        {
            "requestId": request_id,
            "faceDetected": True,
            "embedding": [float(x) for x in vec.tolist()],
            "quality": _quality(True, crop_w, crop_h, det_score),
            "latencyMs": latency_ms,
        },
        200,
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@app.get("/health")
def health() -> dict:
    """Readiness probe. `ok` is true if the process is up; `ready` is true
    only once the model has loaded successfully."""
    body = {
        "ok": True,
        "model": MODEL_NAME,
        "ready": bool(_model_ready),
        "detSize": DET_SIZE,
        "minDetScore": MIN_DET_SCORE,
    }
    if not _model_ready and _load_error:
        body["error"] = _load_error
    return body


@app.post("/embed")
async def embed(request: Request) -> JSONResponse:
    """Return a 512-d L2-normalized embedding for the best face in the image.

    Supports both request styles from the contract by inspecting Content-Type:
      A) JSON body: { imageBase64, imageMimeType?, requestId? }
      B) multipart: file=<jpeg/png>, requestId=<id>
    """
    request_id: Optional[str] = None
    image_bytes: Optional[bytes] = None
    content_type = (request.headers.get("content-type") or "").lower()

    if "multipart/form-data" in content_type:
        # Multipart path (option B).
        form = await request.form()
        request_id = form.get("requestId")  # type: ignore[assignment]
        upload = form.get("file")
        if upload is None or not hasattr(upload, "read"):
            return _failure(request_id, "Missing multipart 'file' field", status_code=400)
        try:
            image_bytes = await upload.read()  # type: ignore[union-attr]
        except Exception as exc:
            return _failure(request_id, f"Could not read uploaded file: {exc}", status_code=400)
        if not image_bytes:
            return _failure(request_id, "Empty uploaded file", status_code=400)
    else:
        # JSON path (option A).
        try:
            body = await request.json()
        except Exception:
            return _failure(
                None,
                "Provide a JSON body with imageBase64 or multipart file",
                status_code=400,
            )
        try:
            payload = EmbedRequest(**body)
        except Exception as exc:
            return _failure(body.get("requestId") if isinstance(body, dict) else None,
                            f"Invalid request body: {exc}", status_code=400)
        request_id = payload.requestId
        if not payload.imageBase64:
            return _failure(request_id, "Missing imageBase64", status_code=400)
        try:
            image_bytes = _decode_base64_image(payload.imageBase64)
        except (binascii.Error, ValueError) as exc:
            return _failure(request_id, f"Invalid base64 image: {exc}", status_code=400)

    result, status_code = _embed_from_bytes(image_bytes, request_id)
    return JSONResponse(status_code=status_code, content=result)


@app.post("/debug/detect")
async def debug_detect(request: Request) -> JSONResponse:
    """Optional helper: return detected face boxes/scores for tuning."""
    if not _model_ready or _face_app is None:
        return JSONResponse(
            status_code=503,
            content={"ready": False, "error": _load_error or "still loading"},
        )

    content_type = (request.headers.get("content-type") or "").lower()
    if "multipart/form-data" in content_type:
        form = await request.form()
        upload = form.get("file")
        if upload is None or not hasattr(upload, "read"):
            return JSONResponse(status_code=400, content={"error": "no image provided"})
        image_bytes = await upload.read()  # type: ignore[union-attr]
    else:
        try:
            body = await request.json()
            image_bytes = _decode_base64_image(body["imageBase64"])
        except Exception:
            return JSONResponse(status_code=400, content={"error": "no image provided"})

    try:
        bgr = _bytes_to_bgr(image_bytes)
    except Exception as exc:
        return JSONResponse(status_code=400, content={"error": f"decode failed: {exc}"})

    faces = _face_app.get(bgr)
    out = []
    for f in faces:
        x1, y1, x2, y2 = (int(v) for v in f.bbox)
        out.append(
            {
                "bbox": [x1, y1, x2, y2],
                "width": x2 - x1,
                "height": y2 - y1,
                "detScore": round(float(getattr(f, "det_score", 0.0) or 0.0), 4),
            }
        )
    return JSONResponse(
        status_code=200,
        content={"faceCount": len(out), "faces": out, "model": MODEL_NAME},
    )


if __name__ == "__main__":  # pragma: no cover
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8000)
