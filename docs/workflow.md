---
title: Workflow
weight: 30
---

# The workflow in detail

What runs at each phase, on which model, for which size, and where it stops
for you. The size tables here, and the `sizes.tsv` file `step.sh` reads
each spawn's model and effort from, are generated from
[`.apm/skills/feat/sizes.json`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/feat/sizes.json)
by `mise run diagrams`; this page adds the explanations. Neither skill
holds a size table or a gate table: `step.sh` applies them.

## Roles

- **`/brief`**: phase 1, in its own context. Interviews you, proposes
  the size, writes the brief (or a capability map for huge ideas) and has
  `feat-brief-reviewer` read it fresh before you confirm it.
- **Coordinator**: the session running `/feat`, started from a clean
  context. It holds every gate and changes only `feat-state.md`, through
  the `state.sh` and `step.sh` scripts (never by hand); it never reads
  code, report files, runs checks or edits artifacts. Each phase boundary
  is one call to
  [`step.sh`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/feat/scripts/step.sh),
  which checks the agents' reports, decides the gate, logs it, runs the
  base check and prints the next spawn with its model and effort; the
  coordinator writes the gate message and makes the spawn. An agent that
  closes a sequential boundary (the specifier, planner, tasker, each
  implementer, the shipper) runs that call itself, as its last step, and
  hands the output back in a block the coordinator acts on as its own.
  The coordinator calls `step.sh` itself at setup, after each reviewer
  batch, for each answer at a hard gate, after a move, when an agent's
  block slipped (missing or unreadable: the same call again, which
  re-prints a decision already made and logs nothing) and for the `done:`
  check after the shipper. Setup is two
  calls to
  [`preflight.sh`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/feat/scripts/preflight.sh)
  around `EnterWorktree` (0 Setup). Every call it makes re-reads its whole
  context, so it stays thin on purpose.
- **Phase agents**: the `feat-*` subagents. Each does one job, can't talk to
  you, starts with no conversation history, and gets what it needs (paths,
  size, conventions, allowed hooks, rejected findings) in its prompt.
  Changes you ask for at a gate go back to the agent that owns the artifact.

## Phases at a glance

| # | Phase         | Runs in                                                                               | Skills used                                                        | Produces                                      | Gate                                                                                                                       |
| - | ------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| 1 | Brief         | `/brief` (your session), then `feat-brief-reviewer`                                   | `interview-me`                                                     | `specs/briefs/<name>.md`, or a capability map | **hard** (confirm the brief and the review's findings)                                                                     |
| 0 | Setup         | coordinator                                                                           | —                                                                  | conventions, hooks checked                    | hard only if a Spec Kit hook won't run (specify, plan, tasks, analyze) or would branch or commit |
| 2 | Specify       | `feat-specifier`                                                                      | `speckit-specify`                                                  | branch/worktree, `spec.md`, `feat-state.md`   | **hard** only on an open question or a blocker; else soft, and its summary opens the next gate                              |
| 3 | Plan          | `feat-planner`                                                                        | `speckit-plan`                                                     | `plan.md` and design docs                     | none (hard for large, opening with the spec summary after a soft phase 2)                                                  |
| 4 | Design review | `feat-design-reviewer` ×1 (small) or ×3, then `feat-planner` writes accepted findings | `security-and-hardening` (cost and design checklists in the agent) | a paraphrase, findings D1… with recommendations | one gate with 3: hard only on a finding that needs you (`user`), a user-call assumption, a constitution violation, a blocker, a size increase, a paraphrase that contradicts the brief or an unchecked checklist item after a soft phase 2, else soft and the `apply` findings are applied (always hard for large) |
| 5 | Tasks         | `feat-tasker`                                                                         | `speckit-tasks`, `speckit-analyze`                                 | `tasks.md`, analysis clean                    | hard on CRITICAL/HIGH, analyze not run, a size increase, an unanswered checklist item or tasks.md not matching the tasker's report (`story.sh`); always for large               |
| 6 | Implement     | `feat-implementer` ×1 per user story, in turn                                         | `speckit-implement`                                                | the code, tasks ticked when their checks ran, a Not verified list | soft (hard per story for large; hard on a design problem)                                                                  |
| 7 | Code review   | `feat-code-reviewer` ×2 (small) or ×5, then `feat-implementer` applies the fixes         | `security-and-hardening`, `performance-optimization`               | findings B, S, P, C, R with recommendations; fixes applied | small/medium: **hard** on a finding that needs you (`user`), an `S` finding or an unmet criterion, else soft; large: **hard** |
| 8 | Ship          | `feat-shipper`                                                                        | —                                                                  | docs updated, commits, push, PR               | none                                                                                                                       |

**Hard gate**: Claude stops and waits for your answer. **Soft gate**: Claude
reports and continues, its one-line summary in the same turn as the next
spawn; anything surprising lets the coordinator turn it into a hard gate
(an override, logged). `step.sh` decides each gate of the table from the
agents' reports and the Log; the gates are the ones the column says.
Every agent's report ends with a `Wrote:` list (its artifacts and the
files it wrote, or `none`). `step.sh` refuses any path that is not
absolute, is outside the worktree, or holds a quote, newline, tab, `$`,
backtick or `..` segment, then checks each path exists and that the
report's own path and artifact path are on the list. A failure fails the
phase: a hard gate that shows the reason, with no automatic retry ("back to
N" reruns it). A report that does not parse (a field outside its fixed
values, a wrapped list item) gets one reformat turn: the same agent writes
it again in its format, changing nothing else, told the line, its field
and what is wrong with it in fixed words (an item under `none`, a count
that is not a bare integer), never the line's text; a second slip is a
hard gate naming the line. In a reviewer batch the groups are
independent: a group whose report is missing is spawned again once,
fresh, alongside the other reports' reformat turns, so one lost report
costs one lens, not the batch; a second miss of that group, or any other
failed check in the call, is the hard gate.

**Report files.** Before each spawn, `step.sh` gets the agent a path from
`state.sh report-path`, `<artifact dir>/reports/<key>.md` (`3-test-2.md` on
a rerun; a report file is never overwritten). The agent writes its full
report there, one field per line with fixed values where `step.sh` reads
them, lists the path on `Wrote:`, and hands back a digest: what the gate
message needs beside `step.sh`'s output (each agent file lists its
fields). The coordinator never reads a report file. `reports/` holds a
`.gitignore` with `*`, so it is never committed. The code and design
reviewers may write their report file and nothing else: `step.sh` takes a
`state.sh snapshot` before each batch of reviewers and runs `state.sh
unchanged` after it, so any other change to the worktree is a hard gate
that lists the paths that changed. The state file is left out: the
coordinator logs to it while the reviewers run. An agent given no report path
(`/tiny`'s reviewer, `/brief`'s) reports in full and writes nothing.

After a soft phase 2, the next gate (3/4, or 3 on large) opens with the spec
summary.

