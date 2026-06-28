# Contributing to Recco

Thanks for working on Recco. This is a monorepo with three independent
components; you usually only touch one at a time.

## Layout

| Path | Stack | Dev command |
|------|-------|-------------|
| `app/ios/Recco` | SwiftUI | open in Xcode, ⌘R |
| `backend` | Convex/TS | `npm run dev` |
| `cv-service` | FastAPI/Python | `uvicorn main:app --port 8000` |

Start with [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## The contract is shared

The boundary types live in [`docs/API_CONTRACTS.md`](docs/API_CONTRACTS.md) and
are mirrored in `app/ios/Recco/Recco/Models/` (Swift) and
`backend/convex/lib/types.ts` (TypeScript). **If you change a shape, update all
three** and call it out in your PR — it affects every component.

## Before you open a PR

Run the checks for whatever you touched:

```bash
# backend
cd backend && npm run typecheck && npm run test

# cv-service
cd cv-service && .venv/bin/python -m uvicorn main:app --port 8000 &
.venv/bin/python test_embed.py path/to/face.jpg

# iOS
xcodebuild -project app/ios/Recco/Recco.xcodeproj -scheme Recco \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Conventions

- **Commits:** short, imperative subject. Conventional-commit prefixes
  (`feat:`, `fix:`, `docs:`, `test:`, `chore:`) are welcome.
- **Branches:** `feat/...`, `fix/...`; open a PR into `main`.
- **Style:** `.editorconfig` is enforced (2-space default; 4 for Python/Swift).
- **No secrets in git.** API keys go in `backend/.env.local` (gitignored) and the
  CV service / iOS read config from the environment.

## Demo-reliability rule

Every external dependency must degrade gracefully. New features should keep
`mockAll` working with no backend, no network, and no keys.
