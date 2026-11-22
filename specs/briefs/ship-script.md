# Brief: Script the ship: `ship.sh` runs the shipper's git and gh steps in all three modes
- Size: medium — ~45 tasks expected: one new script with two subcommands over three modes, a notes-file parser, PR bodies for `/feat` and `/fix`, offline tests with throwaway repos and a fake `gh` per blocked, conflict and rebase case, and the shipper agent rewritten around it
- Short name: ship-script
- Kind: feat
- Issue: #57

## Why
The shipper (`/feat` phase 8, `/fix` phase 5, and rebase mode in both) is
the agent with the least judgement in it. A median spawn makes 20 model
calls, about 14 of them git: number the spec dir, scan for secrets, commit in
a fixed order, recheck the number, push, open the PR, build the PR body from
the state file. It runs on haiku, and its agent file is the longest
(252 lines), because every case is spelled out in prose.

This is for reliability, not tokens or time: the shipper is under 2% of a
run's cost. No shipper misfire has been seen. The point is to stop asking a
small model to follow 150 lines of git prose correctly every time, and to
have those steps done the same way every time by a tested script.

## Today
`feat-shipper.agent.md` describes each step in prose, for three modes:
- ship (`/feat`): number the spec dir with `spec-number.sh`, update docs,
  commit (`docs(specs)` and `feat`, sometimes `perf` or `refactor`), rebase,
  run checks, recheck the number (renumber with fixup and autosquash), run the
  WIP check, push, and open the PR with a body built from the state file
  (`state.sh review-summary`, the not verified items, `Closes <issue>`);
- fix mode (`/fix`): no numbering, one `fix(...)` commit, the secret scan
  before committing, and a PR body built from assessment, fix and test with
  `Fixes <ref>`;
- rebase mode: commit the move's check fixes and the Log lines, rebase, scan
  the range, push with `--force-with-lease`, reset to the lease when the push
  is refused, and edit the PR body under `### Rebases`.

It also has a `!` fallback: when git or gh is blocked in the session, the
model builds a single command for the user to run.

## Behaviour
- The shipper stays one agent. It makes two `ship.sh` calls, with the model's
  work in between:
  1. The model updates the docs the conventions ask for and writes a notes
     file (below) under the run's `reports/` dir.
  2. `ship.sh prepare` numbers the spec dir (ship mode), stages by path from
     the notes, runs the secret scan, commits, fetches and rebases onto
     `origin/<default>`. In rebase mode it commits the check fixes and the Log
     lines first.
  3. The model runs the project's checks and fixes what fails, as today.
  4. `ship.sh publish` rechecks the number (renumbering with fixup and
     autosquash when told to), runs the WIP check and the range secret scan,
     pushes, and opens the PR with `gh pr create`, its body assembled from
     the state file and the notes. In rebase mode it pushes with
     `--force-with-lease=<branch>:<lease>`, resets to the lease when the push
     is refused, and edits the PR body.
- Interface: `ship.sh <prepare|publish> <ship|fix|rebase> …` takes as
  arguments the values the shipper is given today: worktree, default
  branch, state file, notes file, the `spec-number.sh`, `secret-scan.sh`
  and `state.sh` paths, and, by mode, `Security bug`, branch, PR URL,
  lease, check-fix paths and the PR note. It reads the rest (spec dir, issue
  ref) from the state file. The exact flags are the plan's call.
- `prepare` writes a small handoff file next to the notes under `reports/`
  (the number it gave, the lease, the commits made). `publish` reads it,
  and when it is missing reports `PR: blocked` and pushes nothing.
- The notes file has fixed keys. Each `Commit: <subject>` is followed by
  its paths (`- <path>`) and an optional body. The other keys are `Docs:`
  (the docs the model updated, for `Docs updated:`), `Summary:`, `Points to
  look at:` and the model's own `Not verified:` items. The model writes
  every commit subject and decides the split, following the project's
  conventions; the script takes no convention options.
- Rebase mode: the notes carry only the check-fix commit's subject, which the
  model writes. The Log commit is fixed in the script
  (`state.sh restore-phase`, then `docs(specs): log rebase onto <sha>`), and
  the `### Rebases` entry is the PR note the spawn already gets.
- PR body: the model writes the prose parts in `Summary:`. For `/feat` those
  are Why and Behaviour; for `/fix`, the symptom, root cause, fix, and
  verdict with its checks. The script adds the fixed parts: the
  `### Code review` part as `state.sh review-summary` prints it, the
  verdict as `state.sh shipped-verdict` prints it (fix mode), and
  `Not verified` (the implementers' items, then the model's, or `none`). It
  also adds the points to look at, the state-file link (numbered path), and
  `Closes <issue>` (ship mode) or `Fixes <ref>` (fix mode) from the state
  file's `Issue:` line.
