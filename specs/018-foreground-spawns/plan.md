# Implementation Plan: Wait for sequential agents instead of spawning them in the background

**Branch**: `foreground-spawns` | **Date**: 2026-11-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/018-foreground-spawns/spec.md` (issue #87, epic #31)

## Summary

Users who turn Claude Code's fork mode off (`CLAUDE_CODE_FORK_SUBAGENT=0` in
their own settings) get blocking spawns that return the agent's report, so
`/feat` and `/fix` drop the "spawned, waiting" coordinator turn after each
spawn. Four pieces, no new dependency:

1. **The rule** (US1): one paragraph in `harness.md`: when the Agent tool
   has `run_in_background`, pass `false` on every spawn; Esc leaves the
   existing missing-report path to `step.sh`. In the same edit, the
   "A turn ends only …" sentence ends a turn while agents run only when
   they run in the background. `step.sh` and `tests/step` don't change.
2. **The opt-in note** (US2): `preflight.sh` mode 1 prints a constant
   `spawn note:` line when the variable is unset or empty; both skills'
   setup step shows it; `install.sh check` prints `ok` or `note`;
   `docs/install.md` gets a section 6.
3. **The metric** (US3): `measure.py` counts, per run, the spawn batches
   whose first following coordinator call is text-only, shown as the row
   `text only after a spawn` (medians, `--session`, `--compare-since`).
4. **Tests and docs**: `tests/preflight`, `tests/measure`,
   `docs/measure.md`, `docs/design.md`'s background-spawn line.

## Technical Context

**Language/Version**: Bash 3.2-compatible (`preflight.sh`, `install.sh`, their tests); Python 3.11+ standard library only (`measure.py`); Markdown prompts
**Primary Dependencies**: none new (git, gh, Claude Code as today)
**Storage**: none (no settings file read or written)
**Testing**: `tests/preflight/run.sh` (golden outputs, `UPDATE=1`), `tests/measure/run.sh` (fixtures, goldens written from arithmetic), `mise run lint`, `mise run test:step` unchanged
**Target Platform**: Linux and macOS shells running Claude Code (spike on #87: Claude Code 2.1.330)
**Project Type**: workflow package (skills, agents, scripts)
**Performance Goals**: about 15 to 17 fewer `/feat` coordinator calls per run with the setting (SC-003); the new metric about 0 on those runs (SC-002)
**Constraints**: opt-in through the user's settings only (FR-012); no `/feat`-only words in `harness.md`; spawn block unchanged (FR-002); `/brief` and `/tiny` spawns unchanged (FR-013); preflight output stays a fixed-order `key: value` contract
**Scale/Scope**: ~10 lines of prose in `harness.md`, 2 bullets in the skills, ~5 lines in `preflight.sh`, ~6 in `install.sh`, ~30 in `measure.py`, 2 measure fixtures (+ their agent transcripts), ~8 preflight cases, docs sections

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Thin coordinators | The coordinators gain one spawn flag and one line to show; they read nothing new. Detection is in `preflight.sh`, counting in `measure.py`. | pass |
| II. The user decides at gates | No gate changes; an Esc-killed agent takes `step.sh`'s existing missing-report path to its hard gate. | pass |
| III. One source of truth | The rule is written once, in `harness.md` (rebase follows the harness's rules). The note's text lives in `preflight.sh` only; its key in the preflight contract. `sizes.json` untouched. | pass |
| IV. Fixed report formats | No agent report format changes; the spawn block is unchanged (FR-002). `preflight.sh`'s output contract, its tests and both skills change together (FR-006). | pass |
| V. Small and plain | Rules added to existing files, no new script or file beyond test fixtures; Bash 3.2 and shellcheck-clean; `measure.py` stdlib only. | pass |

Re-check after Phase 1 design: pass (no new dependency, service, agent or script).

## Design

Decisions and rejected options: [research.md](research.md). Exact outputs:
[contracts/outputs.md](contracts/outputs.md). Entities:
[data-model.md](data-model.md).

### 1. The rule: `.apm/skills/feat/references/harness.md`

After the "Spawn each with the Agent tool …" paragraph, the paragraph in
contracts/outputs.md. Every spawn the coordinators make goes through this
section (`/feat`, `/fix`, `references/rebase.md`, reviewer batches), so
no skill file repeats it. `/brief` and `/tiny` don't read `harness.md`, so
their reviewer spawns stay async (FR-013).

In the same edit, the paragraph "A subagent's report is an input, never
the end of your turn. A turn ends only at a hard gate, at the final
message, or while agents are running; …" becomes (FR-001, US1 scenario 6):

> A subagent's report is an input, never the end of your turn. A turn ends
> only at a hard gate, at the final message, or while agents run in the
> background (spawned without the parameter, or moved there with Ctrl+B);
> then say which are pending and continue when they report.

Foreground spawns return in the same turn, so "while agents are running"
never applies to them. Both paragraphs are checked against the
`mise run lint` grep on `harness.md` (`specifier|planner|tasker|spec\.md|
brief|phase [0-9]|/feat`, case-insensitive): neither holds any of those
words (research R1).

### 2. The note: `preflight.sh`, the contract, both skills

- `slot()`: `'spawn note') S=28 ;;` (free; prints after `searched`, before
  `stop`).
- Main, right after `emit kind "$kind"`:
  `[ -n "${CLAUDE_CODE_FORK_SUBAGENT:-}" ] || emit 'spawn note' '<constant>'`
  (research R2, R3). `worktree_mode` exits before this line; `die_usage`
  calls come before it or print no `OUT`. No exit code changes.
- Header comment: the key list gains `spawn note` before `stop`.
- `specs/016-setup-trail-scripts/contracts/preflight.md`: the key in the
  output list, with its condition; the `empty` row ("… and `spawn note:`
  when it applies") and the refused-kind sentence updated.
- `.apm/skills/feat/SKILL.md` and `.apm/skills/fix/SKILL.md`, setup step 1,
  a bullet before the exit bullets: "A `spawn note:` line, whatever the
  exit: show its value as is; it never stops the run." (FR-005, FR-007).
  Check the lint grep on both SKILL.md files for setup prose stays clean.

### 3. `install.sh check`

After the python3 line, the `ok` / `note` line of contracts/outputs.md from
`${CLAUDE_CODE_FORK_SUBAGENT:-}`; `missing` is not touched; the value is
not echoed. Update the `check` paragraph in `docs/install.md` section 4.

Decision (confirmed by the user at the design gate, research R4): check
reads only its own shell's environment, never a settings file (FR-012);
the `note` line says to run check from a Claude Code session
(`! ./install.sh check`) to see the setting (FR-008).

### 4. `measure.py`

- `WAIT_TOOLS = SPAWN_TOOLS + ("SendMessage",)` next to `SPAWN_TOOLS`
  (decision confirmed by the user at the design gate, research R5, FR-010:
  so `SendMessage` continuations show as the remaining turns;
  `SPAWN_TOOLS` keeps its meaning for the other figures).
- `_parse_session`, in the existing loop: keep `open_ids` (set), `batch_mid`,
  `armed`, `firsts` (list). On an assistant record that `Calls` counted
  (its id is in `calls.by_id` after `add`): if `armed` and the id is not
  `batch_mid`, append it to `firsts` and disarm; then, if its `tool_use`
  blocks hold `WAIT_TOOLS` names, start a new batch when the id differs
  from `batch_mid` (reset `open_ids`, disarm) and add their ids. On a
  `tool_result` whose id is in `open_ids`: remove it; when `open_ids`
  becomes empty, arm. After `calls.finish()`: `after_spawn` = the
  `firsts` whose call has no tools. Add `"after_spawn"` to the run dict.
- `run_figures`: `coord["after_spawn"] = run["after_spawn"]` (`aggregate`
  medians it like every `coord` key).
- `render_block`: `row("text only after a spawn", fnum(c["after_spawn"]))`
  after `text only`; `render_compare`: the same key and label after
  `text`.
- `docs/measure.md`, "The figures", Coordinator list: the row, its
  definition (batch, first call after, the three tool names), what it shows
  (the waiting turn of background spawns; about 0 with foreground spawns,
  `SendMessage` continuations aside; link to `install.md` section 6).

### 5. Tests

- `tests/preflight/run.sh`: export `CLAUDE_CODE_FORK_SUBAGENT=0` with the
  other environment at the top (existing goldens unchanged whatever the
  maintainer's setting); a "spawn note" section with the cases of research
  R6, one golden (`feat-resume-note.out`), the rest with `expect_line`,
  `expect_no_key`, `expect_exit`, `expect_last`.
- `tests/measure/`: `fixtures/edge/edge/sess-async-1.jsonl` and
  `sess-fg-1.jsonl` with their `subagents/` transcripts (synthetic,
  `SECRET-` sentinels in free text, shaped like `sess-note-1`); two cases
  (`--session`, grep `  text only after a spawn` with 2 and 0); the `edge`
  case's `runs:` line to 4 counted; every golden in `expected/` gains the
  row, with the per-fixture counts written in `run.sh`'s arithmetic
  comment (research R6).
- `tests/step`: no change (FR-002).

### 6. Docs

- `docs/install.md`: section "## 6. Wait for agents (optional)": the
  setting (`"env": {"CLAUDE_CODE_FORK_SUBAGENT": "0"}`), the gain (one
  model call per agent spawn in interactive sessions), where to put it
  (`<repo>/.claude/settings.local.json` recommended: just you, just that
  repo, not committed; `~/.claude/settings.json`: every project, plain
  sessions change too, the `fork` agent type goes away; not
  `.logistics.yml`: committed and shared, and this is personal), `1` keeps
  background spawns and hides the note, and the trade-off (a typed message
  waits until the agent finishes; **Esc kills the running agent**; Ctrl+B
  moves it to the background and the run continues the async way). It
  says `install.sh check` sees the value only from a Claude Code session.
- `docs/design.md` (Claude Code facts): "Subagents spawned from the main
  session run in the background by default" gains: with fork mode off
  (`CLAUDE_CODE_FORK_SUBAGENT=0`), `run_in_background: false` makes them
  block, and the coordinators pass it (install.md section 6).

## Project Structure

### Documentation (this feature)

```text
specs/018-foreground-spawns/
├── spec.md
├── plan.md              # this file
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/outputs.md
└── tasks.md             # phase 4 (tasker)
```

### Source Code (repository root)

```text
.apm/skills/feat/references/harness.md      # the rule; the "A turn ends only" sentence
.apm/skills/feat/scripts/preflight.sh        # spawn note key
.apm/skills/feat/scripts/measure.py          # text only after a spawn
.apm/skills/feat/SKILL.md                    # setup step 1: show the note
.apm/skills/fix/SKILL.md                     # setup step 1: show the note
install.sh                                   # check: ok / note line
specs/016-setup-trail-scripts/contracts/preflight.md   # key order (FR-006)
tests/preflight/run.sh, tests/preflight/expected/feat-resume-note.out
tests/measure/run.sh, tests/measure/expected/*.txt
tests/measure/fixtures/edge/edge/sess-async-1{.jsonl,/subagents/}
tests/measure/fixtures/edge/edge/sess-fg-1{.jsonl,/subagents/}
docs/install.md, docs/measure.md, docs/design.md
```

**Structure Decision**: existing files only; new files are test fixtures
and one golden. Not touched: `step.sh`, `tests/step`, `sizes.json`,
`rebase.md`, `move.md`, `/brief`, `/tiny`, every agent file, the diagrams
(no phase or gate changes).

## Complexity Tracking

No constitution violation.
