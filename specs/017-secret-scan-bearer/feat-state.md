# /feat state: Secret scan flags bearer headers, JWTs and URL credentials

- Branch: secret-scan-bearer Worktree: /home/pierre/Projects/logistics/.claude/worktrees/fix-83-secret-scan-bearer
- Size: small
- Agents: specifier a9465bdb04f52b322, planner ac9a31a36c2b7448d, tasker ad6ca2bc23aa5678d (for SendMessage)
- Current phase: done (shipping)
- Conventions: conventional commits type(scope): message, one logical change per commit, user is sole author (no co-author), stage only task files; git as /usr/bin/git, one plain command per call; rm/cp/mv are -i aliases: use command rm -f etc; type rtk gh / rtk mise forms (rtk hook); checks: mise run lint, mise run test:apm and test:secret-scan, test:trail, test:ship, test:tracker; shellcheck clean, scripts Bash 3.2 with no jq or Python; CHANGELOG generated from commits, never edit versions; PR body says Closes #83, never a commit message
- Allowed Spec Kit hooks: none
- Map: none
- Issue: pdemagny/logistics#83

## Brief

- Size: small — ~12 tasks expected: three pattern entries in one script, their tests in two existing suites and a false-positive pass; no new dependency or service
- Short name: secret-scan-bearer
- Kind: feat
- Issue: pdemagny/logistics#83

## Why
`.apm/skills/feat/scripts/secret-scan.sh` is the one list of secret rules:
the shipper's scan (`ship.sh`, staged/range diffs and commit messages),
`tracker.sh create-issue` and `trail.sh redact` all read it. It has no rule
for three common credential shapes, so command output quoting them passes
both `redact` and the ship scan and is committed in a bug trail, then pushed
to a public PR:

- an `Authorization` header with a `Bearer` token;
- a bare JWT (three base64url parts joined by dots, the first starting `eyJ`);
- a URL carrying credentials in its authority (`scheme://user:<password>@host`).

