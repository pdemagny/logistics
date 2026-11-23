# Tasks: Wait for sequential agents instead of spawning them in the background

**Input**: Design documents from `specs/018-foreground-spawns/` (spec.md, plan.md, research.md, data-model.md, contracts/outputs.md, quickstart.md)

**Tests**: Requested by the spec (FR-007, FR-011): preflight and measure tests are part of US2 and US3. `tests/step` does not change (FR-002).

**Organization**: One phase per user story. Paths are relative to the repository root (the worktree). Never commit from these tasks; never edit CHANGELOG.md or release versions.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [x] T001 Record the baseline: run `mise run lint`, `mise run test:preflight`, `mise run test:measure` and `mise run test:step` from the repo root and note any failure that exists before the change

## Phase 2: Foundational

No blocking prerequisite: the three stories touch different files and are independent.

---

## Phase 3: User Story 1 - Spawns block and return the report (Priority: P1) MVP

**Goal**: Every `/feat` and `/fix` spawn passes `run_in_background: false` when the Agent tool offers it; the turn-end rule agrees.

**Independent Test**: `mise run lint` passes (harness.md greps clean); `git diff` shows `step.sh` and `tests/step` untouched; reading harness.md shows the rule and the reworded sentence.

- [x] T002 [US1] In `.apm/skills/feat/references/harness.md`, right after the "Spawn each with the Agent tool ..." paragraph, add the paragraph from `specs/018-foreground-spawns/contracts/outputs.md` ("harness.md rule"): when the Agent tool has a `run_in_background` parameter pass `run_in_background: false` on every spawn, batch and rebase reference included; an Esc-stopped agent returns no report, so make the usual next call and never re-spawn on your own; without the parameter nothing changes; `SendMessage` unchanged. No `/feat`-only words (lint grep: specifier|planner|tasker|spec.md|brief|phase N|/feat)
- [x] T003 [US1] In `.apm/skills/feat/references/harness.md`, same edit as T002, reword "A turn ends only at a hard gate, at the final message, or while agents are running" to "... or while agents run in the background (spawned without the parameter, or moved there with Ctrl+B); then say which are pending and continue when they report" (contracts/outputs.md, second quote)
- [x] T004 [P] [US1] In `docs/design.md` (Claude Code facts), extend the line "Subagents spawned from the main session run in the background by default": with fork mode off (`CLAUDE_CODE_FORK_SUBAGENT=0`), `run_in_background: false` makes them block, and the coordinators pass it (docs/install.md section 6)
- [x] T005 [US1] Run `mise run lint` and `mise run test:step`; confirm `.apm/skills/feat/scripts/step.sh`, `tests/step` and `.apm/skills/brief/`, `.apm/skills/tiny/` have no diff (FR-002, FR-013)

**Checkpoint**: US1 complete; the rule works for users who set the variable themselves.

---

## Phase 4: User Story 2 - Learn the setting exists (Priority: P2)

**Goal**: A user who has not chosen sees the opt-in note in setup, in `install.sh check` and in the docs.

**Independent Test**: `mise run test:preflight` passes with the new cases; `CLAUDE_CODE_FORK_SUBAGENT=0 ./install.sh check` prints `ok`, any other value prints the `note` line, exit code unchanged.

- [x] T006 [US2] In `.apm/skills/feat/scripts/preflight.sh`: add `'spawn note') S=28 ;;` to `slot()`; right after `emit kind "$kind"` in mode 1 add `[ -n "${CLAUDE_CODE_FORK_SUBAGENT:-}" ] || emit 'spawn note' '<constant from contracts/outputs.md>'`; add `spawn note` before `stop` in the header comment key list. Bash 3.2, shellcheck clean, no exit-code change, nothing in worktree mode or on `die_usage`
- [x] T007 [P] [US2] In `specs/016-setup-trail-scripts/contracts/preflight.md`, add the `spawn note` key (after `searched`, before `stop`, with its condition) to the output list and update the `empty` row and the refused-kind sentence to include it (FR-006)
- [x] T008 [P] [US2] In `.apm/skills/feat/SKILL.md` setup step 1, add the bullet before the exit bullets: "A `spawn note:` line, whatever the exit: show its value as is; it never stops the run." (FR-005, FR-007)
- [x] T009 [P] [US2] In `.apm/skills/fix/SKILL.md` setup step 1, add the same bullet as T008
- [x] T010 [US2] In `tests/preflight/run.sh`, export `CLAUDE_CODE_FORK_SUBAGENT=0` with the top-of-file environment; add a "spawn note" section: unset (golden `tests/preflight/expected/feat-resume-note.out` for `feat resume`: kind, install, hooks allowed, spawn note), empty (line present), `0`, `1` and another value (no `spawn note:` key), a refused kind with the variable unset (exit 1, note present, last line `stop:`), worktree mode unset (no key, exit 0), using `expect_line`, `expect_no_key`, `expect_exit`, `expect_last`; run `mise run test:preflight`
- [x] T011 [P] [US2] In `install.sh`, after the python3 check line, add the `ok` (value `0`) or `note` (anything else) line from contracts/outputs.md, from `${CLAUDE_CODE_FORK_SUBAGENT:-}`; not counted in `missing`, exit code unchanged, value never echoed, the note says to run check from a Claude Code session (`! ./install.sh check`); shellcheck clean
- [x] T012 [US2] In `docs/install.md`: add section "## 6. Wait for agents (optional)" (same heading style as the other sections): the `"env": {"CLAUDE_CODE_FORK_SUBAGENT": "0"}` setting, the gain (one model call per agent spawn in interactive sessions, no number), the three locations (`<repo>/.claude/settings.local.json` recommended: just you, just that repo, not committed; `~/.claude/settings.json`: every project, plain sessions change too, the `fork` agent type goes away; not `.logistics.yml`: committed, shared, this is personal), `1` keeps background spawns and hides the note, the trade-off (typed message waits; **Esc kills the running agent**; Ctrl+B moves it to the background and the run continues the async way), and that `install.sh check` sees the value only from a Claude Code session; update the `check` paragraph in section 4

