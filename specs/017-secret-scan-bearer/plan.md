# Implementation Plan: Secret scan flags bearer headers, JWTs and URL credentials

**Branch**: `secret-scan-bearer` | **Date**: 2026-11-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/017-secret-scan-bearer/spec.md` (issue pdemagny/logistics#83)

## Summary

Add three entries, `bearer-token`, `jwt` and `url-credentials`, at the end of
`SECRET_VENDOR` in `.apm/skills/feat/scripts/secret-scan.sh`, and list them in
the script's header comment. The shipper, `tracker.sh create-issue` and
`trail.sh redact` already loop over that list, so they pick the rules up with
no change of their own (FR-007, FR-008, FR-013). The tests in
`tests/secret-scan` and `tests/trail` gain the three shapes, their near
misses and the redaction checks. A false-positive pass over the tracked
files and this run's artifacts closes the work. The exact patterns are in
[contracts/secret-rules.md](contracts/secret-rules.md), and the reasons for
each choice in [research.md](research.md).

## Technical Context

**Language/Version**: Bash 3.2 or later (POSIX ERE via `[[ =~ ]]`), as the script is today

**Primary Dependencies**: none new (git, grep, shellcheck already used)

**Storage**: N/A

**Testing**: `tests/secret-scan/run.sh` (scratch git repos), `tests/trail/run.sh` (fixtures, goldens); `mise run test:secret-scan`, `test:trail`, `test:ship`, `test:tracker`, `test:apm`, `lint`

**Target Platform**: Linux and macOS shells (the user's machine), Claude Code

**Project Type**: CLI scripts shipped inside a skills package

**Performance Goals**: N/A (three more regex tests per scanned line)

**Constraints**: Bash 3.2 ERE only (no `\s`, lookahead or lazy quantifiers); case-sensitive match; each pattern must not match its own source text; shellcheck clean; no literal the rules match anywhere in the repo or this run's artifacts

**Scale/Scope**: one script (3 array entries and the header comment), two test files, one golden

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- I. Thin coordinators: no change to `/feat` or `/fix`. Pass.
- II. The user decides at gates: no gate changes. Pass.
- III. One source of truth per fact: the rules stay in the one list, `SECRET_VENDOR`. The consumers read it and get no copy. Pass.
- IV. Fixed report formats: no agent report changes. Pass.
- V. Small and plain: three array entries, no new file or script. The scripts stay shellcheck clean, with offline tests extended. Pass.

Post-design re-check: unchanged, pass.

## Design

### 1. `secret-scan.sh` (FR-001 to FR-006, FR-009, FR-010)

- Append to `SECRET_VENDOR`, after `openai-key` and in this order: `bearer-token`, `jwt`, `url-credentials`, with the patterns in [contracts/secret-rules.md](contracts/secret-rules.md). Because the loop stops at the first match, the existing vendor rules win (FR-006). A bearer header that carries a JWT reports `bearer-token`, and its redaction takes the whole header.
- In the password's first-character class, write the excluded characters as `<{$` (in that order) and not as `<${`. Inside single quotes, a `${` makes shellcheck raise SC2016. The match is the same.
- Header comment (FR-010): extend the `Rules:` paragraph with one sentence per new rule, in words, from the contract's "Header comment" text. Write no shape literally, so the file still passes its own scan.
- `secret_line_rule`, `secret_rule` and the scanner functions do not change.

### 2. `tests/secret-scan/run.sh` (FR-011, US1, US2)

- Add sample pieces split by concatenation next to the existing ones: a `Bearer` word, a JWT header part and a credentialed-URL prefix. No line of the file may match a rule, and case 9 ("self") checks this.
- New case 10, "bearer, jwt and URL credentials": a staged file with one line per positive (`Bearer` and `bearer` headers, a bare JWT mid-line, a JWT header and payload with an empty signature (FR-002: nothing is required after the second dot), a credentialed https remote, a password of exactly 6 characters, and `Bearer` followed by a GitHub token) and one line per near miss from US2. The case expects:
  - exit 1;
  - output that lists exactly the positives with `bearer-token`, `jwt`, `url-credentials` and `github-token`;
  - `expect_hidden` on every value.
- Case 2 ("true positives") stays as it is.
- Case 7: its line `my conf.env:1` holds a key whose value is a JWT, so it now reports `jwt` and not `key-literal`, because the vendor rules run before `key-literal`. Update that one expected line and the case comment (see Assumption 1).
- Case 6 (sourced): add one call showing that `secret_rule` returns 0 with `SECRET_RULE=url-credentials` on two-line text. `tracker.sh` uses this path (FR-007).

### 3. `tests/trail/run.sh` and goldens (FR-008, FR-011, US3)

- `sample()`: add one sample per new rule, built by concatenation and matching its own rule name. The "every SECRET_VENDOR rule has a sample" check then passes.
- `fill()` and the "every scan rule alone" loop: add the three names. In that loop, assert that each new rule's file reads `x <redacted>`. The shapes start with a letter, so the leading space stays outside the match and is kept (US3-3).
- Golden `expected/redact-rules.md`: the per-rule loop writes one more line per new rule, `seen in the log: <redacted> (rule <name>)`. Regenerate it with `UPDATE=1` and review the diff: only those three lines are added. All the other goldens stay unchanged (US3-4), and `code.md`'s `Bearer <redacted>` still holds.
- New case, "redact: bearer header, JWT and credentialed URLs": a file built inline with these lines:
  - an `Authorization: Bearer` header;
  - a `remote:` line with a credentialed URL and a path;
  - a `curl` line with a credentialed URL followed by a `:8080/x` port;
  - a JWT in parentheses;
  - the near misses `Bearer <token>`, `https://user:<password>@host` and `git@host:owner/repo`.

  After `redact`, the case checks:
  - the count is 4;
  - the lines read `Authorization: <redacted>`, `remote: <redacted>`, `curl <redacted>:8080/x` and `(<redacted>)`;
  - the near misses are unchanged;
  - `scan_clean`, and `again` (a second run changes nothing).

### 4. False-positive pass (FR-012)

At the end of the work, run the three patterns with `git grep -E` over every tracked text file. Run them with `grep -rE` over this run's untracked artifacts (`specs/017-secret-scan-bearer/`, `specs/briefs/secret-scan-bearer.md`, `.specify/bugs/83-secret-scan-bearer/`) and over the commit messages. The commands are in [quickstart.md](quickstart.md). Record the result, expected to be 0 hits, for the PR body. A preview at plan time found 0 hits in both sets.

### 5. Untouched

`ship.sh`, `tracker.sh`, `trail.sh`, their tests, docs and the README are not edited (FR-013). No other file lists the rule names except the archived bug trail `.specify/bugs/22-secret-scan-blocks/`, which stays as it is.

## Project Structure

### Documentation (this feature)

```text
specs/017-secret-scan-bearer/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── secret-rules.md
└── tasks.md             # next phase
```

### Source Code (repository root)

```text
.apm/skills/feat/scripts/
└── secret-scan.sh            # SECRET_VENDOR + header comment
tests/secret-scan/
└── run.sh                    # case 10, case 7 expectation, case 6 call
tests/trail/
├── run.sh                    # sample(), fill(), per-rule loop, new redact case
└── expected/redact-rules.md  # three added lines
```

**Structure Decision**: these are edits to existing files only. No new script, fixture or doc page.

## Complexity Tracking

No violations.
