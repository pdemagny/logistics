# Contract: `preflight.sh`

Path: `.apm/skills/feat/scripts/preflight.sh`. Bash 3.2, no jq, no Python,
`set -euo pipefail`, `LC_ALL=C`. Everything on stdout, nothing on stderr.
Nothing read (argument, brief, issue, `extensions.yml`, git output) is
evaluated or executed; text from them is printed only after a fixed key, on
one line, control characters replaced by spaces.

```text
preflight.sh <feat|fix> [<argument>] [slug=<words>]     mode 1, before EnterWorktree
preflight.sh feat worktree <short-name> <on|off>          after EnterWorktree
preflight.sh fix worktree <slug> <on|off>
```

`<argument>` is `$ARGUMENTS` as one word (lines joined with spaces); no
argument or an empty one is kind `empty`. `slug=<words>` gives a `/fix`
symptom's slug words; without it a symptom takes its first four words, and
`/fix` ignores it for any other kind, so the coordinator's guess of the kind
is never load-bearing; `/feat` refuses it (exit 2). A first word `worktree` selects the
worktree mode (a brief named `worktree` is given by its path).

Quoting (both skills): every value from `$ARGUMENTS` or from a line this
script printed is written into a Bash command inside single quotes, each
`'` written `'\''`.

## Exit codes

| Exit | Meaning | Last line |
|---|---|---|
| 0 | go on | — |
| 1 | stop | `stop: <why>` (with `pointer:` / `searched:` lines where they apply) |
| 2 | could not run | `preflight: usage: …` or `preflight: error: <why>` |

Exit 1: a refused kind, no brief found, a `tiny` or `huge` brief, a brief
missing fields, a missing install, an unparseable `extensions.yml`, a failed
board check, a failed `git fetch`, an unreadable issue; in worktree mode, a
bug dir already in the worktree or a branch that can't be renamed. Exit 2:
usage (including a bad worktree-mode argument), not a git repository, no
default branch found, `git ls-remote` failing during the slug check.

## Argument kinds

| Argument | `/feat` | `/fix` |
|---|---|---|
| empty | `kind: empty`, `usage:` line, exit 0, nothing else but `spawn note:` | same |
| exactly `resume` | `kind: resume` | same |
| `rebase`, or `rebase` and one whitespace-free word | `kind: rebase`, `rebase target: <x or none>` | same |
| `#N`, `owner/repo#N`, `https://github.com/<o>/<r>/issues/<N>` (parts checked below) | refused: `pointer: /brief <arg>` | `kind: issue`, `github: yes` |
| other `http(s)://` URL | refused: `pointer: /brief <arg>` | `kind: issue`, `github: no` |
| existing file, or `[specs/briefs/]<name>[.md]` with `<name>` = `[a-z0-9][a-z0-9-]*` | `kind: brief` (lookup below) | a `…specs/briefs/<x>.md` path, or an existing file whose first line starts `# Brief:`: refused, `pointer: /feat <arg>` |
| anything else (holds whitespace, or not a short name; `resume button crashes`, `rebase breaks on merge commits`) | `kind: idea`, refused: `pointer: /brief "<arg>"` (a bug: `/fix "<arg>"`) | `kind: symptom` |

Issue parts: `<o>` matches `[A-Za-z0-9][A-Za-z0-9-]*`; `<r>` matches
`[A-Za-z0-9._-]+` and is not `.` or `..`; `<N>` matches `[1-9][0-9]*`; a URL's
host is exactly `github.com` (scheme `https`, no port, no user part) with
nothing after `<N>` but an optional `/`, `#…` or `?…`. A reference that fails
these is not an issue of any repo: an `http(s)://` one is the other-URL kind
(`github: no`, author `unknown`), anything else (`../x#1`) a symptom or idea.
Only checked parts reach `gh api repos/<o>/<r>/issues/<N>`.