- Whatever the conventions, the script enforces these rules: it stages by
  path and never runs `git add -A`; it never stages `reports/`; it refuses a
  closing keyword (`Closes`, `Fixes`, …) in a commit message; it never
  merges; it never force-pushes outside rebase mode's lease. Any changed file
  no commit claims goes on `Left uncommitted:`.
- It checks the notes before staging anything. A `PR: blocked` at any
  point of `prepare` leaves nothing committed, unstages what it staged, and
  pushes nothing.
- On a conflict, `ship.sh` notes the conflicted files, aborts the rebase (in
  rebase mode, also `reset --keep <lease>`), pushes nothing and prints
  `PR: conflict` with `Conflicts:`. It never resolves a conflict.
- Its output is the shipper's report format unchanged: `PR: <url>`,
  `PR: blocked` with its single `!` line, `PR: conflict` with `Conflicts:`,
  `Commits:`, `Left uncommitted:`, `Docs updated:`, `Wrote:` and
  `Not verified:`. `step.sh`'s shipper parser does not change.
- When git or gh is blocked in the session, the `!` fallback in ship and fix
  mode is one line running both calls:
  `! cd '<worktree>' && bash '<ship.sh>' prepare … && bash '<ship.sh>' publish …`.
  The checks the agent ran before count for it. Rebase mode still offers no
  command, since it would be a force-push. The worktree guard refuses
  commands naming `git`, and a `bash ship.sh …` call does not name it, so
  this fallback becomes rare.
- `feat-shipper.agent.md` loses the prose for every step the script runs. It
  keeps the docs step, the notes file, the checks, the two calls and the
  report.

## Out of scope
- Conflict resolution: it stays with the implementer in rebase mode
  (`references/move.md`), the one part of a rebase that needs the model.
- #2 (why some ships take 7–12 minutes): its causes are the rebase, check
  reruns and a second spawn, which this does not change. #2 stays open.
- Commit-convention checks such as subject format: conventions vary by
  project.
- Token or time savings: none are claimed.

## Alternatives rejected
- Do nothing (the shipper is under 2% of a run, and no misfire has been seen):
  the aim is to remove prose a small model must follow, by construction, not
  to fix a measured failure.
- The coordinator calls `ship.sh` after a small "write the ship notes" agent:
  a failing check after the rebase would need a second spawn and a new
  boundary in `step.sh`, `/feat` and `/fix`.
- Ship and fix modes only, with rebase mode as a follow-up (smaller, and
  rebase runs are rare): the rebase prose is the riskiest (force-with-lease,
  reset to the lease), and the agent file would keep it.
- `ship.sh` resolves easy conflicts: deciding why a conflict happened and what
  to keep needs the model, and the rebase-mode implementer already does it,
  with the spec as context.
- `ship.sh` takes the project's commit conventions as options or checks the
  subjects: conventions are prose and differ by project, so a wrong check
  would block shipping where they don't apply.
- Close #2 with this: #2 is about the long cases, which this does not touch.

## Acceptance
- The numbering, secret scan, commit, rebase, number recheck, WIP check,
  push and PR steps of all three modes run in `ship.sh`. The prose steps they
  replace are gone from `feat-shipper.agent.md`.
- Offline tests (`tests/ship`, `mise run test:ship`, run by the `check`
  workflow) use throwaway repos and a fake `gh`. They cover ship, fix and
  rebase mode, and each `PR: blocked` cause: spec number error, secret scan
  match or failure, WIP commit, refused push, closing keyword in a commit.
  They also cover a conflict in ship and rebase mode, a renumber, and
  `reports/` never staged.
- `step.sh` parses each mode's `ship.sh` output on the existing shipper
  fixtures, without changing the parser.
- `mise run test:apm` checks that `scripts/ship.sh` ships. `shellcheck`,
  `mise run lint` and the existing offline tests stay clean.

## Constraints / decisions already made
- Bash 3.2, no jq, no Python, like `step.sh`. It calls `spec-number.sh`,
  `secret-scan.sh` and `state.sh` rather than redoing them.
- The notes file lives under `reports/`, which ignores itself, so it is never
  committed.
- The agent changes, `step.sh`'s spawn inputs (the `ship.sh` path), the
  skills' harness values and `tests/step` change together (CLAUDE.md:
  agent report formats).
- The installed skills run from the main checkout, so the `/feat` run that
  builds this ships with the current shipper. That run's ship phase is
  another data point for #2.
- PR body: `Closes #57`, `Part of #31`; never a closing keyword in a commit.
