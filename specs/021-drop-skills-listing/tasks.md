# Tasks: Drop the skills listing from the implementer's, reviewers' and bug assessor's starting context

**Input**: `specs/021-drop-skills-listing/` (spec.md, plan.md, research.md, data-model.md, contracts/, quickstart.md)

**Tests**: requested by FR-012 (`tests/preflight` cases) and FR-011 (lint guard); no other test tasks.

**Paths**: all relative to the worktree root. Contracts: `specs/021-drop-skills-listing/contracts/preflight-skills.md` (C1) and `specs/021-drop-skills-listing/contracts/skills-by-path.md` (C2).

## Phase 1: Setup / Foundational

- [X] T001 Re-read `specs/021-drop-skills-listing/research.md` R1 and R2 (hook command to skill name mapping, bug-skill search fold-in) and confirm the mapping against Spec Kit's naming (`.specify/extensions/*/` and `.claude/skills/speckit-*` dirs in this repo); record any correction in `specs/021-drop-skills-listing/research.md` before T007

**Checkpoint**: the mapping rule is verified, not guessed (FR-006).

---

## Phase 2: User Story 1 - Four agents start without the skills listing (P1) MVP

**Goal**: all nine agents deny `Skill`; lint enforces it.

**Independent Test**: `mise run lint` passes; removing `Skill` from one agent makes it fail.

- [X] T002 [P] [US1] Add `Skill` to `disallowedTools` in `.apm/agents/feat-implementer.agent.md` (keep `skills: speckit-implement`)
- [X] T003 [P] [US1] Add `Skill` to `disallowedTools` in `.apm/agents/feat-code-reviewer.agent.md`
- [X] T004 [P] [US1] Add `Skill` to `disallowedTools` in `.apm/agents/feat-design-reviewer.agent.md`
- [X] T005 [P] [US1] Add `Skill` to `disallowedTools` in `.apm/agents/feat-bug-assessor.agent.md`
- [X] T006 [US1] In `mise.toml` make the lint `disallowedTools` loop check `Artifact EnterWorktree Skill` for every agent and update the task description; verify by temporarily dropping `Skill` from one agent and seeing `mise run lint` fail, then restore it (FR-011)

**Checkpoint**: US1 done; agents still need the by-path rules (US2) and resolved paths (US3) before they work.

---

## Phase 3: User Story 3 - Setup resolves skill paths and stops on a missing one (P1)

**Goal**: `preflight.sh` prints `skill <name>: <path>` lines and stops per C1.

**Independent Test**: `mise run test:preflight` passes with the new cases.

