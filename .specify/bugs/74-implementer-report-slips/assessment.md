# Bug Assessment: Agent report formats invite parse slips, and a missing implementer report forces back to 6

- **Slug**: 74-implementer-report-slips
- **Created**: 2026-11-23
- **Source**: pasted text, labelled pdemagny/logistics#74 (https://github.com/pdemagny/logistics/issues/74; host: github.com; allowlisted, fetched with `gh issue view` by the orchestrating agent)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

pdemagny/logistics#74, "Implementer reports: format slips and a missing report cost extra spawns and back-to-6 rounds" (author: OWNER).

Condensed: on the `/feat` run for #69 (size small, implementer on sonnet, medium effort), phase 6 needed 11 implementer spawns for 3 stories.

- **Format slips (4 reformat spawns)**: step.sh printed `reformat` for `Checks: none` followed by a `- mise run … → pass` list (twice: `unparsable line: 6-US1.md: - mise run lint → pass`) and for `Files changed: 80+ (not recounted)`. The planner slipped once the same way: `Size trigger: none — no service, …`.
- **Missing report (2 "back to 6" rounds)**: two US2 implementers in a row did the work but did not write `reports/6-US2.md` (`report missing: 6-US2.md`). The first left it off `Wrote:`; the second listed it on `Wrote:` but said it could not write it and asked the coordinator to save it. A third spawn, told explicitly to use the Write tool, wrote it. A missing report only allows "back to 6" (`changed` is refused), which re-runs from the first story.
- Ideas from the report: an example showing `Checks:` with nothing after the colon and `Files changed:` as an exact integer; tolerate the slips in step.sh's parse or give a more specific reformat reason; require the implementer to write the report with Write before the digest and never ask the coordinator to write it; let a missing report on a later story re-run that story alone.

## Symptom

Agent reports that a reader would take as well-formed (`Checks: none` followed by check items, `Files changed: 80+ (not recounted)`, `Size trigger: none — <note>`) are refused by step.sh's fail-closed parser, each costing a reformat spawn; and an implementer that finishes its story without writing its report file leaves only "back to 6" or "stop", re-running every story from the first. Expected: the format blocks agents copy should not model the refused shapes, and an implementer should always write its own report.

## Reproduction