It affects every user of `/fix` and `/feat` whose bug trails or commits
quote HTTP requests, curl commands or git remotes. It was raised as design
finding D7 on the setup-trail-scripts run (#29) and kept out of that feature
because new scan rules change the shipper's and the tracker's behaviour.

## Today
`SECRET_VENDOR` holds five vendor prefixes (private-key, github-token,
aws-key-id, slack-token, openai-key); `key-literal` catches a literal after a
key named password, passwd, token, secret or api key. None of the three
shapes has a vendor prefix or such a key in front of it, so all three fall
through: `secret_line_rule` returns 1 and `trail.sh redact` counts 0 (the
`/fix` assessment in `.specify/bugs/83-secret-scan-bearer/assessment.md`
reproduced it on HEAD 708d407). A JWT is already caught only when it is the
value of such a key (`TOKEN=eyJ…`, `tests/secret-scan` case 7). This is not a
regression: the assessor's old prose list missed these shapes too.

## Behaviour
- `secret-scan.sh` reports a line holding any of the three shapes as
  `<file>:<line>: <rule>`, with the new rule names `bearer-token`, `jwt` and
  `url-credentials`, never the value; same exit codes as today.
- `bearer-token`: `Bearer` or `bearer` (HTTP auth schemes are
  case-insensitive), whitespace, then a run of 16 or more token characters
  (`A-Za-z0-9._~+/-`). `Bearer <token>`, `Bearer <redacted>`, `Bearer $TOKEN`
  and prose such as "a Bearer token" are not flagged. Accepted false
  positive: `Bearer` followed by a hyphenated or dotted word of 16 or more
  characters (in prose, a hyphenated phrase about the auth scheme) is
  flagged and redacted; requiring
  a digit does not combine cleanly with the length in one Bash 3.2 ERE, and
  the case is rare.
- `jwt`: a header part of 10 or more base64url characters starting `eyJ`, a
  dot, a payload part of 10 or more base64url characters, a dot (the
  signature part follows); a bare JWT is flagged anywhere on a line.
  `eyJ..`, or a header or payload shorter than 10, is not flagged.
- `url-credentials`: a scheme, `://`, a user part (no `/`, `:`, `@` or
  whitespace), `:`, a password part of 6 or more characters with no `/`,
  `@` or whitespace that does not start with `<`, `$` or `{`, then `@`.
  `https://user@host`, `user:pass@host` (short), `user:<password>@host`,
  `user:${PASS}@host` and an ssh remote `git@host:owner/repo` are not
  flagged.
- The shipper blocks a commit or commit message with any of these shapes,
  and `tracker.sh create-issue` refuses an assessment holding one, with no
  change of their own: they already go through `secret_line_rule`.
- `trail.sh redact` replaces each shape by `<redacted>` and counts it, with
  no change of its own: its `redact_vendors` already loops over
  `SECRET_VENDOR`. The whole match goes, plus the token-character tail
  `[A-Za-z0-9_/+=.-]*` that `redact_vendors` adds: a bearer header becomes
  `Authorization: <redacted>`, and a credentialed URL loses its scheme,
  credentials, host and path up to the first character outside that set
  (`remote: https://u:…@github.com/o/r.git` becomes `remote: <redacted>`; a
  `:8080/x` port is left). Accepted: safe, and no change to `trail.sh` (see
  Alternatives rejected).
- The rules run after the existing vendor prefixes, so a GitHub token after
  `Bearer` is still reported as `github-token` and the `tests/trail` golden
  `redact-code.md` (`Bearer <redacted>`) is unchanged.
- `secret-scan.sh`'s header comment lists the new rules.

## Out of scope
- Other credential shapes: `Authorization: Basic` headers, cookies,
  `X-Api-Key`-style headers, generic high-entropy strings.
- Readable redaction (keeping `Bearer`, the scheme or the user of a URL):
  needs a change to `trail.sh`.
- Rescanning already-committed files: the scan reads added lines only.
- Any change to `ship.sh`, `tracker.sh` or `trail.sh`.

## Alternatives rejected
- Doing nothing — real tokens in command output reach public PRs through
  bug trails; the issue exists because a design review found the gap.
- A second rule family in `secret_line_rule` (like `key-literal`) instead
  of `SECRET_VENDOR` entries — allows extra checks (a digit in the token),
  but `redact` would then only blank the whole line via its line fallback,
  or need its own change.
- Keeping `Bearer`, the URL scheme or user readable after redaction — needs
  a dedicated branch in `trail.sh`; a trail only has to show a credential
  was there, and an untouched `trail.sh` keeps the change small (user's
  call).
- Flagging any URL password, placeholders included, and making docs build
  examples by concatenation — safer, but blocks ordinary docs
  (`specs/016-setup-trail-scripts/feat-state.md` already quotes a
  `user:pass@host` placeholder) and puts a rule on every doc writer; a real
  password of 5 characters or fewer in a URL is the accepted miss.

## Acceptance
- `tests/secret-scan` reports each shape (built by concatenation) with its
  rule name and never its value, and passes each near miss listed under
  Behaviour (none of them reported).
- `tests/trail`'s `sample()` and its rule-name loops gain the three rules;
  "every SECRET_VENDOR rule has a sample" passes; `redact` replaces each
  shape by `<redacted>`, counts it, and `secret-scan.sh worktree` finds
  nothing in the redacted file; existing goldens are unchanged.
- A lead-character check like the openai rule's (`x <redacted>`) holds for
  any new pattern that matches a leading non-word character.
- A false-positive pass over every tracked text file and this run's own
  artifacts (brief, spec, plan, tasks, PR text) with the three patterns
  finds no hit, or only intended ones, recorded in the PR.
- `mise run lint`, `mise run test:secret-scan`, `mise run test:trail`,
  `mise run test:ship`, `mise run test:tracker` and `mise run test:apm`
  pass.

## Constraints / decisions already made
- Bash 3.2 ERE only (no `\s`, lookahead or lazy quantifiers; POSIX classes);
  no jq, no Python; shellcheck clean.
- Each new pattern holds one bracketed letter, as the existing ones do, so
  `secret-scan.sh` passes its own scan; test samples are built by
  concatenation so the test files pass too.
- `SECRET_VENDOR` matches case-sensitively: spell `[Bb]earer` explicitly.
- `redact_vendors` matches `(pattern)[A-Za-z0-9_/+=.-]*` and keeps a leading
  non-word character: patterns must be shaped so that tail takes the rest of
  the secret (the JWT signature, the URL password's end is already inside
  the match).
- New entries go after the existing vendor prefixes in `SECRET_VENDOR`.
- The run's artifacts (spec, plan, tasks, docs, commit messages, PR text)
  never hold a literal the new rules match: write placeholders
  (`user:<password>@host`, `Bearer <token>`) or build samples by
  concatenation, or the shipper's scan blocks the run's own commit.
- The scan never prints a value; rule names are kebab-case like the others.

## Log

- [x] 0 Setup — brief specs/briefs/secret-scan-bearer.md (small); no Spec Kit hooks; board users/pdemagny/projects/2, #83 set to In progress; existing worktree fast-forwarded to origin/main 43411b2, branch renamed to secret-scan-bearer
- [x] 2 Specify [soft] — spec.md written
    - Stories: US1 Scan reports the three credential shapes (P1); US2 Near misses and placeholders pass (P1); US3 Trail redaction removes the three shapes (P2)
    - Requirements: 13; FR-001..003 the three rules bearer-token, jwt, url-credentials; FR-006 new rules run after existing vendor prefixes; FR-008 redaction replaces with <redacted> and counts; FR-012 false-positive pass; FR-013 no change to ship/tracker/trail scripts
    - Spec assumptions: 1. Out of scope per brief stays out (Basic auth, cookies, readable redaction, rescan, script changes elsewhere) (recommended: keep as written); 2. Short real URL passwords (5 chars or fewer) are an accepted miss (recommended: keep as written)
    - Unchecked checklist items: none
- [x] 3 Plan — merged with 4; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none
- [x] 4 Design review [soft] — auto-applied D1
    - D1 spec.md: FR-002 and US1-2 — FR-002 says the JWT has "the signature after it", but the contract pattern ends at the second dot and requires no signature, so a header.payload. value with an empty signature also matches — rec: apply
    - spec assumptions: kept as recommended
- [x] 3 Plan — amended (D1); assumptions needing you: none; constitution: pass; blockers: none; size trigger: none
- [x] 5 Tasks [soft] — 13 tasks; story.sh: match; analyze ran
- [!] 6 Implement — unparsable: 6-US1.md: line 3 (Tasks not done) — not a "- " item at column 0; reformat 1 of 1
- [x] 6 US1 — not verified: none
    - wrote: specs/017-secret-scan-bearer/tasks.md
- [x] 6 US1 [soft] — checks failed (retry 1 of 1): mise run test:trail
- [x] 6 US1 — not verified: none
    - wrote: tests/trail/run.sh
    - wrote: tests/trail/expected/redact-rules.md
    - wrote: specs/017-secret-scan-bearer/tasks.md
- [x] 6 US2 — not verified: none
    - wrote: specs/017-secret-scan-bearer/tasks.md
- [!] 6 Implement — unparsable: 6-US3.md: line 15 (Files changed) — not a "- " item at column 0; reformat 1 of 1
- [x] 6 US3 — not verified: none
    - wrote: tests/trail/run.sh
    - wrote: specs/017-secret-scan-bearer/tasks.md
- [x] 6 Implement [soft] — tasks done: 13 (0 not verified); checks pass
- [!] 7 Code review — unparsable: 7-7a+7b.md: line 16 (Accepted design findings built (7b)) — not a "- " item at column 0; reformat 1 of 1
- [!] 7 Code review — report missing: 7-7c+7d+7e.md; fresh spawn 1 of 1
- [!] 7 Code review — unparsable: 7-7c+7d+7e.md: line 2 (Cuts (7d)) — an empty field (write none); reformat 1 of 1
- [x] 7 Code review [soft] — auto-applied none; skipped R1 (reviewer: "test-local, three lines apart from use, churn")
    - R1 tests/trail/run.sh:264-269 — Single-letter names b, j, u for the three samples in the new trail case — rec: skip (test-local, three lines apart from use, churn)
- [x] 8 Ship
    - override: hard — a measured finding was lost: url-credentials scheme prefix is quadratic on long lines (first 7c report never written; the rerun dismissed it without measuring); bearer-token also matches when bearer ends a longer word
    - answer: approved (user: "ok a")
    - answer: fix R1 (user: "a")
    - outcome: picked R1
- [x] 7 review fixes — R1 → applied; url-credentials bound → applied; bearer-token word-boundary → applied; performance: url-credentials: 0.71 s per secret_line_rule call (2.141 s for 3 calls) → 0.04 s (0.123 s for 3 calls) (12000-char line of a, via /home/pierre/.claude/jobs/0d922752/tmp/m.sh); checks: rtk mise run lint → pass, rtk mise run test:apm → pass, rtk mise run test:secret-scan → pass, rtk mise run test:trail → pass, rtk mise run test:ship → pass, rtk mise run test:tracker → pass; not verified: none
- [x] 8 Ship
