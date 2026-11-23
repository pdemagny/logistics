---
title: Design notes
weight: 40
---

# Design notes

Why the workflow is built as one orchestrating skill plus phase subagents,
and the Claude Code behaviour it relies on. Checked against the Claude Code
docs ([skills](https://code.claude.com/docs/en/skills),
[subagents](https://code.claude.com/docs/en/sub-agents)) as of v2.1.308.

## The goal

Different phases need different capability: an interview and a plan reward
the strongest model, ticking off a well-specified task list or scanning a
diff for dead code doesn't. Running everything on the session model wastes
money on the easy phases or quality on the hard ones.

## Ways Claude Code lets you choose a model

| Mechanism                                 | Scope                                                                              | Fit                                                                    |
| ----------------------------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `model:` in an inline skill's frontmatter | the rest of the **current turn**; your next message goes back to the session model | No: every hard gate ends a turn, so it would be lost at the first gate |
| `model:` on the `speckit-*` skills        | same, and those files are regenerated on every Spec Kit upgrade                    | No                                                                     |
| `context: fork` + `model:` in a skill     | runs the whole skill in a subagent                                                 | Only for steps that never ask you anything                             |
| `model:` / `effort:` in a subagent file   | that subagent, for its whole run                                                   | **Yes**                                                                |
| `model` / `effort` on the Agent tool call | that one spawn; overrides the file                                                 | **Yes**: lets one agent serve every size                               |

So: the gated workflow stays in the main session, and every phase that
doesn't need you is a subagent spawned with the model and effort from
`sizes.tsv`, printed by `step.sh` in its spawn block.

## Why the orchestrator model is the session model

The skill can't change the main session's model beyond one turn (above).
Start the session on the model you want orchestrating (Opus recommended);
all gate handling runs on it, and `/brief`'s interview on the session
you run it in.

## Why not make /feat itself an agent

Two other shapes were considered:

1. **The whole workflow as one subagent** (`context: fork` or a `feat`
   agent). Rejected: subagents can't use `AskUserQuestion` and can't hold a
   conversation, and five of the eight phases need your judgment.
2. **`claude --agent feat`**: the agent becomes the main session, so its
   model sticks across turns. Rejected as the default: a custom agent's
   prompt replaces Claude Code's default system prompt entirely, and it
   can't be started automatically from an ordinary session when you ask for
   a feature. It remains possible if you want one dedicated session per
   feature.

## Behaviour this relies on

- **Subagents start with no conversation history.** Hence the state file
  and artifacts as the single source of truth, and prompts that pass paths,
  size, conventions and rejected findings explicitly.
- **Subagents start in the main session's working directory.** The
  orchestrator enters the feature worktree before spawning any.
- **`skills:` preloads a skill's full content** into the subagent at
  startup; the subagent can still invoke other skills through the Skill tool
  if it has it.
- **`AskUserQuestion` is removed from every subagent.** Anything that needs
  you comes back to the orchestrator as an open question.
- **Subagents spawned from the main session run in the background by
  default**, keeping Read, Grep, Glob, Bash, Edit, Write, Skill and a few
  others. The orchestrator ends its turn while they run and continues when
  they report. With fork mode off (`CLAUDE_CODE_FORK_SUBAGENT=0`),
  `run_in_background: false` makes them block, and the coordinators pass it
  (docs/install.md section 6).
- **Subagents may spawn subagents** (up to three levels). Writing agents
  disallow `Agent` to keep cost bounded; no feat agent spawns further
  agents.
- **Read-only reviewers** get no Edit; their Write is for their report
  file only, by instruction, checked by `state.sh snapshot`/`unchanged`
  around each batch (a change elsewhere, the state file aside, is a hard
  gate); their Bash is for
  git and grep only, by instruction.
- **`effort` in an inline skill's frontmatter** has no documented duration,
  so effort is set only on subagents.

## Third-party skills inside the workflow

A skill is written to run on its own: it asks the user, commits, applies its
fixes, ends its turn, hands off to the next skill. Loaded inside this
workflow, every one of those instructions competes with the orchestrator. Each
dependency was checked for that, and handled one of three ways:

| Skill                                                      | Conflicting instructions                                                                                                                                                                                | Handling                                                                                                                                                                                                                                                                                                                                                              |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `spec-driven-development`                                  | its own Specify → Plan → Tasks → Implement pipeline, `SPEC-*.md` at the project root                                                                                                                    | **dropped**; the capability-map part (about 30 lines) is inlined in `SKILL.md`, credited                                                                                                                                                                                                                                                                              |
| `performance-optimization`                                 | measure-first web workflow (Lighthouse, Core Web Vitals), fix, commit after each fix                                                                                                                    | **moved to phase 7** (lens 7c of `feat-code-reviewer`), where there is code to measure: the reviewer does its measure and identify steps; `feat-implementer` in fix mode does fix, re-measure and keep-or-revert; the attempt log goes in the state file; commits stay in phase 8. Phase 4's cost review keeps its own checklist.                                     |
| `incremental-implementation`                               | commit after every slice, "no uncommitted changes remain"                                                                                                                                               | **dropped**; `speckit-implement` already works task by task with checks, and the workflow commits only in phase 8                                                                                                                                                                                                                                                     |
| `interview-me`                                             | its own restate and confirmation, then "offer downstream paths" (save to `docs/intent/`, hand off to `spec-driven-development`) and stop                                                                | **overridden** in `/brief`: its restate is the brief, its confirmation is the gate, its step 6 is skipped                                                                                                                                                                                                                                                             |
| `code-simplification`                                      | applies changes and commits; 13.5KB, mostly language examples; its duplication and dead-code rows overlap lenses 7a and 7d                                                                              | **dropped**; its behaviour-preserving rule, readability signals and over-simplification traps (about 35 lines) are inlined in lens 7e, credited. Applying picked changes one at a time with tests is `feat-implementer`'s fix mode.                                                                                                                                   |
| Matt Pocock's `code-review`                                | asks the user for the fixed point and spec, needs issue-tracker setup, diffs `...HEAD` (empty here), runs its two axes in sub-agents; installed as a skill it would replace the built-in `/code-review` | **dropped**; its standards and spec axes and its Fowler smell baseline (about 40 lines) are inlined in lens 7a, credited. The reviewer runs them as separate passes in its own context instead of two sub-agents.                                                                                                                                                     |
| `speckit-implement`                                        | stops to ask about unchecked checklists                                                                                                                                                                 | **overridden**: the orchestrator asks with the spec summary (at the phase 2 gate, or at the next gate when phase 2 didn't stop), again at phase 5 for items that answer doesn't cover, and passes the answer                                                                                                                                                                                                                                                                                       |
| `speckit-tasks`                                            | runs its prerequisite script with no feature directory given, which finds no unnumbered dir                                                                                                             | **overridden** in `feat-tasker`: the script runs with `SPECIFY_FEATURE_DIRECTORY` (the dir is unnumbered until ship)                                                                                                                                                                                                                                                  |
| `speckit-analyze`                                          | ends by asking whether to suggest remediation; runs its prerequisite script with no feature directory given                                                                                             | **overridden** in `feat-tasker`: always yes for CRITICAL/HIGH; the script runs with `SPECIFY_FEATURE_DIRECTORY` (the dir is unnumbered until ship)                                                                                                                                                                                                                    |
| all `speckit-*`                                            | run mandatory hooks from `.specify/extensions.yml`, which may create branches or commit (git extension)                                                                                                 | **overridden**: phase 0 lists hooks, the user decides, the specifier, planner and tasker run no hook (`Skill` is denied; only their preloaded skills are available) and list each as skipped; other agents run only allowed ones                                                                                                                                                                                                                                                           |
| `ponytail-review`                                          | Ponytail 5 turned it into a general quality review (logic, safety, load, tests, speed), overlapping lenses 7a–7c                                                                                        | **dropped**; the earlier over-engineering-only checklist (about 30 lines) is inlined in lens 7d, credited                                                                                                                                                                                                                                                             |
| Elephant-Goldfish Model's `egm-review`                     | an interactive five-stage pipeline with its own gates, report files written to the project, a resolve loop that edits the document, seven reviewer personas, Apache-2.0                                 | **dropped**; four of its reviewers (comprehension, codebase details, zoom out, implementation readiness) and their standards are condensed into the passes of `feat-design-reviewer` (phase 4c), credited. Structural and style checks are left to Spec Kit's templates, the design critic to 4a and 4b; `/feat` merges the findings and `feat-planner` applies them. |
| `security-and-hardening`, `speckit-specify`/`plan`         | none beyond hooks                                                                                                                                                                                       | used as is                                                                                                                                                                                                                                                                                                                                                            |

**Spec Kit's bug extension** (`speckit-bug-assess`, `-fix`, `-test`, used
by `/fix`) is written for a user at the keyboard and is overridden in five
places. Its interactive slug prompt: `/fix` derives the slug, passes it as
`slug=<slug>` and checks the stage reported that same slug. Its refusal to
overwrite an existing report in automated mode: the earlier attempt is
renamed first (`test.md` → `test-<n>.md`), so every attempt stays in the
trail. Its "re-run assess" advice on a `failed` test: `/fix` retries the
fix once with a fresh implementer, then hands it to you with "back to 1"
offered. Its hooks (`before_bug_*`, `after_bug_*` in
`.specify/extensions.yml`) are read as configuration and allowed or
refused at setup, like the other Spec Kit hooks. And the commands a report
asks to run are not run blindly: nothing from an untrusted author runs
without your approval. The rules are in
[`.apm/skills/fix/SKILL.md`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/fix/SKILL.md) and
[`.apm/agents/feat-bug-assessor.agent.md`](https://github.com/pdemagny/logistics/blob/main/.apm/agents/feat-bug-assessor.agent.md);
what both skills share is in
[`.apm/skills/feat/references/harness.md`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/feat/references/harness.md).

Rule for new dependencies: read the whole skill first, look for asking,
committing, editing, branching, handing off and turn-ending instructions,
and either override them explicitly in the agent prompt or inline only the
part you need.

## Token use: why the workflow is shaped this way

On a subscription with a usage limit, tokens processed matter more than
dollars. Every call re-reads its whole context, so the shape follows from
keeping contexts small:

- **The brief is its own command.** The interview is the most
  back-and-forth part; in the same session, every later call of the run
  would re-read it. No skill or hook can clear the context, so the workflow
  splits where you are typing anyway: `/brief`, `/clear`, `/feat`.
- **A thin coordinator.** `/feat` never reads code, runs checks or edits
  artifacts; it reads reports and keeps the state file. Gate changes go back
  to the agent owning the artifact, review findings are verified by the
  reviewers, review fixes are applied by `feat-implementer`, shipping is
  done by `feat-shipper`.
- **One implementer per story**, so no implementer carries the previous
  stories' reads.
- **Fewer, cheaper agents where the feature is small**: one design reviewer
  instead of three, two code reviewers instead of five, medium effort.
- **No pipeline below small.** Each subagent re-reads its context from
  scratch, and a small `/feat` run still spawns about eight of them and
  writes spec, plan and tasks: for a typo or a docs edit that costs far
  more than the edit. `/tiny` does that work in the session you type in,
  with no Spec Kit and no size table. What keeps it safe is the tiny check
  (one reading, no design choice, a few files, nothing sensitive), which
  hands off to `/brief` or `/fix` when it fails, plus the parts that cost
  little: the worktree, the checks, a reread of the diff, the secret scan.
  It spawns one reviewer only for a change to a contract other files
  read, where a reread by the context that wrote it is least trustworthy.

## Distribution: one source, three installers

The repo keeps one copy of everything in APM's layout and lets each
installer read it:

- **APM** (`apm.yml`, `.apm/`): installs the skills and agents into
  `~/.claude`, and the only one that also installs the third-party skills.
  With an `apm.yml`, `apm install` finds agents only as
  `.apm/agents/*.agent.md`, which is why the files live there.
- **Claude Code plugin** (`.claude-plugin/`): native install and updates,
  pointing at the same `.apm/` paths. Plugin components are namespaced, so
  the skills accept both `feat-planner` and `logistics:feat-planner`. A
  plugin can't depend on loose skills (only on other plugins), so the
  third-party skills come from the skills CLI.
- **`install.sh`**: symlinks for working on the workflow itself.

The rules `/feat` and `/fix` share live once. The coordinators' part
(thin orchestrator, the step script, gates, review findings, state file,
board moves, resume) is in `.apm/skills/feat/references/harness.md`,
which `/fix` reaches as `../feat/references/harness.md` from its own base
dir, as `/brief` reaches the tracker script; all three installers keep it
in place, and `mise run lint` greps it for `/feat`-only words. Two
references sit beside it under the same rule, and the lint greps them
too: `move.md`, read only when main moved under a run, and
`rebase.md`, the `rebase` entry point of both skills, read only by a
`rebase` run. The rules a script can apply (checking reports, deciding
gates, merging review findings, the base check, model and effort) are in
`.apm/skills/feat/scripts/step.sh`, which both coordinators call once at
each phase boundary.

Agent frontmatter has no `model` or `effort` (`/feat` passes both on every
spawn, as `step.sh` prints them from `sizes.tsv`) and limits tools with
`disallowedTools`.

Only Claude Code is supported: the skill relies on its Agent tool with
per-call `model` and `effort`, and on `EnterWorktree`. Other harnesses
(Codex, OpenCode, Gemini) were supported through APM and dropped: they got
`/brief` and loose agents but not the build, and the partial install
confused more than it helped. Running every phase inline on harnesses
without agents was considered and rejected: it brings back the single
growing context this workflow exists to avoid.

## Behaviour of the workflow itself

- **Nothing is committed before phase 8.** So phase 7 can't review `git diff
  <default>...HEAD` (it would be empty): the orchestrator marks new files
  with `git add -N` and gives every reviewer `git diff <merge-base>`, which
  compares the working tree with the branch point.
- **Stories are implemented one after the other**, not in parallel
  worktrees: a fresh worktree would start from committed history and miss the
  uncommitted spec, tasks and earlier stories.
- **EnterWorktree names its own branch.** The orchestrator renames it to
  `<short-name>`. The spec number is not in it: the shipper picks it last,
  from the default branch and the open PRs' files, since a branch name says
  nothing about a PR whose branch was never renamed.

## Things to verify on first runs

- That `git diff <merge-base>` after `git add -N` shows every new file in
  your setup (some hooks or command-output filters may hide parts of git's output).
- The `small` column: whether Sonnet at medium effort is enough for spec
  and tasks in your codebase.

## Ideas not taken (yet)

- **Haiku beyond shipping.** Tasks and analyze look mechanical but catch
  cross-artifact inconsistencies; shipping (commits, PR body from the state
  file) is the only phase on Haiku.
- **A separate agent around the built-in `security-review` for phase 7.**
  Lens 7b uses the same skill as phase 4, so it can check that accepted
  design findings were built.
- **A smaller base context for subagents** (fewer tools, no project memory):
  every agent start writes ~36k tokens before working. Left for later.
- **`autoCompactWindow` on implementers** for very long task lists. Large
  features split by story instead.
