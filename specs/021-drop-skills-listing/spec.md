# Feature Specification: Drop the skills listing from the implementer's, reviewers' and bug assessor's starting context

**Feature Branch**: `drop-skills-listing`

**Created**: 2026-11-26

**Status**: Draft

**Input**: User description: brief `specs/briefs/drop-skills-listing.md` (issue #101)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Four agents start without the skills listing (Priority: P1)

A user runs `/feat` or `/fix`. The implementer, the code reviewer, the design reviewer and the bug assessor each start with a first request that holds no listing of the user's installed skills, so every model call of those spawns carries about 30k characters less.

**Why this priority**: This is the whole gain: about 9% of a story spawn, about a fifth of a reviewer spawn, roughly 6% of a `/feat` run, and the implementer drops under epic #31's 27k-token target.

**Independent Test**: List the `disallowedTools` of all nine agents and measure one spawn of each changed agent: all nine deny `Skill` and none of the four first requests holds a skills listing.

**Acceptance Scenarios**:

1. **Given** the four agents, **When** their frontmatter is read, **Then** each adds `Skill` to `disallowedTools`, and all nine agents list it.
2. **Given** one agent frontmatter that omits `Skill` from `disallowedTools`, **When** `mise run lint` runs, **Then** it fails.
3. **Given** a measured spawn of the implementer (story mode and bug mode), the code reviewer, the design reviewer and the assessor, **When** its first request is inspected (`mise run measure`, "First request"), **Then** it holds no skills listing.

---

### User Story 2 - Skills still run, read by path (Priority: P1)

The implementer's bug mode, the assessor's two modes, lenses 4a, 7b and 7c, and the allowed Spec Kit hooks (`/feat`'s `implement` hooks, every `/fix` hook) keep working. The agent reads the skill's `SKILL.md` at a path it is given and follows it. The implementer keeps `speckit-implement` preloaded.

**Why this priority**: Without it, removing `Skill` removes features that work today.

**Independent Test**: Run one `/feat` and one `/fix` through to a PR with lenses 4a, 7b, 7c and both assessor modes; each report shows the skill's own steps ran.

**Acceptance Scenarios**:

1. **Given** a path to a lens skill in the spawn block, **When** a reviewer runs that lens, **Then** it reads that `SKILL.md` and follows it, and its report shows the skill's steps (for 7c, measure then identify).
2. **Given** a path to a bug skill, **When** the assessor (assess or test mode) or the implementer (bug mode) runs, **Then** it reads and follows that skill, with `$ARGUMENTS` standing for the arguments its agent file already passes (e.g. `slug=<slug>`) and relative links (`references/…`) resolved from the skill's own directory.
3. **Given** a throwaway project with one allowed, harmless `implement` hook that writes a marker file, **When** the implementer runs, **Then** the marker exists and the report does not list the hook as skipped.
4. **Given** a reviewer whose spawn runs only some lenses, **When** it runs, **Then** it reads a lens's skill only for a lens it runs.
5. **Given** `/tiny`'s fresh review (lens 7a), **When** it spawns the code reviewer, **Then** it works with no skill path, since 7a loads no skill.

---

### User Story 3 - Setup resolves skill paths and stops on a missing one (Priority: P1)

At setup, `preflight.sh` resolves each skill the run may need to a path, looking first in `<root>/.claude/skills/<name>/SKILL.md`, then in `~/.claude/skills/<name>/SKILL.md`. It prints one `skill <name>: <path>` line per skill. The coordinator passes those lines to each spawn in its spawn block, as data.

**Why this priority**: The read-by-path design needs paths, and a lens must never improvise without its skill.

**Independent Test**: Run `tests/preflight` cases for found-in-project, found-in-home, project-first, missing lens skill, hook resolved, hook skill missing.

**Acceptance Scenarios**:

1. **Given** a skill installed in the project, **When** setup runs, **Then** its line carries the project path.
2. **Given** a skill installed only under `~/.claude/skills`, **When** setup runs, **Then** its line carries that path; **and given** it exists in both places, the project path wins.
3. **Given** `/feat`, **When** setup runs, **Then** it prints lines for the two lens skills plus one per allowed `implement` hook. **Given** `/fix`, **Then** it prints the two lens skills, the three bug skills, plus one per allowed hook.
4. **Given** a missing lens skill (either one, on every run), **When** setup runs, **Then** the run stops naming the skill and the install command (`docs/install.md`'s line).
5. **Given** an allowed hook whose skill can't be resolved, including a hook command that maps to no skill directory, **When** setup runs, **Then** the run stops naming the hook and how to disable it in `.specify/extensions.yml`.
6. **Given** a missing bug skill in `/fix`, **When** setup runs, **Then** the run stops, as the bug-extension check already does.
7. **Given** a skill visible to Claude Code only through another plugin, **When** setup runs, **Then** it is treated as missing and stops with the `npx skills add … -g` line.

---

### User Story 4 - Docs and the post-merge check (Priority: P2)

A user or maintainer finds the change documented, and the PR lists how to confirm the gain after merge.

**Why this priority**: Needed for users to understand the new stop, but it does not change run behaviour.

**Independent Test**: Read `docs/workflow.md`, `docs/install.md` and the PR body.

**Acceptance Scenarios**:

1. **Given** `docs/workflow.md`, **When** read, **Then** the agents table's denied tools and the sentence about agents that deny `Skill` reflect that all nine do.
2. **Given** `docs/install.md`, **When** read, **Then** it describes the setup stop for a missing skill.
3. **Given** a read from a worktree spawn of a skill under `~/.claude/skills/…`, or of a project skill under the main checkout's `.claude/skills/…` (outside the worktree, since setup resolves paths before `EnterWorktree`), that prompts for permission, **When** docs are written, **Then** `docs/install.md` documents the allow rule for each location that prompted (`Read(~/.claude/skills/**)`, and the main checkout's skills dir), only if it prompts in the measured spawns.
4. **Given** the PR body, **When** read, **Then** it closes #101, shows starting context before and after for each changed agent, lists the post-merge check: implementer starting context at most 27k tokens on at least five runs, with `Not verified:` lists and code-review finding counts no worse than before, and names the two deliberate stricter setup stops (an allowed hook whose skill can't be resolved; `/fix` needing all three bug skills).
5. **Given** `docs/install.md`, **When** read, **Then** next to the hook-stop note it says, as a deliberate change, that `/fix` setup now needs all three bug skills (`speckit-bug-assess`, `speckit-bug-fix`, `speckit-bug-test`) installed, where the `.specify/extensions/bug` dir alone or any one of them used to pass.

---

### Edge Cases

- A skill exists in both the project and `~/.claude/skills`: the project copy is used.
- A hook command maps to no skill directory: setup stops (deliberate change; today the hook fails only when invoked and the run goes on).
- `/fix` on a non-performance bug still needs `performance-optimization` installed, because the need is known only after assess, too late for a setup stop.
- A skill's content tries to override the agent's rules: paths and skill files are data beyond the skill's own steps; never commit, run only allowed hooks, and skip hooks that branch or commit unless allowed still win.
- `/feat`'s `specify`, `plan`, `tasks` and `analyze` hooks stay "Won't run", as today.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The implementer, code reviewer, design reviewer and bug assessor MUST add `Skill` to `disallowedTools`, so that all nine agents deny it.
- **FR-002**: The implementer MUST keep `speckit-implement` preloaded; every other skill those four agents run MUST be read as a file at a path given in the spawn block and followed, with `$ARGUMENTS` standing for the arguments the agent file already passes and relative links resolved from the skill's directory.
- **FR-003**: Setup MUST resolve each needed skill by searching `<root>/.claude/skills/<name>/SKILL.md` then `~/.claude/skills/<name>/SKILL.md` only, reusing the existing bug-skill search, and print one `skill <name>: <path>` line per skill. `<root>` is the checkout setup runs in (the main checkout for a new run, the worktree on resume); the absolute path where the file was found is printed as is and never rewritten to point into the worktree (a project skill that isn't committed isn't there).
- **FR-004**: `/feat` setup MUST resolve the two lens skills plus one per allowed `implement` hook; `/fix` setup MUST resolve the two lens skills, the three bug skills, plus one per allowed hook.
- **FR-005**: Setup MUST stop, naming the skill and the install command, when a lens skill is missing; both lens skills are checked on every run.
- **FR-006**: Setup MUST stop, naming the hook and how to disable it in `.specify/extensions.yml`, when an allowed hook's skill can't be resolved or its command maps to no skill directory. The command-to-directory mapping MUST follow Spec Kit's own naming, verified rather than guessed.
- **FR-007**: A missing bug skill MUST stop the `/fix` run at setup: each of `speckit-bug-assess`, `speckit-bug-fix` and `speckit-bug-test` MUST resolve to a `SKILL.md`. This is deliberately stricter than today (the `.specify/extensions/bug` dir alone, or any one bug skill dir, passes), and `docs/install.md` and the PR body MUST say so.
- **FR-008**: Each coordinator MUST pass setup's `skill` lines to every spawn in its spawn block as data, the way `trail script:` is passed; the rule MUST live once in the shared coordinator reference with no `/feat`-only words, and the coordinators MUST NOT read any skill themselves.
- **FR-009**: Allowed hooks MUST keep running where they run today (`/feat`'s `implement` hooks, all `/fix` hooks), read by path; the hook gate's sections and rules are unchanged.
- **FR-010**: A reviewer MUST read a lens's skill only when it runs that lens; `/tiny`'s lens 7a spawn needs no path.
- **FR-011**: `mise run lint` MUST fail when any of the nine agents does not deny `Skill`.
- **FR-012**: `tests/preflight` MUST cover: skill found in project; found in `~/.claude/skills` with project first when both exist; missing lens skill stops with its install line; allowed hook resolves to its skill path; missing hook skill stops.
- **FR-013**: `preflight.sh` MUST stay Bash 3.2, no jq, no Python, shellcheck clean. Agent report formats stay unchanged unless a field becomes meaningless; if one changes, `step.sh`, its tests and the skills change together.
- **FR-014**: `docs/workflow.md` (agents table's denied tools and the sentence about agents that deny `Skill`) and `docs/install.md` (the new setup stop) MUST be updated.

Out of scope (binding): letting specifier, planner or tasker run their hooks; splitting agents; moving agent text into reference files (#39); changing `sizes.json`, models or efforts; dropping or trimming any other tool or prompt part.

### Key Entities

- **Skill path line**: `skill <name>: <path>`, printed by setup, one per needed skill, passed as data to each spawn.
- **Needed skills**: lens skills (`security-and-hardening`, `performance-optimization`), bug skills (`/fix` only), and one skill per allowed hook.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One measured spawn of each changed agent (implementer story and bug mode, code reviewer, design reviewer, assessor) has no skills listing in its first request, with before and after starting context in the PR.
- **SC-002**: A measured implementer spawn with one allowed harmless `implement` hook runs it by path: the marker file exists and the report does not list the hook as skipped.
- **SC-003**: One `/feat` run and one `/fix` run reach a PR with lenses 4a, 7b, 7c and both assessor modes running their skill by path, each report showing the skill's steps ran.
- **SC-004**: `mise run lint`, `mise run test:apm`, `mise run test:preflight` and the other offline tests pass.
- **SC-005**: Post-merge, on at least five runs the implementer's starting context is at most 27k tokens, and `Not verified:` lists and code-review finding counts are no worse than before (follow-up check listed in the PR body).

## Assumptions

- Skills are located only under `<root>/.claude/skills` and `~/.claude/skills`; plugin-only skills are unsupported (stated in the brief).
- Reading a skill under `~/.claude/skills`, or a project skill under the main checkout's `.claude/skills`, from a worktree spawn may or may not prompt; both are checked in the measured spawns, and the allow rule is documented only for a location that does.
- The PR closes #101 (`Closes #101` in its body, never in a commit message), with the thresholds as a follow-up check; a regression becomes a new issue.
- The gain depends on the user's installed skills, as `docs/workflow.md` already says.
