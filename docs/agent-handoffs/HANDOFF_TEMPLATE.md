<!--
Copy this file to docs/agent-handoffs/<PERSON_X>_<LANE>.md and fill it in before
requesting a merge. One handoff per branch. Keep it honest: mark anything not
actually run as "not verified". See docs/INTEGRATION_CHECKLIST.md for how this is
used during merge.
-->

# Handoff — <Lane name>

## Branch
`agent/person-x-...`  →  base `main`

## Owner
<name / GitHub handle>

## Summary
<2–4 sentences: what this branch delivers and why. What's done vs. deliberately
left for a follow-up.>

## Files changed
<Group by area. Note new vs. modified. Call out anything outside your lane.>

- `path/to/file` — <what changed>
- ...

## Commands run (with results)
<Paste the exact commands and their outcome. "Passed/failed", not "should pass".>

```bash
# example
cd backend && npm run verify     # typecheck 0, 49 tests pass, smoke exit 0
```

| Command | Result |
|---------|--------|
| `...` | ✅ / ❌ <evidence> |

## Manual tests
<What you exercised by hand (device/simulator/curl). What you observed.>

- [ ] <test> — <result>

## Known issues
<Bugs, rough edges, flaky bits, anything a reviewer should know. Be candid.>

- <issue> — <severity / workaround>

## Env vars added / changed
<Any new env var, its default, and whether it's optional. Did you update
`backend/.env.local.example` and the relevant README?>

| Variable | Default | Required? | Where read |
|----------|---------|-----------|------------|
| `...` | `...` | optional | backend / iOS / cv-service |

## Merge risks
<Conflict hotspots you touched, contract shapes you changed, ordering
dependencies on other branches. Reference docs/INTEGRATION_CHECKLIST.md.>

- <risk> — <mitigation>

## Contract impact
- [ ] No boundary types changed, **or**
- [ ] Changed `<Type>` — updated `docs/API_CONTRACTS.md` + Swift DTO + TS type together.

## Screenshots / videos (if any)
<Links or attached file names. Especially useful for iOS UI behavior agents
can't verify.>

## Sign-off
- [ ] Pre-merge checks for this lane (docs/INTEGRATION_CHECKLIST.md) pass.
- [ ] No secrets committed; no stray build artifacts.
- [ ] `python scripts/check_markdown_links.py` → OK.
