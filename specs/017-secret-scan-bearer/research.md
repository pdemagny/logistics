# Research: secret-scan-bearer

There were no NEEDS CLARIFICATION items. These are the decisions taken while
planning, checked against the code at HEAD 43411b2.

## R1. Where the rules go

- Decision: three entries at the end of `SECRET_VENDOR`.
- Rationale: `secret_line_rule` (scan, shipper, tracker) and
  `trail.sh redact_vendors` both loop over this array. Entries at the end
  keep the existing vendor names winning (FR-006).
- Alternatives considered: a second rule family next to `key-literal`. The
  brief rejects it, because redaction would then blank the whole line or
  need a change to `trail.sh`.

## R2. Pattern shapes

- Decision: the patterns in [contracts/secret-rules.md](contracts/secret-rules.md).
  - `bearer-token`: `[Bb]earer`, whitespace, then 16 or more token characters.
  - `jwt`: `ey[J]` plus 7 or more base64url characters (a header part of 10 or
    more), a dot, a payload part of 10 or more, then a dot.
  - `url-credentials`: an RFC 3986 scheme (`[A-Za-z][A-Za-z0-9+.-]*`), `://`,
    a user part with no `/`, `:`, `@` or whitespace, `:`, a password part
    whose first character is not `/ @ < { $` or whitespace, followed by 5 or
    more characters with no `/`, `@` or whitespace, then `@`.
- Rationale: these are the spec's FR-001 to FR-003, written as plain POSIX ERE.
  The `jwt` and `url-credentials` patterns stop before the part that varies
  (the signature, the host). `redact_vendors` appends the tail
  `[A-Za-z0-9_/+=.-]*`, which takes the JWT signature, and the URL's host
  and path up to the first character outside that set. No pattern can start
  with a non-word character, so the existing lead-keeping logic has nothing
  to keep inside the match: the character before the shape stays outside it.
- Verified at plan time in bash, with samples built by concatenation:
  - all US1 positives match, under the expected rule;
  - all US2 near misses miss: `Bearer <token>` and `Bearer <redacted>`, a
    `$TOKEN` reference, prose, `eyJ..`, a short header or payload, a URL
    with a user only, a 4-character password, the `<`, `$` and `{`
    placeholders, the ssh remote with and without `ssh://`, and a port
    followed by an `@` in the path;
  - a password of exactly 6 characters matches;
  - the simulated redaction gives `Authorization: <redacted>`,
    `remote: <redacted>`, `curl <redacted>:8080/x` and `(<redacted>)`, and
    a scan of each result finds nothing;
  - `Bearer` followed by a GitHub token gives `Bearer <redacted>` under
    `github-token`.

## R3. Self-scan and shellcheck

- Decision: each pattern holds a bracketed letter at the point where its
  own text would otherwise match: `[B]`/`[b]` in `[Bb]earer`, `ey[J]`, and
  the scheme's `[A-Za-z]`. The URL pattern's own text puts a `*` right
  before `://`, so no scheme can match there. The password's
  first-character class lists `<{$` in that order.
- Rationale: FR-009 requires the script to pass its own scan (case 9 checks
  this). The plan-time grep of the patterns over the repo returned 0 hits,
  `secret-scan.sh` included once the entries are added. With `${` inside
  single quotes, shellcheck reports SC2016 (it exits 1 on info). With `{$`
  it is clean (checked).
- Alternatives considered: a double-quoted pattern with `\$`. It is noisier,
  and the other entries are single-quoted.

## R4. Effect on existing tests

- Decision: one existing expectation changes. `tests/secret-scan` case 7,
  line `my conf.env:1` (a key whose value is a JWT), now reports `jwt`
  instead of `key-literal`. The `tests/trail` golden `redact-rules.md`
  gains three lines from its per-rule loop. All the other goldens stay as
  they are.
- Rationale: vendor rules run before `key-literal`, the same way a GitHub
  token in a key's value already reports `github-token`. In redaction,
  `redact_keys` runs before `redact_vendors`, so the redacted output of a
  key holding a JWT does not change. Keeping `key-literal` would need a
  second rule family (rejected in R1).
- Alternatives considered: change case 7's sample so that it no longer looks
  like a JWT. Rejected: it would hide the overlap the case documents.

## R5. Trail coverage without new fixtures

- Decision: a new inline case in `tests/trail/run.sh` with exact-line checks
  (`grep -qxF`), with no new fixture or golden.
- Rationale: the existing per-rule cases already build their files inline.
  Exact lines state US3-1 to US3-3 directly, and a golden would add a file
  without adding a check.
