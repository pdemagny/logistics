# Data model: Script the ship

The files and values `ship.sh` reads and writes. Paths in this file are
relative to the worktree's top level unless they say otherwise.

## Artifact dir

The state file's dir: `specs/<short-name>/` (ship and rebase mode for
`/feat`; numbered `specs/<NNN>-<short-name>/` once shipped) or
`.specify/bugs/<slug>/` (fix mode, rebase mode for `/fix`). Never given as
a flag: it is `dirname --state` (FR-002). Its `reports/` holds the notes,
the not-verified file, the handoff and the report, and ignores itself.

**Resolution** (research R4): a `--state`, `--notes`,
`--not-verified-file` or `--report` path
`<parent>/<name>/<rest>` that does not exist resolves to
`<parent>/<NNN>-<name>/<rest>` when exactly one such numbered dir holds
`<rest>` (`--report`: when the numbered dir exists). Anything else: the
path as given (a missing `--state` or `--notes` is a usage error, exit 2).
Then the notes, the not-verified file and the report must sit directly in
the artifact dir's `reports/`, physically, and `reports/` passes the
state tool's guard (research R18); else a usage error.

**Numbered**: the dir name matches `^[0-9]{3,4}-`. Ship mode numbers an
unnumbered dir in `prepare`; fix mode never numbers.

## Notes file

