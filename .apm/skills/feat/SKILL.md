---
name: feat
description: >
  Builds a feature from a brief (written by /brief) to a reviewed PR:
  specify and plan it with Spec Kit, review the design for security, cost
  and fit with the code, generate and analyze tasks, implement, review the code, then commit
  and open a PR on its own branch/worktree. Each phase runs in a dedicated
  feat-* subagent whose model and effort follow the feature's size; this
  session only coordinates and holds the gates where the user decides. Use
  it as /feat followed by a brief path or short name, or /feat resume, when a brief exists,
  or /feat rebase to bring a shipped run's PR onto the current main. Without a
  brief, use /brief first. Not for bugfixes (use /fix) or pure refactors.
argument-hint: "specs/briefs/name.md | name | resume | rebase [PR]"
---

# /feat: from a brief to a PR

The user's request: `$ARGUMENTS`

This skill is a harness. It puts the phase agents in a fixed order, carries
the output of one into the next, and stops at gates so the user stays in
charge of the decisions that shape the feature. Two goals, equal weight: the
user ends up understanding the feature as well as you do, and nothing gets
built that nobody agreed to.

Gates are few on purpose. A user asked to approve seven times starts
approving without reading. Stop where the user's judgment changes the
outcome; otherwise report and keep going.

Read `<this skill's base dir>/references/harness.md` now: it holds the
rules this skill follows. The values it refers to are below.

## Harness values

- *Skill*: `feat`.
- *Artifact dir*: the feature dir, `specs/<short-name>/`.
- *State file*: `specs/<short-name>/feat-state.md` (unnumbered until
  phase 8, where the shipper renames it to `specs/<NNN>-<short-name>/`),
  created in phase 2.
- *The state file is created*: when phase 2 creates it.
- *Title* and *input section*: `# /feat state: <feature title>`;
  `## Brief`, `<copied from the brief file>`.
- *Size line*: `small | medium | large`.
- *Agents line*: `<specifier|planner|tasker> <agent id>, … (for
  SendMessage)`.
- *Current phase values*: `<N> <name>`, `done (shipping)` (written
  before each shipper spawn, so it is committed), `done (PR #N)` (local
  copy only).
- *Map line*: `<map path and id, if any>`.
- *Issue ref*: the `Issue:` line (the brief's, then the state file's);
  in the state file, `<the brief's issue, if any>`.
- *State script*: `<this skill's base dir>/scripts/state.sh` (harness,
  State file).
- *Step script*: `<this skill's base dir>/scripts/step.sh` (harness, Step
  script).
- *Sizes file*: `<this skill's base dir>/sizes.tsv`, read only by
  `rebase`.
- *Artifacts the orchestrator reads*: the brief, and the state file once
  on resume (harness, Resume). Open spec.md or plan.md only to quote a
  line the user must decide on.
- *Commands besides the tracker*: git for the worktree; `ls -d -- '<path>'
  …` for `rebase` only, on its own spawns' `Wrote:` paths
  (`references/rebase.md`), never at a boundary.
- *Artifact owners*: specifier: spec.md; planner: plan.md, accepted
  design findings, and spec changes asked at the plan or the design review
  gate; tasker: tasks.md; implementer: code.
- *Agents that may be continued*: specifier, planner, tasker. Implementer:
  always a fresh spawn, one per story and one for fixes.
- *Reviewer context*: the rejected findings (the spawn block's `rejected:`
  lines) and the brief's "Alternatives rejected".
- *Phases that can't be skipped*: none.
- *Tracker script*: `<this skill's base dir>/scripts/tracker.sh`.
- *Board-check step*: Setup step 5.
- *Building move*: at setup (step 5, phases 2–6); on resume in phases 2–6;
  going back from 7 or 8 to 2–6.
- *Review move*: when phase 7 starts; on resume in phases 7–8.
- *Resolver context*: spec.md and plan.md.
- *Implement row*: `6`. *Ship row*: `8`.
- *Number check*: the spec-number script.
- *Secret-scan script*: `<this skill's base dir>/scripts/secret-scan.sh`.
- *Ship script*: `<this skill's base dir>/scripts/ship.sh`.

## Phases

- 0 Setup: you.
- 1 Brief: `/brief`, in its own context (the interview, the brief and its
  fresh-reader review).
- 2 Specify: `feat-specifier`.
- 3 Plan: `feat-planner`.
- 4 Design review: `feat-design-reviewer`, one per group of lenses.
- 5 Tasks: `feat-tasker`.
- 6 Implement: `feat-implementer`, one per user story, one after the other.
- 7 Code review: `feat-code-reviewer`, one per group of lenses; then
  `feat-implementer` for the review fixes.
