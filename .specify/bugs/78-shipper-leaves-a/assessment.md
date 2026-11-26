# Bug Assessment: Shipper leaves a Monitor running after its report

- **Slug**: 78-shipper-leaves-a
- **Created**: 2026-11-26
- **Source**: pdemagny/logistics#78 (https://github.com/pdemagny/logistics/issues/78, fetched with `gh issue view`; host github.com, allowlisted)
- **Verdict**: valid
- **Severity**: low

## Report (verbatim or summarized)

pdemagny/logistics#78, "Shipper leaves a Monitor running after its report, so it re-wakes and resends the report" (author: OWNER). Summary:

- In a `/feat` run, `feat-shipper` waited on the full test suite (`mise run test`, several minutes) with a background Monitor, then delivered its report while the Monitor still ran. Each later monitor event woke it again: it resent the same report about a dozen times or ended with "no report delivered", and the orchestrator got a "waiting on its own background work" notice each time until it stopped the agent with TaskStop.
- No harm to the run (the first report was right and `step.sh` had processed it); the cost is tokens and noise.
- Cause given: step 4 of `.apm/agents/feat-shipper.agent.md` says to run the full checks once, but never says how to run a check that outlasts a plain Bash call, nor to stop background work before the report; nothing in `.apm/` mentions Monitor or background runs; `disallowedTools` does not deny Monitor. Claude Code itself also wakes a subagent on leftover Monitor events after handback (reported upstream separately).
- Fix suggested: in step 4, run a long check in the foreground with a long timeout (up to 600000 ms), or as a background Bash command (one notification on exit), never Monitor; stop every background task before writing the report. Same line in `feat-implementer.agent.md`. Optionally add `Monitor` to both agents' `disallowedTools`.

## Symptom

The shipper (and potentially the implementer) starts a Monitor to wait on a long check suite and hands back its report while that Monitor is still live; each later monitor event re-wakes the finished agent, which resends its report or ends with "no report delivered", until the orchestrator stops it. Expected: the agent's last action is its single report, with no background work left behind.

## Reproduction

1. Run `/feat` (or `/fix`) to the ship phase in a project whose full checks take longer than a default Bash call (several minutes).
2. Watch `feat-shipper` at step 4: with no guidance it may start a Monitor on the suite.
3. After its report, observe repeated wake-ups and resent reports.

Not reproducible here: it needs a live agent run against a multi-minute suite and depends on the model's choice of tool. The code-side cause was confirmed statically (see below).

## Suspected Code Paths

- `.apm/agents/feat-shipper.agent.md:79-90` (step 4, Checks) — says "Run the project's full checks once" and treats a killed or timed-out check as not verified, but gives no way to run a check longer than a default Bash call and no rule to stop background work before reporting.
- `.apm/agents/feat-shipper.agent.md:4` — `disallowedTools: NotebookEdit, Agent, Artifact, EnterWorktree, Skill`: Monitor is allowed.
- `.apm/agents/feat-implementer.agent.md:28-33` (step 2) — runs build, tests and linters after each task group, same gap.
- `.apm/agents/feat-implementer.agent.md:4` — `disallowedTools: Agent, Artifact, EnterWorktree, Skill`: Monitor is allowed.
- `grep -rni 'monitor|run_in_background|600000' .apm/agents` finds nothing: no agent prompt says how to wait on a long command.
- `mise.toml:48` — lint check that every agent's `disallowedTools` holds Artifact, EnterWorktree and Skill; the natural place to also require Monitor if it is denied.

## Root Cause Hypothesis

The agent prompts that run long check suites (shipper step 4, implementer step 2) give no instruction for commands that outlast a plain Bash call and do not deny the Monitor tool, so the model improvises with a Monitor and hands back while it is still armed; Claude Code then re-wakes the subagent on each event. The platform-side re-wake is outside this repo, but the prompt gap is what lets it trigger. Confidence: high.

## Proposed Remediation

**Preferred**: In `feat-shipper.agent.md` step 4 and `feat-implementer.agent.md` step 2, add one rule: run a long check in the foreground with a long Bash `timeout` (up to 600000 ms); when it may run longer, run it as a background Bash command (`run_in_background`, which notifies once on exit) and never use Monitor; stop every background task before writing the report. Add `Monitor` to both agents' `disallowedTools` so the tool cannot be chosen at all.

**Alternatives** (optional):
- Prompt text only, without denying Monitor — smaller change but relies on the model obeying.
- Deny Monitor in every agent's `disallowedTools` and extend the `mise.toml` lint loop to require it — catches future agents too, but touches every agent file and the lint task.

**Files likely to change**:
- `.apm/agents/feat-shipper.agent.md`
- `.apm/agents/feat-implementer.agent.md`
- `mise.toml` (only if the lint check is extended)

**Tests to add or update**:
- If Monitor is required in `disallowedTools`, extend the `mise.toml` lint check (line 48) so `mise run lint` fails when an agent lacks it.
- No `step.sh` or `tests/step` change: the report formats are untouched.

## Risks & Considerations

- A foreground Bash call caps at 600000 ms; a longer suite must use a background Bash command, which the agent must then wait on and stop before reporting.
- Claude Code's own re-wake on leftover Monitor events stays (reported upstream); this fix only removes the trigger.
- No report format change, so `step.sh` and the coordinators are unaffected.

## Open Questions

- Should Monitor be denied in all agents (with a lint check) or only in the shipper and implementer? Recommended: shipper and implementer, the two that run long suites.
