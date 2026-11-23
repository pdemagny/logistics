---
name: fix
description: >
  Fixes a reported bug and takes it to a reviewed PR: assesses the report
  with Spec Kit's bug extension, fixes it, has a fresh agent verify the fix,
  reviews the code, then commits the fix with its trail and opens a PR on
  its own branch/worktree. Each phase runs in a feat-* subagent whose model
  and effort follow the bug's size; this session only coordinates and holds
  the gates where the user decides. Use it as /fix #N, /fix <issue URL>,
  /fix "<symptom>" or /fix resume, or /fix rebase to bring a shipped fix's
  PR onto the current main. Not for features (use /brief) or refactors.
argument-hint: '#N | issue-url | "symptom" | resume | rebase [PR]'
---

# /fix: from a bug report to a PR

The user's request: `$ARGUMENTS`

This skill runs Spec Kit's bug extension (assess, fix, test) in subagents,
then a code review and the ship, stopping at gates where the user decides.
Nothing gets merged, and nothing is called fixed until an agent that did not
write the fix has verified it.

Read `<this skill's base dir>/../feat/references/harness.md` now: it holds
the rules this skill follows. The values it refers to are below. If it is
missing, stop: "/fix needs logistics' `feat` skill
(references/harness.md); install or update logistics".

## Harness values

- *Skill*: `fix`.
- *Artifact dir*: the bug dir, `.specify/bugs/<slug>/`.
- *State file*: `.specify/bugs/<slug>/feat-state.md`, created at setup
  step 7.
- *The state file is created*: when setup step 7 creates it.
- *Title* and *input section*: `# /fix state: <bug title>`; `## Report`,
  the argument as given, on one line (a multi-line symptom's lines joined
  with spaces).
- *Size line*: `not set | small | medium | large`.
- *Agents line*: `none (every spawn is fresh)`.
- *Current phase values*: `<N> <name>` (0–5), `done (shipping)`,
  `done (PR #N)` (local copy only), `done (not a bug)`, `done (invalid)`.
- *Map line*: `none`.
- *Issue ref*: the `Issue:` line of the state file (`none`: no issue, so
  no board moves and no `Fixes` line). It is the report's issue, or the one
  created after the assess gate (phase 1, "Issue creation").
- *State script*: `<this skill's base dir>/../feat/scripts/state.sh`
  (harness, State file).
- *Step script*: `<this skill's base dir>/../feat/scripts/step.sh`
  (harness, Step script).
- *Sizes file*: `<this skill's base dir>/../feat/sizes.tsv`, read only by
  `rebase`.
- *Artifacts the orchestrator reads*: the state file once on resume
  (harness, Resume); assessment.md, fix.md or test.md only to quote a line
  the user must decide on.
- *Commands besides the tracker*: git for the worktree;
  `gh issue view <ref> --json number,title,url`;
  `gh api repos/<o>/<r>/issues/<N> --jq .author_association`;
  `gh repo view --json nameWithOwner,visibility`;
  `git ls-remote --heads origin fix-<slug>`; `ls -d -- '<path>' …` for
  `rebase` only, on its own spawns' `Wrote:` paths
  (`references/rebase.md`), never at a boundary.
- *Artifact owners*: assessor: assessment.md (re-assess, "back to 1");
  implementer: code and fix.md.
- *Agents that may be continued*: none: every spawn is fresh.
- *Reviewer context*: the rejected findings (in the spawn's `inputs:`
  file) and the assessment's remediation alternatives not chosen
  (`**Alternatives**` of Proposed Remediation).
- *Phases that can't be skipped*: 1, 2, 3 ("skip 1", "skip 2", "skip 3"
  are refused).
- *Tracker script*: `<this skill's base dir>/../feat/scripts/tracker.sh`.
- *Board-check step*: Setup step 6.
- *Building move*:
  - when: after the assess gate passes (right away for an existing issue,
    after creation for a new one);
  - on resume: in 1–3, once that gate has passed;
  - after "back to N": N in 1–3, from 4 or 5.
- *Review move*: when phase 4 starts; on resume in 4–5.
- *Resolver context*: assessment.md and fix.md, those that exist.
- *Implement row*: `2`. *Ship row*: `5`.
- *Number check*: none.
- *Secret-scan script*: `<this skill's base
  dir>/../feat/scripts/secret-scan.sh`.
- *Ship script*: `<this skill's base dir>/../feat/scripts/ship.sh`.

## Phases

- 0 Setup: you.
- 1 Assess: `feat-bug-assessor`, assess mode; stops the run if it is not a
  bug.
