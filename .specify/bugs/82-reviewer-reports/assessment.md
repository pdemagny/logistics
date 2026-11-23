# Bug Assessment: Reviewer reports left unwritten, and one missing report cancels the batch's reformat turn

- **Slug**: 82-reviewer-reports
- **Created**: 2026-11-23
- **Source**: pdemagny/logistics#82 (https://github.com/pdemagny/logistics/issues/82), host github.com, allowlisted (read with `gh issue view`)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

pdemagny/logistics#82, "Reviewer reports: a missing report and a lost reformat turn cost a full re-run of phase 7".

On the setup-trail-scripts `/feat` run (#29, size medium), phase 7's first reviewer batch stopped hard and needed "back to 7", which re-ran all four lenses.

- 7d (cuts, sonnet, medium) never wrote its report: its transcript holds Read and Bash calls, then the hand-back, with no Write call. The hand-back carried the full report, `Wrote:` listing `reports/7-7d.md`, and step.sh reported `report missing: 7-7d.md`.
- 7c (performance) slipped on the layout: `Performance (7c):` alone, then `none` on the next line (`unparsable: 7-7c.md: line 2 (Performance (7c)) — not a "- " item at column 0`). Alone, that gets a reformat turn; here the failed check on 7d's report took the turn away and the gate allowed only "back to 7" or "stop".

Root cause per the issue: #74 (184a738) fixed the missing report for the implementer only. The other report-writing agents (`feat-code-reviewer`, `feat-design-reviewer`, `feat-specifier`, `feat-planner`, `feat-tasker`, `feat-bug-assessor`) still say only "write the full report … with Write, as your last write, and hand back the digest". `feat-code-reviewer` also says "With no report path, write no file and hand back the full report". In step.sh's `review_boundary`, a failed check on one report of a batch cancels the reformat turn of the others.

Ideas from the issue: give every report-writing agent the implementer's rule; in a reviewer batch, re-run only the lens whose report is missing and keep the reformat turn for the others.

## Symptom

In a reviewer batch (`/feat` 4, 7, 7e; `/fix` 4), a reviewer that hands back its full report instead of writing it fails the report check (`report missing`), and that one failure turns the whole batch into a hard gate whose only way forward is "back to <N>", re-running every lens and dropping the one reformat turn another report's layout slip would have got. Expected: each report-writing agent writes its own report file, and one lens's missing report costs at most that lens's re-run.

## Reproduction

1. Scratch test (under the system temp dir) that copies the repo's `step.sh`, `state.sh`, `story.sh` and the `tests/step` fixtures `sizes.tsv`, `states/feat.md`, `code-reviewer/7a-plain`, `7b-sec`, `7d-zero` into a throwaway repo, sets Size medium and Current phase `7 Code review`, and runs `step.sh resume` to get the batch's `boundary:` call.
2. 7c's report written as `Performance (7c):` alone, `none` on the next line (the issue's slip).
3. Case A, 7d's report present: `step.sh feat <state> <boundary call>` prints `reformat`, one `feat-code-reviewer` spawn for 7c (`mode: reformat`, `unparsable: 7-7c.md: line 2 (Performance (7c)) — not a "- " item at column 0`) and logs `reformat 1 of 1`.
4. Case B, same call with `7-7d.md` removed: `step.sh` prints `hard:` with `- report missing: 7-7d.md` and `- unparsable: 7-7c.md: line 2 (Performance (7c)) …`, no reformat spawn, and logs `- [x] 7 Code review [hard] — report missing: 7-7d.md; unparsable: 7-7c.md: …`. The symptom is reproduced.

The agent half (a reviewer handing back instead of writing) is a model behaviour and is not reproducible offline; it is grounded in the agent files' text (see below).

## Suspected Code Paths

- `.apm/skills/feat/scripts/step.sh:2680` `review_boundary()` — line 2715, `if (( ! CHK_FAIL && ! SNAPF && turn )); then reformat "$tok"; return 0; fi`: any failed check in the batch (`CHK_FAIL`, set by `fail_check` at line 1038) suppresses the reformat turn of every other report, then the batch falls through to `hard_gate` / `review_gate`.
- `.apm/skills/feat/scripts/step.sh:1069` `check_report()` — line 1077 `fail_check "report missing: $f"`: a missing report is a failed check, not a slip, so it has no per-report retry.
- `.apm/skills/feat/scripts/step.sh:1299` `reformat()` — spawns per unparsable report; has no notion of a fresh re-spawn of a group whose report is missing.
- `.apm/skills/feat/scripts/step.sh:3851` — the same `! CHK_FAIL && turn` guard on another boundary path (single-report boundaries), for comparison.
- `.apm/agents/feat-implementer.agent.md:207-225` — the rule #74 added: "Writing it is your job, never the orchestrator's … Never hand back before that Write has returned, never ask anyone to write it for you; if the Write fails, try once more, then quote its error …".
- `.apm/agents/feat-code-reviewer.agent.md:186-195` — only "write the full report … with Write, as your last write, and hand back the digest", and "With no report path, write no file and hand back the full report, `Wrote: none`".
- `.apm/agents/feat-design-reviewer.agent.md:133-142` — same wording, same "no report path" clause.
- `.apm/agents/feat-specifier.agent.md:56-64`, `.apm/agents/feat-planner.agent.md:59-68`, `.apm/agents/feat-tasker.agent.md:57-65`, `.apm/agents/feat-bug-assessor.agent.md:155-166` — same wording without the implementer's rule.
- `tests/step/run.sh:992` — "report check: a failure and an unparsable line in the same call: hard at once" locks in today's behaviour for a single-agent boundary; `tests/step/run.sh:1419-1500` holds the phase-7 batch cases (`medium7`, `batch: … usage`).
- `.apm/skills/feat/references/harness.md:126-132` and `docs/workflow.md:55-62` — document "a failed check is a hard gate … recommend back to <N>" and the one reformat turn.

