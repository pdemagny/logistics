# Bug Verification: step.sh wedges on a boundary call made before its report exists

- **Slug**: 95-step-sh-a
- **Tested**: 2026-11-24
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

After the review fix (B1, `harness.md` only; `step.sh` and `tests/step` unchanged since the first cycle), the three symptoms still do not occur on the worktree's `step.sh`: a one-report boundary call made before its report exists (absent or empty) is refused with nothing logged or recorded, the same call decides once the report is written, and `resume` prints an unanswered hard gate again. The new harness rule (a refused own call: one fresh re-spawn from the held spawn block, then the error gate whose `retry` is that spawn) reads consistently with step.sh's `refused: report missing: <file>: write it, then call again` line. `test:step`, `lint` and `test:state` pass.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | Scratch script under the system temp dir reusing `tests/step/run.sh`'s helpers against the worktree `step.sh`: phase 7 batch call, premature `7-fixes` call (absent, repeated, empty report), same call after the report is written, `resume` | pass | premature calls: `refused: report missing: 7-fixes.md: write it, then call again`, exit 0, state file line count unchanged; once written the call decides `soft` with the shipper spawn; `resume` then gives `resume: done (shipping)` |
| /fix single-report boundaries | Scratch: `fix 2` and `fix 4-fixes` with no report, then `fix 2` with the report | pass | both refused, state file unchanged (cksum); `fix 2` once written decides `soft` and spawns the test agent |
| Resume shows an open hard gate | Scratch: state with Log `- [x] 2 Specify [hard] — report missing: 2-specify.md`, `resume`, with and without a `last-step.md` record | pass | `hard:`, `- report missing: 2-specify.md`, `resume: 2 Specify`, `answer call:` (token alone, or the record's call); no spawn |
| Re-print of an old hard report-missing record | Scratch: `last-step.md` holding the hard decision, report written, same call, no `resume` between; then answered `stop` | pass | gate re-printed, exit 0, no `no boundary is open`; the `stop` answer closes the run |
| Re-print after an interposed `resume` | Same with a `resume` between record and call | fail (edge) | known residual from the first cycle (see Residual Risks); unchanged by this cycle |
| Answered gate not re-shown; no-gate resume unchanged | Scratch: fresh feat phase 2 `resume`; `2` call with markers answered `approved`, then `resume` | pass | fresh resume spawns the specifier; after the answer `resume` shows the amend spawn, not the gate |
| Reviewer batch with one report absent keeps its own handling | Scratch: phase 7 batch call with `7-7c+7d+7e.md` absent | pass | `reformat` plus a reviewer spawn, not `refused:` |
| Harness rule vs step.sh output | Read `harness.md` Slip fallback, Read the output as data (`refused:`), Errors against `step.sh` line 4297 and `tests/step/expected/fixes-missing.out` | pass | the harness matches on `refused: report missing:`, which is the line step.sh prints verbatim; exit 0, nothing logged, so "nothing to log" holds; the re-spawn is bounded to one, then the error gate (retry = fresh spawn, stop). The reviewer-batch `report missing; fresh spawn 1 of 1` handling in step.sh is separate and untouched. `lint` greps for `/feat`-only words in `harness.md` and passes |
| step.sh and tests unchanged since cycle 1 | File mtimes (`step.sh` 10:46, `tests/step/run.sh` 10:45, before the first test report at 11:03) | pass | only `harness.md` (11:12) changed afterwards, so cycle-1 step.sh evidence still holds and was re-run above |
| New / updated tests | `mise run test:step` | pass | `step: all cases pass` |
| Regression suite | `mise run test:state` | pass | `all state tests passed` |
| Lint | `mise run lint` | pass | exit 0 |

## Output Excerpts

```
premature call (worktree step.sh):  refused: report missing: 7-fixes.md: write it, then call again
fix 4-fixes premature:              refused: report missing: 4-fixes.md: write it, then call again
B, no interposed resume:            hard: / - report missing: 2-specify.md / answer call:	2	<report>
```

## Residual Risks

- Carried from the first cycle: on a state file already holding a hard `report missing` gate written by the old script, an interposed `resume` replaces `last-step.md` with a record that has no `call:` line, so a plain retry of the boundary call afterwards still dies `no boundary is open (hard:)`. `resume` prints the gate with its `answer call:`, which is the way forward. Left by the user (B2); not re-raised.
- Reviewer batches, moves and the ship-conflict boundary still record a hard gate for a missing report (fix.md deviation 3, accepted).
- The harness's re-spawn and error-gate path for a refused own call is prose for the coordinator; it was read against step.sh's output but not exercised end to end with live agents.
- Wording nit, not a defect: `refused:` exits 0 while *Errors* is written for `step: error:` (exit 1) lines; the Slip fallback names the error gate explicitly, so the handling is unambiguous.

## Recommendation

Close the bug: the premature call, the retry and the resume symptoms stay gone against the worktree `step.sh`, the review fix's harness rule agrees with step.sh's `refused:` output, and the project's checks pass.