From phase 3 on, `step.sh` starts each phase with the base check (see
[When main moves](#when-main-moves)): silent when main has not moved; a
move is listed at the next gate, or stops there when it needs your call.

### A small run, call by call

The coordinator's own `step.sh` calls on a small feature, main not moving:

- **Setup**: one call, chained with `preflight.sh feat worktree` and
  `state.sh init`; it prints the specifier's spawn.
- **Specifier, planner**: none. Each runs its boundary's call and hands
  back the next spawn (a hard phase 2 adds one answer call).
- **Design review batch**: one call when the reviewers have reported.
- **Its gate**: one answer call when it is hard; none when soft.
- **Tasker, each story**: none; the last story's block prints the code
  reviewers' spawns.
- **Code review batch**: one call (plus one for 7e on medium); a hard
  gate adds one answer call.
- **Review fixes, shipper**: none.
- **`done:`**: one check call, the shipper's boundary words again; it
  re-prints `done: PR #N`, which gives the final message.

So a small run with one hard gate costs the coordinator five `step.sh`
calls: setup, two batches, one answer and the `done:` check. A Log line it
would write meanwhile (a flag, a brief left in place) rides on the next of
those calls.

## Size × phase matrix

![Grid of phases by size, coloured by model: Opus plans at every size and runs most of a large feature, Sonnet most of a small one, Haiku ships. Split cells are reviewers running in parallel (O = Opus, S = Sonnet).](img/models.svg)

Opus where judgment decides, Sonnet for the routine work, Haiku to ship. A
split cell is a phase whose reviewers run in parallel, one per group of
lenses (O = Opus, S = Sonnet). The picture is drawn from
`.apm/skills/feat/sizes.json` by `mise run diagrams`.

Each cell: model · effort, printed by `step.sh` in every spawn block (from
`sizes.tsv`) and passed by `/feat` on the spawn.

<!-- sizes-start feat-matrix -->

| #  | Phase                        | Agent                  | small           | medium          | large           | huge                         |
| -- | ---------------------------- | ---------------------- | --------------- | --------------- | --------------- | ---------------------------- |
| 1  | Brief                        | your session           | session         | session         | session         | session, plus capability map |
| 1  | Brief review (`/brief`)      | `feat-brief-reviewer`  | sonnet · medium | sonnet · medium | opus · medium   | first capability's size      |
| 2  | Specify                      | `feat-specifier`       | sonnet · medium | sonnet · medium | opus · high     | —                            |
| 3  | Plan                         | `feat-planner`         | opus · high     | opus · high     | opus · xhigh    | —                            |
| 4a | Security design              | `feat-design-reviewer` | sonnet · medium | opus · medium   | opus · high     | —                            |
| 4b | Cost design                  | `feat-design-reviewer` | sonnet · medium | sonnet · medium | opus · medium   | —                            |
| 4c | Clarity and fit              | `feat-design-reviewer` | sonnet · medium | sonnet · high   | opus · medium   | —                            |
| 5  | Tasks                        | `feat-tasker`          | sonnet · medium | sonnet · medium | opus · high     | —                            |
| 6  | Implement                    | `feat-implementer`     | sonnet · medium | opus · medium   | opus · high     | —                            |
| 7a | Correctness, spec, standards | `feat-code-reviewer`   | sonnet · medium | opus · medium   | opus · medium   | —                            |
| 7b | Security                     | `feat-code-reviewer`   | sonnet · medium | opus · medium   | opus · high     | —                            |
| 7c | Performance                  | `feat-code-reviewer`   | sonnet · medium | sonnet · medium | opus · medium   | —                            |
| 7d | Over-engineering             | `feat-code-reviewer`   | sonnet · medium | sonnet · medium | sonnet · medium | —                            |
| 7e | Readability                  | `feat-code-reviewer`   | sonnet · medium | sonnet · medium | sonnet · medium | —                            |
| 8  | Ship                         | `feat-shipper`         | haiku · medium  | haiku · medium  | haiku · medium  | —                            |

<!-- sizes-end feat-matrix -->

Phase 6 runs one implementer per user story, in turn.

**Phase 4 reviewers.** small: one reviewer, lenses 4a+4b+4c. medium and
large: one reviewer per lens, in parallel.

**Phase 7 reviewers.** small: two reviewers, lenses 7a+7b and 7c+7d+7e. medium and large: one reviewer per lens, 7a–7d in parallel, then 7e
with 7d's cuts. A group runs on the strongest model and effort among its lenses.
Applying the review fixes and moving onto a new main use the phase 6 row.
The groups are `sizes.json`'s `groups`, carried into `sizes.tsv` with
their precomputed model and effort.

A huge idea never reaches `/feat` as one unit: each capability of its map
gets its own brief and size column.

### How the sizes differ beyond model and effort

|                      | small                                                                                        | medium                                           | large                                                       | huge                                       |
| -------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------ | ----------------------------------------------------------- | ------------------------------------------ |
| **When**             | up to ~30 tasks; no new service, permissions, network exposure or dependency; docs-only work | ~31–60 tasks, or a small one adding any of those | more than ~60 tasks                                         | capabilities that could ship independently |
| **Hard gates**       | brief, 7 (+2 on a question, +3/4 on a finding or checklist item, +5 on CRITICAL/HIGH or a task mismatch, +7 on a finding that needs you) | brief, 7 (+2, +3/4, +5 and +7 as for small)    | brief, 3, 4, 5, each story in 6, 7 (+2 on a question)       | the map                                    |
| **Design reviewers** | 1                                                                                            | 3                                                | 3                                                           | per capability                             |
| **Code reviewers**   | 2                                                                                            | 5                                                | 5                                                           | per capability                             |
| **PRs**              | 1                                                                                            | 1                                                | 1                                                           | 1 per capability                           |
| **Extra review**     | —                                                                                            | —                                                | `/code-review ultra` suggested before merge (you launch it) | per capability                             |

### Why these choices

- **Plan is on Opus even for small.** Plan quality decides everything after
  it, and it is one agent run.
- **Effort before model.** Raising effort on the same model costs less than
  a bigger model, and pays off most in planning and review.
- **One implementer per story at every size.** Each starts fresh instead of
  carrying the earlier stories' reads; stories run one after the other
  because nothing is committed before phase 8.
- **One design reviewer and two code reviewers for small.** Each agent
  start costs ~36k tokens before any work; a small design doesn't need
  three separate contexts, nor a small diff five. Lens 4c stays a fresh
  reader either way: no design reviewer gets the planner's report.
- **A fresh reader on every brief.** One cheap spawn before anything is
  built; a wrong premise found in phase 4 has already cost a spec, a plan
  and the design reviews.
- **Ship on Haiku.** Commits, push and a PR body from the state file need
  little reasoning; it used to run at the coordinator's full context.
- **Huge is a scoping problem.** One spec with a dozen capabilities gives a
  shallow review and a PR nobody can read.

## Phase details

### 1 Brief (`/brief`)
Reads the code the idea touches, interviews you one question at a time
(`interview-me` steps 1–5; its restate is the brief, its confirmation the
gate, its hand-off step skipped), gives the strongest counter-argument to
each decision before writing it down, proposes a size and writes
`specs/briefs/<name>.md`: why, how it's handled today, behaviour, out of
scope, alternatives rejected with their reasons, acceptance, constraints.
The path is anchored to the checkout's top level (`git rev-parse
--show-toplevel`: the repo, or its worktree), never a temporary dir; outside
a git checkout it asks for the repo's path before the interview and stops
without one, and the board check, the reads and the write all use that
top level. Its last lines print the absolute path.
From an issue (`/brief #N` or its URL) it reads the issue with `gh` as
the idea and records it in the brief; the shipper's PR says `Closes #N`.
With [board tracking](#board-tracking) it checks the board first, moves the
issue to Brief, and after the gate offers to create the issue when the
brief has none. From a tiny brief (`/brief <path>`, what `/tiny` hands off
when the work outgrows it) it takes Why, Behaviour and Acceptance as
answered, asks for the missing sections, sizes it, and writes the full
brief under the same short name and issue in the checkout it runs in;
`/feat` refuses a `Size: tiny` brief.

Then `feat-brief-reviewer` reads the brief with no knowledge of the
interview, as the specifier will, on every brief. It makes four passes:
- **clarity**: it paraphrases what the feature does, for whom and how it's
  handled today; the gate shows this so you can check it against what you
  meant;
- **yagni**: existing code, a dependency or a config option that already
  covers it (it searches and names the path), behaviour that could be
  dropped, a symptom fix, an obvious alternative neither chosen nor
  rejected;
- **gap**: undecided failure and edge cases, acceptance nobody could check,
  existing data or users the change affects, constraints the code
  contradicts, scope that leaks;
- **size**: its own task estimate; a higher size is asked, not applied.

Its passes are adapted from the brainstorm lenses and the Heilmeier and
feature-spec standards of the
[Elephant-Goldfish Model](https://github.com/google/elephant-goldfish-model)
(Apache-2.0). Findings `F…` come with recommendations; the accepted ones are
written into the brief, and a rejected "drop this" goes under "Alternatives
rejected" with your reason, which the specifier, planner and reviewers
treat as settled. Then it tells you to `/clear` and run `/feat` on it.
**Huge:** writes a capability map to `specs/maps/<name>.md` (stable ids,
responsibility, size, one-way dependencies, a build order where each step
ships something usable), gates on it, then writes the first capability's
brief. Detection rules and map format adapted from the scope check in
[addyosmani/agent-skills](https://github.com/addyosmani/agent-skills)'
`spec-driven-development` (MIT).

### 0 Setup (coordinator)
One call to `preflight.sh feat '<argument>'` does what setup can know before
the worktree exists, and prints `key: value` lines the coordinator reads as
data (exit 0 go on, 1 stop with a `stop:` line, 2 could not run):

- It classifies the argument: a brief (a path or a short name,
  `[a-z0-9-]`), `resume`, `rebase [PR]`, empty, or a kind `/feat` refuses
  (an issue or an idea: `/brief`; a bug: `/fix`), printed with the pointer
  to the right command.
- A short name is looked up as `specs/briefs/<name>.md` in this checkout,
  then in every other worktree; one match is used and named, several are
  put to you, none stops the run with every path searched. The brief's
  fields are printed (size, short name, map, issue; Behaviour and
  Acceptance are counted, not printed); `tiny` and `huge` stop the run.
- It checks Spec Kit and the agents, runs the board check with [board
  tracking](#board-tracking), fetches `origin/<default>` (a failed fetch
  stops the run), and reads that branch's `.specify/extensions.yml` as data
  (a file it can't parse stops the run: it may hide a hook that commits).

The coordinator then reads `CLAUDE.md`/`AGENTS.md` and project memory (they
override the skill).

- The specifier, planner and tasker can't run hooks (`Skill` is denied), so
  every hook under `before_`/`after_` `specify`, `plan`, `tasks` or `analyze`,
  git ones included, won't run; an `implement` hook that would branch or
  commit (by its names: the `git` extension, or a word such as `commit`,
  `push`, `merge`, `tag` or `pr`) is skipped unless you allow it.
- If any is found you get one hard gate before anything runs, listing each as
  `<key>: <extension>.<command> → run it by hand: /<command>` (dots as
  hyphens; a hook with no `command` is shown by its extension only) in two
  sections, "Won't run" and "Would branch or commit (implement)".
- They won't run during this run: run them by hand once the PR is open, or
  stop now; there is no "run it anyway" for the first section. On `rebase`
  only the `implement` part applies.

With board tracking it then moves the issue to In progress.

### 2 Specify (`feat-specifier`)
Setup fetched `origin/<default>`, so the run starts from the remote head
rather than a stale local copy. The coordinator enters a worktree
(`EnterWorktree`), so every agent starts there, then makes one Bash call:
`preflight.sh feat worktree` renames the branch to `<short-name>` and
checks `.logistics.yml` is in the worktree, chained with `state.sh init`
and the first `step.sh` call. The spec dir is `specs/<short-name>/` until phase 8 numbers it. The specifier runs `speckit-specify` from the brief and
reports stories, requirements, open `[NEEDS CLARIFICATION]` markers with
recommended answers, assumptions and unchecked checklist items. Before
spawning it, the coordinator copies the brief into `feat-state.md`
(`state.sh init`); once it has reported, it deletes the brief file
only when it is `specs/briefs/<short-name>.md` in the checkout `/feat`
started in (any other stays, and the final message names it). `step.sh`
decides the gate: hard only when the spec has an open marker or the
specifier reports a blocker, at every size (the coordinator may still make
it hard when the report holds something surprising, such as a remark about
size). Otherwise it is soft: one line, `Phase 2 Specify — soft`, and
the run goes on. The summary (stories, requirements, the specifier's
assumptions, unchecked checklist items) is kept in the state file's Log and
opens the next gate, so questions are asked at phase 2 or at the gate that
shows that summary, and later phases don't stop to ask. A hard phase 2 shows
the summary, each marker with a recommended answer, the assumptions and the
checklist question; your answers and edits go back to the specifier in amend
mode, spawned fresh (a subagent's cache lasts 5 minutes, so after you answer
it would rewrite its whole context). The Log keeps the summary, so
`/feat resume` shows it too.

### 3 Plan (`feat-planner`)
Runs `speckit-plan`, kept to what the spec requires; it never asks you
anything. It reports approach, what it touches, new dependencies or
services with reasons, constitution check, a size trigger (new service,
permissions, exposure or dependency), and the decisions the spec didn't
call for as assumptions with a recommendation and whether they need your
call. `step.sh` decides what follows: only a blocker stops the run. Small and medium go straight to phase 4;
large stops here, and after a soft phase 2 that gate opens with the spec
summary; "ok" accepts its recommendations.

### 4 Design review (`feat-design-reviewer`)
One reviewer with all three lenses on small, one per lens in parallel on
medium and large. Each reads spec and plan with the paths only, never the
planner's report. **4a Security** translates the web-app checklist to the
project (exposure, identities, secrets, defaults, input, supply chain,
blast radius); **4b Cost** looks for oversized resources, repeated work, unbounded
loops, extra calls, slow feedback loops, unused code, and may propose
dropping a requirement. **4c Clarity and fit** reads them as someone new to
the project, runs first when lenses share a reviewer, and makes four passes:
- **clarity**: it first paraphrases what the feature does and how the
  system works today, as the documents say; a part it can't paraphrase is a
  finding, and so are undefined project terms and unstated prerequisites;
- **fit**: statements the code contradicts, files, functions or commands
  cited as existing that don't exist, unbacked assumptions, logic in the
  wrong layer;
- **simplicity**: symptom fixes, new helpers the codebase already has (it
  greps for them), speculative abstractions, dead ends;
- **readiness**: decisions the plan leaves to the implementer (formats,
  schemas, error handling, edge cases), criteria nobody could check.

Its passes are adapted from the comprehension, codebase-details, zoom-out
and implementation-readiness reviewers of the
[Elephant-Goldfish Model](https://github.com/google/elephant-goldfish-model)
(Apache-2.0). The paraphrase opens the gate, so you can check it against
what you meant; one that contradicts the brief makes the gate hard.

The reviewer recommends on each finding (`apply`, `skip` or `user`), and
`/feat` never sets a recommendation itself; `step.sh` merges the reports
and decides the gate. `user` marks a finding that
removes or changes a story, a requirement or an acceptance criterion the
brief asked for, overturns a spec assumption, or weakens a control the spec
or plan sets. Large: always hard; you accept or reject each, with `user`
findings first; if the planner amended the plan after the phase 3 gate, this
gate says so under "What you should know". Small and medium: one gate for
phases 3 and 4 ("Plan and design review"); after a soft phase 2 it opens with
the spec summary, before the paraphrase. It is hard only on a finding that
needs you (`user`), an assumption that needs your call, a constitution
violation, a blocker, a size increase or an unchecked checklist item carried
from a soft phase 2; otherwise one status line says how many findings were
applied and skipped (with the security ones named) and the run goes on. On a
hard gate "ok" applies every `apply` and leaves every `skip`, and each `user`
finding needs its own answer. The planner writes the accepted
ones, and any spec change you asked for at this gate (an overturned
assumption, a reworded requirement), in one amend pass, into spec.md (as
requirements) and plan.md;
`[design]` findings are corrections applied where they point. It is the
same one, continued with `SendMessage`, after a soft gate (still warm); a
fresh one after a hard gate.

### 5 Tasks (`feat-tasker`)
Runs `speckit-tasks` then `speckit-analyze`, handing Spec Kit's scripts the
unnumbered feature dir (`SPECIFY_FEATURE_DIRECTORY`), fixes MEDIUM/LOW
findings that don't change meaning, and reports CRITICAL/HIGH with proposed
fixes, task IDs per story, the MVP slice, whether analyze ran, and
unchecked checklist items. When analyze can't run, the tasker cross-checks
spec, plan and tasks by hand and says so (`Analyze: not run`). `step.sh`
decides the gate: hard only on CRITICAL/HIGH findings, analyze not run, a
size increase, or checklist items the checklist answer you already gave
doesn't cover (`speckit-implement` would stop on them).
It also runs `story.sh` on `tasks.md` and compares its task IDs
per group with the tasker's report: a difference, or a script error, is a
hard gate showing both sides, and the task count for the size check comes
from the script.
Last cheap moment to change direction.

**Size changes** are checked at the plan (size trigger) and here (task
count). An increase is always a hard gate: it names the old and new size and
what changes. A decrease is applied, logged with its reason and mentioned at
the next gate; `size <s>` reverses it.

### 6 Implement (`feat-implementer` per story)
One implementer per user story, one after the other (setup tasks with the
first, polish with the last). Each prompt carries `story.sh`'s view of the
story (task IDs, checked state, paths), as data and refreshed on a retry or
resume, and the implementer sends independent tool calls together in one
turn. Each runs `speckit-implement` over its tasks,
reads only what they need, runs build, tests and linters, never weakens a
check, never commits. `step.sh` decides each story's gate and prints the
next story's spawn: failing checks go back once; a needed design change is
a hard gate. **Large:** a gate after each story.

A check that could not run (no credentials, a service down, a manual step,
a killed or timed-out run) leaves its task unticked and listed as Not
verified; the gate shows each list and how many tasks are not verified, and
stays soft for it. A later implementer of the story retries those checks
instead of redoing the tasks.

### 7 Code review (`feat-code-reviewer`)
The last story's `step.sh` call, run by its implementer, makes the
uncommitted work reviewable (`git add -N` on new
files, `git diff` against `git merge-base origin/<default> HEAD`; a
`...HEAD` diff would be empty), writes that diff to
`<artifact dir>/reports/review.diff` (never committed, rewritten at each
review, not written when the diff is empty), and prints the reviewers'
spawns with their lenses and the file under `diff file:`. With [board
tracking](#board-tracking) the coordinator moves the issue to In review in
the response that makes those spawns. Each reviewer reads the file instead of running git to find the diff (`/tiny`'s
reviewer, with no file, runs the `diff:` command), and still reads the
tree to verify its findings:
- **7a Correctness, spec, standards**: three separate passes. Standards:
  the project's documented rules (hard) and a Fowler smell baseline
  (judgement calls). Spec: missing requirements, scope creep, wrong
  implementations, acceptance criteria. Bugs: edge cases, error handling,
  races. The first two are adapted from Matt Pocock's `code-review`
  ([mattpocock/skills](https://github.com/mattpocock/skills), MIT).
- **7b Security**: each accepted `[sec]` design finding is built, plus what
  the implementation introduced.
- **7c Performance**: `performance-optimization`'s measure and identify
  steps on what was built, with the project's own benchmarks or timings
  where cheap, the rest marked `unmeasured`.
- **7d Over-engineering**: what to delete (`delete`, `stdlib`, `native`,
  `reuse`, `yagni`, `shrink`), with the lines it would save; the checklist
  is in the agent, adapted from the pre-v5 `ponytail-review`
  ([dietrichgebert/ponytail](https://github.com/dietrichgebert/ponytail), MIT).
- **7e Readability**: nesting, long functions, dense expressions, flag
  parameters, names and comments, on the code as it will be after the cuts,
  never changing behaviour. Adapted from Addy Osmani's
  `code-simplification` ([addyosmani/agent-skills](https://github.com/addyosmani/agent-skills), MIT).

Reviewers verify their findings and list what they dismissed, in their
report file. You get one
list (`B` bugs and spec mismatches, `S` security, `P` performance, `C` cuts,
`R` readability and `[std]` standards), each ending with the reviewer's
recommendation: `apply`, `skip (<why>)` or `user (<why>)`. `step.sh`
merges them by fixed rules and decides the gate (cut code drops its performance and readability
findings; the same spot with different advice, a high-confidence bug the
reviewer would skip, or a security finding the reviewer would skip, becomes
`user`; a missing recommendation becomes `user`).

On small and medium the gate is soft, and the `apply` findings are
fixed unasked, unless a finding needs your call (`user`), is a security
finding (`S`) or an acceptance criterion is not met; criteria that are
`untested` are listed in the report and the PR but never stop the run. The
hard gate lists the `user` findings first, as fix or leave; "ok" fixes every
`apply` and leaves every `skip`, but not a `user` finding, which gets one
follow-up. Large always stops, with every finding shown with its
recommendation.

An `S` finding left unfixed is published in the PR body and
the state file as id, file and title only. If the fixes fail their checks
twice, or a path on the report's `Wrote:` line is not on disk, or it has no
`Not verified:` line, the run stops before ship. The PR body groups the
findings as applied without asking, picked by you, and not applied (with the
reason).

`feat-implementer` in fix mode applies the fixes: bugs and security, then
cuts, then performance (each measured before and after, kept only if it beats
the noise with tests green, every attempt logged with its numbers), then
readability one change at a time with tests after each.

### 8 Ship (`feat-shipper`)
Before each shipper spawn, `/feat` marks the state file `done (shipping)`,
so the copy the shipper commits is already done and `/feat resume` skips
the run once it is pushed (a ship interrupted before the push, its branch
with no upstream, is still resumed). The shipper updates the docs the
project asks for, writes a notes file (each commit's subject and paths,
the PR summary, the points to look at, its own not verified items) and
makes two calls to `.apm/skills/feat/scripts/ship.sh`, running the
project's checks in between and fixing what fails. The script does every
git and gh step, the same way every time.

`ship.sh prepare` checks the notes before touching anything, then numbers
the spec dir with `.apm/skills/feat/scripts/spec-number.sh`: after fetching `origin/<default>`, the next number free on it and in every open
same-repo PR (the `specs/NNN-*` paths among its files, all pages, or its
branch name when it has no spec files; fork PRs and numbers longer than
four digits are ignored), so two features shipped at the same time get different numbers
whatever their branches are called. The branch keeps its `<short-name>`.
It commits by the notes, in their order (the shipper follows the
project's rules; default: `docs(specs)` then `feat(scope)` with its docs;
`perf` and `refactor` only when separable), staging only the paths each
commit lists and never `reports/`, scans the staged lines for secrets
before each commit, and rebases onto `origin/<default>`. A commit message
holding a closing keyword or a secret is refused. A stop in `prepare`
puts the tree back as it found it: nothing committed, nothing staged.

`ship.sh publish` folds the check fixes into their commits, checks the
number again and, if another PR took it meanwhile, renumbers and folds the
change into the unpushed commits, scans the lines it is about to push for
secrets, pushes, and opens a non-draft PR titled with the main commit,
with the brief, accepted design changes, review results and numbers, a
`Not verified` section (every logged item and the ship's own unrun
checks, or `none`), a link to the state file and `Closes #N`. It runs
the same secret rules over the PR body before pushing, and never pushes
the default branch. A stop after the push (a `gh` failure) can be retried
with `publish` alone. If the session blocks the call, the shipper returns
one `! cd … && bash … ship.sh prepare … && bash … ship.sh publish …`
command for you to run, holding only paths and fixed words. If the
spec-number script fails (git or gh error),
nothing is pushed: `/feat` shows its `! spec-number: error: …` line as an
error and sets the state file back to `8 Ship`, so `/feat resume` picks
the run up again. Resume also skips a run whose branch has a merged or
closed PR. Never merges.

If main moved since the phase's base check and the shipper's rebase
conflicts, it aborts the rebase, pushes nothing and reports `PR: conflict`
with the conflicting files; it never resolves them itself. `/feat` (and
`/fix` at its phase 5) then moves the run with `feat-implementer` in
rebase mode, as at any phase boundary (see [When main moves](#when-main-moves)),
and spawns the shipper a second time, as the first. That move's Log line
is written after the second report, in the local state file only, and the
final message lists it. Before any push, in every mode, the shipper checks
the commits it would push: a `logistics-wip:` commit (a move's temporary
WIP commit) stops it with `PR: blocked` and `! WIP commit on <branch>;
nothing pushed`.

## Board tracking

Optional, and off unless the repo has a `.logistics.yml`; setup, scope and
the board's own workflows are in [install.md](install.md#5-board-tracking-optional).
The skills run `.apm/skills/feat/scripts/tracker.sh` (no agent does): one
`check` at the start of each run, which prints the board it will write to,
then one move per moment, only when the brief has an `Issue:` line.

| Moment                                                                                  | Status      |
| --------------------------------------------------------------------------------------- | ----------- |
| `/brief` writes the brief (from an idea: once confirmed at the gate, after creating the issue) | Brief       |
| `/feat` setup; resume in phases 2–6; "back to N" (2–6) from 7 or 8                      | In progress |
| Phase 7 starts; resume in phases 7–8                                                    | In review   |
| The PR is merged and closes the issue                                                   | Done, by the board's "Item closed" workflow |

A failed move never stops the run: it is logged as a `[!]` line in the
state file and flagged at the next gate. A failed `check` stops it.

## The state file

`specs/<short-name>/feat-state.md` (`specs/<NNN>-<short-name>/` once the
shipper numbers it) is the memory of the run: branch,
worktree, size, current phase, conventions, allowed hooks, the issue if any, the brief, and a
log of every gate with what you accepted and rejected (and why) and every
performance attempt with its numbers, and each implementer's Not verified
list (the latest one per implementer counts). Every agent reads it; `/feat resume`
starts from it; the PR links to it. It's updated at each gate, only
through [`state.sh`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/feat/scripts/state.sh):
`init` creates it, `set` changes one header field, `log` appends Log
lines, and fixed queries answer what `step.sh` and the shipper read from
the Log (the test cycle and retry, the shipped verdict, phase 2's mode on
resume, a refused base, the resume and rebase searches, the PR body's code
review part). `step.sh` writes the gate lines, `Current phase`, `Size`
and the moves; the coordinator writes only the setup line, an override,
the tracker's and the issue's lines. The agents' report files sit beside
it, in `reports/`, never committed.

Each gate line carries its tag, `[soft]` or `[hard]`, after the phase
name, and its sub-lines say what happened at it:

```markdown
- [x] 4 Design review [hard] — finding needs you: D2
    - D2 <spot> — <a few words> — rec: user (<why>)
    - answer: leave D2 (user: "behind the VPN")
    - outcome: picked D1; rejected D2 (user: "behind the VPN")
- [x] 5 Tasks [soft] — analyze ran, no CRITICAL/HIGH
```

- `answer:` is your answer, its kind first (`approved`, `changed`,
  `picked`, `back to N`, `stop`, …) and your words quoted;
- `outcome:` is what the answer led to, when it is more than the answer
  says (the findings picked and rejected, a size change);
- `override: hard — <reason>` is the coordinator turning a soft verdict
  into a hard gate, written just before the boundary call.

`resume` reads the tags and the `answer:` lines, so an answered gate is
never asked again and an amend it led to is not redone.

## When main moves

Runs go in parallel, one worktree each; when one merges, the others fall
behind `origin/<default>`, and the open PRs among them may conflict.
Running runs keep up on their own; `/feat rebase [PR]` and `/fix rebase
[PR]` (as a plugin, `/logistics:feat rebase` and `/logistics:fix rebase`)
bring shipped runs back onto the current main. The rules are in
[`.apm/skills/feat/references/move.md`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/feat/references/move.md),
read only when `step.sh` reports that main moved, and, for shipped runs, in
[`.apm/skills/feat/references/rebase.md`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/feat/references/rebase.md),
read only by a `rebase` run.

- **Before each phase** (from phase 3 of `/feat`, phase 2 of `/fix`, and
  any phase rerun by "back to N"): `step.sh` runs `git fetch origin
  <default>` and `git merge-base --is-ancestor origin/<default> HEAD`. When
  main has not moved, nothing happens: no agent, nothing shown or logged.
  When it has, the move below runs before the phase. A move that went
  through is listed at the next gate (`Main moved <old> → <new>; checks
  <result>`, then each file resolved alone); one that needs you stops
  before the phase at `## Main moved — needs your call`, where you answer
  "ok" (the recommendations), your own resolution, "stay" (the run stays
  on the old base until main moves again) or "stop". A failed fetch is
  logged as `[!] move — git fetch failed`, flagged at the next gate, and
  the run goes on.
- **Which PRs** (`rebase`): with an argument (a PR number, URL or branch), that PR;
  without one, every open PR of yours on this repository that GitHub marks
  conflicting. Only your own PRs of this repository whose branch adds one
  state file: forks and other repositories are skipped, and naming
  another author's PR stops to ask before anything is fetched.
- **The move**: `feat-implementer` in rebase mode, on the implement row
  at the run's size, rebases the branch onto `origin/<default>`, resolves
  alone the conflicts that keep both sides' intent and undoes the whole
  move to ask you about the others (`move.md` has the rules); then the
  checks (the full ones on a PR).
- **Uncommitted work**: set aside in a temporary `logistics-wip:` commit
  and a pre-move ref, never the stash and never pushed, both gone once the
  move reports.
- **Undo and repair**: when you refuse a recommendation at the move's
  gate, or stop there, the run stays on the old base: the move was undone
  before it asked, the WIP commit too, so tracked files and the index are
  as before (untracked files a check created may remain). A run that died
  mid-move is repaired by `resume` before anything else: it aborts an
  unfinished rebase, puts the branch back on the pre-move ref and undoes a
  leftover `logistics-wip:` commit (found by its subject even when the ref
  was never set), then logs `move — repaired`.
- **The log**: every move, kept or refused, gets a `move —` line in the
  state file's Log (format in `move.md`, written by `step.sh`), so
  `resume` and the PR body show it.
- **The push**: `feat-shipper` in rebase mode, on the ship row, through
  the same two `ship.sh` calls, commits
  the move's mechanical check fixes in a commit of their own, then the
  move's Log lines alone (`docs(specs): log rebase onto <short sha>`,
  holding only Log lines: the local `done (PR #N)` mark stays out),
  checks the spec number again, and pushes with
  `--force-with-lease=<branch>:<the PR head it started from>`. If someone
  pushed to the PR meanwhile, the push is refused, the branch goes back to
  that PR head, nothing is overwritten, and the run says so. It scans for
  secrets twice: the staged files before each commit, and before the push
  the lines the PR brings onto the new main, none of main's own commits.
  Before the push it checks that the PR's head is the run's branch and
  the PR is in this repo. A check that fails after the move is listed
  under `Not verified`, never fixed at this point. It adds a
  note under `### Rebases` in the PR body (what was resolved alone, what
  you decided, the checks), and points the body's state-file link at the
  new path when the spec number changed.
- **Several PRs waiting on you**: without an argument, a PR whose move
  needs your call waits, undone, and the next one goes on. After the last
  PR, one gate lists every waiting PR's questions under `PR #<n>`
  headings, after what was already pushed or skipped; then each one moves
  with your answers. A PR you refuse stays as it is, its `stayed on` line
  logged, nothing pushed.
- **At the end**: one line per PR: pushed with what was resolved alone
  and decided, nothing to do, skipped with why, waiting, or its error.
  Never a command for you to run.

## /fix

`/fix #N`, `/fix <issue URL>`, `/fix "<symptom>"` or `/fix resume` takes a
bug report to a reviewed PR with Spec Kit's bug extension (`specify
extension add bug`): assess, fix and test, each in a subagent, then the
code review and the ship of `/feat`. It reads the same harness as `/feat`
([`.apm/skills/feat/references/harness.md`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/feat/references/harness.md):
thin orchestrator, the step script, gate shape, review findings, state
file, board moves, resume) and calls the same `step.sh`; its own values
and gate messages are in [`.apm/skills/fix/SKILL.md`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/fix/SKILL.md),
which is what the coordinator reads for this section. Its sizes and
reviewer groups are `sizes.json`'s `fix` part.

### Roles

- **Coordinator**: the session running `/fix`. As in `/feat`, it holds the
  gates `step.sh` decides, changes only the state file (through `state.sh`
  and `step.sh`), never reads
  code, report files or runs checks; it
  quotes a line of assessment.md, fix.md or test.md only when you must
  decide on it. The calls to `step.sh` split as in `/feat`: the assessor
  (assess and test), the implementer (fix and review fixes) and the
  shipper each run their boundary's call and hand the output back; the
  coordinator calls it at setup, after the review batch, for each answer,
  after a move, when an agent's block slipped and for the `done:` check
  after the shipper. Setup is two `preflight.sh` calls around `EnterWorktree`:
  the first classifies the argument, checks the install and the bug
  extension, runs the board check, fetches the default branch, reads the
  hooks as data, reads an issue's title and its author's association, and
  builds a slug unused by any bug dir, local branch or remote branch
  `fix-<slug>`; the second renames the branch to `fix-<slug>`, chained
  with `state.sh init` and the first `step.sh` call. The model still
  judges a refactor, a backport, several bugs in one report, the `/tiny`
  offer and a symptom's slug words.
- **`feat-bug-assessor`**: runs `speckit-bug-assess` (phase 1) or
  `speckit-bug-test` (phase 3); never edits source. Every test is a fresh
  spawn, never the agent that wrote the fix. Its chores are calls to
  [`trail.sh`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/feat/scripts/trail.sh):
  `rotate` numbers an earlier report, `sections` checks the required
  parts, `slug` compares the slugs, and `redact` replaces every
  secret-looking value in the report with `<redacted>` by
  `secret-scan.sh`'s own rules (a key's value whatever its length).
- **`feat-implementer`** in bug mode runs `speckit-bug-fix` (phase 2),
  with `trail.sh`'s `rotate`, `slug` and `redact` on `fix.md`; in fix mode
  it applies the review fixes (phase 4).
- **`feat-code-reviewer`**, unchanged, with a subset of its lenses.
- **`feat-shipper`** in fix mode commits `fix(<scope>)` with the
  `.specify/bugs/<slug>/` trail and opens the PR through the same two
  `ship.sh` calls, with no numbering and `Fixes #N`; its `Not verified`
  section lists the implementer's logged items, then its own unrun
  checks. Never merges. Before
  committing it runs `.apm/skills/feat/scripts/secret-scan.sh` on the
  staged diff (as `/feat`'s ship now does too): only added lines count, and a match (a vendor token prefix,
  a key named password, token, secret or api key holding a literal
  value, an `Authorization` `Bearer` token, a bare JWT, or a URL with a
  password in its authority) stops the ship with `<file>:<line>` and the
  rule, never the value. The tracker refuses an issue body by the same rules.

No agent is continued: every spawn is fresh.

### Phases at a glance

| # | Phase       | Runs in                                         | Produces                                          | Gate                                                                                         |
| - | ----------- | ----------------------------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| 0 | Setup       | coordinator                                     | worktree on `fix-<slug>`, state file              | hard only if a hook would branch or commit                                                   |
| 1 | Assess      | `feat-bug-assessor` (assess mode)               | `assessment.md`, the proposed size                | **stop** if not a bug; **hard** by default; soft only when nothing needs your call (below)   |
| 2 | Fix         | `feat-implementer` (bug mode)                   | the code, `fix.md`                                | soft unless deviations from the assessment, a failing check or a status other than `applied` |
| 3 | Test        | `feat-bug-assessor` (test mode), always fresh   | `test.md` with `verified`, `partial` or `failed`  | soft on `verified`; **hard** on `partial` or an item left unaccounted; `failed` back to 2 once, then **hard**              |
| 4 | Code review | `feat-code-reviewer` ×1 (small, medium) or ×2–3 | findings B, S, P, C with recommendations; fixes applied, then 3 again | **hard** on a security risk area, `Size: large`, or a `user` or `S` finding; else soft |
| 5 | Ship        | `feat-shipper` (fix mode)                       | one `fix(<scope>)` commit, push, PR               | none                                                                                         |

From phase 2 on (once the assess gate has set the size), each phase starts
with the base check of [When main moves](#when-main-moves).

### Gates

`step.sh` decides each of them from the reports and the Log, as in `/feat`.

- **Assess** stops the run when the report is not a bug (a missing
  feature points to `/brief #N`), invalid or unintelligible; the issue is
  left untouched. It is soft only for a small fix with high confidence, a
  reproduced bug, one remediation, no public behaviour change, a trusted
  report author, no open question, no security risk and no issue to
  create. Nothing from the report (command, script or code) runs unless
  you approve it, and only an `OWNER`, `MEMBER` or `COLLABORATOR` of this
  repo's issue (or you, for a typed symptom) counts as trusted. A security bug is always hard: it
  suggests a private security advisory instead of an issue and states the
  repo's visibility. The assessor makes this boundary's `step.sh` call
  itself, so the gate (or phase 2's spawn) arrives in its hand-back;
  issue creation and the building move follow it, before the
  implementer's spawn.
- **Fix** turns hard on deviations from the assessment (handled like a size
  increase: one size step up, or "back to 1"), a failing check, or a status
  other than `applied`.
- **Test**: the tester gets the checks the fix could not run (the fix gate
  doesn't show them): it runs each one its rules allow or lists it under
  `Missing for verified` (`partial`); an item it leaves unaccounted makes
  the gate hard, and so does a missing `Not verified:` line in the review
  fixes' report just before the test. `partial` asks you for the missing environment or evidence;
  the first `failed` goes back to the fix once (`retry 1 of 1` in the
  log), a second one, or one after review fixes, is hard with "back to 1"
  offered. A verdict other than `verified` reaches ship only on your
  explicit words, logged and copied into the PR body.
- **Code review**, in this order: a security bug is hard (the go-ahead
  to ship is asked here); `Size: large` is hard; a `user` or `S` finding is
  hard; otherwise soft, and the reviewers' `apply` findings are fixed
  unasked. Fixes go to the implementer in fix mode, then a fresh test
  (`after review fixes`) must say `verified` again.
- At every phase, a failed check of the agent's `Wrote:` line (assessment.md,
  fix.md or test.md must be on it) makes the gate hard before any other
  rule, as in `/feat`.
- "skip 1", "skip 2" and "skip 3" are refused; "skip 4" on a security bug
  still asks for the go-ahead to ship; every "back to N" is logged and
  starts a new test cycle.

### Size matrix

Each cell: model · effort, printed by `step.sh` in every spawn block and
passed by `/fix` on the spawn. The size is set
at the assess gate, so phase 1 is the same in every column.

<!-- sizes-start fix-matrix -->

| #  | Phase                                  | Agent                | small           | medium          | large           |
| -- | -------------------------------------- | -------------------- | --------------- | --------------- | --------------- |
| 1  | Assess                                 | `feat-bug-assessor`  | opus · medium   | opus · medium   | opus · medium   |
| 2  | Fix                                    | `feat-implementer`   | sonnet · medium | opus · medium   | opus · high     |
| 3  | Test                                   | `feat-bug-assessor`  | sonnet · medium | sonnet · high   | opus · medium   |
| 4a | Correctness, spec, standards (lens 7a) | `feat-code-reviewer` | sonnet · medium | opus · medium   | opus · medium   |
| 4b | Security (lens 7b)                     | `feat-code-reviewer` | sonnet · medium | opus · medium   | opus · high     |
| 4c | Performance (lens 7c)                  | `feat-code-reviewer` | sonnet · medium | sonnet · medium | opus · medium   |
| 4d | Over-engineering (lens 7d)             | `feat-code-reviewer` | sonnet · medium | sonnet · medium | sonnet · medium |
| 5  | Ship                                   | `feat-shipper`       | haiku · medium  | haiku · medium  | haiku · medium  |

<!-- sizes-end fix-matrix -->

**Phase 4 reviewers.** small: one reviewer, lenses 7a+7b+7d. medium: one
reviewer, 7a+7b (7a+7b+7c for a performance bug). large: 7a and 7b in
parallel, plus 7c for a performance bug. A group runs on the strongest
model and effort among its lenses. These groups are now in `sizes.json`'s
`fix.groups` (the `performance` set for a performance bug), carried into
`sizes.tsv`. The spec pass reads assessment.md and fix.md, as a bug has no
spec.md. Applying the review fixes and moving onto a new main use the
phase 2 row.

### Why these choices

- **Assess on Opus at every size.** Every later phase builds on its root
  cause, and the size isn't known until it reports.
- **A different agent tests the fix.** The fixer never marks its own work:
  each test run is a fresh `feat-bug-assessor`.
- **One retry, then you.** A first `failed` is often a missed case the fix
  can catch; a second means the assessment is wrong, which a person should
  see.
- **Fewer reviewers than `/feat`.** A fix is a small diff against a known
  root cause; readability (7e) and the design review are left out, and
  performance joins only for a performance bug.
- **A hard assess gate by default.** Running a stranger's reproduction
  steps, opening a public issue for a security bug or fixing the wrong
  thing costs more than one stop.

### Board moments

| Moment                                                                       | Status      |
| ---------------------------------------------------------------------------- | ----------- |
| Assess gate passes (after creating the issue for `/fix "<symptom>"`); resume in 1–3; "back to N" (1–3) from 4 or 5 | In progress |
| Phase 4 starts; resume in 4–5                                                | In review   |
| The PR (`Fixes #N`) is merged                                                | Done, by the board's workflow |

Setup runs `check` only. With board tracking and no issue, `/fix
"<symptom>"` creates a `bug` issue from the assessment after the gate,
in the repo you confirm (never for a report that isn't a bug, nor by
default for a security bug). Without an issue there are no moves and no
`Fixes` line.

### State file

`.specify/bugs/<slug>/feat-state.md`, beside the extension's reports, in
`/feat`'s format (`# /fix state: <bug title>`, a `## Report` section
instead of the brief). It is committed with the trail (state file,
assessment, fix and test files; never `reports/`), already marked
`done (shipping)`. `/fix resume` searches it in this checkout and in every
worktree of `git worktree list`, enters that worktree, and asks when
several runs are unfinished.

## /tiny

`/tiny "<change>"`, `/tiny #N` or `/tiny <tiny brief>` makes a trivial
change in the session you type in: no Spec Kit, no size table, no state
file, no harness. [`.apm/skills/tiny/SKILL.md`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/tiny/SKILL.md)
is authoritative for this section; `mise run lint` keeps it under 200
lines.

| # | Phase | Runs in                                       | Gate                                                       |
| - | ----- | --------------------------------------------- | ---------------------------------------------------------- |
| 1 | Frame | you                                           | **hard**: the tiny brief, and issue or not                 |
| 2 | Do    | you                                           | none                                                       |
| 3 | Check | you; `feat-code-reviewer` (7a) for a contract | only on a `user` finding or a check that stays red         |
| 4 | Ship  | you                                           | none: ends with the PR link (stops on a secret or conflict) |

**The tiny check**, in Frame and whenever something new comes up: one
reading of the ask, no design choice left open; no new dependency,
service, permission or exposure, nothing touching auth, secrets, personal
data or a public interface; about 10 files and 300 changed lines at most;
for a bug, a cause plain from the code. A failed condition stops the run
with the handoff (`/brief <tiny brief>`, `/brief #N` or `/brief "<ask>"`,
`/fix #N` or `/fix "<symptom>"`), worktree and edits left in place.
`/brief` (before its interview) and `/fix` (at setup) offer `/tiny` for
work that passes it.

**The tiny brief** is `/brief`'s format cut to its header (`Size: tiny`),
Why, Behaviour and Acceptance, in `specs/briefs/<short-name>.md`, and is
committed with the change so the issue's `Brief:` link resolves. `tracker.sh
create-issue` reads it as it reads a brief.

**Board moves** use the same `tracker.sh`: `check` at the start;
`create-issue` at the Frame gate when you choose it; `building` after that
gate and `review` when Check starts, both only with an issue; `Closes #N`
in the PR. A failed move is shown and never blocks.

**Fresh review**, only when the diff changes a contract other files read
(a report format, a mirrored table, a schema, a script's output):
`feat-code-reviewer`, sonnet · medium, lens 7a, with the tiny brief as the
spec. Its `apply` findings are applied, `skip` ones go in the PR body.

## Agents

<!-- sizes-start agents-table -->

| Agent                  | Phase(s)                                                                       | small size                                     | Denied tools                                                     | Loads                                              | Writes                                               |
| ---------------------- | ------------------------------------------------------------------------------ | ---------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------- | ---------------------------------------------------- |
| `feat-brief-reviewer`  | 1                                                                              | sonnet · medium                                | Edit, Write, NotebookEdit, Agent, Artifact, EnterWorktree, Skill | —                                                  | nothing                                              |
| `feat-bug-assessor`    | `/fix` 1 (assess mode), 3 (test mode)                                          | opus · medium (assess), sonnet · medium (test) | Edit, NotebookEdit, Agent, Artifact, EnterWorktree               | `speckit-bug-assess`, `speckit-bug-test`           | assessment.md, test.md                               |
| `feat-specifier`       | 2                                                                              | sonnet · medium                                | NotebookEdit, Agent, Artifact, EnterWorktree, Skill              | `speckit-specify`                                  | spec.md                                              |
| `feat-planner`         | 3, 4 (amend)                                                                   | opus · high                                    | NotebookEdit, Agent, Artifact, EnterWorktree, Skill              | `speckit-plan`                                     | plan.md, design docs; accepted findings into spec.md |
| `feat-design-reviewer` | 4                                                                              | sonnet · medium                                | Edit, Write, NotebookEdit, Agent, Artifact, EnterWorktree        | per lens, on demand                                | nothing                                              |
| `feat-tasker`          | 5                                                                              | sonnet · medium                                | NotebookEdit, Agent, Artifact, EnterWorktree, Skill              | `speckit-tasks`, `speckit-analyze`                 | tasks.md, small artifact fixes                       |
| `feat-implementer`     | 6, 7 (fix mode), any boundary (rebase mode); `/fix` 2 (bug mode), 4 (fix mode) | sonnet · medium                                | Agent, Artifact, EnterWorktree                                   | `speckit-implement`; `speckit-bug-fix` in bug mode | code, tasks.md; fix.md in bug mode                   |
| `feat-code-reviewer`   | 7                                                                              | sonnet · medium                                | Edit, Write, NotebookEdit, Agent, Artifact, EnterWorktree        | per lens, on demand                                | nothing                                              |
| `feat-shipper`         | 8; `/fix` 5 (fix mode); `rebase` (rebase mode)                                 | haiku · medium                                 | NotebookEdit, Agent, Artifact, EnterWorktree, Skill              | —                                                  | docs, commits, PR                                    |

<!-- sizes-end agents-table -->

`feat-code-reviewer` also runs `/fix`'s phase 4, unchanged, with lenses
7a–7d only, and `/tiny`'s fresh review with lens 7a. Agent files carry no model or effort: `/feat` and `/fix` pass
both on every spawn, as `step.sh` prints them from `sizes.tsv` (`/brief` for
`feat-brief-reviewer`). Tool limits are deny lists (`disallowedTools`) rather
than allow lists, so a new tool is available to an agent unless denied. Every agent denies `Artifact` and `EnterWorktree` (`mise run lint` checks it), and the five that never invoke a skill by name also deny `Skill`. The saving from these denials depends on your setup (which tools and skills your Claude Code loads, and whether the run is interactive, background or headless). No agent but the shipper commits (the implementer's rebase mode makes
one temporary WIP commit, undone before it reports and never pushed), and
no agent spawns further agents.
Every report ends with `Wrote:`, absolute paths: the specifier, planner and
tasker always list their artifact (spec.md, plan.md, tasks.md) plus every
file they created or changed in that spawn; the implementer lists the
files it created plus its artifacts (never files it only modified or
deleted); the code and design reviewers list only their report file. Each
agent given a report path lists it too (the shipper under the numbered
dir); with none, the reviewers say `none`. The coordinator checks them on
disk before accepting the report.

## Baseline

What `/feat` and `/fix` runs cost before the changes meant to make them
cheaper, measured with [`measure.py`](measure.md) so a later change can be
judged against it (`--compare-since` the day it merged). The figures are the
medians of the `all repos` block of a `measure.py --all` run over the
maintainer's own runs: read them as one person's workload, not a benchmark.

- **Date**: 2026-11-19, on transcripts written by Claude Code 2.1.308 to
  2.1.328.
- **Weights** (the defaults):

  ```text
  weights: input 1, cache read 0.1, output 5, cache write 1h 2, cache write 5m 1.25; haiku 1, sonnet 3, opus 5
  ```

  One model had no weight and took the highest:
  `unweighted models: claude-fable-5-2 (weighted as 5)`.
- **Runs**: 104 counted (97 finished, 7 unfinished, 0 resumed), 0 left out.
  The medians are over the finished ones: 78 of `/feat`, 19 of `/fix`.

### Coordinator

| Per run (median)             | `/feat` | `/fix` |
| ---------------------------- | ------: | -----: |
| model calls                  |      62 |     45 |
| … that spawn an agent        |      14 |      8 |
| … chores only                |      21 |     21 |
| … text only                  |      26 |     13 |
| context, first call          |   51.8k |  58.2k |
| context, median of its calls |  112.9k |  86.5k |
| context, max of its calls    |  167.3k | 118.5k |
| share of the run's cost      |     15% |    30% |

Failed tool calls are totals, not medians. `/feat`, over 78 runs: Bash 167,
Edit 18, Agent 11, ExitWorktree 3, EnterWorktree 1. `/fix`, over 19 runs:
Bash 33, Agent 12, EnterWorktree 1, ExitWorktree 1.

### Agents

Each row is a median over the runs where the type appears (`runs`), so the
cost shares need not add to 100%. `feat-sec-reviewer` and
`feat-cost-reviewer` are the design reviewers of earlier versions, since
merged into `feat-design-reviewer`.

`/feat`:

| Type                 | runs | spawns/run | calls/spawn | ctx first | cost share | model min | tool min |
| -------------------- | ---: | ---------: | ----------: | --------: | ---------: | --------: | -------: |
| feat-implementer     |   78 |          6 |        40.8 |     38.6k |        47% |       4.2 |      2.7 |
| feat-planner         |   78 |          2 |        30.2 |     36.2k |        18% |       6.9 |      0.4 |
| feat-code-reviewer   |   78 |          5 |          11 |     34.9k |         8% |       1.6 |      0.2 |
| feat-design-reviewer |   50 |          3 |        12.8 |     33.5k |         4% |       1.9 |      0.1 |
| feat-sec-reviewer    |   28 |          1 |           5 |     36.6k |         2% |       0.7 |      0.2 |
| feat-tasker          |   78 |          1 |           8 |     41.2k |         2% |       1.7 |      0.1 |
| feat-cost-reviewer   |   28 |          1 |           3 |     29.1k |         1% |       0.3 |      0.0 |
| feat-specifier       |   78 |          1 |           5 |     39.2k |         1% |       0.9 |      0.1 |
| feat-shipper         |   78 |          1 |          25 |     34.3k |         1% |       1.7 |      0.7 |
| Explore              |    2 |          1 |         9.5 |     16.1k |         1% |       0.8 |      0.4 |
| general-purpose      |    1 |          1 |           6 |     36.5k |         0% |       0.2 |      0.2 |

`/fix`:

| Type               | runs | spawns/run | calls/spawn | ctx first | cost share | model min | tool min |
| ------------------ | ---: | ---------: | ----------: | --------: | ---------: | --------: | -------: |
| feat-implementer   |   19 |          2 |          27 |     40.1k |        35% |       3.5 |      1.1 |
| feat-bug-assessor  |   19 |          3 |        16.3 |     35.8k |        18% |       1.4 |      0.5 |
| feat-code-reviewer |   19 |          1 |          14 |     35.7k |        11% |       2.2 |      0.1 |
| feat-shipper       |   19 |          1 |          14 |     35.7k |         2% |       0.7 |      0.9 |
| general-purpose    |    1 |          1 |           8 |     35.8k |         1% |       0.5 |      0.2 |
| claude-code-guide  |    1 |          1 |           4 |     28.1k |         0% |       0.4 |      0.4 |

### Wall clock

| Per run (median)     | `/feat` min | share | `/fix` min | share |
| -------------------- | ----------: | ----: | ---------: | ----: |
| agents working       |        81.1 |   49% |       21.4 |   35% |
| waiting for the user |        55.7 |   44% |       40.0 |   58% |
| coordinator thinking |         7.4 |    5% |        4.3 |    7% |
| coordinator tools    |         0.5 |    0% |        0.7 |    1% |
| run duration         |       156.6 |       |       73.7 |       |
| user answers         |           4 |       |          4 |       |

### First request

What the first request of each type's first spawn in a run is made of, in
characters (medians).

`/feat`:

| Type                 |   tools | skills listing | system prompt | instructions |   total |
| -------------------- | ------: | -------------: | ------------: | -----------: | ------: |
| feat-implementer     |   53482 |        25093.5 |          3876 |         5574 |   88225 |
| feat-planner         | 53563.5 |        25093.5 |          4056 |         5574 |   88405 |
| feat-code-reviewer   |   51821 |        25093.5 |          9584 |         5574 |   92272 |
| feat-design-reviewer |   51984 |          25649 |          7169 |         6059 |   91051 |
| feat-sec-reviewer    |   51821 |          24925 |          2470 |         4559 | 83309.5 |
| feat-tasker          | 53563.5 |        25093.5 |          3146 |         5574 |   87495 |
| feat-cost-reviewer   |   48280 |          24925 |          2111 |         4559 |   79430 |
| feat-specifier       | 53563.5 |        25093.5 |          3249 |         5574 |   87598 |
| feat-shipper         |   53482 |        25087.5 |          4637 |         5574 |   88725 |
| Explore              | 13783.5 |          23840 |        3299.5 |            0 |   40923 |
| general-purpose      |   58828 |          29794 |          3158 |         6214 |   97994 |

`/fix`:

| Type               | tools | skills listing | system prompt | instructions | total |
| ------------------ | ----: | -------------: | ------------: | -----------: | ----: |
| feat-implementer   | 53899 |          25658 |          6178 |         6533 | 92428 |
| feat-bug-assessor  | 52906 |          25658 |          9789 |         6533 | 95046 |
| feat-code-reviewer | 52238 |          25658 |         10011 |         6533 | 94600 |
| feat-shipper       | 53899 |          25658 |          7554 |         6533 | 93804 |
| general-purpose    | 58651 |          25658 |          3158 |         6693 | 94160 |
| claude-code-guide  |  7941 |              0 |         59913 |         6533 | 74387 |

The tool schemas of a `/feat` implementer's first request, by name: Artifact
37883.5, EnterWorktree 4042, Bash 3541, Read 1948, Skill 1832, ToolSearch
1469, Edit 993, SubagentHandback 892, Write 668, DeferredToolPlaceholder
204, advisor 91. The other `feat-*` types carry the same two largest ones.

### Tokens

| Per run (median) |    `/feat` |     `/fix` |
| ---------------- | ---------: | ---------: |
| input            |       1067 |        391 |
| cache write      |       2.2M |     599.0k |
| cache read       |      50.6M |      13.5M |
| output           |     450.8k |     129.7k |
| cost units       | 44,600,754 | 12,268,203 |

Before sharing such output: it holds repo paths, the home directory and
session ids. Post only the `all repos` block's figures, without the
per-repo blocks or the unfinished, resumed and left-out lists
([measure.md](measure.md#before-sharing-the-output)).
