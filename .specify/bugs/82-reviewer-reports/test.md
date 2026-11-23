# Bug Verification: Reviewer reports left unwritten, and one missing report cancels the batch's reformat turn

- **Slug**: 82-reviewer-reports
- **Tested**: 2026-11-23
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

Second cycle, after the code-review fixes (B2 test case `batch-missing-changed`, `diff_base` helper shared by `review_respawn` and `spawn_7e_block`). The assessment's reproduction (7c slip plus a missing 7d report in a `/feat` 7 medium batch) still no longer reproduces: `step.sh` answers `reformat` with a 7c reformat spawn plus a fresh 7d review spawn, where the pre-fix `step.sh` (HEAD) gave `hard:` with `report missing: 7-7d.md` and no reformat. The step suite and every other `mise run` check pass. The agent half (a model actually writing its report) is not testable offline.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix), pre-fix control | Scratch script in the system temp dir: the setup and helpers of `tests/step/run.sh` (header cut before its cases), then a `/feat` 7 medium batch with 7a, 7b, the 7c slip fixture (`Performance (7c):` then `none`) and no 7d report; run against HEAD's `step.sh` (control) and the worktree's | pass | HEAD: `hard:` with `report missing: 7-7d.md` and `unparsable: 7-7c.md`, no spawn (symptom reproduced). Worktree: `reformat`, a 7c `mode: reformat` spawn, a fresh 7d `mode: review` spawn with its diff keys (the shared `diff_base` path), and a `boundary:` call with `sum=` for 7a and 7b only |
| Log of the re-spawn | same scratch run, state file tail | pass | `- [!] 7 Code review — unparsable: 7-7c.md: …; reformat 1 of 1` then `- [!] 7 Code review — report missing: 7-7d.md; fresh spawn 1 of 1` |
| New / updated tests | `mise run test:step` | pass | `step: all cases pass`; includes the 7 earlier cases and the new `batch-missing-changed` |
| B2 case | read `tests/step/expected/batch-missing-changed.{out,log}` | pass | a 7a-7d report edited plus a missing 7e report: `hard:` with `report missing: 7-7e.md` and `report changed since checked: 7-7a.md`, no respawn |
| Agent rule present | `grep` in `.apm/agents/feat-*.agent.md` | pass | code-reviewer, design-reviewer, specifier, planner, tasker, bug-assessor each carry the write-your-own-report rule (retry once, then say so); shipper, brief-reviewer and implementer untouched |
| Regression suite | `mise run test:apm`, `test:state`, `test:story`, `test:sizes`, `test:ship`, `test:tracker`, `test:spec-number`, `test:measure`, `test:trail`, `test:preflight`, `test:secret-scan` | pass | all exit 0 |
| Lint / type-check | `mise run lint` | pass | exit 0 (shellcheck, actionlint, prompt greps, harness `/feat`-word grep) |

## Output Excerpts

```
HEAD step.sh, 7d missing:
hard:
- report missing: 7-7d.md
- unparsable: 7-7c.md: line 2 (Performance (7c)) — not a "- " item at column 0

Worktree step.sh, 7d missing:
reformat
spawn: feat-code-reviewer   row: 7c   mode: reformat
spawn: feat-code-reviewer   row: 7d   mode: review   report: .../7-7d.md
log: - [!] 7 Code review — report missing: 7-7d.md; fresh spawn 1 of 1

batch-missing-changed.out:
hard:
- report missing: 7-7e.md
- report changed since checked: 7-7a.md

mise run test:step: step: all cases pass
```

## Residual Risks

- The agent half (a reviewer writing its report with Write instead of handing it back) is model behaviour; only the prompt text was checked, not a live run.
- As fix.md notes, a Log line between a respawn and its boundary call that `reformat_keys` does not skip (for example `- [!] tracker:`) renews the reformat and respawn allowances; unchanged behaviour for the reformat turn.
- The `/feat` and `/fix` coordinators' reading of a `reformat` verdict that holds a fresh `mode: review` spawn was checked in `harness.md` and the goldens only, not in a live run.

## Recommendation

Close the bug: the reproduction is fixed after the review fixes too (HEAD control reproduces it, the worktree gives the per-group respawn plus the reformat turn, a changed report with a missing one stays hard), and all test and lint tasks pass. Watch the next `/feat` or `/fix` reviewer batch for a live confirmation that the agents write their own reports.
