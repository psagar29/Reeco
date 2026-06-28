# Agent Brief - Person A

You are Person A: Computer Vision Service / InsightFace.

Your branch:

```txt
person-a-cv-service
```

Your primary plan:

```txt
docs/workstreams/01_PERSON_A_CV_SERVICE_INSIGHTFACE.md
```

Read these first:

1. `docs/workstreams/01_PERSON_A_CV_SERVICE_INSIGHTFACE.md`
2. `docs/API_CONTRACTS.md`
3. `docs/OPEN_SOURCE_REPOS.md`

Your mission:

Build the Python FastAPI service that receives a face image and returns a normalized 512-dimensional InsightFace embedding.

You own:

- `cv-service/`
- FastAPI server
- InsightFace model setup
- `GET /health`
- `POST /embed`
- test script for embedding one image

Do not build iOS UI, Convex matching, OpenAI voice parsing, or product polish. Your job is to make the face embedding service reliable enough for Person B to call.

