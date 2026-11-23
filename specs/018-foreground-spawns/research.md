# Research: foreground spawns

No `NEEDS CLARIFICATION` was left in the Technical Context. The decisions
below settle what the spec leaves open.

## R1. Where the rule lives

- **Decision**: one paragraph in `.apm/skills/feat/references/harness.md`,
  right after "Spawn each with the Agent tool …": when the Agent tool has a
  `run_in_background` parameter, pass `run_in_background: false` on every
  spawn (a batch's included, and those of the rebase reference); the call
  returns the agent's report, so the next call is the one that follows a
  report (the boundary call). An agent stopped before it reports (Esc)
  returns no report: make that next call as usual, never spawn it again on
  your own. Without the parameter, nothing changes. `SendMessage` is not
  touched. In the same edit, the sentence "A turn ends only at a hard
  gate, at the final message, or while agents are running" becomes "…, or
  while agents run in the background (spawned without the parameter, or
  moved there with Ctrl+B)": a foreground spawn returns in the same turn,
  so the old wording would contradict the new rule (design review D1).
- **Rationale**: FR-001, brief constraint (the flag lives in `harness.md`,
  not in `step.sh`). `rebase.md` already follows "the harness's rules", so
  its spawns are covered without editing it.
- **Alternatives considered**: a `background: false` key in `step.sh`'s
  spawn block (rejected in the brief); a copy of the rule in each
  `SKILL.md` (principle III: written once).
- Wording check, on both the new paragraph and the reworded sentence: no
  `brief`, `phase <n>`, `/feat`, `specifier`, `planner`, `tasker`,
  `spec.md` (the `mise run lint` grep on `harness.md`, case-insensitive),
  and none of the other `harness.md` greps' phrases (`review phase`,
  `report keys`, merge-rule and base-check prose).

## R2. The preflight key: name, slot, when it prints

- **Decision**: key `spawn note`, slot 28 (free today: `searched` is 27,
  `worktree` 29, `stop` 99), so it prints after `searched:` and before
  `stop:`; a stop's last line stays `stop:`. Emitted once, in mode 1, right
  after `emit kind` (every classified argument: every kind, `empty` and the
  refused kinds included, so a later stop or `die_error` flushes it too),
  when `${CLAUDE_CODE_FORK_SUBAGENT:-}` is empty. Never in worktree mode,
  never on a `die_usage` (exit 2 before classification prints one usage
  line and nothing else, by contract).
