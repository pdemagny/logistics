# Data model: setup-trail-scripts

No stored state is added; these are the values the scripts read and print.

## Preflight result (mode 1)

| Field | Values | Source |
|---|---|---|
| kind | brief, issue, symptom, resume, rebase, empty, idea | the argument (issue parts checked: contracts/preflight.md) |
| brief path, candidates, in checkout | absolute paths, yes/no | lookup in this checkout and every worktree |
| title, size, size note, short name, map, issue | text lines | the brief (data) |
| behaviour, acceptance | `<n> lines` (non-blank lines; 0 stops) | the brief's sections, counted, not printed |
| github, author | yes/no; association, `unknown`, `user` | `gh repo view`, `gh api …/issues/<N>` |
| install, bug extension | ok; version or `unknown` | files under `.specify/`, agents dirs; `extension:`'s two-space `version:` |
| board | tracker line or `off` | `tracker.sh check` |
| default, fetch | branch; ok | `step.sh`'s `default_branch` rule, git |
| hooks | won't run, would branch or commit, allowed | `.specify/extensions.yml` of `origin/<default>` (brief, issue, symptom) or the checkout (`resume`, `rebase`) |
| slug | `[a-z0-9-]{1,40}` | see Slug |
| exit | 0 go on, 1 stop, 2 could not run | |

Validation: a refused kind, a missing field, a failed check stop before
anything later runs; a `stop:` line always ends an exit-1 output.

## Hook entry

| Field | Rule |
|---|---|
| event key | `[a-z][a-z0-9_]*` under `hooks:`, else unparseable |
| enabled | `true/false/yes/no/on/off` (any case); absent = enabled; `false` entries ignored |
| extension | `[A-Za-z0-9][A-Za-z0-9._-]*`, else unparseable |
| command | same pattern, optional |
| class | won't run / would branch or commit (name rule, spec FR-004) / allowed (research R3) |

## Slug

`<base>[-<n>]`, `[a-z0-9-]`, ≤ 40 characters, no leading or trailing `-`.
Base from an issue (`<N>-<words>`, or `<N>` alone), the model's words
(symptom) or a URL's last segment (`bug` when either normalises to nothing).
Built by preflight mode 1: free when no bug dir (`origin/<default>`,
`HEAD`), no local `fix-<slug>` and no remote `fix-<slug>` (one `ls-remote`).
Worktree mode then fails on a bug dir in the worktree or a local
`fix-<slug>` that appeared since (exit 1).

## Bug trail report

`assessment.md`, `test.md`, `fix.md` in `.specify/bugs/<slug>/`; earlier
attempts `<report>-<n>.md`, `n` increasing with time. Required parts per
report: contracts/trail.md. Each holds a `- **Slug**:` bullet.

## Review diff file

`<artifact dir>/reports/review.diff`: the current review boundary's diff,
rewritten at each one, absent before the first non-empty one, never
committed.
