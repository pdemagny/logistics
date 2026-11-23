# Contract: what changes in the outputs

Everything else these scripts print stays as it is. `step.sh`'s spawn
block does not change (FR-002).

## harness.md rule (both coordinators)

After "Spawn each with the Agent tool …", one paragraph, no `/feat`-only
words:

> When the Agent tool has a `run_in_background` parameter (the user turned
> Claude Code's fork mode off), pass `run_in_background: false` on every
> spawn, a batch's and the rebase reference's included: the call returns
> the agent's report, so make the call that follows a report at once. An
> agent stopped before it reports (Esc) returns none: make that call as
> usual, and never spawn it again on your own. Without the parameter,
> spawns run in the background as before. A `SendMessage` is unchanged.

In the same edit, the next paragraph's sentence on when a turn ends:

> A subagent's report is an input, never the end of your turn. A turn ends
> only at a hard gate, at the final message, or while agents run in the
> background (spawned without the parameter, or moved there with Ctrl+B);
> then say which are pending and continue when they report.

## preflight.sh, mode 1

New key, slot 28: after `searched:`, before `stop:`. Printed once per mode-1
call that classified its argument (every kind), when
`CLAUDE_CODE_FORK_SUBAGENT` is unset or empty; never in worktree mode,
never with a `preflight: usage:` line. A constant:

```text
spawn note: to wait for each agent instead of running it in the background, add "env": {"CLAUDE_CODE_FORK_SUBAGENT": "0"} to <repo>/.claude/settings.local.json (docs/install.md): one model call less per agent spawn in interactive sessions; "1" keeps background spawns and hides this note
```

Exit codes unchanged. Updated in the same commit: the header comment of
`preflight.sh` (key order), `specs/016-setup-trail-scripts/contracts/preflight.md`
(the key list, and the `empty` row and refused-kind sentence, which now
include it), and setup step 1 of `.apm/skills/feat/SKILL.md` and
`.apm/skills/fix/SKILL.md`: "A `spawn note:` line, whatever the exit: show
its value as is; it never stops the run."

## install.sh check

One line after the python3 line, never counted in `missing`:

```text
ok       CLAUDE_CODE_FORK_SUBAGENT=0 (agents run in the foreground)
note     CLAUDE_CODE_FORK_SUBAGENT is not 0 in this shell: to wait for each agent, add "env": {"CLAUDE_CODE_FORK_SUBAGENT": "0"} to <repo>/.claude/settings.local.json; Claude Code sets it in its own sessions, so run check from one (! ./install.sh check) to see it (docs/install.md section 6)
```

## measure.py

New coordinator row, under `text only`, in the medians block, the
`--session` block and the `--compare-since` block (same columns as its
neighbours):

```text
  text only after a spawn            2
```

Value: per run, the batches of `Agent`, `Task` or `SendMessage` calls whose
first following coordinator call holds no tool call (data-model.md); the
block shows the median over runs.