- 8 Ship: `feat-shipper`; ends with the PR link.

`step.sh` decides every gate after setup, the groups of reviewers, and each
spawn's model and effort for the run's size (harness, Step script). Below:
what you add to each prompt, and what each gate message shows.

---

## 0. Setup

0. This workflow needs Claude Code: subagents spawned by name with a
   `model` and `effort` per call, and `EnterWorktree`. If you can't do
   that here, stop: say `/feat` runs only in Claude Code, and that the
   brief can be built there. Don't run the phases inline instead.
1. `$ARGUMENTS` must be a brief: its path or its short name (or `resume`,
   or `rebase`, below). If
   it is an idea instead, stop and point to `/brief "<idea>"`; if it is an
   issue (`#N` or its URL), to `/brief #N`; if it describes a bug, to
   `/fix "<symptom>"` (or `/fix #N`; `/logistics:fix` as a plugin).
   **Find the brief**: an existing file as given is the brief. Else take
   `<name>` (the argument without a leading `specs/briefs/` and a trailing
   `.md`); it must be a short name (`[a-z0-9][a-z0-9-]*`), else stop as
   for no match. Look for `specs/briefs/<name>.md` under `git rev-parse
   --show-toplevel` (this checkout), then under every other worktree `git
   worktree list --porcelain` names. One match: use it and say its
   absolute path. Several: list them and ask which; never pick one. None:
   stop, naming every path searched, and point to `/brief`. Keep the
   brief's absolute path for phase 2, and whether it is exactly `<this
   checkout's top level>/specs/briefs/<short name>.md`, the short name
   matching `[a-z0-9][a-z0-9-]*` (a file given by path counts only then).
   Read the brief; check it has size, short name, behaviour and acceptance.
   Huge isn't a size here, nor tiny: stop and point to `/tiny <path>`,
   or `/brief <path>` to grow it when it outgrew tiny. Older briefs and
   state files say "normal" or "big": read them as medium and large; older
   briefs may lack "Today" and "Alternatives rejected".
   - `resume`: run steps 0, 2, 3 and 4, then the harness's Resume.
   - `rebase [<PR number, URL or branch>]`: run steps 0, 2, 3 and 4 (no
     step 5: `rebase` makes no board moves), then read `<this skill's base
     dir>/references/rebase.md` and follow it; no other run reads that
     file.
2. Read the project's `CLAUDE.md` / `AGENTS.md` and project memory. They
   override this file where they disagree. Keep the few lines agents need
   (commit style, branch rules, where checks live, docs to update).
3. Check `.specify/` exists (else stop: `specify init --here --integration
claude`) and the `feat-*` agents are installed (plain or
   `logistics:`-prefixed).