A refused kind prints `kind:`, `pointer:`, `spawn note:` (when it applies) and
`stop: …`, exits 1 and checks nothing else. The coordinator adds the plugin form of each command.

## Steps per kind (mode 1), in this order

| Step | brief | issue / symptom | resume | rebase |
|---|---|---|---|---|
| brief lookup and fields | yes | — | — | — |
| install (`.specify/`, agents; `/fix`: bug extension) | yes | yes | yes | yes |
| board check (`.logistics.yml` present) | yes | yes | — | — |
| default branch, `git fetch origin <default>` | yes | yes | — | — |
| hooks | yes (from `origin/<default>`) | yes (from `origin/<default>`) | yes (checkout) | yes (checkout; `/feat`: implement part only) |
| issue title and author (`/fix`) | — | yes | — | — |
| slug (`/fix`) | — | yes | — | — |

## Output keys, in this order (each only when it applies)

```text
kind: brief | issue | symptom | resume | rebase | empty | idea
usage: /feat <brief path or short name> | resume | rebase [PR]      (empty; /fix: its usage)
rebase target: <PR number, URL or branch> | none
brief: <absolute path> | several
candidate: <absolute path>                (several: one per match, then exit 0)
brief in checkout: yes | no               (exactly <top>/specs/briefs/<short name>.md)
title: <brief title | issue title | URL's last path segment>
size: small | medium | large              (normal → medium, big → large)
size note: <the text after the size word>
short name: <short name>
map: <map line | none>
issue: <brief's Issue line | owner/repo#N | URL | none>
behaviour: <n> lines                      (non-blank lines of ## Behaviour)
acceptance: <n> lines                     (non-blank lines of ## Acceptance)
github: yes | no                          (/fix issue)
author: <association> | unknown | user    (/fix issue, symptom)
install: ok
bug extension: <version | unknown>        (/fix)
board: <tracker.sh check's line> | off
default: <branch>
fetch: ok
hook won't run: <key>: <extension>.<command> → run it by hand: /<command, dots as hyphens>
hook would branch or commit: <key>: <extension>.<command> → run it by hand: /<command, dots as hyphens>
hooks allowed: <key>: <extension>.<command>, … | none
slug: <slug>                              (/fix issue, symptom)
pointer: <command>                        (refusals, no match, tiny, huge)
searched: <path>                          (no match: one per path)
spawn note: <constant>                    (every kind; only when CLAUDE_CODE_FORK_SUBAGENT is unset or empty; never in worktree mode)
stop: <why>                               (exit 1)
```

A hook with no `command` prints `<key>: <extension>` with no manual command.
A hook enabled under several keys prints once per key. `hooks allowed:` is
what the coordinator writes on `Allowed Spec Kit hooks`.

### Brief fields

Header = the lines before the first `## `. Required: `- Size:` whose first
word is `small|medium|large|normal|big` (`tiny`, `huge`: stop, pointer
`/tiny <path>` or `/brief <path>` for tiny, `/brief <path>` for huge),
`- Short name:` matching `[a-z0-9][a-z0-9-]*`, a `## Behaviour` and a
`## Acceptance` section each with a non-blank line. Missing ones: `stop:
brief lacks <size, short name, behaviour, acceptance>`, exit 1. The section
lines are counted, not printed.

### Bug extension version

`.specify/extensions/bug/extension.yml`: the first line matching exactly two
spaces, `version:`, a value, among the lines after the column-0 `extension:`
line and before the next column-0 key (so `requires:`'s `speckit_version:`
never counts). Surrounding quotes stripped; printed only when it matches
`[A-Za-z0-9][A-Za-z0-9._-]*`, else `unknown` (also for a missing file or
line).

### Default branch

