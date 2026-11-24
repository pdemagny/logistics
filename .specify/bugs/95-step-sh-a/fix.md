# Bug Fix: step.sh wedges on a boundary call made before its report exists

- **Slug**: 95-step-sh-a
- **Fixed**: 2026-11-24
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

A one-report boundary call whose report is absent or empty is now refused (`refused: report missing: <file>: write it, then call again`) with nothing logged or recorded, so the same call decides once the report is written. A record left by the old behaviour re-prints its hard gate instead of dying, and `resume` prints an unanswered gate again instead of restarting the phase.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `.apm/skills/feat/scripts/step.sh` | modified | A: `do_boundary` refuses an absent or empty report (the `RENUM` lookup kept) before `phase_head`/`check_report`; B: `accept` re-prints a recorded `hard:` decision whose sums hold a missing report when the words match; C: `do_resume` calls `open_gate` and, when a gate is open, the new `show_gate` prints `hard:`, the reasons from its Log line and its `answer call:` (the record's when it carries this gate's token, else the token alone); header comment updated |
| `.apm/skills/feat/references/harness.md` | modified | Slip fallback: a `refused: report missing:` block is a slip (remake the call); the coordinator's own call refused that way is handled as an error; Read the output as data: `refused:` at a boundary points to the slip fallback; Resume: an unanswered gate is printed again |
| `tests/step/run.sh` | modified | new cases for A (feat 2, fix 2, feat 7-fixes), B and C; the `feat 2: report missing` case now checks the refusal, that no record is written, and the decision once the report exists |
| `tests/step/expected/feat2-missing.*`, `check-empty.*` | updated golden | now the refusal, state file unchanged |
| `tests/step/expected/fix2-missing.*`, `fixes-missing.*`, `missing-record-reprint.*`, `resume-open-gate.*`, `resume-open-gate-no-record.*` | added golden | the new cases |

## Diff Highlights (optional)

```bash
  f=${A_REPORTS[0]}
  if [[ ! -e $f && -n $RENUM && ${RENUM##*/} == "${f##*/}" ]]; then f=$RENUM; fi
  if [[ ! -s $f ]]; then refuse "report missing: ${f##*/}: write it, then call again"; return 0; fi
```

## Tests Added or Updated

- `tests/step/run.sh` "feat 2: report missing: refused, then decided once written" — refused, no Log line, no `last-step.md`; the report written, the same call gives `feat2-soft`'s output.
- `tests/step/run.sh` "fix 2: report missing: refused, then decided once written" — the same on a `/fix` boundary (`fix2-missing`, then `fix2-soft`).
- `tests/step/run.sh` merge-rule-2 case: `7-fixes` with no report → `fixes-missing` (refused), then the report written → `fixes-pass` unchanged (the issue's reproduction).
- `tests/step/run.sh` "report check: an empty report" — a zero-byte report is refused too (the user's answer).
- `tests/step/run.sh` "a hard report-missing record (before the refusal)…" — B: same words, report now present → the hard gate re-printed, nothing written (no `no boundary is open`).
- `tests/step/run.sh` "resume: an unanswered hard gate is shown, its answer call the record's" — C: the gate re-printed with the recorded answer call, and that answer call then answered as `feat2-markers-approved`.
- `tests/step/run.sh` "resume: an unanswered hard gate with no record: the token alone" — C on the issue's Log line (`7 review fixes [hard] — report missing`): no reviewer spawn.

## Local Verification

- Commands run: `mise run test:step` → all cases pass; `mise run lint` → exit 0; `mise run test:state` → all state tests passed.
- Manual checks: `UPDATE=1` regeneration changed no existing golden other than `feat2-missing` and `check-empty` (existing resume goldens unchanged).

## Deviations from Assessment

- B uses the assessment's minimal option: matching words re-print a recorded `hard:` decision whose sums hold a missing report, rather than deciding again; deciding again would leave the old hard gate unanswered in the Log. The re-printed gate takes `back to` or `stop` (a failed report check).
- `owed_fixes` is unchanged: with C, resume shows the open `7 review fixes [hard] — report missing` gate before `next_step` runs, and that gate's only valid answers (`back to`, `stop`) leave phase 7, so `owed_fixes` never reads that line as fixes done while it matters.
- Reviewer batches, moves and the ship-conflict boundary keep their own handling of a missing report (batches defer it, a move's missing report is the repair check); only one-report boundaries are refused.

## Follow-ups

- Agent last-step wording is unchanged: agents already call after writing their report; a premature call now lands on the coordinator's slip fallback.
