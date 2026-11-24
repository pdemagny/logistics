# Bug Verification: step.sh wedges on a boundary call made before its report exists

- **Slug**: 95-step-sh-a
- **Tested**: 2026-11-24
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The three symptoms no longer occur on the worktree's `step.sh`: a one-report boundary call made before its report exists (absent or empty) is refused with nothing logged or recorded, the same call decides once the report is written, and `resume` prints an unanswered hard gate again instead of restarting the phase. The same scratch reproduction run against the main checkout's unfixed `step.sh` shows all three symptoms (negative control). One residual edge on state files written by the old script is listed under Residual Risks. The project's `test:step`, `lint` and `test:state` pass.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | Scratch script under the system temp dir reusing `tests/step/run.sh`'s helpers, against the worktree `step.sh`: phase 7 batch call, premature `7-fixes` call, retry after writing the report, `resume` | pass | premature call: `refused: report missing: 7-fixes.md: write it, then call again`, exit 0; `last-step.md` and the state file byte-identical (cksum) before and after; repeated and empty-report calls refused alike; call after the report is written gives `soft` with the shipper spawn; `resume` then gives `resume: done (shipping)` |
| Negative control | The same steps against the main checkout's `step.sh` (no fix) | pass (symptoms reproduce there) | premature call → `hard:` `- report missing: 7-fixes.md`; retry → exit 1 `step: error: no boundary is open (hard:)`; `resume` → `soft`, `resume: 7 Code review`, gate dropped |
| /fix single-report boundaries | Scratch: `fix 2` and `fix 4-fixes` with no report, then (fix 2) with the report | pass | both refused with the state file unchanged; `fix 2` once written decides `soft` and spawns the test agent |
| Resume shows an open hard gate (C) | Scratch: state with Log `- [x] 2 Specify [hard] — report missing: 2-specify.md` (no record, then with a record), `resume` | pass | `hard:`, `- report missing: 2-specify.md`, `resume: 2 Specify`, `answer call:` (token alone without a record, the record's call with one); no spawn |
| Re-print of an old hard report-missing record (B) | Scratch: a `last-step.md` holding the hard decision (`sums:	2-specify.md:`), report written, the same call, no `resume` in between | pass | the hard gate re-printed, exit 0, no `no boundary is open` |
| Re-print after an interposed `resume` | Same as B with a `resume` between the record and the call | fail (edge) | `resume` rewrites `last-step.md` with its own output (no `call:` line), so the call dies `no boundary is open (hard:)`; only reachable from a state file written by the old script; see Residual Risks |
| Answered gate not re-shown; no-gate resume unchanged | Scratch: feat phase 2 fresh `resume`; `2` call with markers answered `approved`, then `resume` | pass | fresh resume spawns the specifier as before; after the answer `resume` shows the amend spawn, not the gate |
| Reviewer batch with one report absent keeps its own handling | Scratch: phase 7 batch call with `7-7c+7d+7e.md` absent | pass | `reformat` plus a reviewer spawn for that row, not `refused:` |
| New / updated tests | `mise run test:step` | pass | `step: all cases pass` (includes the new fixes-missing, fix2-missing, feat2-missing, missing-record-reprint, resume-open-gate, resume-open-gate-no-record cases) |
| Regression suite | `mise run test:state` | pass | `all state tests passed` |
| Lint | `mise run lint` | pass | exit 0 |

## Output Excerpts

```
premature call (worktree step.sh):   refused: report missing: 7-fixes.md: write it, then call again
premature call (unfixed step.sh):    hard: / - report missing: 7-fixes.md
retry after the report (unfixed):    step: error: no boundary is open (hard:)
resume with an open hard gate (fix): hard: / - report missing: 2-specify.md / resume: 2 Specify / phase2-mode: hard / answer call:	2
```

## Residual Risks

- On a state file already holding a hard `report missing` gate from the old script, an interposed `resume` replaces `last-step.md` with a record that has no `call:` line, so a plain retry of the boundary call afterwards still dies `no boundary is open (hard:)`. `resume` now prints the gate with its `answer call:` (`back to` or `stop`), which is the way forward, and a retry with no `resume` in between re-prints it. No new run can reach this state through a one-report boundary.
- Reviewer batches, moves and the ship-conflict boundary still record a hard gate for a missing report (fix.md deviation 3, accepted at the gate); the issue's wedge on them is not addressed here.
- Agents' last-step wording is unchanged: a premature agent call now ends in `refused:`, which the coordinator handles through harness.md's slip fallback. Not exercised end to end with a live agent.

## Recommendation

Close the bug: the premature call, the retry and the resume symptoms are gone, with a negative control showing they reproduce without the fix and the project's checks passing. Consider a follow-up for `resume` preserving the `call:`/`sums:` lines of an open gate's record (the residual edge above).