A copy of `step.sh`'s `default_branch` (named in a comment): `git
symbolic-ref -q --short refs/remotes/origin/HEAD` stripped of `origin/`, else
the `ref: refs/heads/<x>` line of `GIT_TERMINAL_PROMPT=0 git ls-remote
--symref origin HEAD`. An empty name, a leading `-`, or a name `git
check-ref-format --branch` doesn't return unchanged → `preflight: error: no
default branch found`, exit 2.

### Hooks

Source: for a brief, an issue or a symptom, after the fetch, `git cat-file
-e refs/remotes/origin/<default>:.specify/extensions.yml` (absent: no hooks)
then `git show` of it; for `resume` and `rebase`, the checkout's
`.specify/extensions.yml`. Read per research R2 (subset, fail closed: `stop:
<source> can't be read as data (line <n>); it may hide a hook that commits`,
exit 1, `<source>` being `origin/<default>:.specify/extensions.yml` or
`.specify/extensions.yml`). An event key outside
`[a-z][a-z0-9_]*`, or an `extension` or `command` outside
`[A-Za-z0-9][A-Za-z0-9._-]*`, is unparseable.

"Would branch or commit", on the lowercased extension and command: the
extension is `git`; or either has a word starting with `git`, or `pr`,
`pull`, `tag` or `worktree` as one of its `.`/`-`/`_`-separated words; or
either contains `commit`, `branch`, `push`, `merge`, `rebase`, `checkout`,
`switch`, `release`, `publish`, `pullrequest`, `amend`, `squash` or
`cherry` anywhere. Names only: a hook's description and prompt are not read. Where
each class goes per skill and key: research R3.

### Slug (`/fix`)

Base: issue `<N>-<first three title words>` (two when over 40; `<N>` alone
when the title has no `[a-z0-9]` word); symptom the `slug=` words (none
given: its first four words);
non-GitHub URL its last path segment (without query or fragment). Normalised:
lowercase, every run of `[^a-z0-9]` → `-`, `-` trimmed at both ends, cut to
40 at a `-`. A symptom or URL base empty after this is `bug`.

Clash check: one `GIT_TERMINAL_PROMPT=0 git ls-remote --heads origin 'fix-*'`
(failure: exit 2), its ref names kept. Candidates `<base>`, then `<base>-2`,
`-3`, … with the base trimmed (and a trailing `-` dropped) so the slug stays
≤ 40. A candidate is taken when `git cat-file -e` finds `.specify/bugs/<slug>`
in `refs/remotes/origin/<default>` or `HEAD`, `refs/heads/fix-<slug>` exists
locally, or the kept list holds exactly `refs/heads/fix-<slug>`. The first
free one is printed.

## Worktree mode

1. Arguments: `<short-name>` must match `[a-z0-9][a-z0-9-]*`; `<slug>` the
   same and at most 40 characters; the last argument `on` or `off`. Else
   `preflight: usage: …`, exit 2.
2. `git rev-parse --show-toplevel` (exit 2 if not a repo); print
   `worktree: <top>`.
3. `/fix`: `<top>/.specify/bugs/<slug>` exists → `stop: slug <slug> is taken
   (bug dir); run setup again`, exit 1.
4. Branch: target `<short-name>` or `fix-<slug>`; equal to `git branch
   --show-current` → `branch: <name>`; else `git branch -m <name>` →
   `branch: <name>`, or on failure (a local branch of that name exists)
   `stop: can't rename the branch to <name>: <git's first line>`, exit 1.
5. `<on|off>` is `on` and `<top>/.logistics.yml` is missing → `flag: - [!]
   tracker: .logistics.yml is not in the worktree; commit and push it (board
   moves skipped)`.

No network call: a remote `fix-<slug>` created after mode 1 is caught at
push.

Coordinator call, one Bash command:

```text
bash '<preflight script>' feat worktree '<short name>' '<on|off>' && S init feat … && S log … && T feat '<state file>' setup
bash '<preflight script>' fix worktree '<slug>' '<on|off>' && S init fix '.specify/bugs/<slug>/feat-state.md' … && S log … && T fix '<state file>' setup
```