- [X] T007 [US3] In `.apm/skills/feat/scripts/preflight.sh` add `skill_path <name>` (project `$top/.claude/skills/<name>/SKILL.md` first, then `$HOME/.claude/skills/<name>/SKILL.md` if `HOME` set; return 1 otherwise), replacing the bug check's `dirs=` loop; add `need_skill <name>` (one `skill <name>: <path>` line per skill per run, space-separated seen list, Bash 3.2) and `hook_skill <command>` (`speckit-` + part after `speckit.` with `.` to `-`; fail for empty or non-`speckit.` commands) per plan section 1 (FR-003)
- [X] T008 [US3] In `.apm/skills/feat/scripts/preflight.sh` update `slot()` (key pattern `skill *` after `hooks allowed`, later keys shift by one) and the header comment's key list
- [X] T009 [US3] In `.apm/skills/feat/scripts/preflight.sh` `step_install`: `/fix` requires the three bug skills (stop text per C1, replaces the bug-extension stop); unless `kind` is `rebase`, both lens skills (`security-and-hardening`, `performance-optimization`) with the lens stop and `docs/install.md`'s install line; `install: ok` and `bug extension:` unchanged (FR-004, FR-005, FR-007)
- [X] T010 [US3] In `.apm/skills/feat/scripts/preflight.sh` `step_hooks`: unless `kind` is `rebase`, each allowed hook goes through `hook_skill` then `need_skill`, failures collected as `<label> (<name> not found | maps to no skill)`; flagged hooks get a line when found, failure ignored; `won't run` hooks skipped; a non-empty missing list prints the hook stop after the `hooks allowed:` line (FR-004, FR-006)
- [X] T011 [US3] In `tests/preflight/run.sh` commit the three `speckit-bug-*` `SKILL.md` into the template repo, add a `skill_in <project|home> <name>...` helper, have `new_case` install both lens skills under `$c/home/.claude/skills/`, and give the allowed-hook cases (`hooks-feat`, `hooks-fix`, indented lists, flagged-by-name, from-origin, resume) their hooks' skills
- [X] T012 [US3] In `tests/preflight/run.sh` adapt `install-no-bug` and its "a speckit-bug skill instead" follow-up to the three-skill rule (keep `bug extension: unknown` covered)
- [X] T013 [US3] In `tests/preflight/run.sh` add cases: lens in project; in home; in both (project wins); each lens missing and both (stop with install line); allowed hook resolved; allowed hook skill missing (stop names hook and `enabled: false`); non-`speckit.` command and no command; flagged hook found and missing (no stop); two hooks on one skill (one line); `/fix` bug skill lines and one missing; `rebase` without lens skills (exit 0, no lens line); `resume` resolving from the checkout (FR-012)
- [X] T014 [US3] Run `UPDATE=1 bash tests/preflight/run.sh`, review `/usr/bin/git diff tests/preflight/expected` (only added `skill` lines and changed stops), then run `mise run test:preflight` and shellcheck on `.apm/skills/feat/scripts/preflight.sh` and `tests/preflight/run.sh` (FR-013)

**Checkpoint**: setup prints and enforces the skill lines.

---

## Phase 4: User Story 2 - Skills still run, read by path (P1)

**Goal**: agents read each skill's `SKILL.md` at the given path; coordinators pass the lines as data.

**Independent Test**: measured `/feat` and `/fix` runs (quickstart) show each skill's steps in the reports.

