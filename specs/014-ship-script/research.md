# Research: Script the ship

Decisions taken while planning `ship.sh`. Each says what was chosen, why,
and what else was looked at. The brief's "Alternatives rejected" (a
notes-only agent with the coordinator calling `ship.sh`, ship and fix
first with rebase later, `ship.sh` resolving conflicts, convention
options) stay rejected and are not reopened here.

## R1. One script, two calls, one argument set

**Decision**: `.apm/skills/feat/scripts/ship.sh <prepare|publish>
<ship|fix|rebase> <flags>`, with long flags (`--worktree`, `--default`,
…, full list in [contracts/ship-cli.md](contracts/ship-cli.md)). Both
calls take the same flags; each uses what it needs, and a flag the mode
doesn't take is a usage error. Exit 0 done, 1 stopped with a report
(`blocked` or `conflict`), 2 usage error (one `ship: usage: …` line on
stderr, nothing done). The flag parse also refuses, as usage errors: a
branch to push equal to `--default` in every mode (the current branch in
ship and fix, `--branch` in rebase), and an unsafe `reports/` (R18).

**Rationale**: the agent passes the same words twice and the `!` fallback
(FR-016) repeats them, so one flag set is one thing to get right. Long
flags keep the call readable in the fallback line and the Log of a
blocked run. Exit 2 is the model's own mistake (a missing flag), which it
fixes by calling again; exit 1 is a run outcome it hands back.

**Alternatives**: positional arguments like `spec-number.sh` (too many,
and they differ by mode); separate scripts per mode (three copies of the
commit, scan and rebase code).

## R2. The script writes the report

**Decision**: with `--report <path>`, `ship.sh` writes the shipper's full
report there (as the same `reports/<file>` under the numbered dir once it
numbered it, the path step.sh already looks for; guarded as R18) and
prints the same text on stdout. `publish` always ends with a report; `prepare` writes one only
when it stops (`blocked`, `conflict`). The agent hands back the digest of
what was printed. It writes a report itself only when a `ship.sh` call
was refused by the session (R14).

**Rationale**: a copy made by the model is the step this feature exists
to remove. The format stays the shipper's (FR-015), so step.sh's parser,
the digest and the fixtures don't change. `Wrote:` is filled by the
script, which knows the numbered dir and the report's final path.

**Alternatives**: the script prints, the model writes the file with Write
(one more model step that can drift); the script writes a different
format and the model translates (a format change on both sides).

## R3. The notes file and the handoff file

