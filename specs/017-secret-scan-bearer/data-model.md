# Data model: secret-scan-bearer

## Secret rule (an entry of `SECRET_VENDOR`)

| Field | Type | Rule |
|-------|------|------|
| name | kebab-case word | what the scan prints, `<file>:<line>: <name>`; never the value |
| pattern | POSIX ERE (Bash 3.2), single-quoted | matched case-sensitively; holds a bracketed letter so it does not match its own source; must not start with a non-word character unless the redaction lead check covers it |

- The entries are an ordered list, and the first match wins. The new
  entries follow `openai-key`, in this order: `bearer-token`, `jwt`,
  `url-credentials`.
- `key-literal` is checked only when no entry matches, so a vendor rule wins
  over it.
- Redaction (`trail.sh redact_vendors`) replaces `(pattern)` followed by
  `[A-Za-z0-9_/+=.-]*` with `<redacted>`. It skips `private-key`, which is
  handled by line.

## Credential shapes added

| Shape | Rule name | Redacted as |
|-------|-----------|-------------|
| bearer authorization header token | `bearer-token` | the `Bearer` word, the token and its tail |
| bare JWT (header, payload, signature) | `jwt` | the whole token |
| URL with a password in its authority | `url-credentials` | the scheme, credentials, host and path up to the first character outside the tail set |

There are no state transitions.
