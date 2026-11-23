# Bug Fix: Review gate goes hard when the coordinator logs to the state file during a review

- **Slug**: 76-review-snapshot-state
- **Fixed**: 2026-11-23
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

The reviewers' snapshot (`state.sh snapshot` / `unchanged`) now leaves the run's state file out of its manifest, like `reports/`, so a coordinator Log line (a board move, or its `- [!]` failure line) written while the reviewers run no longer hardens the `/feat` phase 7 or `/fix` phase 4 gate. Per the user's answer, every change to the state file is ignored, not only appended Log lines.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `.apm/skills/feat/scripts/state.sh` | modified | `snap_setup` sets `SX`, the state file relative to the worktree top; `manifest()` skips it; header and comments say so |
| `tests/state/run.sh` | updated test | a `state.sh log` between `snapshot` and `unchanged` now gives `unchanged`; a `set` on the state file plus a new file in the same window lists only the new file |
| `tests/step/run.sh` | added tests | `/feat` 7 medium and `/fix` 4 small: a state-file Log line between the review spawn and its boundary gives the same output and Log as without it (reuses the `feat7-medium-gate` and `fix4-soft-zero` goldens) |
| `docs/workflow.md` | modified | the snapshot sentence says the state file is left out |
| `docs/design.md` | modified | the read-only reviewers bullet says the same |

## Diff Highlights (optional)

```bash
SX=${EX%reports/}${1##*/}
...
[[ -n $p && $p != "$EX"* && $p != "$SX" ]] || continue
```

`EX` is computed from the state file dir's physical path relative to `TOP`, so `SX` matches the `git status` path whether the state file is tracked or untracked.

## Tests Added or Updated

- `tests/state/run.sh` "unchanged: edit to a modified file, new file, deleted file" — a state-file log is `unchanged`; a state-file `set` alongside another new file reports only that file.
- `tests/step/run.sh` "feat 7 medium: a state-file log line between the 7e spawn and its boundary stays soft" — no `files changed outside the reports` reason; output and Log equal `feat7-medium-gate`.
- `tests/step/run.sh` "fix 4 small: a state-file log line between the spawn and its boundary stays soft" — `soft`, phase 5; output and Log equal `fix4-soft-zero`.

## Local Verification

- Commands run: `mise run test:state` → all state tests passed; `mise run test:step` → all cases pass; `mise run lint` → exit 0 (shellcheck clean).
- Manual checks: `UPDATE=1 bash tests/step/run.sh` rewrote no existing golden; the two new cases' generated goldens were byte-identical to `feat7-medium-gate` and `fix4-soft-zero`, so the cases point at those and the duplicates were removed.

## Deviations from Assessment

None. `docs/design.md` was updated too (the assessment listed it as optional).

## Follow-ups

- A reviewer that wrote the state file is no longer caught by the snapshot (the trade the report asked for); reviewers remain instructed to write only their report.