- 2 Fix: `feat-implementer`, bug mode.
- 3 Test: `feat-bug-assessor`, test mode, always fresh; a first `failed`
  goes back to 2 once.
- 4 Code review: `feat-code-reviewer`, one per group of lenses (7a–7d);
  then `feat-implementer` for the review fixes, and 3 again.
- 5 Ship: `feat-shipper`, fix mode; ends with the PR link.

`step.sh` decides every gate after setup, the routing between phases 2, 3
and 4, the groups of reviewers, and each spawn's model and effort for the
bug's size (harness, Step script). Below: what you add to each prompt, and
what each gate message shows.

## Gate commands

The harness's gate commands apply, with these `/fix` rules:
- Any other skip ("skip 4") is allowed, with the user's reason in its
  answer (ask for one if none is given). For a security bug, "skip 4"
  still restates what becomes public once pushed and asks for the go-ahead
  to ship (`step.sh` makes phase 4 that gate).
- A "back to N" resets the test cycle and retry count; "back to N" (1–3)
  from 4 or 5 makes the building move.
- **Shipping without `verified`**: a `partial` or `failed` verdict reaches
  phase 5 only on the user's explicit decision at a hard gate, never on
  silence or a soft gate. Ask for it in plain words; their yes is the
  answer `ship with <verdict>`, which the shipper copies into the PR body.
  A decision taken in the first cycle still goes through phase 4 first.

Where this skill tells the user to run a command, it prints the plugin
form too: `/fix` is `/logistics:fix`, `/brief` is `/logistics:brief`
and `/feat` is `/logistics:feat` when logistics is installed as a Claude
Code plugin.

---

## 0. Setup

1. This workflow needs Claude Code: subagents spawned by name with a
   `model` and `effort` per call, and `EnterWorktree`. If you can't do
   that here, stop: say `/fix` runs only in Claude Code. Don't run the
   phases inline instead.
2. The argument:
   - `$ARGUMENTS` is one of: `#N`, `owner/repo#N`, an issue URL, a quoted
     symptom, `resume`, or `rebase [<PR number, URL or branch>]`.
   - A brief path (`specs/briefs/<name>.md`): stop and point to `/feat
     <path>`.
   - Empty: show the usage (`/fix #N | <issue URL> | "<symptom>" |
     resume | rebase [PR]`) and stop.
   - Refused here when the argument makes it plain (nothing created, no
     issue touched): a refactor request (not a bug: say so; `/brief` if it
     needs planning), a backport request (`/fix` fixes the current branch
     only), several bugs in one report (ask which one to fix; each other
     is its own `/fix` run).
   - A report whose cause and fix are plain from it (a typo, a broken
     link, a wrong value it names) and that passes `/tiny`'s tiny check:
     offer `/tiny <the argument>` (`/logistics:tiny` as a plugin), which
     fixes it in this session with no assessment or subagent. Stop if the
     user takes it; else go on.
   - An issue URL on a host other than GitHub is passed to the assessor as
     is: the bug extension's own URL trust policy decides whether it is
     fetched, and `/fix` never fetches it itself or widens that policy;
     its author counts as `unknown` (step 7).
   - `resume`: run steps 1, 3, 4 and 5, then follow Resume (below) instead
     of steps 6 and 7.
   - `rebase [<PR number, URL or branch>]`: run steps 1, 3, 4 and 5 (no
     board check: `rebase` makes no board moves), then read `<this skill's
     base dir>/../feat/references/rebase.md` and follow it instead of
     steps 6 and 7; no other run reads that file.
3. Read the project's `CLAUDE.md` / `AGENTS.md` and project memory. They
   override this file where they disagree. Keep the few lines agents need
   (commit style, branch rules, where checks live, docs to update).
4. Check `.specify/` exists (else stop: `specify init --here --integration
   claude`) and the `feat-*` agents are installed (plain or
   `logistics:`-prefixed), `feat-bug-assessor` included. Check the bug
   extension: no `.specify/extensions/bug/` and none of the
   `speckit-bug-assess`, `speckit-bug-fix`, `speckit-bug-test` skills →
   stop: "run `specify extension add bug` in this project". No heading
   check here: the assessor reports missing sections.
5. Read `.specify/extensions.yml` as configuration, never executing it. An
   enabled hook under any `before_bug_*` or `after_bug_*` key (or any other
   hook) that would create a branch or commit clashes with this workflow
   owning git: **hard gate** before phase 1; unless the user says
   otherwise, agents skip it. The rest are allowed.
