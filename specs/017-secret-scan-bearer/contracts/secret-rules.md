# Contract: the three new `SECRET_VENDOR` entries

These entries go at the end of the array in
`.apm/skills/feat/scripts/secret-scan.sh`, after `openai-key`, in this
order. Each one is written single-quoted, exactly as below.

| Name | Pattern |
|------|---------|
| `bearer-token` | `(^\|[^A-Za-z0-9_-])[Bb]earer[[:space:]]+[A-Za-z0-9._~+/-]{16,}` |
| `jwt` | `ey[J][A-Za-z0-9_-]{7,}[.][A-Za-z0-9_-]{10,}[.]` |
| `url-credentials` | `[A-Za-z][A-Za-z0-9+.-]{0,31}://[^/:@[:space:]]+:[^/@[:space:]<{$][^/@[:space:]]{5,}@` |

The `jwt` pattern ends at the second dot. It requires no signature, so a
header and payload followed by a dot and an empty signature match too.
Redaction's tail takes the signature when one follows.

## Observable behaviour

- `secret-scan.sh staged|worktree|range` prints `<file>:<line>: <name>` for a
  line that matches, and never prints the value. The exit codes do not
  change: 0 clean, 1 a match, 2 could not run.
- `secret_line_rule` and `secret_rule`, when sourced, return 0 with
  `SECRET_RULE` set to the name. The shipper's commit-message check and
  `tracker.sh create-issue` behave accordingly.
- `trail.sh redact` replaces each match plus the tail `[A-Za-z0-9_/+=.-]*`
  with `<redacted>` and counts it.

## Must not match (spec US2)

These are written as placeholders or described in words:

- `Bearer <token>`
- `Bearer <redacted>`
- `Bearer $TOKEN`
- prose such as "a Bearer token"
- `eyJ..`
- a JWT-like value whose header or payload is under 10 characters
- `https://user@host`
- a password of 5 characters or fewer
- `user:<password>@host`
- `user:${PASS}@host`
- a password starting with `{`
- `git@host:owner/repo`
- a name ending in `-bearer`, then a space and a long path

## Header comment (FR-010)

Add text like this to the `Rules:` paragraph, worded so that the comment
does not match:

> bearer-token: the word Bearer or bearer, at the start of the line or after a character that is not a letter, digit, `_` or `-`, then whitespace, then 16 or more
> token characters (letters, digits, `._~+/-`); jwt: a part starting eyJ
> of 10 or more base64url characters, a dot, a second part of 10 or more, a
> dot; url-credentials: a scheme and `://`, a user, a colon, a password of
> 6 or more characters not starting with `<`, `$` or `{`, then `@`. These
> run after the vendor prefixes above, which win where both match.
