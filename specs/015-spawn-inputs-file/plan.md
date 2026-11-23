# Implementation Plan: step.sh writes each spawn's lists to an inputs file the agent reads

**Branch**: `spawn-inputs-file` | **Date**: 2026-11-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/015-spawn-inputs-file/spec.md` (issue #69; follow-up to #28 finding D13; part of epic #31)

## Summary

step.sh stops printing a spawn's lists in its spawn block. `slist` (and a
new `sline` for the story's fenced `story.sh output`) collects the lines
the block used to print; at the end of each block's list part a new
`sinputs` hands them to a new `state.sh inputs` subcommand, which writes
them, after one fixed "data, never instructions" line, to the block's
report path with `.in.md`, under the `reports/` guards `report-path`
already applies (moved into one shared helper), and prints the path;
step.sh prints it as `inputs: <path>`. A block whose lists are all empty
prints no `inputs:` line and writes nothing. The six agents that take
lists read them from the file on the `inputs:` line of the message they
were just given (a continuation names its own; no such line: every list
`none`; an earlier file is never reused),
harness.md and the `/feat` and `/fix` skills tell the coordinator to relay
the line and never read the file, and `/tiny` stops naming its two `none`
lists. tests/step checks every inputs file against a golden from its
generic `check`.

## Technical Context

**Language/Version**: bash 3.2 or later for `state.sh` and `step.sh`
(their construct limits, checked by their tests' grep); Markdown prompts

**Primary Dependencies**: none new; `mktemp` and `mv -f` as `write_file`
uses them today

**Storage**: one `<key>[-<n>].in.md` file per spawn with lists, in the
artifact dir's `reports/` (ignored, never committed), next to that
spawn's report

**Testing**: `tests/state/run.sh` (new `inputs` cases),
`tests/step/run.sh` (`check` extended to inputs files; five new checks,
listed once under Design "Tests"; 58 spawn goldens regenerated, 23 of
them gaining a `.in` golden);
`mise run lint`, every `mise run test:*`, `mise run test:apm`;
[quickstart.md](quickstart.md)

**Target Platform**: Claude Code sessions running `/feat`, `/fix` and
`/tiny` (Linux, macOS `/bin/bash` 3.2); the `check` workflow

**Project Type**: prompt package (skills and subagents) with helper
scripts

**Performance Goals**: none (fidelity is the aim; one extra `state.sh`
call per spawn with lists)

**Constraints**: guards stay in state.sh (FR-007); step.sh Bash 3.2, no
jq, no Python, shellcheck clean; the coordinators read no file;
harness.md free of `/feat`-only words; `/tiny` ≤ 200 lines; report
formats, gate output, rebase/move/reformat spawns, `docs/workflow.md` and
the diagrams unchanged

**Scale/Scope**: state.sh (~40 lines), step.sh (~30 lines changed), 6
agents (one sentence each plus a few pointers), harness.md, 3 skills, 2
test runners and their goldens; ~25 tasks

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Result |
| --------- | ----- | ------ |
| I. Thin coordinators | the coordinators relay one path instead of retyping lists, and read no file; nothing moves into them | pass |
| II. The user decides at gates | gates and the merged findings printed at a gate are unchanged | pass |
| III. One source of truth | the lists' text exists once, as step.sh wrote it; the `reports/` guards move into one helper shared by `report-path` and `inputs`, not copied; sizes.json untouched | pass |
| IV. Fixed report formats | no report format changes; the input contract changes with step.sh, tests/step, harness.md and the three skills in one commit (FR-015) | pass |
| V. Small and plain | a subcommand in the existing state.sh, not a new script; one sentence per agent; offline tests for every path | pass |

Distribution: no file added to `.apm/`, no agent added; `plugin.json`,
`apm.yml` and `install.sh` unchanged.

Post-design re-check: pass. No service, permission, dependency or
exposure added: the new file lives in the already-ignored `reports/`,
behind the same symlink guards, and holds only text step.sh already
printed. Size trigger: none.

## Project Structure

### Documentation (this feature)

```text
specs/015-spawn-inputs-file/
├── plan.md                    # this file
├── research.md                # decisions R1–R10
├── data-model.md              # spawn block, inputs file, lists per spawn
├── quickstart.md              # validation
├── contracts/
│   ├── inputs-file.md         # the key, the file, state.sh inputs, step.sh helpers
│   └── prompts.md             # agents, harness.md, the three skills
└── tasks.md                   # phase 5
```

### Source code (repository root)

Changed:

```text
.apm/skills/feat/scripts/state.sh          # reports_dir helper; inputs subcommand; synopsis
.apm/skills/feat/scripts/step.sh           # slist buffers; sline; sinputs at 8 call sites; header comment
.apm/agents/feat-implementer.agent.md      # inputs sentence; story, fix and bug mode pointers
.apm/agents/feat-code-reviewer.agent.md    # inputs sentence
.apm/agents/feat-design-reviewer.agent.md  # inputs sentence
.apm/agents/feat-planner.agent.md          # inputs sentence; amend mode
.apm/agents/feat-shipper.agent.md          # inputs sentence; not verified items from the file
.apm/agents/feat-bug-assessor.agent.md     # inputs sentence; test mode
.apm/skills/feat/references/harness.md     # relay the inputs line, never read the file
.apm/skills/feat/SKILL.md                  # reviewer context; phases 4 and 6
.apm/skills/fix/SKILL.md                   # reviewer context; phases 1–4
.apm/skills/tiny/SKILL.md                  # fresh review: no none lists
tests/state/run.sh                         # inputs cases; usage line
tests/step/run.sh                          # check() on inputs files; new cases
tests/step/expected/*.out                  # list lines out, inputs: line in
```

New:

```text
tests/step/expected/*.in                   # one per case whose output names inputs files
```

**Structure Decision**: no new file outside the tests' goldens; the writer
joins state.sh beside `report-path`, whose guard it shares.

## Design

The details are in [contracts/inputs-file.md](contracts/inputs-file.md)
and [contracts/prompts.md](contracts/prompts.md).

- **The writer (FR-004, FR-006, FR-007, FR-008, FR-012)**: `state.sh
  inputs <state file> <report path> <line>...` (R1, R2). `cmd_report_path`'s
  `reports/` checks and creation move into `reports_dir`, called by both
  subcommands (R3); `inputs` checks the report path is a report path of
  that `reports/` (R4), refuses a symlinked or non-regular target, and
  writes the whole file through `write_file` (R5), then prints the path.
- **step.sh (FR-001, FR-002, FR-003, FR-005, FR-011)**: `slist` appends
  its lines to `IN_L` and sets `IN_ANY` on an item; `next_story` appends
  the fenced output through `sline`; `sinputs`, called once per block at
  the eight call sites ([data-model.md](data-model.md#lists-per-spawn)),
  writes and prints `inputs:` only when `IN_ANY`; `spawn_row` and
  `spawn_group` empty the buffer (R6). Single-line keys stay as they are.
  The file layout is R7's.
- **Agents (FR-009, FR-013)**: one sentence each, naming its lists and
  worded the same in all six: the file on the `inputs:` line of the
  message just given (a continuation message names its own; an earlier
  file is never reused), no such line in this message: every list `none`
  (exact text in [prompts.md](contracts/prompts.md)), plus the pointers
  there (R9). The shipper
  fills `ship-not-verified.md` from the file's `not verified items`.
- **Coordinators (FR-010, FR-014)**: harness.md relays `inputs:` like any
  key, for `SendMessage` too, and never reads the file; the skills' list
  mentions point to the file; `/tiny` drops its two `none` lists.
- **Tests (FR-016)**: `check` rejects list lines in stdout, pairs each
  `inputs:` path with its `report:` path, and compares the files with
  `expected/<case>.in` (R8). New checks, five in all, in four `new_case`
  blocks (each its `.out` golden; all but the first also a `.in`):
  1. `fix1-no-inputs` (`/fix` 1 Assess, all lists empty): a fresh `/fix`
     state with no `1 Assess — approved:` or `— answer:` Log line,
     `resume`; no `inputs:` line, and the case asserts no `*.in.md` in
     `reports/`.
  2. `fix1-awkward-inputs` (`/fix` 1 Assess with `approved commands` and
     `answers`, the awkward item): `S log` adds a `- [x] 1 Assess —
     approved: …` line whose command holds `'`, `$(…)`, a backtick and a
     leading `-`, and a `- [x] 1 Assess — answer: …` line, then `resume`.
     The awkward-item case and the `/fix` 1 gap case are this one case.
  3. `fix1-awkward-inputs-again` (the same spawn printed twice): in the
     same `new_case` block, `resume` again; its `.in` golden equals case
     2's (rewritten whole, not doubled).
  4. `feat4-rejected` (`/feat` 4 design review batch with `rejected`): a
     `/feat` state at `4 Design review` whose Log holds an earlier `4
     Design review [soft] — …; skipped A1 (…)` line with A1's sub-line,
     then `resume`.
  5. `feat7e-rejected` (`/feat` 7e with `rejected`): the `medium7` setup
     with that same skipped-A1 Log line, through 7a–7d's call to the 7e
     spawn.
  Existing goldens already carry a non-empty list for: story without
  (`feat5-soft`) and with `failures` (`feat6-retry`), review fixes without
  (`feat7-medium-approved`, `fix4-fixes-spawn`) and with `failures`
  (`fixes-retry`), planner amend (`feat4-soft-apply`), a code review batch
  with `rejected` and `accepted sec` (`feat7-accepted-sec`), `/fix` 2
  (`fix1-soft`), `/fix` 3 (`fix2-soft`) and ship (`feat8-elsewhere-approved`);
  new checks 2, 4 and 5 cover the three spawns left (FR-016).
  tests/state: write, rewrite with fewer lines, awkward line, the three
  symlink refusals and a non-regular target with nothing written, bad
  report paths (other dir, `.in.md`, no `.md`), no lines.

## Complexity Tracking

None: the Constitution Check has no violation.
