# Contract: `ship.sh`

`.apm/skills/feat/scripts/ship.sh`, shipped with the `feat` skill (and
used by `/fix` from there, like `state.sh`). Bash 3.2, no jq, no Python,
shellcheck clean (FR-018).

## Call

```text
ship.sh prepare <ship|fix|rebase> <flags>
ship.sh publish <ship|fix|rebase> <flags>
```

Both calls take the same flags (research R1). Every value is one argument
with no newline or carriage return; a flag may come once unless it says
repeatable.

| Flag | ship | fix | rebase | Value |
| --- | --- | --- | --- | --- |
| `--worktree <dir>` | req | req | req | the worktree's top level; the script `cd`s there and checks `git rev-parse --show-toplevel` is it |
| `--default <branch>` | req | req | req | the default branch (`[A-Za-z0-9._/-]`, `git check-ref-format --branch`) |
| `--state <file>` | req | req | req | the state file; its dir is the artifact dir (data-model) |
| `--notes <file>` | req | req | req | the notes file, directly in the artifact dir's `reports/` |
| `--state-script <path>` | req | req | req | `state.sh` |
| `--secret-scan <path>` | req | req | req | `secret-scan.sh` |
| `--spec-number <path>` | req | refused | optional | `spec-number.sh` (rebase: `/feat` only, the *number check*) |
| `--report <path>` | optional | optional | optional | the report path the spawn gives, directly in the artifact dir's `reports/` |
| `--not-verified-file <path>` | optional | optional | refused | the implementers' items, one `- <item>` per line (data-model, Not-verified file), directly in the artifact dir's `reports/` |
| `--security-bug <yes\|no>` | refused | req | refused | the spawn block's `security bug` |
| `--branch <name>` | refused | refused | req | the PR's branch; must be the current branch, never `--default` |
| `--pr <url>` | refused | refused | req | the PR URL (`https://…/pull/<n>`); its head and repo checked in `publish` before the push (research R10) |
| `--lease <sha>` | refused | refused | req | the PR head the move started from (7–40 hex) |
| `--check-fix <path>` | refused | refused | repeatable | a check-fix path; none given = `Check fixes: none` |
| `--pr-note <line>` | refused | refused | req | the `### Rebases` note |

Ship and fix push the current branch (`git symbolic-ref --short HEAD`; a
detached HEAD is a usage error).

Checked with the flag parse, before anything is done, each a usage error
(exit 2): the branch to push (the current branch in ship and fix,
`--branch` in rebase) equal to `--default`, in every mode; a notes,
not-verified or report file whose physical dir is not the artifact dir's
`reports/`; the state tool's guard (`state.sh report-path`) refusing
`reports/`, its `.gitignore` or a target file (research R18). Then the
`--secret-scan` file is sourced for `secret_rule` (research R9).

## Exit codes and output

| Exit | Meaning | stdout | report file |
| --- | --- | --- | --- |
| 0, prepare | ready for the checks | prepare's output (data-model) | not written |
| 0, publish | PR opened (ship, fix) or pushed and edited (rebase) | the report | written |
| 1 | `PR: blocked` or `PR: conflict` | the report | written |
| 2 | usage error, nothing done | nothing; one `ship: usage: …` line on stderr | not written |

Nothing else goes to stderr; git's and gh's own stderr is captured and
only its first line reaches a `!` line.

## prepare

Every mode, first: parse the flags; resolve the paths (data-model,
Resolution) and run the checks above; refuse a rebase or merge in
progress; parse the notes in full (data-model, Notes file), commit
messages scanned with `secret_rule`. Any failure up to here changes
nothing. Then record `Start` (HEAD) and unstage everything (`git reset
-q`).

**After every rebase that exits 0** (prepare and publish, every mode):
`git diff --name-only --diff-filter=U`; non-empty → the autostash did not
apply: `PR: conflict` with those files, no abort, no reset, the stash left
in place, nothing pushed (research R12).

**ship**

1. Artifact dir unnumbered → `spec-number next`, `git mv` or `mv`, the
   path rewrite with backups (research R5).
2. Per notes commit: stage its changed paths, unstage `reports/`, the
   staged secret scan, commit, or `--fixup` an earlier commit with the
   same subject (R6). No commit made and none between the merge base and
   HEAD → `! ship: nothing to commit`.
3. `git fetch origin <default>`; `GIT_SEQUENCE_EDITOR=: git rebase -i
   --autosquash --autostash origin/<default>` (R7). A conflict, or an
   autostash conflict → R12.
