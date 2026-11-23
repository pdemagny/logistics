# Bug Fix: Agent report formats invite parse slips, and a missing implementer report forces back to 6

- **Slug**: 74-implementer-report-slips
- **Fixed**: 2026-11-23
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

The agents' report format blocks no longer show the shapes step.sh refuses (`<Key>: none` directly above an item template, `Files changed: <count>`, `Size trigger: none | … — <what>`), the implementer is told plainly that writing its report file is its own job, and step.sh's unparsable reason now says, in fixed words, what is wrong with the named line, so a reformat spawn knows what to fix. The parser stays fail-closed.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `.apm/skills/feat/scripts/step.sh` | modified | `pbad` takes a fourth argument, `P_WHY` (fixed words, never the line's text); every line-level refusal sets one; `unparsable_reason` appends ` — <why>` to `<file>: line <n> (<Key>)`. The "missing field" form is unchanged. No parse rule changed. |
| `.apm/agents/feat-implementer.agent.md` | modified | Format block: list headers alone above their item template (`Tasks not done:`, `Checks:`, `Not verified:`, `Deviations`, `Resolved alone`, `Decided`, `Needs decision`); `Files changed: <integer>` with "a bare integer, nothing after it (count them; no `+`, no note)"; the prose says `<Key>: none` is the whole field, never both. Report-file rule: writing the report is the implementer's job, never the orchestrator's; never hand back before the Write returned, never ask anyone to write it; on a failed Write, retry once then quote the error on the digest's `Design problems:` line. Reformat mode names the new `— <what is wrong>` suffix. |
| `.apm/agents/feat-planner.agent.md` | modified | `New dependencies or services:` and `Assumptions:` headers alone above their items; `Size trigger: none \| <kind> — <what>` and prose "`none` alone, nothing after it"; list-field rule as above; reformat suffix. |
| `.apm/agents/feat-specifier.agent.md` | modified | `Open markers: <n>` above its item, prose "`none` alone when no marker is left … never `none` above an item"; reformat suffix. |
| `.apm/agents/feat-tasker.agent.md` | modified | `Open findings:` header alone above its item; prose for `none` and a bare-integer `Total tasks`; reformat suffix. |
| `.apm/agents/feat-shipper.agent.md` | modified | `Conflicts:`, `Commits:`, `Not verified:` headers alone; list-field rule; reformat suffix. |
| `.apm/agents/feat-bug-assessor.agent.md` | modified | `Would run:` (both modes), `Open questions:`, `Not verified items:` headers alone; list-field rule; reformat suffix. |
| `.apm/agents/feat-code-reviewer.agent.md` | modified | Prose: a section with items has its header alone, never `none` above an item; reformat suffix. Block already had headers alone. |
| `.apm/agents/feat-design-reviewer.agent.md` | modified | Same as the code reviewer. |
| `.apm/agents/feat-brief-reviewer.agent.md` | modified | Prose: `Findings: none` when empty, never `none` above an item (its block already showed the header alone; step.sh does not parse it). |
| `docs/workflow.md` | modified | The reformat turn is told the line, its field and what is wrong in fixed words, never the line's text. |
| `tests/step/run.sh` | modified | `reformat_on` accepts the ` — <why>` suffix; new `reformat_why` helper; three new cases; the rebase-mode parser literal now expects `— a value outside its format`. |
| `tests/step/fixtures/agents/implementer/bad-checks-none.md` | added | `Checks: none` above `- mise run lint → pass`. |
| `tests/step/fixtures/agents/implementer/bad-files-plus.md` | added | `Files changed: 80+ (not recounted)`. |
| `tests/step/fixtures/agents/planner/bad-trigger-note.md` | added | `Size trigger: none — no service, no new permission`. |
| `tests/step/expected/*` | modified / added | 40 goldens gain the reason suffix (reviewed one by one); 6 new goldens for the new cases. |

## Diff Highlights (optional)

```bash
none*) pbad "$n" "${PK[CUR]}" "$line" 'an item under none (write the header alone)'; break ;;
n/a | pass) pbad "$n" "${PK[CUR]}" "$line" "an item under ${PV[CUR]} (write the header alone)"; break ;;
...
UR="$P_FILE: line $P_LINE ($P_KEY)"
if [[ -n $P_WHY ]]; then UR+=" — $P_WHY"; fi
```

Reasons used: `an item under none|n/a|pass (write the header alone)`, `not a bare count or none`, `the count differs from its items`, `items under none`, `items under pass`, `violations with no item`, `a value outside its set`, `an empty field (write none)`, `the field written twice`, `text after a list header`, `not a "- " item at column 0`, `a value outside its format`, `an item outside its format`. None contains `; ` or `: `, so the Log's `; reformat 1 of 1` and `reformat_keys`' `<file>: ` cut still read.

## Tests Added or Updated

- `tests/step/run.sh` "format: implementer bad-checks-none" — `Checks: none` above an item → reformat, reason `an item under none (write the header alone)` on stdout and in the Log.
- `tests/step/run.sh` "format: implementer bad-files-plus" — `Files changed: 80+ (not recounted)` → reformat, reason `not a bare count or none`.
- `tests/step/run.sh` "format: planner Size trigger none with a note" — reformat, reason `a value outside its format`.
- Existing reformat/hard cases: goldens updated to the suffixed reason; `reformat_on` still checks that the line's text never reaches the Log.

## Local Verification

- Commands run: `bash tests/step/run.sh` (= `mise run test:step`) → `step: all cases pass`; `mise run lint` → pass; `mise run test:apm`, `test:ship`, `test:state`, `test:story`, `test:sizes`, `test:tracker`, `test:spec-number`, `test:measure` → pass.
- Manual checks: reviewed every changed golden line (`git diff -U0 tests/step/expected`): each differs only by the ` — <why>` suffix.

## Deviations from Assessment

- Expanded scope, per the user's answer at the assess gate: the format-block fix applies to all nine `.apm/agents/*.agent.md`, not only the implementer and planner; `docs/workflow.md` gains one sentence on the reformat reason.
- Every line-level refusal gets a reason, not only the three common cases, so the reformat request is uniform.

## Follow-ups

- File an issue: let a missing implementer report on a later story re-run that story alone instead of only "back to 6" (out of scope here, per the user; it changes gate rules `/fix` shares).
- The missing-report fix is prompt-side only (agent behaviour); it cannot be tested offline. Watch the next `/feat` runs' Logs for `report missing:`.
