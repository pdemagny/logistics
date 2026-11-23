# Feature Specification: Secret scan flags bearer headers, JWTs and URL credentials

**Feature Branch**: `secret-scan-bearer`

**Created**: 2026-11-23

**Status**: Draft

**Input**: User description: "Brief specs/briefs/secret-scan-bearer.md (issue pdemagny/logistics#83): the shared secret rules have no rule for a bearer authorization header, a bare JWT or a URL carrying credentials, so command output quoting them passes both the bug-trail redaction and the shipper's scan."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Scan reports the three credential shapes (Priority: P1)

A maintainer (or the shipper, the tracker's issue creation and the trail redaction, which all read the one rule list) scans text holding a bearer authorization header, a bare JWT or a URL with a password in its authority. The scan reports each as `<file>:<line>: <rule>` with the rule name `bearer-token`, `jwt` or `url-credentials`, never the value, and exits as it does today for any finding.

**Why this priority**: This is the gap. Without it nothing downstream (shipper block, tracker refusal, redaction) can act.

**Independent Test**: Feed the scan a file with one line per shape (samples built by concatenation) and check the three rule names are reported, no value is printed, and the exit code matches today's for a finding.

**Acceptance Scenarios**:

1. **Given** a line with the word `Bearer` (or `bearer`), whitespace and a run of 16 or more token characters, **When** the scan runs, **Then** it reports `bearer-token` for that line.
2. **Given** a bare JWT (header part starting `eyJ`, dot, payload part, dot) anywhere on a line, **When** the scan runs, **Then** it reports `jwt`. Anything after the second dot is optional, so a value with an empty signature is reported too; redaction removes the signature along with the rest.
3. **Given** a URL with scheme, user, a password of 6 or more characters and `@host`, **When** the scan runs, **Then** it reports `url-credentials`.
4. **Given** a line with a GitHub token after `Bearer`, **When** the scan runs, **Then** it is still reported as `github-token` (existing rules win).

---

### User Story 2 - Near misses and placeholders pass (Priority: P1)

A writer quotes placeholders, short or incomplete shapes, or ordinary prose in docs, specs and trails. None of them is reported.

**Why this priority**: A rule that blocks ordinary docs is rejected by users and would force workarounds on every doc writer.

**Independent Test**: Run the scan on each listed near miss and check nothing is reported.

**Acceptance Scenarios**:

1. **Given** `Bearer <token>`, `Bearer <redacted>`, `Bearer $TOKEN` or prose such as "a Bearer token", **When** scanned, **Then** nothing is reported.
2. **Given** `eyJ..`, or a JWT-like value whose header or payload is shorter than 10 characters, **When** scanned, **Then** nothing is reported.
3. **Given** a URL with a user but no password, a password of 5 characters or fewer, a placeholder password starting `<`, `$` or `{`, or an ssh remote of the `git@host:owner/repo` form, **When** scanned, **Then** nothing is reported.

---

### User Story 3 - Trail redaction removes the three shapes (Priority: P2)

A user runs a `/fix` or `/feat` whose command output quotes a bearer header, a JWT or a credentialed git remote. The trail redaction replaces each with `<redacted>`, counts it, and a later worktree scan of the redacted file finds nothing.

**Why this priority**: It is what keeps credentials out of committed trails and public PRs; it depends on story 1 and needs no change of its own.

**Independent Test**: Redact a sample file holding each shape; check the replacement, the count, and a clean worktree scan of the result.

**Acceptance Scenarios**:

1. **Given** an `Authorization: Bearer` header with a real-looking token, **When** redacted, **Then** the line reads `Authorization: <redacted>`.
2. **Given** a git remote line with a credentialed URL, **When** redacted, **Then** the scheme, credentials, host and path up to the first character outside the token set are replaced by one `<redacted>` (a port or later path after such a character is left).
3. **Given** a line where the shape follows a leading non-word character, **When** redacted, **Then** that character is kept (as for the existing vendor rules).
4. **Given** existing redaction samples, **When** redacted, **Then** existing golden outputs are unchanged.

---

### Edge Cases

- `Bearer` followed by a hyphenated or dotted word of 16 or more characters (for instance a prose phrase about the auth scheme) is flagged and redacted: an accepted false positive.
- A real URL password of 5 characters or fewer is not caught: an accepted miss.
- Redaction of a credentialed URL removes more than the credential (host and path up to the first character outside the token set): accepted, safe.
- Already-committed files are not rescanned; only added lines are read.
- The scan's own source and its tests hold the patterns and samples, and must still pass the scan.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The shared secret scan MUST report a line holding a bearer token as `<file>:<line>: bearer-token`: `Bearer` or `bearer`, whitespace, then 16 or more characters from letters, digits and `. _ ~ + / -`.
- **FR-002**: It MUST report a line holding a bare JWT as `jwt`: a header part of 10 or more base64url characters starting `eyJ`, a dot, a payload part of 10 or more base64url characters, a dot; anywhere on the line. What follows the second dot is not required: a header-payload pair with an empty signature is reported, not treated as a near miss. Redaction takes the signature when one follows.
- **FR-003**: It MUST report a line holding URL credentials as `url-credentials`: a scheme, `://`, a user part (no `/`, `:`, `@` or whitespace), `:`, a password part of 6 or more characters (no `/`, `@` or whitespace) not starting with `<`, `$` or `{`, then `@`.
- **FR-004**: It MUST NOT report the near misses listed in user story 2, and MUST NOT report `Bearer` followed by a placeholder or prose.
- **FR-005**: It MUST never print the matched value, only file, line and rule name; exit codes are unchanged.
- **FR-006**: The new rules MUST run after the existing vendor prefixes, so existing rule names win where both match, and the existing redaction golden stays unchanged.
- **FR-007**: The shipper MUST block a commit or commit message holding any of the shapes, and the tracker's issue creation MUST refuse an assessment holding one, through the shared rule list alone.
- **FR-008**: Trail redaction MUST replace each shape, together with the token-character tail the existing vendor redaction adds, by `<redacted>`, count it, and keep a leading non-word character; a worktree scan of the redacted output MUST find nothing.
- **FR-009**: Rule names MUST be kebab-case; patterns MUST work in Bash 3.2 extended regex only, match case-sensitively (so `Bearer` and `bearer` are spelled out), each hold one bracketed letter so the scan's own source passes its scan, and the shellcheck check stays clean.
- **FR-010**: The scan script's header comment MUST list the three new rules.
- **FR-011**: The scan's tests and the trail tests MUST cover each shape (samples built by concatenation), each near miss, the leading-character check for any pattern that can match a leading non-word character, and the "every vendor rule has a sample" check.
- **FR-012**: A false-positive pass of the three patterns over every tracked text file and this run's artifacts MUST find no hit, or only intended ones, recorded in the PR.
- **FR-013**: No change to the shipper, tracker or trail scripts themselves.

### Key Entities

- **Secret rule**: a named pattern in the single shared list; reported by name, never by value.
- **Credential shape**: bearer header token, bare JWT, or URL with credentials in its authority.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Each of the three shapes is reported with its rule name in 100% of the test samples, and none of the listed near misses is reported.
- **SC-002**: After redaction, a worktree scan of a file holding all three shapes reports 0 findings, and the redaction count includes each.
- **SC-003**: All existing scan, trail, ship and tracker tests and goldens pass unchanged except for the added samples.
- **SC-004**: The false-positive pass over tracked text files and this run's artifacts finds 0 unintended hits.
- **SC-005**: Lint, the scan, trail, ship, tracker and package test tasks all pass.

## Assumptions

- The brief's "Out of scope" holds: no `Authorization: Basic`, cookies, API-key headers or high-entropy strings; no readable redaction (keeping the scheme or user); no rescan of committed files; no change to the shipper, tracker or trail scripts.
- Placeholders are kept out of the rules, by the placeholder start characters rule and the 16-character and 6-character minimums; a short real password is an accepted miss.
- This run's artifacts (spec, plan, tasks, docs, commit messages, PR text) use placeholders or describe shapes in words, so the run's own commit passes the scan.