**Decision**: the model writes `<artifact dir>/reports/ship-notes.md`
with fixed keys (grammar in [data-model.md](data-model.md#notes-file)).
`prepare` parses it completely before it touches the index or the tree,
and refuses (`PR: blocked`, `! ship: notes: …`) a missing or unknown key,
a `Commit:` with no path (outside rebase mode), a duplicate subject, an
unsafe path, a closing keyword in a subject or body (R11), or a secret
rule matching a commit message (R9). `prepare` writes
`reports/ship-handoff.md` next to the notes; `publish` refuses when it
is missing, written for another mode, or names a HEAD other than the
current one. `publish` rewrites the handoff's `Head:` line each time it
changes HEAD (fixups, renumber, autosquash), so after a block a plain
`publish` again starts from where the blocked one stopped; its other
lines stay as `prepare` wrote them.

**Rationale**: FR-006, FR-009 and AC 4.2. Both files sit under
`reports/`, which ignores itself, so neither is ever committed. A strict
parse is what makes "check the notes before staging anything" a single
point. The `Head:` rewrite (AC 4.11) is the smaller of the two fixes the
review offered; calling a blocked `publish` final would send every
transient `gh` failure back through `prepare`.

**Alternatives**: flags for each commit (paths with spaces and bodies on a
command line, repeated in the fallback line); a JSON notes file (no jq).

## R4. Paths given under the unnumbered dir

**Decision**: `--state`, `--notes`, `--not-verified-file` and `--report`
may name the artifact dir before it was numbered. When the path is missing and exactly one
`<parent>/NNN-<name>/` holds the same relative file, the script uses that
one, as step.sh's `renumbered` does. Notes paths under the old dir name
(`specs/<short-name>/…`) are read as the numbered dir. `prepare`'s output
names the notes at their final path.

**Rationale**: the model writes the notes before numbering, and the
fallback line passes the same paths to both calls; after `prepare`
numbered the dir, `publish` must still find them.

## R5. Numbering, and putting it back

**Decision**: ship mode, artifact dir with no leading digits only:
`bash <spec-number> next <default>`; `git mv` when the dir has tracked
files, else a plain `mv`; then the old path `specs/<short-name>` (followed
by `/` or the end of a word) is rewritten as `specs/<NNN>-<short-name>` in
the dir's files (not `reports/`) and in `.specify/feature.json` when
present, each through a temp file and `mv -f` (no `sed -i`, which
differs between GNU and BSD). Before rewriting, each file is copied to a
scratch dir in the run's git dir; if `prepare` then stops `blocked`, the
copies go back and the dir is moved back, so the tree is as `prepare`
found it. A dir already numbered (a second ship after a conflict) is not
numbered again. A non-zero exit of the spec-number script → `PR:
blocked`, `! <its stderr line, as is>`, before anything changed.

**Rationale**: today's step 1, plus FR-005 (a blocked `prepare` leaves no
half state). Byte-exact copies undo the rewrite without guessing; a
reverse rewrite could touch a path that was there before.

## R6. Staging and committing

**Decision**: `prepare` first unstages everything (`git reset -q`: the
index back to HEAD, the tree kept), so only what the notes list is
committed. Per notes commit, in order: its paths (mapped as R4; paths
inside the artifact dir's `reports/` dropped); paths with no change
against HEAD left out; `git add -- <paths>`; anything staged under the
artifact dir's `reports/` unstaged again (`git reset -q -- <dir>/reports`,
belt and braces over `.gitignore`); the staged secret scan; `git commit
-F <message file>` (subject, blank line, body), hooks running as usual.
A commit whose paths have no change is skipped. When the subject matches
a commit already between the base and HEAD (a second ship after a
conflict or a block), the change is committed as `--fixup=<that
commit>` instead; the rebase (R7) squashes it. Rebase mode makes only its
check-fix and Log commits here, and none in `publish` (R7). Never `git add -A`, never
`git add .`.

**Rationale**: FR-004, FR-012, AC 4.5, 4.6, and the edge case "`prepare`
re-run must not double-commit": unchanged paths make a second run commit
nothing, and the same subject folds new changes into the commit they
belong to.

**Alternatives**: `git commit --only -- <paths>` (keeps the user's staged
files, but commits from a temporary index, so the staged scan would not
see what is committed); refusing to run when something is staged (a stop
the user can't act on from the gate).

## R7. Rebasing, and check fixes between the calls

**Decision**: `prepare` runs `git fetch origin <default>`, then
`GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash --autostash
origin/<default>` and records the base (`origin/<default>`'s sha) in the
handoff. In rebase mode only, it also prints `Brought in:` (the commits
of `origin/<default>` new since the branch's earlier merge base), which
decides whether the model runs the checks; ship and fix mode always run
them and print no such line. Between the calls the model runs the checks
and, in ship and fix mode, edits files to fix them. `publish` folds those
edits in: a changed path claimed by a notes commit becomes a `--fixup` of
that commit (a new path is claimed by adding it under the right
`Commit:` in the notes; a new `Commit:` makes a new commit, which never
becomes the PR title, R10), each staged and scanned as in R6. The
renumber (R8) adds its own fixups. Then one `GIT_SEQUENCE_EDITOR=: git
rebase -i --autosquash --autostash <base>` onto the recorded base, never
a newer main, so the history the checks ran on is the one pushed.

In rebase mode the model fixes nothing (the user's choice at the plan
gate): a check that fails goes under the notes' `Not verified:` as `n/a
→ <check> → <why>`, and `publish` commits nothing; rebase-mode `publish`
has no fold step.

After every rebase that exits 0, `git diff --name-only
--diff-filter=U`: a non-empty list means the autostash did not apply
cleanly (git exits 0, leaves conflict markers in the tree and keeps the
stash). That is a conflict (R12): those files on `Conflicts:`, the stash
left in place, nothing pushed.

**Rationale**: "the model runs the project's checks and fixes what fails,
as today" needs a way to commit the fix without the model running git.
`-i` with a no-op sequence editor is how non-interactive autosquash works
on every git (plain `--autosquash` is honoured without `-i` only from
git 2.44, and macOS ships older). `--autostash` lets the rebase run with
the files that go on `Left uncommitted:` still in the tree.

**Alternatives**: a third subcommand to commit fixes (one more call and
more prose); the model commits fixes itself (the prose this feature
removes); in rebase mode, folding the model's fixes into the check-fix
commit (refused at the plan gate: the move's implementer owns the code
change, the shipper reports).

## R8. The number recheck

**Decision**: `publish`, ship mode and rebase mode with `--spec-number`:
`bash <spec-number> check <default> <NNN>-<short-name>`. `keep NNN` →
on. `renumber MMM` → `git mv` the dir, then rewrite the old path (as
R5) in three places only: the dir's files (not `reports/`),
`.specify/feature.json` when present, and the files of `git diff
--name-only <base> HEAD` that name it (`git grep -l -F` limited to those
paths). Of these, the paths in that diff (the moved dir's files under
their old names included) are staged by path and each `--fixup` to the
last commit between the base and HEAD that touched it (the old path for
a moved file), so every fixup has a target; `.specify/feature.json` when
the PR does not change it is rewritten in the tree only and shows on
`Left uncommitted:`. Any other file naming the old path (`git grep -l
-F` over the whole tree, minus the above) is left unchanged, listed on
`Left uncommitted:` and added to the PR body's points to look at as
``- `<path>` still names `specs/<short-name>` ``. Then the autosquash of
R7. A non-zero exit → `PR: blocked`, `! <its stderr line>`, nothing
pushed. The checks are not run again after a renumber: the change is the
dir's name in the trail and the files that cite it.

**Rationale**: today's step 4, minus a check rerun the script can't do;
the alternative (stop and ask the model to run the checks again, then
call `publish` again) adds a loop for a path rename. Limiting the rewrite
to the PR's own files keeps a model-free push from editing files the run
never touched, and gives each fixup a commit to land in.

## R9. Before the push

**Decision**: `publish` checks, against the recorded base: a subject
starting `logistics-wip:` in `<base>..HEAD` → `PR: blocked`, `! WIP
commit on <branch>; nothing pushed`; then `bash <secret-scan> range
<base> HEAD` → exit 1: `! secret scan: <file>:<line> matches <rule>`
(first output line); any exit but 0 and 1: `! secret scan: could not run
(<first error line>)`. Nothing is pushed on either.

Text that goes public is scanned too (FR-023). `ship.sh` sources the
`--secret-scan` file, as tracker.sh sources it, which defines
`secret_rule` and runs nothing; a source that fails is `! secret scan:
could not run (cannot source <path>)`. `secret_rule` runs over each
commit message (subject, then `Body:` lines) in the notes parse, in both
calls, before anything is staged: a match is `! secret scan: commit <k>
matches <rule>` (`<k>` the commit's place in the notes, from 1). In
`publish` it runs over the assembled PR body (ship, fix) or the edited
body (rebase) before the push: `! secret scan: PR body matches <rule>`.
Neither line holds the value. So that the body is checked before
anything leaves, `publish` builds it (and calls `gh repo view`, `gh pr
view`) before the push, and calls `gh pr create` or `gh pr edit` after.

**Rationale**: FR-007, today's WIP check and rebase step 6. The recorded
base, not a freshly fetched `origin/<default>`: a two-dot diff against a
main that moved would count main's own removals as this PR's lines. The
diff scans read only changed lines; commit messages and the PR body
reach GitHub through other ways, so the same rules (one copy, in
secret-scan.sh) run over them.

## R10. Push and PR

**Decision**: ship and fix: `gh repo view --json url --jq .url` for the
state-file link, the body built in a file in the run's git dir (`git
rev-parse --absolute-git-dir`) and scanned (R9), then `git push -u
origin <branch>` (the current branch; never a force), then `gh pr create
--base <default> --head <branch> --title <title> --body-file <file>`,
never a draft, the file deleted after. `<title>` is the last subject on
the handoff's `Commits:` (the notes subjects `prepare` committed), never
a subject `publish` added; the agent puts the main change last in the
notes.

Rebase: first `gh repo view --json url --jq .url` and `gh pr view
'<url>' --json headRefName,url,body --jq '.headRefName, .url, .body'`
(line 1 the head, line 2 the URL, the rest the body; gh's own `--jq`,
not the jq binary). Unless the head is `--branch` → `! gh pr view: PR
head is not <branch>`; unless the URL is `<repo url>/pull/<n>` → `! gh
pr view: PR is not in <repo url>`; both before the push. The note is
appended under `### Rebases` (the heading added at the end when
missing), the old state-file path replaced with the new one when R8
renumbered, and the edited body scanned (R9). Then `git push
--force-with-lease=<branch>:<lease> origin <branch>`; rejected
(`[rejected]` or `stale info` in its error) → `git reset --keep
<lease>`, `! push refused: <branch> moved on GitHub since <lease7>;
nothing overwritten` (`; <branch> left rebased locally` when the reset
fails); any other push error → `! git push: <first error line>`, no
reset. Then `gh pr edit '<url>' --body-file <file>`. A `gh` failure →
`! gh <verb>: <first error line>`.

**Rationale**: FR-007, FR-008, US3 AC3, AC 3.5. The title comes from the
handoff because the notes may gain a check-fix `Commit:` between the
calls, and a separable `perf` or `refactor` could follow the feature;
`prepare`'s commits, with the main change last, are the PR's own. No
title key is added to the notes (FR-009 fixes the keys). The draft
option goes: it would be a convention option, which FR-009 refuses
(spec assumption 7). The head and repo check keeps a wrong or injected
`--pr` from rewriting another PR's body.

## R11. Closing keywords

**Decision**: a commit subject or body is refused when, case-insensitive
(`shopt -s nocasematch`, bash 3.2 has no `${v,,}`), a word `close`,
`closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves` or
`resolved`, with an optional `:`, is followed by an issue reference:
`#<n>`, `<owner>/<repo>#<n>`, or an `…/issues/<n>` or `…/pull/<n>` URL.
`fix(scope): …` with no reference is not one. The check runs in the notes
parse, before staging; the fixed Log commit holds none.

**Rationale**: these are the words GitHub acts on; a bare "fixes the
parser" closes nothing and must stay writable.

## R12. Conflicts

**Decision**: when a rebase stops on a conflict: `git diff --name-only
--diff-filter=U` → `Conflicts:`, `git rebase --abort`; rebase mode then
`git reset --keep <lease>`; nothing pushed; `PR: conflict`. Ship and fix
leave their commits in place (the move rebases them, and the next ship
finds them, R6); a conflict is not a block, so FR-005's "nothing
committed" does not apply.

When the rebase exits 0 but the same `git diff` lists files (the
autostash pop conflicted, R7): those files → `Conflicts:`, `PR:
conflict`, nothing pushed. There is no rebase to abort and no reset in
any mode (the tree holds the conflict, which a `reset --keep` refuses);
the stash git kept stays in `git stash list`, untouched. `prepare`
writes no handoff; `publish` has already recorded the new HEAD (R3).

**Rationale**: FR-014, today's step 4 and rebase step 4; step.sh's
conflict path (the move, then the ship again) is unchanged.

## R13. The implementers' not verified items and `Security bug`

**Decision**: when the spawn's `not verified items` is not `none`, the
model copies them with Write, one `- <item>` line each as given, to
`<artifact dir>/reports/ship-not-verified.md`, next to the notes, and
passes `--not-verified-file <path>` (none: no flag). `publish` reads it
(lines `- <item>`, blank lines ignored, anything else `! ship: not
verified file: unknown line (line <n>)`); its items go first in the PR
body's `Not verified`, then the notes' items; the report's `Not
verified:` keeps the model's items only. In both ship and fix mode, as
FR-011 reads. The file is data: never evaluated, scanned with the body
(R9). `--security-bug yes|no` is required in fix mode and
checked; the scan runs in every mode whatever its value (US2 AC3); the
only thing it changes is what the model leaves out of `Summary:` (the
reproduction steps), as today.

**Rationale**: FR-002 takes the values given today as arguments, and
FR-016 keeps free text off the fallback line: the items are written by
implementers and can hold `'`, `$(…)` or a backtick, so as flags they
would reach a shell line the user runs. By file, the line holds a path.

**Alternatives**: repeated `--not-verified '<item>'` flags with the
`'\''` quoting rule (the line still carries other agents' text, and one
quoting slip runs a command in the user's shell); `prepare` writing the
items to the handoff (the fallback's `prepare` would still need them as
flags).

## R14. When the session blocks a call

**Decision**: the agent's rule, not the script's: when the session
refuses `bash '<ship script>' prepare …` (a hook, a permission), ship and
fix mode run the checks on the tree as it is, then report `PR: blocked`
with `! cd '<worktree>' && bash '<ship script>' prepare <the same flags>
&& bash '<ship script>' publish <the same flags>`; rebase mode reports
`! ship.sh: refused in this session` and no command. A refused `publish`
after a `prepare` that ran gives the same line: `prepare` again commits
nothing new (R6).

The line holds only paths (worktree, scripts, state, notes,
not-verified file, report) and fixed words (subcommands, modes, flag
names, the default branch, `yes`/`no`): no model or implementer text
(R13). Quoting rule: every flag value in POSIX single quotes, each `'`
inside written `'\''` (`it's` → `'it'\''s'`), nothing double-quoted;
only `cd`, `bash`, `&&`, the subcommands, the modes and the flag names
(all `[a-z-]`) stay bare. A value holding a newline or
carriage return can't be one shell word on one line: the agent then
offers no command and reports `! ship.sh: refused in this session; a
path holds a newline` (ship.sh refuses such a value as a usage error
too). tests/ship builds the line with this rule from a case's flags and
runs it with `bash -c` (R17).

**Rationale**: FR-016. The worktree guard refuses commands naming `git`;
`bash ship.sh …` names none, so this is rare. The old fix-mode pre-scan
of the fallback (`secret-scan.sh worktree`) goes: the scan now runs inside
`prepare`, whoever runs it.

## R15. Where the script's path comes from

**Decision**: step.sh's ship spawn block gains `ship script: <its own
dir>/ship.sh`, printed after `not verified items`. Both skills' `##
Harness values` gain *Ship script* (`/feat`: `<base dir>/scripts/ship.sh`;
`/fix`: `<base dir>/../feat/scripts/ship.sh`), which `references/rebase.md`
names for the rebase-mode spawn (rebase runs outside step.sh). `/feat`'s
phase 8 now also passes the *secret-scan script*, since ship mode scans.

**Rationale**: FR-019. step.sh already prints paths from its own dir
(`read: …/references/move.md`), and tests/step writes that dir `@SKILL@`.
rebase.md takes the value by name, so no `/feat`-only word enters it.

## R16. Bash 3.2 for the scripts the ship calls

**Decision**: `ship.sh` keeps step.sh's construct limits (no `declare
-A`, `mapfile`, `${v,,}`, `declare -n`, `[[ -v ]]`, `;;&`, `|&`;
empty arrays as `${a[@]+"${a[@]}"}`), checked by a grep in tests/ship.
`secret-scan.sh`'s one bash 4 construct, `lower="${1,,}"`, is replaced by
matching the key-literal patterns under `shopt -s nocasematch` (restored
after), with the same rules and output; the same grep then covers it.

**Rationale**: FR-018. `/feat`'s ship now runs the secret scan, and
under macOS's `/bin/bash` 3.2 `${1,,}` is a bad substitution that exits 1,
which the shipper reads as a match: every `/feat` ship would block. The
interface does not change (spec assumption 3).

## R17. Tests

**Decision**: `tests/ship/run.sh` (`mise run test:ship`, a `check.yml`
step, shellcheck in `mise run lint`) builds one template, a bare origin
and a clone of it with the base commit, once per run in a temp dir, and
gives each case its own copy (`cp -R` of both, the clone's `origin` URL
reset to the copy's bare repo), so no case runs `git init` or `git
clone`; target: `mise run test:ship` under 30 seconds on the CI runner,
printed at the end as the run's time. A stub `tests/ship/bin/gh` first
on PATH answers from case
files (`pr list` and `api …/files` for spec-number, `repo view`, `pr
create`, `pr view`, `pr edit`, each with a `fail-<verb>` switch) and logs
its calls, and runs the real `spec-number.sh`, `secret-scan.sh` and
`state.sh`. Each case checks the exit code, the report against
`tests/ship/expected/<case>.out` (`@TOP@` for the case's top level,
`@H1@`… for commit hashes, `UPDATE=1` to rewrite, as tests/step), and the
repo itself: commits and their files, the index, origin's refs, the gh
calls and the PR body. tests/step gains cases that feed tests/ship's
`ship-pr`, `fix-pr`, `ship-conflict`, `ship-blocked` and `rebase-pr`
goldens (hashes made 7-hex) as shipper reports to the ship boundary and
expect the existing goldens' verdicts (`done: PR #N`, the move spawn,
the hard gate). `mise run test:apm` checks `scripts/ship.sh` ships.

The review's cases join the list (spec AC 3.4–3.5, 4.7–4.11, 5.3): a
secret in a commit message, in the ship PR body and in the rebase
body; `--pr` of another branch and of another repo; the branch equal to
`--default` (ship and rebase); `--notes` and `--report` outside
`reports/`, a symlinked `reports/` and a symlinked target, an emptied
`.gitignore` put back to `*`; an autostash conflict; a renumber with a
file outside the PR naming the old path; `publish` retried after a `gh
pr create` failure; the title kept when `publish` adds a check-fix
`Commit:`; `Brought in:` absent in ship mode; and `fallback-quoting`:
the not-verified file holds an item with `'`, `$(touch <case>/pwned)`
and a backtick, the fallback line is built by R14's rule (a `sq`
function in run.sh) and run with `bash -c`; checks: both calls exit 0,
the PR body holds the item verbatim, no `pwned` file.

**Rationale**: FR-020, FR-021, SC-004: the parser is tested on the
script's real output, with no parser and no fixture change. A copied
template keeps about 45 cases fast enough to run before every commit.

## R18. The reports dir: where ship.sh may write

**Decision**: `--notes`, `--report` and `--not-verified-file` must sit
directly in `<artifact dir>/reports/`: after the R4 resolution, the
physical dir of each (`cd -P` to its dirname, then `pwd -P`) must equal
the artifact dir's physical path plus `/reports`; anything else is a
usage error (exit 2, `ship: usage: <flag> is not in <artifact
dir>/reports`), nothing done. Then, still before anything is done, the
script calls the state tool's own guard once per file it will write:
`bash <state-script> report-path <state file> ship-handoff`, and with
`--report` `report-path <state file> <key>`, `<key>` being the report's
file name less its `.md` (a name that is not a valid key is a usage
error). That refuses a symlinked `reports/`, `reports/.gitignore` or
`reports/<key>.md` (the target is checked before the call looks for a
free name), creates `reports/` if needed and rewrites a `.gitignore`
that is not exactly `*`; its printed path is not used (the handoff and
the report keep their fixed names). A non-zero exit is a usage error
carrying its `state: error: …` line. Each write then goes through a
temp file in the same dir and `mv -f`, after a last `[[ -L ]]` check on
the target. After a numbering or renumber the guard runs again on the
numbered dir before the report is written there.

**Rationale**: FR-024. The handoff and report are the script's only
writes under `reports/`, and `reports/` staying ignored is what keeps
them (and the notes) out of every commit. `state.sh report-path` already
holds these checks for every other report, so calling it keeps one copy
(spec assumption 3: its interface is unchanged).

**Alternatives**: a copy of `no_symlink` and the `.gitignore` rewrite in
ship.sh (a second copy to keep in step); sourcing state.sh (it runs its
dispatcher when sourced).