- **Rationale**: SC-005 ("100% of first setup calls with the variable unset
  or empty"); one `emit` line in one place; the slot needs no renumbering;
  `emit` never changes the exit code (FR-005).
- **Alternatives considered**: only for the kinds that start a run (brief,
  issue, symptom, resume, rebase): a second condition for no gain, and it
  misses SC-005 on refusals; a slot next to `install` (renumbers slots).

## R3. The note's text

- **Decision**: a constant (nothing read goes into it):

  ```text
  spawn note: to wait for each agent instead of running it in the background, add "env": {"CLAUDE_CODE_FORK_SUBAGENT": "0"} to <repo>/.claude/settings.local.json (docs/install.md): one model call less per agent spawn in interactive sessions; "1" keeps background spawns and hides this note
  ```

- **Rationale**: FR-004: the `env` line and where it goes, the gain with no
  number, what `1` does.

## R4. `install.sh check`

- **Decision** (confirmed by the user at the design gate): check reads only
  its own shell's environment, and the `note` line says to run check from a
  Claude Code session (`! ./install.sh check`) to see the setting. After
  the python3 line, read `${CLAUDE_CODE_FORK_SUBAGENT:-}`:
  `0` prints `ok       CLAUDE_CODE_FORK_SUBAGENT=0 (agents run in the
  foreground)`; anything else prints `note     CLAUDE_CODE_FORK_SUBAGENT is
  not 0 in this shell: to wait for each agent, add "env":
  {"CLAUDE_CODE_FORK_SUBAGENT": "0"} to <repo>/.claude/settings.local.json;
  Claude Code sets it for its own sessions, so run check from one (! ./install.sh
  check) to see it (docs/install.md section 6)`. Not counted in `missing`.
  The user's value is never printed.
- **Rationale**: FR-008 and FR-012 (environment only, no settings file
  read). A settings `env` value reaches only the shells Claude Code starts,
  so from a plain terminal the line is always a note; the text says so
  rather than misleading.
- **Alternatives considered**: grepping the three settings files for the
  key (FR-012 says environment only; JSON from Bash without jq is the
  fragility the brief rejected); prompting and writing the key (rejected in
  the brief).

## R5. The measure metric

- **Decision**: in `_parse_session`, on the coordinator's own records:
  - a *spawn batch* is the spawn `tool_use` blocks of one coordinator call
    (one `message.id`, whatever the number of records it spans); its ids
    wait for their `tool_result`s. A new batch replaces an open one (a
    result that never comes can't hold the count back).
  - when the batch's last result arrives, the next counted coordinator call
    (a new `message.id`, not a synthetic or API-error record, which `Calls`
    skips) is its *first call after*; if that call ends with no `tool_use`
    (its `tools` list empty when `Calls.finish` runs), the batch counts 1.
  - the tool names: `SPAWN_TOOLS` (`Agent`, `Task`) and `SendMessage`, in a
    tuple of its own (`WAIT_TOOLS`); `SPAWN_TOOLS` and every other figure
    stay as they are (confirmed by the user at the design gate; FR-010
    now names `SendMessage`).
  - the run carries `after_spawn` (an int); `run_figures` puts it in
    `coord`; `aggregate` takes its median like every `coord` key; the row
    `text only after a spawn` goes under `text only` in `render_block` (the
    medians block and `--session`) and in `render_compare`.
- **Rationale**: FR-010's definition (first turn after the last result of a
  batch, counted once per batch, both spawn tool names). `SendMessage` is
  added so the edge case and SC-002 hold ("only `SendMessage` continuations
  may remain" must be visible in the count); in `SPAWN_TOOLS` it would move
  calls from `chores` to `spawn an agent`. A median per run is how every
  coordinator figure reads.
- **Alternatives considered**: counting every text-only turn after a spawn
  until the next tool call (counts the final message of every run);
  counting async results (`status: async_launched`) instead of turns (says
  nothing about the call the coordinator spent); `Agent` only (FR-010 says
  every name in `SPAWN_TOOLS`).

## R6. Tests

- **preflight**: `tests/preflight/run.sh` exports
  `CLAUDE_CODE_FORK_SUBAGENT=0` with its other environment, so every
  existing golden stays as it is whatever the maintainer's own setting. New
  cases: unset (a golden, `feat resume`: `kind`, `install`, `hooks
  allowed`, `spawn note`), empty (line present), `0`, `1` and another value
  (no `spawn note:` key), a refused kind with the variable unset (exit 1,
  note present, last line `stop:`), worktree mode with the variable unset
  (no key, exit 0).
- **measure**: two new finished runs under `fixtures/edge/edge/` (their own
  config dir, so no golden of the default config changes for them):
  `sess-async-1`, a `/feat` run with two background spawns, each result
  `async_launched` and followed by a text-only waiting turn, then the peer
  report and a Bash call (count 2), and `sess-fg-1`, with a two-spawn
  foreground batch and a foreground shipper, each result `completed` (the
  report) and followed by a Bash call, then the final text (count 0). Each case runs `--session <id>` and greps the row, as the
  `notification` case does; the `edge` case's line becomes `runs: 4
  counted (4 finished, 0 unfinished, 0 resumed), 1 left out`. Every golden
  of `tests/measure/expected/` gains the new row; its values come from the
  fixtures (arithmetic in `run.sh`'s comment, not from the script):
  sess-feat-1 1, sess-feat-2 2, sess-feat-3 1 (its foreground shipper is
  followed by the final text), sess-feat-6 2, sess-fix-1 1; `/feat`
  median of 1, 2, 1, 2 = 1.5.
