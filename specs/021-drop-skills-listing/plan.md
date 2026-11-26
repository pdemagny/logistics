# Implementation Plan: Drop the skills listing from the implementer's, reviewers' and bug assessor's starting context

**Branch**: `drop-skills-listing` | **Date**: 2026-11-26 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/021-drop-skills-listing/spec.md` (issue #101)

## Summary

The four agents that still keep `Skill` (implementer, code reviewer,
design reviewer, bug assessor) deny it, so their first request carries no
skills listing. Every skill they run besides the implementer's preloaded
`speckit-implement` is read as a file: `preflight.sh` resolves each needed
skill at setup (project `.claude/skills`, then `~/.claude/skills`), prints
`skill <name>: <path>` lines and stops the run on a missing one; the
coordinator passes those lines to every spawn (one rule in `harness.md`);
each agent reads the `SKILL.md` at its line and follows it. Lint checks
that all nine agents deny `Skill`; docs describe the new stop.

## Technical Context

**Language/Version**: Bash 3.2 (`preflight.sh`, its tests, the lint
one-liner); Markdown prompts (agents, skills, `harness.md`, docs).

**Primary Dependencies**: none new. Spec Kit (specify-cli 1.2.1, pinned
in `mise.toml`) is read for its hook-to-skill naming only (research R1).

**Storage**: N/A (no state-file field, no `sizes.json` change).

**Testing**: `tests/preflight/run.sh` (throwaway repos, stub `gh` and
tracker, golden outputs; `UPDATE=1` regenerates), `mise run lint`,
`mise run test:apm`, the other `test:*` tasks; measured spawns by hand
(`quickstart.md`).

**Target Platform**: Claude Code, all three distributions (APM, plugin,
`install.sh`).

**Project Type**: Claude Code skill and agent package.

**Performance Goals**: about 30k characters less in every model call of
the four agents' spawns; implementer starting context ≤ 27k tokens
(post-merge check, SC-005).

**Constraints**: `preflight.sh` Bash 3.2, no jq, no Python, shellcheck
clean; report formats unchanged; no `/feat`-only words in `harness.md`;
coordinators read no skill.

**Scale/Scope**: 4 agent files, `preflight.sh` and its tests, 2
coordinator skills, `harness.md`, `mise.toml`, 3 docs pages,
`.claude/CLAUDE.md`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- I Thin coordinators: pass. The coordinators pass `preflight.sh`'s lines
  on, as data; they read no skill. The new work is in `preflight.sh` and
  the agents.
- II The user decides at gates: pass. No gate changes; a missing skill
  stops at setup instead of letting a lens improvise.
- III One source of truth: pass. One resolver (the bug-skill search is
  folded into it); the spawn rule lives once in `harness.md`; `sizes.json`
  and its copies are untouched except the hand-owned "Denied tools" cells
  of the agents table, which `sizes.py` keeps and re-pads.
- IV Fixed report formats: pass. No format changes, so `step.sh` and
  `tests/step` don't change.
- V Small and plain: pass. Each agent gains one short paragraph and loses
  ~30k characters of listing; the resolver is a small bash function with
  offline tests.
- Distribution: pass. Nothing new to ship; `preflight.sh` already ships
  in all three. The lens names and install line in `preflight.sh` join
  the third-party-skill checklist in `.claude/CLAUDE.md`.

Post-design re-check: pass (no violation; Complexity Tracking empty).

## Project Structure

### Documentation (this feature)

```text
specs/021-drop-skills-listing/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── preflight-skills.md
│   └── skills-by-path.md
└── tasks.md             # phase 5
```

### Source Code (repository root)

All files exist; none is created.

```text
.apm/skills/feat/scripts/preflight.sh     # resolver, skill lines, stops
tests/preflight/run.sh                    # new cases; skills in the template and new_case
tests/preflight/expected/*.out            # regenerated (skill lines), reviewed
.apm/agents/feat-implementer.agent.md     # deny Skill; Skills by path; bug mode, hooks
.apm/agents/feat-code-reviewer.agent.md   # deny Skill; Skills by path; 7b, 7c
.apm/agents/feat-design-reviewer.agent.md # deny Skill; Skills by path; 4a
.apm/agents/feat-bug-assessor.agent.md    # deny Skill; Skills by path; assess, test, hooks
.apm/skills/feat/references/harness.md    # one bullet: pass the skill lines
.apm/skills/feat/SKILL.md                 # setup keeps skill lines; hook-gate reason
.apm/skills/fix/SKILL.md                  # setup keeps skill lines
mise.toml                                 # lint: every agent denies Skill too
docs/workflow.md                          # agents table, denial sentence, setup, hook reason
docs/install.md                           # the setup stop for a missing skill
docs/design.md                            # hook row and skills: note
.claude/CLAUDE.md                         # third-party-skill checklist names preflight.sh
```

**Structure Decision**: changes stay in the files that own each rule;
no new file outside this feature dir.

## How

### 1. `preflight.sh` (FR-003–FR-007, FR-013)

- `skill_path <name>`: `SP` = `$top/.claude/skills/<name>/SKILL.md` if it
  is a file, else `$HOME/.claude/skills/<name>/SKILL.md` if `HOME` is set
  and it is a file; return 1 otherwise. It replaces the bug check's
  `dirs=…` loop (research R2). `$top` is where preflight runs: the main
  checkout for a new run (before `EnterWorktree`), the worktree on resume.
  The path is printed as found and never rewritten to point into the
  worktree, so for a new run a project skill's path is outside the
  spawn's worktree cwd, like a `~/.claude/skills` one; the measured spawns
  check both for a permission prompt (quickstart step 5).
- `need_skill <name>`: emits `skill <name>: <SP>` once per run (a
  space-separated seen list, Bash 3.2 has no associative arrays); returns
  1 when `skill_path` fails.
- `hook_skill <command>`: `HS` = `speckit-` + the part after `speckit.`
  with `.` → `-`; return 1 for an empty command or one not starting
  `speckit.` (research R1).
- `slot()`: key pattern `skill *` gets the slot after `hooks allowed`;
  `slug`, `pointer`, `searched`, `spawn note` and the worktree keys shift
  by one. Header comment's key list gains `skill <name>`.
- `step_install`: after the agents check, `/fix` needs the three bug
  skills (all kinds): missing ones → the bug stop. Deliberately stricter
  than today, where the `.specify/extensions/bug` dir alone or any one
  bug skill dir passes (FR-007); docs/install.md and the PR body say so. Then, unless `kind` is
  `rebase`, both lens skills: missing ones → the lens stop. Texts:
  `contracts/preflight-skills.md`. `install: ok` and `bug extension:`
  unchanged.
- `step_hooks`: unless `kind` is `rebase`, each hook that goes to
  `allowed` → `hook_skill` then `need_skill`; a failure adds `<label>
  (<name> not found | maps to no skill)` to a missing list. Each flagged
  hook (`hook would branch or commit:`) → `need_skill` when it maps,
  failure ignored. `hook won't run` hooks are skipped as today. After the
  loop and the `hooks allowed:` line, a non-empty missing list → the hook
  stop. The comment "the specifier, planner and tasker can't run hooks"
  stays true and stays.

### 2. `tests/preflight` (FR-012)

- Template repo: commit `.claude/skills/speckit-bug-{assess,fix,test}/SKILL.md`
  (as `specify extension add bug` does). `new_case`: put both lens skills
  under `$c/home/.claude/skills/`. A helper `skill_in <project|home> <name>…`
  creates `SKILL.md` files.
- Hook cases whose hooks are allowed (`hooks-feat`, `hooks-fix`, the
  indented-lists, flagged-by-name, from-origin and resume cases) install
  those hooks' skills so they still test the sorting.
- `install-no-bug` and its "a speckit-bug skill instead" follow-up: now
  the three skills decide (the extension dir alone, or one skill, is no
  longer enough); `bug extension: unknown` still covered.
- New cases: lens in project; in home; in both (project wins); each lens
  missing and both (stop, install line); allowed hook resolved (line with
  its path); allowed hook's skill missing (stop naming hook and
  `enabled: false`); hook with a non-`speckit.` command and one with no
  command (maps to no skill); flagged hook found (line) and missing (no
  stop); two hooks on one skill (one line); `/fix` bug skills lines and
  one missing; `rebase` with no lens skill (exit 0, no lens line);
  `resume` resolving from the checkout.
- `UPDATE=1 bash tests/preflight/run.sh`, then review `git diff
  tests/preflight/expected`: only added `skill` lines and the changed
  stops.

### 3. The four agents (FR-001, FR-002, FR-009, FR-010)

Per `contracts/skills-by-path.md`: add `Skill` to `disallowedTools`; one
**Skills by path** paragraph each (next to the existing "Spec Kit hooks"
paragraph in the implementer and the assessor; next to "Read a lens's
skill only when you run that lens" in the reviewers); the in-place wording
changes in its table. The implementer keeps `skills: speckit-implement`.
Report formats untouched.

### 4. Coordinators and `harness.md` (FR-008)

- `harness.md`: one bullet in "Give each one, in its prompt" (contract
  text). The lint grep for `/feat`-only words must stay clean: the bullet
  says "setup" and "resume", nothing else.
- `/feat` `SKILL.md` setup step 1: `kind: brief` keeps the `skill` lines
  too; step 3's reason "(`Skill` is denied)" becomes "(they run no
  hooks)" since the implementer now denies `Skill` and still runs hooks.
- `/fix` `SKILL.md` setup step 2: `kind: issue` or `symptom` keeps the
  `skill` lines too. Resume in both: covered by the harness bullet.
- `/tiny`: no change (lens 7a reads no skill).

### 5. Lint (FR-011)

`mise.toml` lint: the `disallowedTools` loop checks `Artifact
EnterWorktree Skill`; the task description says so.

### 6. Docs (FR-014, US4)

- `docs/workflow.md`: add `Skill` to the four rows' "Denied tools" cells,
  then `mise run diagrams` (re-pads the table; `sizes.py --check` in lint
  confirms; `docs/img` should not change); the sentence becomes "Every
  agent denies `Artifact`, `EnterWorktree` and `Skill` (`mise run lint`
  checks it): the implementer, reviewers and assessor read a skill's
  `SKILL.md` at the path setup resolved"; the `/feat` setup bullet and the
  `/fix` setup paragraph mention the skill resolution and its stop; the
  hook bullet's "(`Skill` is denied)" reason as in `/feat`.
- `docs/install.md` section 2: setup resolves the lens skills (and the
  bug skills, section 3) in `<project>/.claude/skills` then
  `~/.claude/skills`, stops naming the missing one and this install line;
  a plugin-only copy isn't found. Hooks: an allowed hook whose skill isn't
  installed stops setup; disable it with `enabled: false`. Next to that
  note, section 3: as a deliberate change, `/fix` setup now needs all
  three bug skills installed (the extension dir alone, or one of them, no
  longer passes). The allow rule only for a location the measured spawns
  prompted on (quickstart step 5): `Read(~/.claude/skills/**)`, and the
  main checkout's `.claude/skills` dir.
- `docs/design.md`: the hook row's "(`Skill` is denied; …)" and the
  `skills:` note say the agents read skills by path.
- `.claude/CLAUDE.md`: the third-party-skill checklist adds
  `preflight.sh`'s lens list and install line.

### 7. Verification and PR

`quickstart.md`: offline checks, the lint guard, the measured spawns
(SC-001–SC-003, numbers for the PR body, the permission check on both
skill locations), the PR body items (`Closes #101`, before/after, the
post-merge check, and the two deliberate stricter setup stops: an allowed
hook whose skill can't be resolved, `/fix` needing all three bug skills).

## Complexity Tracking

None.
