# Tasks: Secret scan flags bearer headers, JWTs and URL credentials

**Input**: Design documents from `specs/017-secret-scan-bearer/` (plan.md, spec.md, research.md, data-model.md, contracts/secret-rules.md, quickstart.md)

**Prerequisites**: plan.md, spec.md

**Tests**: Requested (FR-011): the scan's tests and the trail tests cover each shape, near miss and leading-character check.

**Organization**: grouped by user story. All sample values in tests are built by concatenation; no task, file or commit message may hold a literal the new rules match (placeholders or words only).

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

**Purpose**: confirm the baseline before editing

- [X] T001 Run `mise run test:secret-scan`, `mise run test:trail` and `mise run lint` from the worktree root and confirm all pass before any edit (baseline for SC-003)

---

## Phase 2: Foundational (blocking)

**Purpose**: the three rules themselves; every story's tests depend on them

- [X] T002 Append the three entries `bearer-token`, `jwt`, `url-credentials`, in this order after `openai-key`, to `SECRET_VENDOR` in `.apm/skills/feat/scripts/secret-scan.sh`, single-quoted, with the patterns exactly as in `specs/017-secret-scan-bearer/contracts/secret-rules.md` (FR-001 to FR-003, FR-006, FR-009). In the url-credentials password's first-character class write `<{$` in that order, never the reverse (shellcheck SC2016). Leave `secret_line_rule`, `secret_rule` and the scanners unchanged.
- [X] T003 In `.apm/skills/feat/scripts/secret-scan.sh`, extend the header comment's `Rules:` paragraph with the contract's "Header comment" text (FR-010), in words, writing no shape literally so the file passes its own scan. Run `shellcheck` on the file and `bash tests/secret-scan/run.sh` case 9 ("self") to confirm.

**Checkpoint**: the scan reports the new rules; tests next.

---

## Phase 3: User Story 1 - Scan reports the three credential shapes (Priority: P1) MVP

**Goal**: the scan reports `bearer-token`, `jwt` and `url-credentials` as `<file>:<line>: <rule>`, never the value, exit codes unchanged.

**Independent Test**: `mise run test:secret-scan` passes with the new case 10 positives.

- [X] T004 [US1] In `tests/secret-scan/run.sh`, add sample pieces split by concatenation next to the existing ones (a `Bearer` word, a JWT header part, a credentialed-URL prefix) so no line of the file matches a rule (case 9 "self" must still pass).
- [X] T005 [US1] In `tests/secret-scan/run.sh`, add case 10 "bearer, jwt and URL credentials": a staged file with one positive line each for `Bearer` and `bearer` headers, a bare JWT mid-line, a JWT header and payload with an empty signature, a credentialed https remote, a password of exactly 6 characters, and `Bearer` followed by a GitHub token (expected `github-token`). Expect exit 1, output listing exactly the positives with their rule names, and `expect_hidden` on every value (FR-005, US1 scenarios 1 to 4).
- [X] T006 [US1] In `tests/secret-scan/run.sh` case 7, change the expected rule for line `my conf.env:1` (a key whose value is a JWT) from `key-literal` to `jwt` and update the case comment (research R4).
- [X] T007 [US1] In `tests/secret-scan/run.sh` case 6 (sourced), add one call showing `secret_rule` returns 0 with `SECRET_RULE=url-credentials` on two-line text (FR-007, the tracker's path).

**Checkpoint**: US1 verified by `mise run test:secret-scan`.

---

## Phase 4: User Story 2 - Near misses and placeholders pass (Priority: P1)

**Goal**: placeholders, short or incomplete shapes and prose are not reported.

**Independent Test**: case 10 near-miss lines produce no output lines.

- [x] T008 [US2] In `tests/secret-scan/run.sh` case 10, add one near-miss line each (built by concatenation or placeholders): `Bearer <token>`, `Bearer <redacted>`, a `Bearer` followed by a `$TOKEN` reference, prose "a Bearer token", `eyJ..`, a JWT-like value with a short header, one with a short payload, a URL with a user and no password, a 5-character password, passwords starting `<`, `$` and `{`, and an ssh remote of the `git@host:owner/repo` form. Assert none of their line numbers appear in the output (FR-004, US2 scenarios 1 to 3).

**Checkpoint**: US1 and US2 both verified by `mise run test:secret-scan`.

---

## Phase 5: User Story 3 - Trail redaction removes the three shapes (Priority: P2)

**Goal**: `trail.sh redact` replaces each shape with `<redacted>`, counts it, keeps a leading non-word character, and a later worktree scan is clean.

**Independent Test**: `mise run test:trail` passes with the new samples, loop entries and case.

- [x] T009 [US3] In `tests/trail/run.sh`, add one sample per new rule to `sample()` (built by concatenation, each matching its own rule name), add the three names to `fill()` and to the "every scan rule alone" loop, and in that loop assert each new rule's file reads `x <redacted>` (FR-011, US3-3). The "every SECRET_VENDOR rule has a sample" check must pass.
- [x] T010 [US3] Regenerate `tests/trail/expected/redact-rules.md` with `UPDATE=1 bash tests/trail/run.sh`, then review `/usr/bin/git diff tests/trail/expected/`: only three added lines of the form `seen in the log: <redacted> (rule <name>)` are allowed; every other golden stays unchanged (US3-4).
- [X] T011 [US3] In `tests/trail/run.sh`, add case "redact: bearer header, JWT and credentialed URLs": a file built inline with an `Authorization: Bearer` header, a `remote:` line with a credentialed URL and path, a `curl` line with a credentialed URL followed by a `:8080/x` port, a JWT in parentheses, and the near misses `Bearer <token>`, a `user:<password>@host` URL and a `git@host:owner/repo` remote. After `redact` check with `grep -qxF`: count is 4; lines read `Authorization: <redacted>`, `remote: <redacted>`, `curl <redacted>:8080/x` and `(<redacted>)`; near misses unchanged; `scan_clean`; a second run changes nothing (FR-008, US3-1 to US3-3).

**Checkpoint**: all three stories verified.

---

## Phase 6: Polish and cross-cutting

- [X] T012 False-positive pass (FR-012, SC-004): run the three `git grep -E` patterns from `specs/017-secret-scan-bearer/quickstart.md` over tracked text files, the same patterns with `grep -rnE` over `specs/017-secret-scan-bearer`, `specs/briefs/secret-scan-bearer.md` and `.specify/bugs/83-secret-scan-bearer`, and over `git log --format=%B origin/main..HEAD`. Expect no hit; note the result for the PR body.
- [X] T013 Run `mise run lint`, `mise run test:secret-scan`, `mise run test:trail`, `mise run test:ship`, `mise run test:tracker` and `mise run test:apm`; all must pass (SC-003, SC-005). Confirm `git status` shows no change to `ship.sh`, `tracker.sh` or `trail.sh` (FR-013).

---

## Dependencies and Execution Order

- T001 first; T002 before T003 and before every test task (T004 onward).
- US1 (T004 to T007) and US2 (T008) all edit `tests/secret-scan/run.sh`: sequential, in order.
- US3 (T009 to T011) edits `tests/trail/` only, so it can run in parallel with US1/US2 once T003 is done; T010 follows T009, T011 follows T010.
- T012 and T013 last, after all test edits.

## Parallel Opportunities

- After T003: T004 to T008 (secret-scan tests) and T009 to T011 (trail tests) touch different files and can proceed in parallel.

## Implementation Strategy

- MVP: T001 to T007 (rules plus positive coverage, the P1 gap). Then T008 (near misses), then US3 coverage, then polish.
- Commit as one logical change per the project rules; the run's commit must itself pass the scan.
