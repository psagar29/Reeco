"""Smoke test for the Recco CV service (Person A).

Usage:
    # 1. Start the service in another terminal:
    #    uvicorn main:app --port 8000
    #
    # 2. Run this against a real face image (JSON base64 path):
    python test_embed.py path/to/face.jpg
    #
    # 3. Or test the multipart path:
    python test_embed.py path/to/face.jpg --multipart
    #
    # 4. With no image argument, a synthetic noise image is sent to exercise
    #    the "no face -> clean error" path:
    python test_embed.py

This script verifies the response shape Person B's Convex backend depends on:
  - faceDetected is a bool
  - embedding is exactly 512 finite floats (on success)
  - embedding is L2-normalized (norm ~= 1.0)
  - a no-face image returns a clean error, not a crash
"""

from __future__ import annotations

import argparse
import base64
import io
import math
import sys

import requests

try:
    from PIL import Image
    import numpy as np
except Exception:  # pragma: no cover
    Image = None
    np = None

BASE_URL = "http://127.0.0.1:8000"
EMBED_DIM = 512


def _synthetic_image_bytes() -> bytes:
    """A random-noise JPEG that should contain no detectable face."""
    if Image is None or np is None:
        raise SystemExit("Pillow/numpy required to generate a synthetic image")
    arr = (np.random.rand(256, 256, 3) * 255).astype("uint8")
    buf = io.BytesIO()
    Image.fromarray(arr).save(buf, format="JPEG")
    return buf.getvalue()


def check_health() -> None:
    print(f"GET {BASE_URL}/health")
    r = requests.get(f"{BASE_URL}/health", timeout=30)
    r.raise_for_status()
    data = r.json()
    print("  ->", data)
    assert data.get("ok") is True, "health.ok should be True"
    if not data.get("ready"):
        print("  WARNING: model not ready yet:", data.get("error"))


def _validate_success(data: dict) -> None:
    emb = data.get("embedding")
    assert data.get("faceDetected") is True, "expected faceDetected=True"
    assert isinstance(emb, list), "embedding must be a list"
    assert len(emb) == EMBED_DIM, f"embedding must be {EMBED_DIM} floats, got {len(emb)}"
    assert all(isinstance(x, float) and math.isfinite(x) for x in emb), "all values must be finite floats"
    norm = math.sqrt(sum(x * x for x in emb))
    assert abs(norm - 1.0) < 1e-3, f"embedding must be L2-normalized, norm={norm:.6f}"
    print(f"  OK: 512-d, L2 norm={norm:.6f}, latencyMs={data.get('latencyMs')}")
    print(f"  quality={data.get('quality')}")


def _validate_failure(data: dict) -> None:
    assert data.get("faceDetected") is False, "expected faceDetected=False"
    assert data.get("embedding") is None, "embedding must be None on failure"
    assert data.get("error"), "failure must include an error message"
    print(f"  OK: clean failure -> {data.get('error')}")


def embed_json(image_bytes: bytes, request_id: str, expect_face: bool) -> None:
    b64 = base64.b64encode(image_bytes).decode("ascii")
    print(f"POST {BASE_URL}/embed (json, requestId={request_id})")
    r = requests.post(
        f"{BASE_URL}/embed",
        json={"imageBase64": b64, "imageMimeType": "image/jpeg", "requestId": request_id},
        timeout=120,
    )
    data = r.json()
    assert data.get("requestId") == request_id, "requestId must be echoed back"
    if expect_face:
        _validate_success(data)
    else:
        _validate_failure(data)


def embed_multipart(image_path: str, request_id: str) -> None:
    print(f"POST {BASE_URL}/embed (multipart, requestId={request_id})")
    with open(image_path, "rb") as fh:
        r = requests.post(
            f"{BASE_URL}/embed",
            files={"file": (image_path, fh, "image/jpeg")},
            data={"requestId": request_id},
            timeout=120,
        )
    data = r.json()
    assert data.get("requestId") == request_id, "requestId must be echoed back"
    _validate_success(data)


def main() -> int:
    global BASE_URL
    parser = argparse.ArgumentParser(description="Recco CV service smoke test")
    parser.add_argument("image", nargs="?", help="path to a face image")
    parser.add_argument("--multipart", action="store_true", help="use multipart upload")
    parser.add_argument("--base-url", default=BASE_URL)
    args = parser.parse_args()

    BASE_URL = args.base_url

    check_health()

    if args.image:
        if args.multipart:
            embed_multipart(args.image, "track_multipart")
        else:
            with open(args.image, "rb") as fh:
                embed_json(fh.read(), "track_json", expect_face=True)
    else:
        print("No image supplied -> testing no-face path with synthetic noise.")
        embed_json(_synthetic_image_bytes(), "track_noface", expect_face=False)

    print("\nAll assertions passed.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"\nFAILED: {exc}")
        sys.exit(1)
