# Bug Verification: Agent report formats invite parse slips, and a missing implementer report forces back to 6

- **Slug**: 74-implementer-report-slips
- **Tested**: 2026-11-23
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

The format-slip half of the fix holds: no agent format block shows a list header with `none`/`n/a` directly above an item template any more (7 such lines in the implementer's block before the fix, 0 in any of the nine agents after), `Files changed: <integer>` and the planner's "`none` alone" rule are in place, and step.sh still refuses the three slipped shapes, now with a fixed-words reason the reformat spawn can act on. Every offline suite passes. The missing-report half is a prompt change only (the implementer must write its own report with Write and never ask the coordinator to); it is agent behaviour and cannot be verified offline, hence `partial`.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix): parser | scratch harness under the system temp dir sourcing step.sh's lines from `SCH_K=()` to `# --- reports: the check`, running `parse` + `validate` on the assessment's four reports | pass | well-formed report `ok`; the three slipped shapes still refused (fail-closed kept), each with a specific reason (see excerpts) |
| Reproduction (post-fix): format blocks | awk over each `.apm/agents/*.agent.md` fenced block for a `<Key>: none`/`n/a` line directly above a `- ` item line; same on `HEAD`'s implementer | pass | 0 hits across all nine agents after the fix; 7 hits in `HEAD`'s implementer block |
| Implementer prompt: `Files changed` and report-writing rule | read `git diff .apm/agents/feat-implementer.agent.md` | pass | `Files changed: <integer>` + "bare integer, nothing after it"; "Writing it is your job, never the orchestrator's … never ask anyone to write it … quote its error on `Design problems:`" |
| Planner prompt: `Size trigger` | read `.apm/agents/feat-planner.agent.md` lines 70-100 | pass | prose: "`Size trigger` is `none` alone, nothing after it, or names one kind … followed by ` — <what>`" |
| New / updated tests | `mise run test:step` | pass | `step: all cases pass` (includes the three new cases bad-checks-none, bad-files-plus, planner trigger-note) |
| Lint | `mise run lint` | pass | shellcheck, actionlint, plugin validate and the repo greps all clean (rc 0) |
| Regression suites | `mise run test:apm`, `test:ship`, `test:state`, `test:story`, `test:sizes`, `test:tracker`, `test:spec-number`, `test:measure`, `test:secret-scan` | pass | all rc 0 |
| Not verified item: implementer writes its own report (prompt change) | none | not-run | agent behaviour, not testable offline; needs a live /feat run |

## Output Excerpts

Scratch harness (post-fix):

```
ok: good.md
unparsable: checks-none-items.md: line 4 (Checks) — an item under none (write the header alone) -- text: - mise run lint → pass
unparsable: files-plus.md: line 7 (Files changed) — not a bare count or none -- text: Files changed: 80+ (not recounted)
unparsable: planner-trigger.md: line 9 (Size trigger) — a value outside its format -- text: Size trigger: none — no service, no new permission
```

Format-block scan: no hit after the fix; `HEAD implementer hits: 7`.

`mise run test:step`: `step: all cases pass`. `mise run test:apm`: `.claude/agents 9`, `.claude/skills 7`. `mise run test:ship`: `ship tests: 59 cases in 20s`.

## Residual Risks

- The missing-report fix is prompt-side only: whether implementers now always write their report can only be seen in live `/feat` runs (watch Logs for `report missing:`).
- The planner's format block still reads `Size trigger: none | <service | permissions | exposure | dependency> — <what>`; the prose beside it says `none` stands alone, but a model copying the block line alone could still attach `— <what>` to `none` (the parser would refuse it, now with a clear reason).
- The gate change (a missing report on a later story re-running that story alone) is out of scope and stays a follow-up.

## Recommendation

Accept the fix for the format slips (verified offline end to end) and ship; keep the missing-report half under watch on the next live `/feat` runs, and file the follow-up issue for the story-level re-run on a missing report.