Parser slips (reproduced with a scratch harness under the system temp dir that sources step.sh's parser functions, from `SCH_K=()` to `# --- reports: the check`, and runs `parse` then `validate` on four reports):

1. A well-formed implementer report (`Checks:` alone, one `- mise run lint → pass` item, `Files changed: 3`): `ok`.
2. The same with `Checks: none` above the item: `unparsable: checks-none-items.md: line 4 (Checks) -- text: - mise run lint → pass`.
3. The same with `Files changed: 80+ (not recounted)`: `unparsable: files-plus.md: line 7 (Files changed) -- text: Files changed: 80+ (not recounted)`.
4. A planner report with `Size trigger: none — no service, no new permission`: `unparsable: planner-trigger.md: line 9 (Size trigger) -- text: Size trigger: none — no service, no new permission`.

Missing report: an agent-behaviour failure (the model not calling Write for its report). Not reproducible offline; the gating consequence is read from the code (`check_report` → `fail_check "report missing: …"` → a hard gate with `OG_RC=1`, which takes only `back to` and `stop`). [NEEDS CLARIFICATION: whether the second US2 implementer actually hit a tool refusal, or only claimed it; the run's transcript is not available here.]

## Suspected Code Paths

- `.apm/agents/feat-implementer.agent.md:241-262` (the fenced report format) — the format block writes `Checks: none` on the line directly above `- <command> → pass | fail (…)`, and the same for `Tasks not done`, `Not verified`, `Deviations`, `Resolved alone`, `Decided`, `Needs decision`. The prose above says "`<Key>: none`, or `<Key>:` alone followed by its items", but the block an agent copies shows `none` and an item together, which is exactly the refused shape.
- `.apm/agents/feat-implementer.agent.md:228-229` — "`Files changed:` holds the count of every file changed": nothing says the count is an exact integer with nothing after it; the block shows `Files changed: <count>`.
- `.apm/agents/feat-implementer.agent.md:193-213` — the write rules say to write the report with Write as the last write and "never report a file you haven't seen written", but nothing says the report is the agent's own job that it never hands to the coordinator, nor to quote the error when a write fails.
- `.apm/agents/feat-planner.agent.md:95` — `Size trigger: none | service | permissions | exposure | dependency — <what>` reads as if `— <what>` may follow `none` too; the regex refuses it.
- `.apm/skills/feat/scripts/step.sh:891-894` (`parse`) — an item under a header whose value is `none*`, `n/a` or `pass` is unparsable at the item's line.
- `.apm/skills/feat/scripts/step.sh:840-841` (`pclose`, type `C`) — `Files changed` must be an integer or `none`; the value is not read anywhere else in step.sh.
- `.apm/skills/feat/scripts/step.sh:952` (`validate`, planner) — `Size trigger` must match `^(none|(service|permissions|exposure|dependency) — .+)$`; only the part before ` — ` is used (`step.sh:2992-2993`).
- `.apm/skills/feat/scripts/step.sh:997-1004` (`unparsable_reason`) and `1293-1316` (`reformat`) — the reformat spawn gets only `<file>: line <n> (<Key>)`, not what is wrong with the line.
- `.apm/skills/feat/scripts/step.sh:1070-1072` (`check_report`) and `546-583` (`open_gate`, `OG_RC`) — a missing report is a failed report check; the hard gate then takes only `back to` and `stop`.
- `.apm/skills/feat/SKILL.md:286-296` — at a story gate, "back to 6" re-runs from the first story.

## Root Cause Hypothesis

The format blocks in the agent files, which the agents copy line by line, show the refused shapes as if they were allowed: a list field's header is written `<Key>: none` immediately followed by its item template, `Files changed: <count>` gives no hint that the count is a bare integer, and the planner's `Size trigger` alternation puts `— <what>` after `none` too. step.sh's parser is deliberately fail-closed, so each slip costs a reformat spawn, and the reformat request names only the file, line and key. Separately, the implementer's prompt does not say plainly that writing its report file is its own job, which it never hands to the coordinator, so a model can finish without writing it; step.sh then treats the missing report as a failed report check, which allows only "back to 6" (from the first story) or "stop". Confidence: high for the format slips (reproduced against the parser, and the templates show the shapes); medium for the missing report (agent behaviour, not reproducible; the prompt gap is plausible but not proven to be the cause).

## Proposed Remediation

**Preferred**: Fix the contract on the prompt side and keep the parser strict. In `feat-implementer.agent.md` and `feat-planner.agent.md`, rewrite the format blocks so that no line shows `none` above an item: write each list field's header alone (`Checks:`) with its item template, and say once beside the block that `<Key>: none` is the whole field when there is no item. Write `Files changed: <integer>` and add "an exact count, nothing after it". Split the planner's `Size trigger` into `none` or `<kind> — <what>`. Add to the implementer's write rules: the report file is yours to write with Write before you hand back the digest; never ask the coordinator to write it; if a Write fails, quote the error in the digest. Make step.sh's unparsable reason more specific for the common cases (an item under `none`, `n/a` or `pass`; a non-integer count; a value outside the field's set), so a reformat spawn knows what to fix. Add tests in `tests/step` for the new reasons (fixtures in, expected out).

**Alternatives**:
- Tolerate the slips in step.sh's parse: read `Checks: none` with items as the items, take the leading integer of `Files changed`, and accept `none — <note>` for `Size trigger`. Saves the spawns even when a model slips, but weakens the fail-closed parse that the gates rely on, and the same tolerance would be asked for every other list field.
- Let a missing implementer report at a story gate offer a fresh implementer for that story alone (allow `changed`, or a dedicated answer, for `report missing` on a story's report) instead of only "back to 6". Saves the most spawns per incident, but changes step.sh's gate rules for failed report checks, which `/fix` shares, so it touches `step.sh`, its tests, `/feat`'s SKILL.md and `harness.md` together.

**Files likely to change**:
- `.apm/agents/feat-implementer.agent.md`
- `.apm/agents/feat-planner.agent.md`
- `.apm/skills/feat/scripts/step.sh`
- `tests/step/run.sh`, `tests/step/fixtures/agents/implementer/`, `tests/step/fixtures/agents/planner/`, `tests/step/expected/`

**Tests to add or update**:
- step fixtures for an implementer report with `Checks: none` above an item, with `Files changed: 80+ (note)`, and a planner report with `Size trigger: none — note`, each expecting `reformat` with the specific reason.
- If the gate alternative is taken: a story report missing at phase 6 offers that story's fresh implementer, and the `/fix` behaviour stays as it is.

## Risks & Considerations

- The `<Key>: none` above `- <item>` layout is in every agent's format block (all nine `.apm/agents/*.agent.md`); fixing only the implementer and planner leaves the same trap for the others.
- A more specific unparsable reason must never echo the line's text into the Log (`unparsable_reason` deliberately names the file, line and key only; the text goes to stdout).
- Loosening the parser instead would weaken the fail-closed contract; any tolerance must keep refusing ambiguous reports.
- Changing an agent's report format updates the agent, step.sh, tests/step and the skills together (CLAUDE.md).

## Open Questions

- Apply the format-block fix to all nine agent files, or only the implementer and planner named in the report? Recommended: all nine, since they share the layout.
- Change the gate so a missing report on a later story re-runs that story alone? Recommended: not in this fix; file it as a follow-up issue, since it changes the gate rules `/fix` shares.