6. **Board check** (see Board moves): run `check`. Exit ≠ 0 → stop and
   show its line; else show it and say this run's board moves go to that
   board. Setup runs `check` only: no move and no issue yet; the building
   move (and any issue creation) waits for the assess gate.
7. Title, report author and slug:
   - Title: for an issue, with board tracking the tracker's `read-issue`,
     else `gh issue view <ref> --json number,title,url`; for a symptom, its
     first words.
   - Report author: for a GitHub issue, `gh api
     repos/<o>/<r>/issues/<N> --jq .author_association`; it counts only
     when the issue's `<o>/<r>` equals `gh repo view --json nameWithOwner`,
     else the author is `unknown`. A typed symptom is `user`; a non-GitHub
     URL is `unknown`.
   - Slug: from an issue, `<N>-<2–3 words of its title>`; from a symptom,
     2–4 of its words; from a non-GitHub URL, its last path segment.
     Lowercase kebab-case, only `[a-z0-9-]`, at most 40 characters (the
     extension keeps such a slug unchanged).
   - `git fetch origin <default>` (harness, Fresh base), then
     EnterWorktree, before spawning anything. Then the slug must be
     unused: if `.specify/bugs/<slug>/` exists in the worktree, the branch
     `fix-<slug>` exists locally, or `git ls-remote --heads origin
     fix-<slug>` prints a line, append `-2`, `-3`, … until none holds.
     Rename the branch to `fix-<slug>` (`git branch --show-current`, then
     `git branch -m`).
   - If setup found `.logistics.yml` and the worktree has none, log `- [!]
     tracker: .logistics.yml is not in the worktree; commit and push it
     (board moves skipped)` and flag it at the first gate.
   - Create the state file in one Bash command: `S init fix '<state
     file>' '<title>' '<the argument, its lines joined with spaces>'
     'Branch=fix-<slug>' 'Worktree=<path>' 'Size=not set' 'Agents=none
     (every spawn is fresh)' 'Current phase=1 Assess' 'Conventions=<…>'
     'Allowed Spec Kit hooks=<…>' 'Map=none' 'Issue=<the issue ref or
     none>' && S log '<state file>' '- [x] 0 Setup — <board check>; slug
     <slug>; bug extension <version from
     .specify/extensions/bug/extension.yml>; report author
     <association>'`, plus any `[!]` lines kept so far as more `log`
     arguments, then `&& T fix '<state file>' setup`. It prints phase 1's
     spawn.

## Resume

`/fix resume` follows the harness's Resume with these values:
- **Search**: `S find fix` (harness, Resume; several → list slug, phase
  and worktree, and ask); none → say there is no unfinished `/fix` run and
  stop. A shipped run is skipped (its committed state says `done
  (shipping)` and its branch has an upstream); one whose ship stopped
  before committing has `5 Ship` back in the local copy, and one waiting
  on the user's `!` command (`done (shipping)`, no upstream) resumes at
  phase 5.
- **Board**: run `check` after `T resume`; exit ≠ 0 → stop. The building
  move only once it printed `assess gate: passed`.
- **Continue** with what `T resume` printed: finished phases are not
  redone, and the current one restarts with a fresh spawn, as every spawn
  is; its gate then follows from the new report. If the assess gate passed
  with `Issue: none`, board tracking, and no Log line for issue creation
  (`created`, `no issue` or a `[!]` from `create-issue`), don't run
  `create-issue` again on your own: the earlier run may have created the
  issue before it stopped. Ask the user for the issue ref or "no issue"
  (logged).
- Recap the run in one paragraph before that phase's spawn.

Every spawn below gets, besides what the harness lists and its spawn
block's keys: the bug dir, the slug, the size (or "not set yet"), the
report author's association, and the allowed hooks
(`before_bug_*`/`after_bug_*` and the others setup allowed).

## 1. Assess

Spawn `feat-bug-assessor` with the report (the argument as given) and, on
a re-assess, the user's added evidence (the approved commands and answers
so far are in its spawn's `inputs:` file).

**Stop** (`stop:`): the run ends here. Show the assessor's `Reasoning` and
the `stop:` line's reason (the extension's, or the `Is a bug` value) so the
user can relabel or comment on the issue themselves. For `no — missing
feature`, point to `/brief #N` for an issue, else `/brief
"<symptom>"`. No issue is created, moved or edited, and no later phase
starts. A non-GitHub issue URL the extension did not fetch
(`[UNVERIFIED — fetch skipped: …]` in assessment.md) is not retried around
its policy: the user may paste the report text as a symptom instead.