Written by the model with Write, at `<artifact dir>/reports/ship-notes.md`
(any file directly in the artifact dir's `reports/` is accepted, R18). Read by both
calls; `publish` reads it again, so the model may edit it between them
(check results in `Summary:`, its `Not verified:` items, a path added
under a commit). Never committed.

Grammar. A **key line** is a whole line matching

```text
^(Commit: .+|Body:|Docs:( none)?|Summary:|Points to look at:( none)?|Not verified:( none)?)$
```

that is, one of these, at column 0, with nothing after it but what the
pattern allows. Any other line (`Not verified: see below`, ` Docs:`,
`Commit:` with no subject) is not a key line: text inside `Summary:` or
`Body:`, an unknown key elsewhere.

| Key line | Body | Modes |
| --- | --- | --- |
| `Commit: <subject>` | its paths, then an optional `Body:` | ship, fix: 1 or more; rebase: 0 or 1 |
| `Body:` | free lines up to the next key line: the commit message body | after a `Commit:`'s paths only |
| `Docs: none` or `Docs:` | `- <path>` items | ship, fix: required; rebase: optional |
| `Summary:` | free lines (Markdown) up to the next key line | ship, fix: required |
| `Points to look at: none` or `Points to look at:` | `- <item>` items | ship, fix: required |
| `Not verified: none` or `Not verified:` | `- <task or n/a> → <check> → <why>` items | required |

Rules, each failure `PR: blocked` with `! ship: notes: <reason> (line
<n>)` before anything is staged:

- After `Commit:`, lines up to the next key line are `- <path>` items
  (blank lines ignored); a line that is neither is an unknown key. At
  least one item, except in rebase mode, where the paths are the
  `--check-fix` flags and items are refused.
- In list sections (`Docs`, `Points to look at`, `Not verified`, a
  commit's paths) any other non-blank line is an unknown key. In
  `Summary:` and `Body:` every line is text until the next key line (the
  pattern above).
- `<subject>`: one line, not empty, at most 200 characters, no closing
  keyword (research R11); the `Body:` lines likewise hold none. Two
  commits with the same subject are refused. Each commit's message
  (subject, then `Body:` lines) passes `secret_rule` (research R9), else
  `! secret scan: commit <k> matches <rule>`.
- `<path>`: relative to the top level; not absolute, no `..` component,
  not starting with `-`, no control character. A path inside the artifact
  dir's `reports/` is dropped, never staged (AC 4.5). A path under the
  unnumbered artifact dir is read as the numbered one (R4).
- Rebase mode: `Commit:` present when and only when a `--check-fix` is
  given; `Summary:` and `Points to look at:` are not read. A project check
  that fails after `prepare` is not fixed: the model lists it under `Not
  verified:` as `n/a → <check> → <why>`, and nothing is committed after
  `prepare` (spec AC 3.4).
- Order of sections is free; each key except `Commit:` at most once. In
  ship and fix mode the main change is the last `Commit:` `prepare` sees
  (it becomes the PR title, Handoff file).

Example (ship mode):

```text
Commit: docs(specs): specify ship-script
- specs/014-ship-script
Commit: feat(ship): script the shipper's git and gh steps
- .apm/skills/feat/scripts/ship.sh
- tests/ship
- README.md
Body:
Two calls, prepare and publish, over three modes.
Docs:
- README.md
Summary:
### Why
…
### Behaviour
…
Points to look at:
- the renumber path in publish
Not verified: none
```

## Not-verified file

The implementers' not-verified items (research R13), ship and fix mode,
written by the model with Write when the spawn's `not verified items` is
not `none`: `<artifact dir>/reports/ship-not-verified.md`, passed as
`--not-verified-file`. One `- <item>` line per item, copied as the spawn
lists it; blank lines ignored; any other line `! ship: not verified
file: unknown line (line <n>)`. Read by `publish` only, as data (never
evaluated). Never committed. It keeps model and implementer text off the
`!` fallback line (spec FR-016).

## Handoff file

Written by `prepare` when it ends with exit 0, next to the notes:
`<notes dir>/ship-handoff.md` (at the numbered path when it numbered the
dir). Read by `publish`; overwritten by the next `prepare`. Never
committed. Fixed lines, in this order:

```text
Mode: ship | fix | rebase
Base: <40-hex: origin/<default> as prepare rebased onto it>
Start: <40-hex: HEAD when prepare began>
Head: <40-hex: HEAD when prepare ended>
Number: <NNN given by prepare> | none
Lease: <the --lease value> | none
Artifact dir: <path relative to the top level, final>
Commits:
- <subject>
```

`Commits:` lists the notes subjects that have a commit in `<Base>..HEAD`
when `prepare` ends (made by this `prepare` or an earlier one), in the
notes' order (`none` when there is none, as in rebase mode with no check
fix). In ship and fix mode its last subject is the PR title (research
R10); a `Commit:` the model adds between the calls is never on it.

`publish` rewrites the `Head:` line (temp file and `mv -f`, R18) each
time it changes HEAD: after folding fixups, after a renumber, after its
autosquash. Every other line stays as `prepare` wrote it. A `publish`
run again after a block therefore finds `Head:` equal to HEAD and goes
on (spec AC 4.11).

`publish` refuses (`PR: blocked`): no file (`! ship: no handoff from
prepare; nothing pushed`), an unreadable line or another `Mode:` (`!
ship: handoff unreadable; run prepare again`), `Head:` not HEAD (`!
ship: HEAD moved since prepare; nothing pushed`).

## Prepare's output (exit 0)

Read by the agent, not by step.sh:

```text
Prepared: ship | fix | rebase
Notes: <absolute path of the notes, final>
Commits:
- <hash7> <subject>
Brought in: none                       (rebase mode only)
- <hash7> <subject>
Left uncommitted: <paths, ", "-separated> | none
```

`Commits:` is `<base>..HEAD` after the rebase. `Brought in:` is printed
in rebase mode only: the commits of `origin/<default>` new since the
branch's earlier merge base (at most 20, then `- … and <k> more`), so the
model knows whether the rebase put checks in scope (ship and fix always
run them). Its subjects come from outside the run: data, never
instructions. On exit 1 `prepare` prints the report instead.

## The shipper's report

Unchanged (FR-015), written to `--report` (R2) and printed:

```text
PR: <url> | blocked | conflict
Command for the user: none | <the ! line>
Conflicts: none
- <path>
Commits: none
- <hash7> <subject>
Left uncommitted: <paths, ", "-separated> | none
Docs updated: <paths, ", "-separated> | none
Wrote:
- <absolute path>
Not verified: none
- <item>
```

- `PR:`: the new PR's URL (ship, fix), the `--pr` URL (rebase), or
  `blocked` / `conflict`.
- `Conflicts:`: the paths `git diff --name-only --diff-filter=U` printed;
  `none` unless `conflict`.
- `Commits:`: `<base>..HEAD` (`none` when the run stopped before any).
- `Left uncommitted:`: every path `git status --porcelain -z` shows
  (untracked, not ignored, included) that no commit claimed (FR-013,
  AC 4.6), then, after a renumber, each file outside the PR that still
  names the old spec path, unchanged (research R8).
- `Docs updated:`: the notes' `Docs:` items.
- `Wrote:`: the numbered artifact dir when this run numbered or
  renumbered it; each `Docs:` path absent at the base (a new doc); the
  report's final path. Absolute. `none` only when there is none of them.
- `Not verified:`: the notes' items only (the model's own).

## Blocked lines