## Root Cause Hypothesis

Two causes compound. First, commit 184a738 (#74) gave only `feat-implementer` the explicit rule that writing the report file is the agent's own job, never to be handed back before the Write returns, retried once on failure with the error quoted; the reviewers and the other report-writing agents kept the weaker wording, and `feat-code-reviewer` / `feat-design-reviewer` keep a "no report path: hand back the full report" branch whose shape 7d's hand-back matches, so a reviewer can end its run with the report in the hand-back and no Write. Second, `review_boundary` treats a batch as one unit: `CHK_FAIL` from any report (here `report missing: 7-7d.md`) disables the reformat turn for all reports and makes the gate hard, so the coordinator's only exits are "back to <N>" (all lenses again) or "stop". The second behaviour is deliberate today (documented in harness.md and locked by a test) but disproportionate in a batch, where the failed report belongs to one independent group. Confidence: high (the step.sh half is reproduced; the agent-file half is read directly from the files and matches the transcript the issue describes).

## Proposed Remediation

**Preferred**: Two parts, changed together per the repo's rule (agent, step.sh, tests/step and skills move together).

1. Agent files: copy the implementer's rule into every report-writing agent (`feat-code-reviewer`, `feat-design-reviewer`, `feat-specifier`, `feat-planner`, `feat-tasker`, `feat-bug-assessor`): writing the report is the agent's job, never the orchestrator's; never hand back before the Write has returned; never ask anyone to write it; on a failed Write try once more, then quote the error on a named digest line. In the two reviewers, make the "no report path" branch explicit that it applies only when no path was given in the request (the spawn's `report:` key).
2. `step.sh` `review_boundary`: when a batch's only failed checks are `report missing` on some groups (no other check failure, no snapshot change, turns not used), answer with the reformat verdict extended to the batch: a fresh spawn of each group whose report is missing (its own new report path, mode as at the batch start) plus the usual reformat spawn for each unparsable report, and the next `boundary:` call carrying `sum=` for the reports that passed. Log the re-spawn so a second miss of the same group is hard. Other check failures (changed report, bad `Wrote:`, snapshot) stay hard as today.

**Alternatives**:
- Agent files only (part 1), leaving `review_boundary` as it is: smallest change, fixes the cause seen in the run, but a future missing report still re-runs the whole batch.
- Keep the hard gate but add a gate answer "back to <lens>" (re-run only the named group) and let the reformat turns of the others still run: the user decides, at the cost of one more gate stop and a new answer form both coordinators must learn.

**Files likely to change**:
- `.apm/agents/feat-code-reviewer.agent.md`
- `.apm/agents/feat-design-reviewer.agent.md`
- `.apm/agents/feat-specifier.agent.md`
- `.apm/agents/feat-planner.agent.md`
- `.apm/agents/feat-tasker.agent.md`
- `.apm/agents/feat-bug-assessor.agent.md`
- `.apm/skills/feat/scripts/step.sh`
- `tests/step/run.sh` and new `tests/step/expected/*.out` / `*.log`
- `.apm/skills/feat/references/harness.md`
- `docs/workflow.md`

**Tests to add or update**:
- tests/step: a `/feat` 7 medium batch with 7d's report missing and 7c unparsable gives a reformat verdict with a fresh 7d spawn and a 7c reformat spawn, not a hard gate.
- tests/step: the same with only 7d missing gives a fresh 7d spawn; a second miss of 7d after its re-spawn is hard.
- tests/step: a `/fix` 4 batch with a missing group report behaves the same.
- tests/step: a batch with a non-missing failed check (`report changed since checked`, bad `Wrote:`) stays hard at once (today's rule).
- The existing "a failure and an unparsable line in the same call: hard at once" case keeps passing for single-agent boundaries.
- `mise run lint` (agent prompt greps, shellcheck) and `mise run test:apm`.

## Risks & Considerations

- step.sh's output is a contract both coordinators read: a reformat verdict that holds a fresh (non-reformat) spawn is a new shape; `/feat` and `/fix` and harness.md's `reformat` entry must be checked against it.
- The documented rule "a failed check is a hard gate" changes for reviewer batches; harness.md and docs/workflow.md must say so, keeping `/feat`-only words out of harness.md (lint greps them).
- Bash 3.2, no jq, shellcheck-clean constraints on step.sh.
- The 7c slip itself is already covered by the format text 184a738 added (`An empty section is <Key>: none on its header line`); it is a model slip the reformat turn exists for, not a separate defect.

## Open Questions

- Should part 2 (the per-group re-spawn in `review_boundary`) ship in this fix, or only part 1 with part 2 as a follow-up issue? — recommended: ship both here, the issue names both and the step.sh part is what turned one miss into four re-runs.
- Should the fresh re-spawn of a missing group count against the batch's one reformat turn (so a second slip anywhere is hard), or have its own one-time allowance? — recommended: its own allowance per group, logged, second miss hard.
- Should `feat-shipper` and `feat-brief-reviewer` get the rule too? — recommended: no; the shipper's report is written by `ship.sh` and the brief reviewer cannot Write.
