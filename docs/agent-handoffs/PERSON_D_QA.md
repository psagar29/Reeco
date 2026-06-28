# Handoff — Person D (Integration QA, Docs, Demo Readiness)

## Branch
`agent/person-d-integration-docs-qa`  →  base `main`

## Owner
Person D — integration QA / demo-readiness (docs-only lane; no app/backend/CV behavior changed).

## Summary
Made the four-agent project **mergeable, runnable, and demoable** without touching
feature code. Added the demo runbook, integration/merge checklist, QA checklist,
and a branch-handoff template; fixed stale docs links left over from the
`docs/ → docs/planning/` move; made the root README status honest about what is
and isn't wired; added a standard-library Markdown link checker; and ran the
required backend + CV verification on Windows.

No Swift, backend logic, CV model, or generated files were modified.

## Files changed

**New docs**
- `docs/DEMO_RUNBOOK.md` — demo-day runbook (objective, hardware, accounts, env
  vars, happy-path setup, 2-min script, recovery plan).
- `docs/INTEGRATION_CHECKLIST.md` — merge order, per-branch pre-merge checks,
  conflict hotspots, contract checks, post-merge end-to-end checks.
- `docs/QA_CHECKLIST.md` — backend / CV / iOS / product checks with **evidence**
  of what was actually run, plus `npm audit` known status.
- `docs/agent-handoffs/HANDOFF_TEMPLATE.md` — fill-in template for every branch.
- `docs/agent-handoffs/PERSON_D_QA.md` — this file.

**New tooling**
- `scripts/check_markdown_links.py` — stdlib-only relative-link checker (ignores
  external URLs + anchors, skips code fences). Advisory, not a CI gate.

**Edited (docs only)**
- `README.md` — honest Status section; added Demo Runbook nav link; Windows notes
  for local Convex + CV venv + JSON-arg quoting.
- `backend/README.md` — fixed the stale Person B spec link.
- `docs/planning/workstreams/0{1,2,3,4}_*.md` — repointed `docs/workstreams/...`
  and `docs/OPEN_SOURCE_REPOS.md` references to `docs/planning/...`.

## Commands run (with results)

| Command | Result |
|---------|--------|
| `cd backend && npm ci` | ✅ installed (npm 11 `allow-scripts` advisories only) |
| `npm run typecheck` | ✅ **exit 0** |
| `npm run test` | ✅ **49/49 passed** (filter 11, opener 7, similarity 17, voice 14) |
| `npm run smoke` | ✅ **exit 0**, contract-shaped JSON for every function |
| `npm audit` | ⚠️ 5 advisories (3 moderate / 1 high / 1 critical) — **all dev-only** (vitest→vite/vite-node/esbuild). Not fixed (would force a breaking `vitest` major). |
| `python -m py_compile cv-service/main.py cv-service/test_embed.py` | ✅ **exit 0** |
| `python scripts/check_markdown_links.py` | ✅ **OK** — 16 files, 0 broken relative links |

Environment: Windows 11, PowerShell + Git Bash, Node 24, Python 3.14 (for
`py_compile` only). **No Xcode** — iOS build not run here (owner-verified).

## Manual tests
- [x] Re-ran the link checker before/after fixes — went from 1 broken link to 0.
- [x] Grep swept the repo for `docs/workstreams` / `docs/OPEN_SOURCE_REPOS` /
      `docs/FOUR_PERSON_HANDOFF` — no stale references remain (outside
      `AGENT_PROMPT.md`, which intentionally lists them as search patterns).

## Broken links fixed
1. `backend/README.md` → `../docs/workstreams/02_...` ⟶ `../docs/planning/workstreams/02_...` (caught by the link checker).
2. `docs/planning/workstreams/01_*` → `docs/OPEN_SOURCE_REPOS.md` ⟶ `docs/planning/OPEN_SOURCE_REPOS.md`.
3. `docs/planning/workstreams/02_*` → `docs/workstreams/01_*` ⟶ `docs/planning/workstreams/01_*`.
4. `docs/planning/workstreams/03_*` → `docs/workstreams/02_*` and `04_*` ⟶ `docs/planning/workstreams/...`.
5. `docs/planning/workstreams/04_*` → `docs/workstreams/03_*` ⟶ `docs/planning/workstreams/03_*`.

(Items 2–5 are bare inline-code paths in prose, not `[](…)` links, so the checker
doesn't flag them — they were found by grep and fixed for accuracy.)

## Known issues / honest gaps
- **iOS live mode is not wired on `main`.** `app/ios/Recco/Recco/State/Backend/ConvexBackend.swift`
  delegates every call to `MockBackend` (`// TODO(convex)`), so `mockCV`/`live`
  currently behave like mock. Real wiring is Person A's branch.
- **Full iOS Xcode build is unverified by agents** (no Xcode). `docs/planning/PROGRESS_LOG.md`
  shows pure logic (19/19) + non-UI type-check passed; the `xcodebuild`/Simulator
  run must be confirmed by the iOS owner.
- **CV `/embed` not run here** — only `py_compile`. InsightFace needs Python
  3.10–3.11; this machine has 3.14, so a real embedding run is owner-verified.
- **Minor doc drift to watch:** the root README and `cv-service/README.md` quote
  different warm latencies (~90 ms vs ~380 ms). I removed the specific number
  from the README status rather than assert an unmeasured figure; the lanes
  should reconcile the real number post-merge.
- **`npm audit`** advisories remain (dev-only) — intentionally not auto-fixed.

## Env vars touched
None added. Documented existing ones across the runbook/checklists:
`DEMO_MODE`, `CONVEX_URL`, `RECCO_API_BASE_URL` (planned HTTP bridge),
`CV_SERVICE_URL`, `OPENAI_API_KEY`, `DEEPGRAM_API_KEY`,
`FACE_STRONG_MATCH_SCORE`, `FACE_TENTATIVE_MATCH_SCORE`.

## Merge risks predicted
- **README.md / sub-READMEs** are edited by every lane → conflicts. Keep one
  honest status block; union the quick-start rows. See
  [INTEGRATION_CHECKLIST](../INTEGRATION_CHECKLIST.md#conflict-hotspots).
- **`docs/API_CONTRACTS.md`** — if Person C's HTTP bridge or Person A's client
  nudges a shape, reconcile the contract + both DTO/type mirrors **together**.
- **`backend/.env.local.example`** — Person C may add HTTP-bridge vars
  (`RECCO_API_BASE_URL` / port); take the union, keep keys optional.
- **iOS `ConvexBackend.swift`** — Person A replacing the `TODO(convex)` bodies is
  the highest-value, highest-risk change; gate it on Person C + B being merged.

## Recommended merge order
1. **Person C** — backend HTTP bridge (defines the surface).
2. **Person B** — CV / enrollment workflow (real embeddings).
3. **Person A** — iOS live client / overlay (wires it together).
4. **Person D** — docs / QA (reflect final reality).

Run the per-branch pre-merge checks **after each** merge, then the post-merge
end-to-end checklist. Details in [INTEGRATION_CHECKLIST](../INTEGRATION_CHECKLIST.md).

## Contract impact
- [x] No boundary types changed (docs-only lane).
