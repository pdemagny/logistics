# Feature Specification: Wait for sequential agents instead of spawning them in the background

**Feature Branch**: `foreground-spawns`

**Created**: 2026-11-23

**Status**: Draft

**Input**: User description: brief `specs/briefs/foreground-spawns.md` (issue #87)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Spawns block and return the report (Priority: P1)

A user who has turned off fork mode (`CLAUDE_CODE_FORK_SUBAGENT=0` in their own Claude Code settings) runs `/feat` or `/fix`. Every agent spawn, sequential or reviewer fan-out, `rebase` included, blocks and returns the agent's report as its result. The coordinator's next call goes straight to the boundary call, with no "spawned, waiting" turn. Without the setting nothing changes.

**Why this priority**: This is the saving itself: about a third of coordinator calls per `/feat` run, each re-reading the whole context.

**Independent Test**: In a session with the setting at `0`, run a spawn from `/feat` or `/fix` and check that it returns the report and never "Async agent launched". In a session without it, check that spawns stay async as today.

**Acceptance Scenarios**:

1. **Given** the Agent tool offers a `run_in_background` parameter, **When** a coordinator spawns any agent, **Then** it passes `false`.
2. **Given** the setting is `0`, **When** a spawn is made, **Then** its result is the agent's report and the coordinator's next call is the boundary call.
3. **Given** several reviewers are spawned in one message, **When** they run, **Then** they still run concurrently.
4. **Given** the setting is absent, **When** a spawn is made, **Then** the Agent tool has no such parameter and the spawn is async as before.
5. **Given** a foreground agent is killed with Esc and returns no report, **When** the coordinator's next turn (or `resume`) makes its usual boundary call, **Then** the existing missing-report path applies (reformat or fresh spawn, then a hard gate) and the coordinator never re-spawns on its own.
6. **Given** the shared coordinator rules, **When** they say when a turn ends, **Then** a turn ends while agents are running only when those agents run in the background (spawned without the parameter, or moved there with Ctrl+B); foreground spawns return in the same turn.

---

### User Story 2 - Learn the setting exists (Priority: P2)

A user who has not chosen is told how to opt in on every first setup call until they choose `0` or `1`, by the setup note in `/feat` and `/fix`, by `install.sh check`, and by a short docs section.

**Why this priority**: The opt-in is invisible otherwise; nothing today tells the user it exists.

**Independent Test**: Run the setup's first call with the variable unset, empty, `0` and `1`, in worktree mode and outside it; run `install.sh check` with the same values.

**Acceptance Scenarios**:

1. **Given** the variable is unset or empty and setup is in its first call (before `EnterWorktree`), **When** `preflight.sh` runs, **Then** it prints a one-line note: how to opt in (the `env` line and where it goes), that it saves one model call per agent spawn in interactive sessions (no hard-coded number), and that setting `1` keeps background spawns and hides the note. The coordinator shows it and the run continues.
2. **Given** the variable is `0` or `1`, or setup is in worktree mode, **When** `preflight.sh` runs, **Then** it prints no note.
3. **Given** any value, **When** `preflight.sh` runs, **Then** its exit code is the same as without the note.
4. **Given** the variable is `0`, **When** `install.sh check` runs, **Then** it reports `ok`; for any other value it prints a `note` line with the line to paste, not counted as missing and not changing the exit code.
5. **Given** a user reads `docs/install.md`, **When** they reach the new section, **Then** it gives the setting, the gain, where to put it (`<repo>/.claude/settings.local.json` recommended: just you, just that repo, not committed; `~/.claude/settings.json`: every project, plain sessions change too, the `fork` agent type goes away; not `.logistics.yml`: committed and shared, and this is personal) and the trade-off: while an agent runs a typed message waits until it finishes, **Esc kills the running agent**, Ctrl+B moves it to the background and the run continues the async way.

---

### User Story 3 - Measure the gain (Priority: P3)

The maintainer runs `measure.py` and sees, per run, how many text-only coordinator turns follow an `Agent` result, so `--compare-since <date>` shows the effect directly.

**Why this priority**: The median calls per run is too noisy to judge on; the metric also judges the rest of epic #31.

**Independent Test**: Run the measurement on a transcript with async spawns (count above 0) and one with foreground spawns (count 0).

**Acceptance Scenarios**:

1. **Given** a transcript where a spawn batch (one or more spawns in one message) is followed by a coordinator turn with no `tool_use` block, **When** measured, **Then** that turn counts once per batch, for every tool name in `SPAWN_TOOLS` and for `SendMessage`.
2. **Given** a transcript with foreground spawns, **When** measured, **Then** the count is 0.
3. **Given** `docs/measure.md`, **When** read, **Then** it describes the metric.

---

### Edge Cases

- A `SendMessage` continuation (`continue: <id>`) may still return async: left as is, and the new metric shows it as a remaining turn.
- The variable is set to an unexpected value (neither `0`, `1`, unset nor empty): treated as chosen for the preflight note (no note); `install.sh check` prints the `note` line.
- The user presses Esc on a running agent: covered by US1 scenario 5.
- A coordinator drops the flag: not handled by a per-spawn key; revisit only if measurement shows it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The shared coordinator rules MUST say that when the Agent tool has a `run_in_background` parameter, every spawn passes `false`, with no `/feat`-only words in that shared file. Their sentence on when a turn ends MUST say the same in the same edit: a turn ends while agents are running only when they run in the background.
- **FR-002**: The spawn block printed by `step.sh` and its tests MUST NOT change.
- **FR-003**: `preflight.sh` MUST print the opt-in note in its first call only, when `CLAUDE_CODE_FORK_SUBAGENT` is unset or empty, never in worktree mode and never when the value is `0` or `1`.
- **FR-004**: The note MUST state the `env` line and where it goes, that it saves one model call per agent spawn in interactive sessions (no hard-coded number), and that `1` keeps background spawns and hides the note.
- **FR-005**: The note MUST NOT change `preflight.sh`'s exit code and MUST NOT stop the run; the coordinators' setup steps show it.
- **FR-006**: The new output key MUST sit in the fixed `key: value` order of `preflight.sh`, its `setup-trail-scripts` contract, and both coordinators' setup steps, together.
- **FR-007**: `tests/preflight` MUST cover unset, empty, `0`, `1` and worktree mode; `.apm/skills/feat/SKILL.md` and `.apm/skills/fix/SKILL.md` MUST say their setup shows the note.
- **FR-008**: `install.sh check` MUST print `ok` when the variable is `0` and otherwise a `note` line, not counted as missing, with the line to paste. It reads only its own shell's environment, so the `note` line MUST say to run check from a Claude Code session (`! ./install.sh check`) to see the setting.
- **FR-009**: `docs/install.md` MUST have a short section covering the setting, the gain, the three locations and the trade-off listed in US2 scenario 5.
- **FR-010**: `measure.py` MUST report per run the number of text-only coordinator turns right after an `Agent` result: the first coordinator assistant turn with no `tool_use` block after the last tool result of a spawn batch, for every tool name in `SPAWN_TOOLS` and for `SendMessage` (so continuations show as the remaining turns), with `SPAWN_TOOLS` and every other figure unchanged.
- **FR-011**: `tests/measure` MUST cover an async-spawn transcript (count above 0) and a foreground-spawn transcript (count 0); `docs/measure.md` MUST describe the metric.
- **FR-012**: The setting MUST be opt-in only, through the user's own Claude Code settings, read from the environment the shell sees; logistics adds no switch of its own, writes no settings file and detects no Claude Code version.
- **FR-013**: `/brief`'s reviewer spawn and `/tiny`'s reviewer spawn MUST stay async and unchanged.
- **FR-014**: `mise run lint` and the offline tests MUST pass; shell stays Bash 3.2 without jq or Python, and `measure.py` stays Python 3.11+ standard library only.

### Key Entities

- **Spawn batch**: one or more agent spawns issued in one coordinator message; ends at its last tool result.
- **Text-only turn**: a coordinator assistant turn with no `tool_use` block.
- **Setting**: `CLAUDE_CODE_FORK_SUBAGENT` in the environment: `0` foreground opt-in, `1` explicit keep-background, unset or empty undecided.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a session with the setting at `0`, 100% of `/feat` and `/fix` spawns return the agent's report as their result.
- **SC-002**: After merge, `mise run measure --compare-since <merge date>` on runs with the setting shows text-only turns after an `Agent` result at about 0 (only `SendMessage` continuations may remain).
- **SC-003**: `/feat`'s median coordinator calls per run falls by about 15 to 17 on those runs.
- **SC-004**: Without the setting, spawn behaviour is identical to today.
- **SC-005**: The note appears in 100% of first setup calls with the variable unset or empty and in none otherwise.

## Assumptions

- A `settings.json` or `settings.local.json` `env` value reaches the shell the scripts run in (shown by the spike on #87, Claude Code 2.1.330).
- Parallel foreground spawns in one message still run concurrently (spike on #87).
- Only the maintainer is affected today; no migration is needed.
- Out of scope: `/brief` and `/tiny` spawns, `SendMessage` continuations, #88, setting the variable for the user.