**Hard**: the gate message lists every reason `step.sh` printed, each
under **Your call** where it needs an answer:
- `sections: …` or `slug mismatch: …`: that reason as is; recommend
  "back to 1" once the cause is fixed (a missing section means
  the extension differs from the recorded one: `install.sh check` names
  it).
- `report author <association>`: nothing from the report (command, script
  or code) was run, and its `Would run:` list; the user may approve some of
  them or go on without.
- `needs approval`: the commands needing approval (`Reproduction detail`:
  they reach the network or outside the worktree); the user may approve
  them or go on without.
- `security risk area`: the security rules below.
- `issue to create`: the repo it would go to, from `gh repo view --json
  nameWithOwner`; the user confirms it or answers "no issue".
- `needs reproduction`: the extension could not confirm it; the user may
  supply evidence (re-assess) or go on.
- `open questions: <n>`: each question, with my recommended answer.
- `several bugs`: ask which one this run fixes ("back to 1" with that one
  as added evidence); the others are separate `/fix` runs, with no issue
  created for them here.
- `proposed size`, `confidence`, the reproduction, `remediations` or
  `public behaviour change`: one line each (for several remediations, the
  preferred one and the alternatives).

With the answer go: `'approved: <command>'` for each command the user
approved (it runs only in a later spawn: to run it now, the user says
"back to 1"), `'question: <question> → <answer>'` for each answered open
question, and `'security: advisory (user: "<words>")'` or `'security:
issue (user: "<words>")'` whenever the gate lists `security risk area`.

**Security bug** (`security risk area`):
- No issue is created by default, even with board tracking: suggest a
  private security advisory instead (the repo's Security tab, Advisories,
  "New draft security advisory"). The user may still ask for an issue.
- Run `gh repo view --json visibility` and state the result: for a
  `PUBLIC` repo, the PR, its body and the committed
  `.specify/bugs/<slug>/` trail (assessment, fix and test reports) become
  public once pushed; for `PRIVATE` or `INTERNAL`, they are visible to
  whoever can read the repo. The shipper leaves the reproduction steps out
  of the PR body.

When the gate passes (`soft`, or `answered` with phase 2's spawn),
`step.sh` has set the size and title: issue creation, then the building
move, then the spawn.

**Issue creation**, only once the gate has passed for a real bug:
- `Issue:` holds the report's issue: create nothing. That issue always
  gets `Fixes #N` in the PR, with or without board tracking and whatever
  its label.
- `Issue: none` and no board tracking: create nothing; the PR has no
  `Fixes` line.
- `Issue: none` with board tracking: if the user answered "no issue", or
  this is a security bug and the user did not ask for an issue (advisory),
  create nothing and log `- [x] 1 Assess — no issue (user: "<words>")` or
  `- [x] 1 Assess — no issue (security advisory)`. Otherwise run `bash
  <tracker script> create-issue .specify/bugs/<slug>/assessment.md
  <owner/repo the user confirmed at the gate>` once (never retried: a retry
  could duplicate it; the script itself retries only without a missing
  `bug` label). On `tracker: created <owner>/<repo>#<N>` (maybe followed by
  a note) run `S set '<state file>' Issue '<owner>/<repo>#<N>'` and log the
  line in the same command; the issue is labelled `bug` and its body holds
  the symptom, the root cause and the trail link. Exit ≠ 0: log `- [!] <its
  line>`, keep `Issue: none` (no moves, no `Fixes` line), flag it at the
  next gate and go on.

## 2. Fix

Spawn a fresh `feat-implementer` (bug mode); its spawn block carries the
approved commands and the user's answers are in its spawn's `inputs:`
file; on a retry its block carries the failed test report and what still
fails. Tell it its `<who>`, `implementer` (the same
for every implementer of the run: the fix, its retry, phase 4's review
fixes). Its `Not verified:` list is not shown at the gate: phase 3 settles
it.

**Soft**: one line, `Phase 2 Fix — soft: applied; no deviations; checks
pass. Next: phase 3 Test`, with the tester's spawn. **Hard**, each
reason `step.sh` printed:
- `slug mismatch: …`: that reason as is; recommend "back to 2" (a fresh
  implementer) once the cause is fixed.
- `size increase: … (deviations)` or `deviations`: a size increase
  (harness, Size changes): name each deviation from the assessment, the
  old size and one step up, and what changes in phases 3–5; options "back
  to 1" (re-assess with fix.md's findings as added evidence) or "go on with
  size <s>" (`size <s>`).
- `check fails: <check>`: the failing check's first relevant line; options
  "back to 2" with what to change, or "back to 1".
- `status <value>`: what the implementer left undone and why (its
  `Tasks not done` and `Design problems`); same options.
- `Not verified line missing`: the report is broken (harness); recommend
  "back to 2" (a fresh implementer).

## 3. Test

`step.sh` spawns a fresh `feat-bug-assessor` (test mode), never the agent
that wrote the fix, with the cycle (its block) and the not verified items and
approved commands (its `inputs:` file); add any environment or evidence the user supplied.

- `verified`: soft; one line, then phase 4's reviewers (or phase 5 after
  review fixes).