**Checkpoint**: US2 complete; preflight tests pass.

---

## Phase 5: User Story 3 - Measure the gain (Priority: P3)

**Goal**: `measure.py` reports `text only after a spawn` per run, in medians, `--session` and `--compare-since`.

**Independent Test**: `mise run test:measure` passes: async fixture shows 2, foreground fixture 0.

- [x] T013 [US3] In `.apm/skills/feat/scripts/measure.py`: add `WAIT_TOOLS = SPAWN_TOOLS + ("SendMessage",)` next to `SPAWN_TOOLS`; in `_parse_session` track `open_ids`, `batch_mid`, `armed`, `firsts` per plan.md section 4, compute `after_spawn` (firsts whose call has no tools, after `calls.finish()`) and add it to the run dict; in `run_figures` set `coord["after_spawn"]`; in `render_block` add `row("text only after a spawn", fnum(c["after_spawn"]))` after `text only`, and the same key and label in `render_compare` after `text`. `SPAWN_TOOLS` and all other figures unchanged; Python 3.11 stdlib only
- [x] T014 [P] [US3] Create synthetic fixtures `tests/measure/fixtures/edge/edge/sess-async-1.jsonl` (+ `sess-async-1/subagents/` transcripts): a `/feat` run with two background spawns, each result `async_launched` and followed by a text-only turn, then the peer report and a Bash call (count 2); and `sess-fg-1.jsonl` (+ `sess-fg-1/subagents/`): a two-spawn foreground batch and a foreground shipper, results `completed` and followed by a Bash call, then final text (count 0). Shape them like `sess-note-1`, with `SECRET-` sentinels in free text
- [x] T015 [US3] In `tests/measure/run.sh` add two `--session` cases grepping `  text only after a spawn` (expect 2 and 0), change the `edge` case's line to `runs: 4 counted (4 finished, 0 unfinished, 0 resumed), 1 left out`, write the per-fixture counts in the arithmetic comment (sess-feat-1 1, sess-feat-2 2, sess-feat-3 1, sess-feat-6 2, sess-fix-1 1; `/feat` median 1.5), and add the row to every golden in `tests/measure/expected/`; run `mise run test:measure`
- [x] T016 [P] [US3] In `docs/measure.md`, "The figures", Coordinator list: add the row `text only after a spawn` with its definition (spawn batch, first coordinator call after its last result, tools `Agent`, `Task`, `SendMessage`), what it shows (the waiting turn of background spawns; about 0 with foreground spawns, `SendMessage` continuations aside), and a link to `install.md` section 6

**Checkpoint**: US3 complete; measure tests pass.

---

## Phase 6: Polish

- [x] T017 Run `mise run lint`, `mise run test:apm`, `mise run test:preflight`, `mise run test:measure`, `mise run test:step`; fix any failure (shellcheck, harness.md greps, python 3.11 syntax)
- [x] T018 Walk through `specs/018-foreground-spawns/quickstart.md` and confirm each scenario holds; confirm no diff in CHANGELOG.md, versions, `step.sh`, `/brief`, `/tiny`

---

## Dependencies & Execution Order

- Phase 1 first. No Phase 2. US1, US2, US3 are independent after T001; priority order P1, P2, P3.
- T003 follows T002 (same file). T005 follows T002-T004.
- T006 before T010 (tests need the key); T007-T009 and T011 are parallel with T006 (different files); T012 after T011 (documents its wording).
- T013 before T015; T014 parallel with T013; T015 needs T013 and T014; T016 parallel.
- Polish after all stories.

## Parallel Example

```text
US2: T007, T008, T009, T011 together after (or alongside) T006
US3: T013 with T014 and T016
```

## Implementation Strategy

- MVP: T001-T005 (US1): the rule alone delivers the saving for a user who sets the variable.
- Then US2 (discoverability), then US3 (measurement), then Polish. Do not commit; the orchestrator handles it.