4. Read `.specify/extensions.yml` (enabled entries only; ignore
   `enabled: false`).
   - The specifier, planner and tasker can't run hooks (`Skill` is denied):
     every hook under `before_`/`after_` `specify`, `plan`, `tasks` or
     `analyze`, git ones included, will not run. `implement` hooks are
     allowed, except those that create a branch or commit (the git
     extension's, which clash with this workflow owning git), which agents
     skip unless the user says otherwise.
   - If any hook won't run or would branch or commit, **hard gate** before
     phase 2, one message: each such hook as `<key>: <extension>.<command>
     → run it by hand: /<command, dots as hyphens>` (a hook with no
     `command` is shown by its extension only, with no manual command), in
     two sections ("Won't run", "Would branch or commit (implement),
     skipped unless you allow it"), omitting an empty one; a hook enabled
     under several keys appears once per key.
   - Say that these won't run during this run: run them by hand once the PR
     is open, or stop now. The user continues with them skipped, or stops,
     and says whether to allow a branching or committing `implement` hook;
     there is no "run it anyway" for the first section. Log the answer on
     the setup line. On `rebase`, only the `implement` part applies.
5. **Board check** (see Board moves): run `check`. Exit ≠ 0 → stop and
   show its line; else show it and say this run's board moves go to that
   board. Then the building move (phases 2–6; review from phase 7).

## 2. Specify

1. Create branch `<short-name>` and tell the specifier the feature dir is
   `specs/<short-name>/`: no `NNN` yet, because a worktree can't see the
   numbers other in-flight features take. The shipper numbers it in phase 8
   with the spec-number script (free on the fetched `origin/<default>` and
   in every open PR's files), checks it again before pushing, and leaves
   the branch name as is. `git fetch origin <default>` (harness, Fresh
   base), then prefer a worktree (EnterWorktree). EnterWorktree picks its own
   branch name: check `git branch --show-current` and `git branch -m` it if
   needed. Enter it before spawning anything: agents start in your
   directory. If setup found `.logistics.yml` and the worktree has none,
   log `- [!] tracker: .logistics.yml is not in the worktree; commit and
   push it (board moves skipped)` and flag it at the first gate.
2. Create the state file in one Bash command: `S init feat '<state file>'
   '<brief path>' 'Branch=<short-name>' 'Worktree=<path>' 'Size=<size>'
   'Current phase=2 Specify' 'Conventions=<…>' 'Allowed Spec Kit
   hooks=<…>' 'Map=<…>' 'Issue=<…>'` (the brief's title and lines go into
   it), then `S log` of the setup line `- [x] 0 Setup — …` and any `[!]`
   lines kept so far, then `T feat '<state file>' setup`, joined with
   `&&`. It prints the specifier's spawn.
3. Spawn `feat-specifier` with the brief's path. Once it has reported,
   delete the brief file, by the absolute path setup found, only when setup
   marked it as this checkout's `specs/briefs/<short name>.md` (the
   checkout `/feat` started in). Any other brief (in another worktree,
   elsewhere in this checkout, outside it) stays: `S log '<state file>'
   '- [!] brief left in place: <path>'` chained before the boundary call,
   and name it in the final message, so the user decides.

**Hard** (`step.sh`'s reasons: open markers, a blocker, no spec, a size
remark): stories and requirements in a few lines, the open markers each
with its recommended answer, the specifier's assumptions, and the
unchecked items of `checklists/` (`speckit-implement` stops on them: ask
now whether to proceed). "ok" takes the recommended answers; answers and
edits go to the specifier amend `step.sh` prints. A spec with open markers
isn't approvable as it is.

**Soft**: one line, `Phase 2 Specify — soft: spec.md written (<n>
stories, <m> requirements, no open question); summary at the next gate.
Next: phase 3 Plan`, with the planner's spawn. Keep the digest's stories,
requirements, spec assumptions (each "recommended: keep as written") and
unchecked checklist items: the next gate shows them as the spec block
(`**The spec (phase 2 didn't stop):** …`), then the checklist question.
`step.sh` logged them and records what the user answered there.

On `/feat resume`, the resume call's `phase2-mode:` line prints `soft <G>
open` when phase 2 was soft and gate `<G>`, the one that carries the
summary, has not passed: open that gate with the spec block from the state
file's Log (the resume read). `soft <G> closed`, `hard` or `none`: no
summary to show.

Questions are asked at phase 2 or at the gate that shows its summary, so
later phases don't stop to ask.

## 3. Plan

Spawn `feat-planner`. It never asks the user anything: a decision the spec
didn't call for comes back as an assumption with a recommendation and
`needs user: yes|no`, and only a blocker (the spec can't be planned as
written) stops the run. It also reports a size trigger (new service,
permissions, exposure or dependency).

Small and medium: no gate here; `step.sh` prints phase 4's reviewers.
**Large**, a hard gate: after a soft phase 2 it opens with the spec block,
then approach, what it touches, new dependencies or services with reasons,
constitution check, the planner's assumptions. "ok" accepts the
recommendations. A spec change asked here is `changed`: give it to the
planner amend `step.sh` prints; phase 4's reviewers follow its report with
no second stop.

## 4. Design review

Give each `feat-design-reviewer` the spec, plan and state file paths only,
never the planner's report: lens 4c is a fresh reader on purpose. Every
gate of this phase starts with the 4c paraphrase from its digest, as
reported: the user checks it against what they meant (`step.sh`'s
`paraphrase:` line says whether it contradicts the brief).

On small and medium, one gate covers phases 3 and 4, headed "Plan and
design review". It shows, in order: after a soft phase 2 the spec block,
then the paraphrase, approach, what it touches, assumptions, any size
increase (asked first), then the findings.

**Soft** (small and medium): the paraphrase (after the spec block), then
one line `Phase 4 Design review — soft: <step.sh's counts:>; none needs
your call. Next: phase 5 Tasks`, with the spawn `step.sh` prints: the
planner continued with the `apply` findings, or the tasker when there is
none.

**Hard**: titled `Phase 3–4: Plan and design review — needs your call` on
small and medium (`Phase 4: Design review — needs your call` on large).
What you should know: `step.sh`'s reasons; on large, a `note: plan amended
after gate 3` line in one line (what the amend changed). Your call: each
`user` finding first as "apply or leave?" with the reviewer's why, then
every other finding with its `rec` (on large too, even when none is
`user`), per the harness (Review findings, "fix" read as "apply"; its `S`
notice does not apply here). Spec changes asked at this gate (an
overturned assumption, a reworded requirement) are `changed`: give them,
quoted, to the planner amend `step.sh` prints, with the picked findings
on its `apply:` lines. A change that rewrites stories is "back to 2".

## 5. Tasks

Spawn `feat-tasker`. **Hard** shows `step.sh`'s reasons: open
CRITICAL/HIGH findings with their proposed fixes (accepted fixes are
`changed`: the tasker amends and reruns analyze), analyze not run (with its
error: spec, plan and tasks were only cross-checked by hand) or not said,
each `story.sh:` line where tasks.md and the report differ (recommend
sending it to the tasker as an accepted fix), a size increase, unanswered
checklist items (`speckit-implement` would stop on them), and `large`.
**Soft**: one line `Phase 5 Tasks — soft: MVP <the digest's MVP slice>;
analyze ran. Next: phase 6 Implement`, with the first story's spawn. Last cheap
moment to change direction: raise any hesitation you noticed.

## 6. Implement

`step.sh` prints one implementer per story, in tasks.md order, with its
`who`, `story` and `story.sh` output (setup and foundational tasks come
with the first story, polish with the last). Add the checklist answer from
phases 2–5. Not in parallel: nothing is committed before phase 8, so a
separate worktree would miss the spec and earlier stories.

**Soft** after the last story (hard after each one for large): `Phase 6
Implement — soft: <step.sh's tasks:>`. Under "What you should know" show
each story's latest `Not verified:` list from the digests (`Not verified:
none` when empty; for large, the per-story gate shows that story's list).
A non-empty list is not a surprise. Failing checks get one retry
(`step.sh` prints it with the failures); then, or on a design problem or a
report without its `Not verified:` line, a hard gate, recommending a fresh
implementer for that story. Never accept a weakened test or check. At a
story gate: `approved` → the next story, `changed` → that story again with
the user's changes, "back to 6" → from the first story.

## 7. Code review

Before the first reviewers' spawns, the review move (see Board moves). The
call that prints them prepared the diff (`diff:` key; `added:` and
`untracked, not in the diff:` lines). Give each `feat-code-reviewer` its
spawn block's keys. On medium and large, 7a–7d's boundary call prints
`7e` with 7d's cuts; the gate comes after 7e. For large, suggest the user
also runs `/code-review ultra` before merging.

**Soft**: one line, `Phase 7 Code review — soft: <step.sh's counts:>;
none needs your call. Next: <review fixes, then phase 8 Ship | phase 8
Ship>`, with the fix-mode implementer `step.sh` prints (merge rule 1
first: harness, Review findings).

**Hard**: titled `Phase 7: Code review — needs your call`. What you should
know: `step.sh`'s reasons and any `untested` criterion. Your call: every
finding with its `rec` (on large too), `user` first, "ok" rule and
follow-up and `S` publication notice per the harness (Review findings).
Next: review fixes, then phase 8 Ship.

**Review fixes**: `step.sh` retries failing checks once; a second failure,
a failed report check or a report without its `Not verified:` line is a
hard stop before phase 8, recommending a fresh implementer with the same
findings. There, `changed` → a fresh fix-mode implementer with the user's
instructions; `approved` → phase 8 as it is.

## 8. Ship

`step.sh` sets `done (shipping)` before each shipper spawn, so the copy the
shipper commits is already done. Give `feat-shipper` the state file, the
*state script* (`State script:`), the spawn block's `ship script` (`Ship
script:`), the conventions, the worktree, the default branch, the
spec-number script (`<this skill's base dir>/scripts/spec-number.sh`),
the *secret-scan script* and the issue, if any. It updates the docs the
conventions call for, writes its notes (the commit split among them),
runs `ship.sh prepare` (numbering, commits, rebase), the checks, then
`ship.sh publish` (secret scan, push, PR), or reports `blocked` or
`conflict`. Never merge.

- `done: PR #N`: the final message.
- `stop: ship blocked on a command for you`: give the `command:` line to
  the user as is (`ship.sh` blocked in the session); the state file stays
  done (resume finds the run while its branch has no upstream).
- `hard:` `ship blocked`: show the `command:` line as an error, not a
  command; `approved` ships again.
- `PR: conflict`: `read:` (harness, Moving onto a new main).

Final message: the PR link, the branch/worktree, the two or three things
you'd look at first in review, the shipper's `Not verified:` list when it
is not `none`, any report logged with `Not verified line missing`, a move
onto a new main kept since the last gate or at ship (`references/move.md`),
a brief left in place (the Log's `brief left in place` line), for large
`/code-review ultra`, and for a capability from a map, the next capability
with `/brief <map> <id>`.