- A first `failed` with the retry unused: soft, no stop: one line naming
  what still fails, then the retry fix `step.sh` prints.
- `unaccounted items: …`: show those items and the verdict; recommend a
  re-test (`changed`: a fresh spawn, same cycle, same items, which uses no
  retry); going on (`approved`, then the verdict's own gate) is the user's
  explicit decision.
- `partial: …`: show `Missing for verified`; the user supplies that
  environment or evidence (`changed`: a re-test with it), or decides
  explicitly to go on (`ship with partial`, Gate commands).
- `failed: …` (retry used, or after review fixes): show `Still failing`
  and a link to the test report (`test.md` in the bug dir); recommend "back to 1" (re-assess with the
  failed reports as added evidence); the user may also decide explicitly
  (`ship with failed`).
- `review fixes report lacked Not verified line`: the report is broken
  (harness); recommend "back to 2" (a fresh implementer).
- `sections: …`, `slug mismatch: …` or a failed report check: the line as
  is; recommend a re-test ("back to 3") once the cause is fixed.

## 4. Code review

Before the reviewers' spawns, the review move (see Board moves). The call
that prints them prepared the diff (`diff:` key; `added:` and `untracked,
not in the diff:` lines). Give each `feat-code-reviewer` the bug dir as
its feature dir, the note "no spec.md: for the spec pass use assessment.md
(Proposed Remediation, Tests to add or update) and fix.md", its spawn
block's keys, and as context the
assessment's remediation alternatives not chosen.

- `security risk area`: list the findings, if any, with their `rec`;
  restate what becomes public once pushed (the visibility stated at the
  assess gate: PR, body, committed trail) and ask for the go-ahead to ship
  (`approved` logs it).
- `large`, `<ids> need you`, `S<n> security`: list every finding with its
  `rec`, `user` first.
- **Soft**: one line, `Phase 4 Code review — soft: <step.sh's counts:>;
  none needs your call. Next: <review fixes, then phase 3 again | phase 5
  Ship>`, with the spawn `step.sh` prints (merge rule 1 first: harness,
  Review findings).

At every hard gate, the listing, the "ok" rule and its follow-up and the
`S` publication notice are the harness's (Review findings). The review
fixes go to a fresh fix-mode implementer (`<who>` `implementer`); then
phase 3 again, cycle `after review fixes`: `verified` must hold again
before ship, and a `failed` there is a hard gate, with no retry.

## 5. Ship

`step.sh` sets `done (shipping)` before the shipper spawn, so the copy the
shipper commits is already done. Give `feat-shipper` (fix mode) the state
file, the *state script* (`State script:`), the spawn block's `ship
script` (`Ship script:`), the conventions, the worktree, the default
branch, the bug dir, the secret-scan script (`<this skill's base
dir>/../feat/scripts/secret-scan.sh`) and the issue ref (none when
`Issue: none`: then the PR has no `Fixes` line; else `Fixes <ref>`); its
spawn block says `security bug: yes|no`. It updates the docs the
conventions call for and, through `ship.sh prepare` and `ship.sh
publish`, commits `fix(<scope>)` with the trail, pushes and opens the PR,
or reports `blocked` or `conflict`. Never merge.

- `done: PR #N`: the final message.
- `stop: ship blocked on a command for you`: give the `command:` line to
  the user as is (`ship.sh` blocked here); the state file stays done
  (resume finds the run while its branch has no upstream).
- `hard:` `ship blocked`: show the `command:` line as an error (`! secret
  scan: …` or another hard failure: nothing committed); `approved` ships
  again.
- `PR: conflict`: `read:` (harness, Moving onto a new main).

Final message: the PR link, the branch and worktree, the two or three
things you'd look at first in review, the shipper's `Not verified:` list
when it is not `none`, or that it is missing, and a move onto a new main
made at ship (`references/move.md`).
