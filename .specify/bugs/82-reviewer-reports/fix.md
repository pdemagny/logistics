# Bug Fix: Reviewer reports left unwritten, and one missing report cancels the batch's reformat turn

- **Slug**: 82-reviewer-reports
- **Fixed**: 2026-11-23
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

Both parts of the preferred remediation. The six report-writing agents now carry the implementer's rule (writing the report is their own job; never hand back before the Write returns; retry once, then say so), and the reviewers' "no report path" branch applies only when the request gives no path at all. In `step.sh`'s `review_boundary`, a reviewer batch whose only failures are missing new reports gets a `reformat` verdict that spawns each missing group again, fresh and in review mode, next to the usual reformat spawns of the unparsable reports. Each group gets this once, logged; a second miss, or any other failed check in the call, is the hard gate as before.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `.apm/skills/feat/scripts/step.sh` | modified | `check_report`: with `DEFER_MISS=1`, a missing new report is a reason plus `RP_MISS`, not yet a failed check. `review_boundary`: one fresh spawn per missing group when nothing else failed (no other check, no snapshot change, no reformat turn already used, group not already respawned); otherwise each miss becomes `fail_check` (hard). `reformat`: logs `- [!] <head> — report missing: <file>; fresh spawn 1 of 1` and spawns the group again (`review_respawn`); a missing report gets no `sum=`. `reformat_keys` also collects those keys (`FSK`). `open_gate` does not read the fresh-spawn line as a failed check. The group spawn was moved out of `review_batch` into `review_spawn`, and the 7e block out of `spawn_7e` into `spawn_7e_block`, so a respawn matches the batch's spawn (diff, rejected, accepted sec, cuts). |
| `.apm/agents/feat-code-reviewer.agent.md`, `feat-design-reviewer.agent.md` | modified | Implementer's rule added. The "no report path" branch is limited to a request with no `report:` key and no path, and a full report handed back in place of a given path counts as a missing report. |
| `.apm/agents/feat-specifier.agent.md`, `feat-planner.agent.md`, `feat-tasker.agent.md`, `feat-bug-assessor.agent.md` | modified | Implementer's rule added. |
| `.apm/skills/feat/references/harness.md` | modified | The `reformat` verdict can hold a fresh `mode: review` spawn of a missing group. The Reported files section describes the one-time respawn and the hard second miss. No `/feat`-only words (lint passes). |
| `docs/workflow.md` | modified | The same rule, in the hard/soft gate paragraph. |
| `tests/step/run.sh` | added tests | 7 new cases (see below). |
| `tests/step/fixtures/agents/code-reviewer/bad-7c-slip.md` | added | The issue's 7c slip (`Performance (7c):` alone, `none` on the next line). |
| `tests/step/expected/{batch-missing*,feat7e-missing,fix4-missing}.{out,log}` | added | Goldens. |

## Diff Highlights (optional)

```bash
# review_boundary: a group's missing report gets one fresh spawn, with the
# others' reformat turns, when nothing else failed
if (( ! CHK_FAIL && ! SNAPF && turn && again && slip )); then reformat "$tok"; return 0; fi
for (( i = 0; i < ${#RP_PATH[@]}; i++ )); do
  if (( RP_MISS[i] )); then fail_check "report missing: ${RP_PATH[i]##*/}"; fi
done
```

## Tests Added or Updated

- `tests/step/run.sh` "batch: 7d's report missing and 7c's slip" (`batch-missing-slip`, `batch-missing-slip-7e`): `reformat`, with a 7c reformat spawn and a fresh 7d review spawn. The next call needs `sum=` for 7a/7b and goes on to 7e.
- "batch: 7d's report missing twice: hard" (`batch-missing`, `batch-missing-twice`): the first miss gets a fresh 7d spawn; the second miss is hard `report missing: 7-7d.md`.
- "batch: 7d's report missing and a failed check: hard at once" (`batch-missing-check`): a bad `Wrote:` item in 7a keeps the batch hard.
- "batch: 7d's report missing and a file changed outside the reports" (`batch-missing-snapshot`): hard at once.
- "batch: 7e's report missing" (`feat7e-missing`): a fresh 7e spawn that keeps its `cuts:` key; after it, the gate matches `feat7-medium-gate`.
- "fix 4 medium: a group's report missing" (`fix4-missing`): the same in `/fix` 4.
- The existing "a failure and an unparsable line in the same call: hard at once" (single-agent boundary) still passes unchanged.

## Local Verification

- Commands run: `mise run lint` → pass (shellcheck, actionlint, prompt greps; the README marketplace notice it prints is informational, exit 0)
- `mise run test:step` → all cases pass
- `mise run test:apm`, `test:state`, `test:story`, `test:sizes`, `test:ship`, `test:tracker`, `test:spec-number`, `test:measure`, `test:trail`, `test:preflight`, `test:secret-scan` → all pass
- Manual checks: read the new goldens. The respawned spawn block matches the batch's original block for that group.

## Deviations from Assessment

- The fresh spawn's report path comes from `state.sh report-path` like any spawn. The missing file does not exist, so the path is the same name (`7-7d.md`), not a `-2` path; nothing is overwritten.
- A missing report that was passed again with `sum=` (checked before, deleted since) is still a failed check: only a new report gets the respawn.
- The respawn allowance is read from the Log's trailing entries, the same way the reformat turn's is. A Log line the coordinator writes between the respawn and its boundary call that `reformat_keys` does not skip (for example a `- [!] tracker:` line) would reset both allowances. This is today's behaviour for the reformat turn, unchanged here.

## Follow-ups

- `reformat_keys` could skip the coordinator's `- [!] tracker:` lines, so a board-move line between a spawn and its boundary never renews a reformat or respawn allowance.