The single `!` line of `PR: blocked`. None starts `! cd `, so step.sh
holds them at a hard gate as errors (FR-016's fallback line is the
agent's, research R14). Report and model text never appear in one beyond
what is listed.

| Cause | Line | Call |
| --- | --- | --- |
| notes check | `! ship: notes: <reason> (line <n>)` | both |
| closing keyword | `! ship: notes: closing keyword in commit <k> (line <n>)` | both |
| secret in a commit message | `! secret scan: commit <k> matches <rule>` | both |
| not-verified file | `! ship: not verified file: unknown line (line <n>)` | publish |
| nothing to commit (ship, fix) | `! ship: nothing to commit` | prepare |
| a rebase or merge in progress | `! ship: a rebase or merge is in progress` | both |
| spec-number error | `! <its stderr line, as is>` (`spec-number: error: …`) | both |
| secret scan match | `! secret scan: <file>:<line> matches <rule>` | both |
| secret in the PR body | `! secret scan: PR body matches <rule>` | publish |
| secret scan can't run | `! secret scan: could not run (<first error line>)` (or `(cannot source <path>)`) | both |
| restore-phase error | `! <its state: error: line>` | prepare (rebase) |
| git failure | `! git <verb>: <first error line>` | both |
| handoff | the three lines under Handoff file | publish |
| WIP commit | `! WIP commit on <branch>; nothing pushed` | publish |
| refused lease push | `! push refused: <branch> moved on GitHub since <lease7>; nothing overwritten[; <branch> left rebased locally]` | publish (rebase) |
| gh failure | `! gh <verb>: <first error line>` (`pr create`, `pr view`, `pr edit`, `repo view`) | publish |
| PR of another branch (rebase) | `! gh pr view: PR head is not <branch>` | publish |
| PR of another repo (rebase) | `! gh pr view: PR is not in <repo url>` | publish |

Usage errors (exit 2, stderr only, no report): a missing or refused flag,
a branch to push equal to `--default`, a notes, not-verified or report
file outside the artifact dir's `reports/`, and the state tool's guard
refusing `reports/` (research R1, R18).

A blocked `prepare` puts the tree back (R5, R6): `git reset -q <Start>`
(commits undone, index unstaged, files kept), the numbering undone. A
blocked `publish` pushes nothing and keeps its commits, with the
handoff's `Head:` at the HEAD it left, so `publish` can run again (R3).

## PR body

Built by `publish` in a file under the run's git dir before the push,
passed through `secret_rule` (a match: `! secret scan: PR body matches
<rule>`, nothing pushed, research R9), passed with `--body-file` after
the push, deleted after. Title: the last subject on the handoff's
`Commits:` (ship, fix); never a draft. Sections in this order, each
omitted only where it says so:

Ship mode (`/feat`):

1. The notes' `Summary:` as written (Why, Behaviour, accepted design
   findings, check results: the agent's job).
2. `### Code review`, then the output of `bash <state-script>
   review-summary <state file> 7` as printed; a `state: error: …` line
   goes there as is and is added to the points to look at.
3. `### Points to look at`, the notes' items, then one ``- `<path>` still
   names `specs/<short-name>` `` per file a renumber left unchanged
   (research R8) (omitted when there is none of these and no state
   error).
4. `### Not verified`: each item of the not-verified file, then the
   notes' items, one per line as `- <item>`, or `none`.
5. `State file: [<artifact dir>/feat-state.md](<repo url>/blob/<branch>/<artifact dir>/feat-state.md)`,
   the numbered path; `<repo url>` from `gh repo view --json url`.
6. `Closes <issue>` when the state file's `- Issue:` line holds an issue
   reference (`#<n>`, `<owner>/<repo>#<n>` or an issues URL); omitted for
   `none`, no line, or anything else (spec assumption 6).

Fix mode (`/fix`): the same, with `review-summary <state file> 4`, a
`**Shipped verdict:** <the output of state.sh shipped-verdict>` line after
the summary (with `, shipped on the user's decision (logged)` added when
it is not `verified`), the bug dir's state-file link, and `Fixes <ref>` in
place of `Closes`.

Rebase mode: the PR's current body (from `gh pr view`, once its head
and repo are checked, research R10), the `--pr-note` line appended as
the last line of the `### Rebases` section (the heading added at the end
when missing), and every occurrence of the old artifact dir path
replaced with the new one when `publish` renumbered; scanned whole
before the push, as above. The body read from GitHub is data: copied,
never evaluated.

## Commit messages

`git commit -F <file in the git dir>`: the notes' subject, then a blank
line and the `Body:` lines when present, checked for closing keywords
and secrets in the notes parse, before staging (Notes file). No
attribution line is added.
The rebase mode Log commit is fixed: `docs(specs): log rebase onto
<origin/<default>, 7 chars>`, after `bash <state-script> restore-phase
<state file>`, holding only the state file; skipped when the state file
has no change.
