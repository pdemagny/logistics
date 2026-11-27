---
title: Usage
weight: 20
---

# Using the workflow

Everything here runs in Claude Code. A feature takes two commands, in two
contexts:

```
/brief "let users edit a stack's config from the CLI"
   … interview, brief, size …
/clear
/feat specs/briefs/edit-stack-config.md
   … gates …  → PR link
```

A bug takes one: `/fix #42` ([below](#fixing-a-bug-fix)). So does a
trivial change, in a single session: `/tiny "fix the install link"`
([below](#a-trivial-change-tiny)).

Words you'll meet:

- **Brief**: a one-page description of the feature (why, behaviour, scope,
  acceptance), written with you by `/brief`. `/feat` builds from it alone.
- **Size**: small, medium, large or huge. It picks the model and effort of
  every agent and how often the run stops for you ([Sizes](#sizes)).
- **Gate**: a point where the run reports to you. At a *hard* gate it waits
  for your answer; at a *soft* one it reports and goes on.
- **Phase agent**: a `feat-*` subagent that does one phase (plan, review,
  implement…) in its own fresh context, then reports back.
- **Lens**: one angle of a review (security, cost, performance…). Reviews
  are numbered by phase and lens: 4a is the design's security lens, 7d the
  code's over-engineering lens.
- **State file**: `feat-state.md`, the run's memory: size, phase, every
  decision you made. `/feat resume` and `/fix resume` start from it.

## 1. Brief: `/brief "<idea>"`

Claude reads the code the idea touches, then asks you questions one at a
time (`interview-me`), each with its guess attached. When a question is a real choice between
roads, you get one table of the options by criteria, the recommended one
marked, before the guess; yes/no questions get none. It proposes a size and
writes the brief to `specs/briefs/<short-name>.md` at the top of the repo
(of its worktree when you run it in one): why, how it's handled
today, behaviour, out of scope, alternatives rejected, acceptance,
constraints, size, short name. Expect pushback: before writing a decision
down, Claude gives its strongest counter-argument. It ends by printing the
brief's absolute path; run outside a git checkout, it asks for the repo's
path before anything else (and stops without one), and the brief never
goes to a temporary dir.

A fresh agent (`feat-brief-reviewer`) then reads the brief without the
interview, as the build will. You confirm the brief together with its
paraphrase of the feature, its own size estimate and its findings `F1…`,
each with a recommendation; "ok" accepts them all.

Claude may also start it on its own when you ask it to build a feature.
It's not for bugfixes (use [`/fix`](#fixing-a-bug-fix)), trivial changes
(use [`/tiny`](#a-trivial-change-tiny)) or pure refactors. You
can also write a brief by hand in the same format and skip this step.

From a GitHub issue, run `/brief #N` (or pass its URL): Claude reads it
with `gh`, its title and body are the idea and its unchecked checklist items
are questions the interview answers. It reads the code and docs the
issue touches and opens with "Where it stands" (the ask, today with
file:line, what is decided, what is open), then asks its first question in
the same message. The brief records the issue, and the PR
says `Closes #N`, so merging closes it.

From a tiny brief, run `/brief <its path>` (`/tiny` hands you this when
the work outgrew it): its why, behaviour and acceptance stand, the
interview asks only for the rest, and the full brief keeps its short name
and issue. `/feat` refuses a tiny brief and points here or to `/tiny`.

**Board tracking** (optional): with a `tracker:` section in `.logistics.yml`
at the repo root,
`/brief` and `/feat` move the issue across a GitHub Projects board (Brief,
In progress, In review; Done when the PR merges). Each run first prints the
board it will write to. A brief without an issue gets one created after you
confirm it at the gate. Setup: [install.md](install.md#5-board-tracking-optional).

**Huge** ideas (several capabilities that could ship on their own) get a
capability map in `specs/maps/<name>.md` instead: you approve the map, then
it writes the first capability's brief. Each later capability starts with
`/brief specs/maps/<name>.md <capability-id>`.

## 2. Fresh context: `/clear`

The brief step ends by telling you to run `/clear`. Do it: the build's
coordinator re-reads its whole context on every call, so starting it
without the interview in it is the single cheapest thing in the workflow.
A skill can't clear the context itself; that's why the workflow is split
into two commands at this point, where you are typing anyway. Opening a new
session works too.

Start that session on the model you want coordinating (Opus recommended):
the coordinator runs on the session's model.

## 3. Build: `/feat <brief>`

The session becomes a thin coordinator: it never reads code. Every phase runs
in a `feat-*` subagent and Claude stops only at gates; see
[workflow.md](workflow.md) for which phases stop and when. It ends with a PR
link and never merges.

`<brief>` is the brief's path or just its short name (`/feat
edit-stack-config`): then `/feat` looks for `specs/briefs/<name>.md` in
this checkout and in the repo's other worktrees, asks when it finds more
than one, and names every path it searched when it finds none. Once the
brief is in the run's state file, `/feat` deletes it only when it is this
checkout's `specs/briefs/<short-name>.md`; any other brief (in another
worktree, or a file elsewhere you gave by path) stays, and the final
message names it.

A check an agent could not run (no credentials, a service down, a manual
step, a killed run) is never passed off as green: its task stays unticked,
the implementation gate lists it as Not verified, and the PR body repeats it
under `Not verified`. Run it and tick the task yourself.

State lives in `specs/<NNN-name>/feat-state.md`, next to the spec, plan and
tasks (`specs/<name>/` until the shipper numbers it). The feature is built
on branch `<name>`, in a worktree under
`.claude/worktrees/` when possible, so your checkout stays untouched.

## Answering a gate

```
## Phase 3–4: Plan and design review — needs your call
**What I did:** feat-design-reviewer ×3 on spec + plan: 4a (opus · medium), 4b (sonnet · medium), 4c (sonnet · high)
**How a fresh reader understood it:** … (check it against what you meant)
**What you should know:** D2 needs you
**Your call:**
1. D2 [cost] … — apply or leave? reviewer: drops FR-004, which the brief asked for
2. D1 [sec] … — rec: apply
3. D3 [design] plan says `config.Load` validates the file; it doesn't → validate in the new command — rec: apply
**Next:** phase 5 Tasks
```

On small and medium features, plan and design review share one gate, which
stops only when something needs your call. "ok" applies every `apply` and
leaves every `skip`; a `user` finding needs its own answer. A size increase is always asked on its
own; a decrease is applied and logged.

When the spec leaves no question open, phase 2 doesn't stop. The next gate
(phase 3 on large, by default) opens with the spec, the specifier's assumptions and the
checklist question, and "ok" accepts those too. A spec change you ask for
there is written by the planner together with the findings; "back to 2" is
for a rewrite.

Answer in plain words ("apply D1, leave D2: behind the VPN"). Rejections
are logged with your reason and never proposed again. You can also say:

| Say                            | Effect                                                       |
| ------------------------------ | ------------------------------------------------------------ |
| `back to N`                    | rerun phase N with what you now know                         |
| `skip N`                       | skip phase N; the skip and your reason are logged            |
| `size large` (or small/medium) | change the size from now on; later phases use the new column |
| `stop`                         | pause; the state file keeps everything                       |

Silence or an ambiguous answer is not taken as approval.

**Answer within the hour when you can.** After an hour the prompt cache
expires and the next call re-processes the whole context. Back later? Prefer
`/clear` then `/feat resume`: it starts from the state file, which is
smaller than the conversation.

## Resuming

```
/feat resume
```

Finds the latest unfinished `feat-state.md` (asks if there are several),
recaps, and shows the gate you were at.

## Fixing a bug: `/fix`

```
/fix #42                      # a GitHub issue (or owner/repo#42, or its URL)
/fix "export drops the last row when the file has no trailing newline"
/fix resume
```

One command, no brief and no `/clear` step: `/fix` assesses the report
with Spec Kit's bug extension (install it once per project: `specify
extension add bug`), fixes it, has a different agent verify the fix,
reviews the code and opens a PR with `Fixes #N` when there is an issue.
Installed as a plugin, it is `/logistics:fix`. A report that turns out to
be a missing feature stops at the first gate and points to `/brief #N`.

The gates you see:
- **Assess**: the root cause, its confidence, whether it was reproduced,
  the remediation and the proposed size. It stops for you unless all of
  it is plain and safe; it always stops when the report comes from someone who
  is not an owner, member or collaborator of the repo (nothing from it runs
  unless you approve it), for a
  security bug, and before it creates an issue for a `"<symptom>"` with
  board tracking.
- **Fix**: shown when the fix deviates from the assessment or a check
  fails.
- **Test**: it also tries each check the fix could not run, and one it
  still can't run makes it `partial`, so the PR's `Not verified` section
  lists only checks the shipper could not run. `verified` goes on;
  `partial` asks for what is missing; a `failed` test goes back to the fix
  once, then asks you. A fix that is not `verified` ships only if you say
  so.
- **Code review**: the reviewers' recommendations are applied unless the bug
  touches security, is large, or a finding is a judgement call or a security
  finding; then you pick.

The same answers work at every gate (`back to N`, `size <s>`, `stop`),
except that assess, fix and test can't be skipped. `/fix resume` finds the
unfinished run in this checkout or any of its worktrees (it asks when
there are several) and continues where it stopped. Phases, models and
board moves: [workflow.md](workflow.md#fix).

## A trivial change: `/tiny`

```
/tiny "fix the broken install link in the README"
/tiny #42                     # a GitHub issue (or owner/repo#42, or its URL)
/tiny specs/briefs/<name>.md  # a tiny brief from an earlier run
```

For a typo, a docs or markdown change, a small obvious feature or a bug
whose cause is plain: the whole run happens in the session you type in,
with no Spec Kit and no subagent. Installed as a plugin, it is
`/logistics:tiny`.

1. **Frame**: at most three questions, then a tiny brief in
   `specs/briefs/` (`Size: tiny`, Why, Behaviour, Acceptance) in its own
   worktree. You confirm it at the one gate; with board tracking and no
   issue, you also choose to **create an issue** from it or **proceed
   without one**. With an issue, the card moves to *In progress*.
2. **Do**: the edit, plus what your conventions say moves with it, then
   your project's checks.
3. **Check**: the card moves to *In review*; the diff is reread against
   the brief. When the change touches a contract other files read (a
   report format, a mirrored table, a schema), one `feat-code-reviewer`
   reads it fresh; it stops for you only on a judgement call.
4. **Ship**: secret scan, one commit with the brief, rebase on main, push,
   PR with `Closes #N`.

It stays tiny on purpose: one reading of the ask, no design choice, about
10 files and 300 lines at most, nothing touching auth, secrets, personal
data or a public interface, a bug's cause plain from the code. When the
work breaks one of these, `/tiny` stops and hands you the next command,
`/brief <tiny brief>` (or `/brief #N`) or `/fix #N`; the card stays on the
board for it. `/brief` and `/fix` offer `/tiny` the other way round.

## When main moves

```
/feat rebase           # every open PR of yours here that conflicts
/feat rebase 57        # one PR (number, URL or branch)
/fix rebase            # the same for /fix runs
```

While a run is going, it keeps up with main on its own: before each phase
(from Plan in `/feat`, from Fix in `/fix`) it checks whether main has
moved. When it has not, nothing changes and you see nothing. When it has,
the run moves onto the new main and the next gate says so, with the files
it resolved alone. A conflict that would drop or change behaviour stops
before the phase, with the move undone and the run on its old base:

| Answer        | Effect                                                          |
| ------------- | --------------------------------------------------------------- |
| `ok`          | the move again, with my recommendations                         |
| your words    | the move again, with your resolution for that file              |
| `stay`        | the phase runs on the old base; asked again once main moves on  |
| `stop`        | pause, as at any gate                                           |

When another PR merges first, yours may conflict with the new main.
`rebase` (as a plugin, `/logistics:feat rebase` or `/logistics:fix
rebase`) brings it back on its own: it rebases the branch onto the current
main, resolves the conflicts that keep both sides' intent, runs the full
checks and pushes with `--force-with-lease`, so nothing someone else
pushed to the PR is overwritten. It takes only your own PRs of this
repository whose branch holds a `/feat` or `/fix` state file; naming
someone else's PR asks first. A conflict that would drop or change
behaviour stops for your call; nothing is pushed until you answer. With
several PRs, the ones that need you wait and the others go on: their
questions come together in one gate at the end, grouped by PR.

Every move is logged in the run's state file. On a PR, that Log line
lands in its own commit, `docs(specs): log rebase onto <short sha>`
(nothing but Log lines), and the PR body gets a note under `### Rebases`
with what was resolved alone, what you decided and the checks.

At the end you get one line per PR: pushed, with what was resolved alone
and what you decided; nothing to do; skipped, with why; waiting; or its
error.
You never get a command to run. Details:
[workflow.md](workflow.md#when-main-moves).

## Sizes

Proposed by `/brief`; you decide.

| Size   | When                                                                                 | What changes                                                                                             |
| ------ | ------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| tiny   | one reading, no design choice, ~10 files / 300 lines, nothing sensitive              | no `/feat`: [`/tiny`](#a-trivial-change-tiny) in one session, no subagent                                |
| small  | up to ~30 tasks, no new service, permissions, exposure or dependency; docs-only work | Sonnet at medium effort for most phases, two code reviewers, fewest gates                                |
| medium | ~31–60 tasks, or a small one adding a service, permissions, exposure or dependency   | Opus for planning, design security, implementation, correctness and security review; five code reviewers |
| large  | more than ~60 tasks                                                                  | Opus for nearly every phase, higher effort on planning and reviews; gates at 3, 4, 5 and after each story by default ([configurable](workflow.md#configuring-the-gates)) |
| huge   | capabilities that could ship on their own                                            | a capability map; one brief, `/feat` run and PR per capability                                           |

Full matrix in [workflow.md](workflow.md#size--phase-matrix).

## Tuning

[`.apm/skills/feat/sizes.tsv`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/feat/sizes.tsv)
is what the runs read: `step.sh` prints the `model` and `effort` for each
spawn from it, and the coordinator passes them on every agent call.

- **In a checkout**, edit
  [`.apm/skills/feat/sizes.json`](https://github.com/pdemagny/logistics/blob/main/.apm/skills/feat/sizes.json)
  (models, efforts and the reviewer groups of `/feat` phases 4 and 7 and
  `/fix` phase 4) and run `mise run diagrams`, which regenerates
  `sizes.tsv` and the tables in [workflow.md](workflow.md).
- **In an install**, edit the installed `sizes.tsv`: the `row` line for
  the phase and size, and every `group` line that names that row. A group
  line carries its own model and effort (the strongest of its rows), and
  the groups are what `/feat` phases 4 and 7 and `/fix` phase 4 spawn.

Agent files carry no model or effort; outside the workflow an agent runs
on the session's model unless you name one.

| Setting         | Values                                                 | Effect                                                       |
| --------------- | ------------------------------------------------------ | ------------------------------------------------------------ |
| model           | `haiku`, `sonnet`, `opus`, `fable`, or a full model ID | capability vs. usage; Opus also has its own plan limit       |
| effort          | `low`, `medium`, `high`, `xhigh`, `max`                | thinking per step and number of tool calls on the same model |
| reviewer groups | `groups` in `sizes.json` (the `group` lines of `sizes.tsv`) | fewer reviewers = fewer cold starts                     |
| gates           | decided by `step.sh` (a checkout change, with its tests) | more stops where mistakes cost more                        |

Suggested approach: run two or three real features, note the phase where
results were weakest, and raise that phase's effort before its model.

## Using the agents on their own

They're ordinary Claude Code subagents: "have feat-code-reviewer review my
uncommitted diff with lenses 7b and 7d", "have feat-design-reviewer review
this plan with lens 4b". Installed as a plugin, they're `logistics:feat-code-reviewer` and
so on.

## When something goes wrong

| What you see | What to do |
| --- | --- |
| `apm` or `specify`: command not found after installing | `uv tool update-shell`, then open a new shell |
| `/brief`, `/feat`, `/fix` or `/tiny` is not a known command | Restart Claude Code after installing. Installed as a plugin, they are `/logistics:brief` and so on. `install.sh check` lists what is missing ([install.md](install.md#4-check)) |
| `/fix` stops at setup and names `specify extension add bug` | Run it in the project, then `/fix` again |
| `tracker: error: …` at the start of a run | Check `.logistics.yml` is committed and pushed, and `gh auth refresh -s project` ([board tracking](install.md#5-board-tracking-optional)); setup's `origin/<default>:.logistics.yml line <n>: …` names a line of the file as pushed (its `gates:` section included): fix that line and push it ([gates](install.md#7-configure-the-gates-optional)) |
| A `[!] tracker:` line at a gate | A board move failed; the run went on. Move the card by hand |
| The run ends with a line starting `! cd … && bash … ship.sh prepare …` | The ship script was blocked in the session. Type that line as is: the `!` runs it in Claude Code |
| The run ends with `! spec-number: error: …` | Nothing was pushed. Fix the cause (usually `gh` auth or network), then `/feat resume` |
| Your PR conflicts after another one merged | `/feat rebase <PR>` (or `/fix rebase <PR>`) ([When main moves](#when-main-moves)) |
| `rebase` ends with `! push refused: …` | Someone pushed to the PR since the run started; nothing was overwritten and the branch is back on the PR's head. Look at what they pushed, then run `rebase` again |
| `rebase` ends with `! secret scan: …` or `! WIP commit …` | Nothing was pushed. Look at the file it names, or at the branch's last commits |
| A `[!] move — git fetch failed` line at a gate | Check the network; the run went on, on the base it had |
| The session closed, crashed or ran out of context mid-run | `/feat resume` (or `/fix resume`) continues from the state file |
| Your plan has no Opus (or no Sonnet) | Change the model in `sizes.tsv` ([Tuning](#tuning)) |