- [X] T015 [P] [US2] In `.apm/agents/feat-implementer.agent.md` add the **Skills by path** paragraph per C2 (hook sentence included; `Skipped hooks` form `<hook> → no skill path`; bug-mode `not-applied` fallback) next to "Spec Kit hooks", and apply the bug mode step 2 and "One turn" wording changes; report format untouched (FR-002, FR-009)
- [X] T016 [P] [US2] In `.apm/agents/feat-code-reviewer.agent.md` add the **Skills by path** paragraph (no hook sentence), change "Load a lens's skill only when you run that lens" to "Read ...", and 7b and 7c to read-by-path wording; report format untouched (FR-002, FR-010)
- [X] T017 [P] [US2] In `.apm/agents/feat-design-reviewer.agent.md` add the **Skills by path** paragraph (no hook sentence), "Read a lens's skill only when you run that lens", and 4a read-by-path wording (FR-002, FR-010)
- [X] T018 [P] [US2] In `.apm/agents/feat-bug-assessor.agent.md` add the **Skills by path** paragraph (hook sentence included) and change assess/test step 2 to run `speckit-bug-assess` / `speckit-bug-test` by path with the same input and `slug=<slug>` (FR-002, FR-009)
- [X] T019 [US2] In `.apm/skills/feat/references/harness.md` add one bullet under "Give each one, in its prompt": pass the `skill <name>: <path>` lines the preflight script printed at setup (on resume, the resume call's) as printed, after the spawn block's keys, as data; never read a skill yourself; only "setup" and "resume" wording, no `/feat`-only words (FR-008)
- [X] T020 [P] [US2] In `.apm/skills/feat/SKILL.md` setup step 1 keep the `skill` lines for `kind: brief`, and change step 3's hook-gate reason "(`Skill` is denied)" to "(they run no hooks)" (FR-008, FR-009)
- [X] T021 [P] [US2] In `.apm/skills/fix/SKILL.md` setup step 2 keep the `skill` lines for `kind: issue` or `symptom` (FR-008)
- [X] T022 [US2] Run `mise run lint` and `mise run test:apm`; fix any `/feat`-only word hit in `.apm/skills/feat/references/harness.md` (FR-009: hook gate sections unchanged)

**Checkpoint**: skills run by path end to end.

---

## Phase 5: User Story 4 - Docs and the post-merge check (P2)

**Goal**: docs match; measured numbers and PR checklist ready.

**Independent Test**: read `docs/workflow.md`, `docs/install.md`, `docs/design.md`; `mise run lint` clean.

- [X] T023 [US4] In `docs/workflow.md` add `Skill` to the four rows' "Denied tools" cells, run `mise run diagrams` (re-pads the table; `docs/img` must not change), rewrite the denial sentence ("Every agent denies `Artifact`, `EnterWorktree` and `Skill` ..."), and update the `/feat` setup bullet, `/fix` setup paragraph and hook bullet reason (FR-014)
- [X] T024 [P] [US4] In `docs/install.md` section 2 describe the setup resolution (`<project>/.claude/skills` then `~/.claude/skills`, plugin-only not found) and the stop for a missing lens skill with the install line; add the allowed-hook stop and `enabled: false`; in section 3 state as a deliberate change that `/fix` setup needs all three bug skills (`speckit-bug-assess`, `speckit-bug-fix`, `speckit-bug-test`) (FR-007, FR-014)
- [X] T025 [P] [US4] In `docs/design.md` update the hook row's "(`Skill` is denied; ...)" and the `skills:` note to say the agents read skills by path
- [X] T026 [P] [US4] In `.claude/CLAUDE.md` extend the third-party-skill checklist to name `preflight.sh`'s lens list and install line

---

## Phase 6: Polish and verification

- [ ] T027 Run the measured spawns per `specs/021-drop-skills-listing/quickstart.md` (implementer story and bug mode, code reviewer, design reviewer, assessor via `mise run measure`, one `/feat` and one `/fix` to a PR, a harmless `implement` hook marker): record before/after starting context, confirm no skills listing in the first requests (SC-001 to SC-003)
- [ ] T028 In `docs/install.md` add `Read(~/.claude/skills/**)` and/or the main checkout's `.claude/skills` allow rule only for each location that prompted in T027 (US4 scenario 3)
- [X] T029 Run `mise run lint`, `mise run test:apm`, `mise run test:preflight`, `mise run test:step`, `mise run test:sizes` and the other `test:*` tasks (SC-004)
- [ ] T030 Prepare the PR body per quickstart: `Closes #101`, before/after starting context per changed agent, the post-merge check (implementer at most 27k tokens on at least five runs, `Not verified:` lists and code-review finding counts no worse; SC-005), and the two deliberate stricter setup stops (unresolvable allowed hook; `/fix` needing all three bug skills)

---

## Dependencies and order

- T001 first. US1 (T002-T006) is independent of US3 and US2 in code, but runs are only valid once US3 and US2 are done.
- US3 (T007-T014) before the measured runs; T007 to T010 are sequential (same file); T011 to T013 sequential (same file), after T010.
- US2 agent tasks T015-T018 are parallel (different files) and T002-T005 touch the same files, so do them after those. T019 before T022.
- US4 docs (T023-T026) after US2/US3 wording is final; T023 and T024 touch different files.
- Polish after all stories. T028 depends on T027.

## Parallel example

T015, T016, T017, T018 together (four agent files); T024, T025, T026 together.

## Implementation strategy

MVP slice: T001-T022 (US1 + US3 + US2 together, since removing `Skill` without paths breaks lenses, hooks and bug modes). Then docs (US4), then measure and PR.