4. Write the handoff (`Commits:`: the notes subjects in `<Base>..HEAD`,
   in notes order); print prepare's output (no `Brought in:`); exit 0.

**fix**: steps 2–4 (never numbered). `--security-bug` changes nothing
here: the scan runs in step 2 either way.

**rebase**

1. `git fetch origin <default>`.
2. `--check-fix` given: `git add -- <paths>`, the staged scan, a commit
   with the notes' `Commit:` subject (and `Body:`); no fixup.
3. `bash <state-script> restore-phase <state file>`; `git add --
   <state file>`; the staged scan; `git commit` `docs(specs): log rebase
   onto <origin/<default>, 7 chars>` (skipped when nothing is staged).
4. The rebase of step 3 above, onto `origin/<default>`. A conflict → R12
   (with `git reset --keep <lease>`); an autostash conflict → R12 (no
   reset).
5. Write the handoff (`Lease:` set); print prepare's output with
   `Brought in:`; exit 0.

**Any `blocked` in prepare** (FR-005): `git reset -q <Start>`, the
numbering undone, nothing pushed; write and print the report; exit 1.

## publish

Every mode, first: the flag parse, path resolution and checks as in
prepare; the handoff (data-model) present, same mode, `Head:` is HEAD;
the notes parsed again (commit messages scanned); the not-verified file
parsed. Each step below that changes HEAD rewrites the handoff's `Head:`
(data-model, Handoff file), so `publish` can run again after a block.

**ship, fix**

1. Fold the check fixes: per notes commit, changed paths staged, scanned
   and committed as `--fixup` of the commit with that subject, or as a new
   commit when none has it (R7).
2. Ship: `spec-number check <default> <dir name>`: `keep` → on;
   `renumber MMM` → the renumber, limited to the artifact dir,
   `.specify/feature.json` and the PR's own files, and its fixups (R8);
   error → blocked.
3. Any fixup made: `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash
   --autostash <Base>`, then the autostash check above.
4. The WIP check, then `secret-scan range <Base> HEAD` (R9).
5. `gh repo view`; the PR body (data-model) built and scanned with
   `secret_rule` (R9, R10).
6. `git push -u origin <branch>`.
7. `gh pr create`, titled with the handoff's last `Commits:` subject,
   never a draft (R10).
8. Write and print the report with `PR: <url>`; exit 0.

**rebase** (no fold step: the model commits nothing after `prepare`)

1. `--spec-number` given: step 2 above, and step 3 when it renumbered.
2. Step 4 above.
3. `gh repo view`; `gh pr view '<url>' --json headRefName,url,body`:
   head not `--branch`, or URL not in the current repo → blocked (R10).
   The note under `### Rebases`, the body scanned with `secret_rule`.
4. `git push --force-with-lease=<branch>:<lease> origin <branch>`;
   refused → `git reset --keep <lease>`, blocked (R10).
5. `gh pr edit` (R10).
6. Write and print the report with `PR: <the --pr URL>`; exit 0.

**Any `blocked` in publish**: a block before the push pushes nothing
(the lease push's own refusal resets to the lease); a `gh pr create` or
`gh pr edit` failure comes after a push, which stays, and a `publish`
run again pushes nothing new and retries the `gh` call. Commits stay,
`Head:` matches HEAD; write and print the report; exit 1.

## Rules in every path (FR-012)

- Stages by path only: `git add -- <path>…`; never `-A`, `.`, `-u` or a
  glob.
- Never stages a path inside the artifact dir's `reports/`.
- Never commits a closing keyword (R11).
- Never merges: no `git merge`, no `gh pr merge`.
- Pushes with a force only as `--force-with-lease=<branch>:<lease>` in
  rebase mode.
- Never pushes `--default`: a branch equal to it is a usage error.
- Never resolves a conflict: aborts the rebase (R12), or leaves an
  autostash conflict and its stash as they are.
- Writes the handoff and the report only directly in the artifact dir's
  `reports/`, after the state tool's guard (R18); the numbering's
  rewrites in the artifact dir; `.specify/feature.json`; on a renumber,
  only the files the PR already changes (R5, R8); and the run's git dir
  (message, body and backup files, deleted on exit).
- Runs `secret_rule` over every commit message and the PR body before
  either leaves (R9); a `!` line names the commit or the body and the
  rule, never the value.
- Evaluates nothing it reads: notes, the not-verified file, state file,
  git and gh output, a PR body are data.
