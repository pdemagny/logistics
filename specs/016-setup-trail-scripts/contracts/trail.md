# Contract: `trail.sh`

Path: `.apm/skills/feat/scripts/trail.sh`. Bash 3.2, no jq, no Python,
`set -euo pipefail`, `LC_ALL=C`. Sources `secret-scan.sh` from its own
directory (as `tracker.sh` does; missing → exit 2). Everything on stdout,
nothing on stderr. Called by `feat-bug-assessor` and `feat-implementer`
(bug mode) as one plain `bash '<trail script>' …` each; the path comes from
the spawn block's `trail script:` key.

```text
trail.sh rotate <bug dir> <assessment|test|fix>
trail.sh sections <file> <assessment|test>
trail.sh slug <bug dir> <slug> <file> [<printed slug>]
trail.sh redact <file>
```

Exit 0 done (a mismatch or a section error is output, not an exit code);
2 with one `trail: usage: …` or `trail: error: <why>` line (bad arguments,
a missing bug dir or file where one is required, a symlink, a write that
failed). Callers don't run `sections`, `slug` or `redact` on a report that
was not written: the assessor's `Assessment: none (…)` path skips all three
and reports `Sections: ok` with no slug mismatch. A stage that printed no
slug is checked with `slug` without its fourth argument.

## rotate

`<bug dir>/<report>.md` absent → prints `none`. Present → renamed to
`<report>-<n>.md`, `n` = 1 + the highest `n` of an existing
`<report>-<n>.md` (1 when none); prints the new absolute path (the agent's
`Wrote:` lists it). A symlink at either name is refused.

## sections

| Report | Required parts |
|---|---|
| `assessment` | a line starting `# Bug Assessment:`, `**Verdict**`, `**Severity**`, `## Symptom`, `## Reproduction`, `## Suspected Code Paths`, `## Root Cause Hypothesis`, `## Proposed Remediation`, `## Open Questions` |
| `test` | `**Result**`, `## Checks Performed` |

`## ` headings match the whole line (trailing spaces ignored); `**…**`
parts match anywhere in a line. Prints `Sections: ok` or `Sections: error:
<file name> lacks <part>, <part>, …` (parts in the table's order).

## slug

`<printed slug>` and the file's first `- **Slug**:` bullet value each lose
backticks and a trailing ` (<note>)`, then surrounding spaces. Prints `ok`
when the bullet equals `<slug>`, the printed slug (when given) equals
`<slug>`, and the file resolves (`pwd -P`) under the resolved bug dir; else
`mismatch (<printed slug, else the bullet value, else none>)`. A missing
file is a mismatch.

## redact

Rewrites `<file>` in place, then prints the number of replacements (`0`
when none). Rules, in order (research R5):

1. private-key block → one `<redacted>` line. It starts at a line matching
   the `private-key` rule and ends at whichever comes first: the first line
   holding `-----END` (part of the block), the first line that is neither
   key body nor a header, i.e. not matching
   `^[[:space:]]*([A-Za-z0-9+/=]+|Proc-Type:.*|DEK-Info:.*)[[:space:]]*$`
   (a blank line, a code fence, a heading, a bullet, prose: not part of the
   block, kept and read by the rules below), or the end of the file. A
   report that mentions the begin marker in prose loses only that line,
   even with a heading or a bullet right after it;
2. a key (`SECRET_KEY`, any case) followed by a value → the value is
   `<redacted>`, the key and separator kept. An unquoted value after a key
   that is the line's first token (after the indent, an optional `- `,
   `export ` or an opening quote) runs to the end of the line, minus a
   trailing ` #` comment; after a key inside a line it stops at whitespace
   or one of `` ,;&)}]"'<>` ``:

   | Line | After |
   |---|---|
   | `password=hunter2` | `password=<redacted>` |
   | `password: correct horse battery staple` | `password: <redacted>` |
   | `  - password: two words  # rotated` | `  - password: <redacted>  # rotated` |
   | `export API_KEY=abc def` | `export API_KEY=<redacted>` |
   | `api_key: "abc1"` | `api_key: <redacted>` |
   | `token = getToken()` | `token = <redacted>` |
   | `url?token=abc&x=1` | `url?token=<redacted>&x=1` |
   | `token:` (end of line) | unchanged |
   | `token: str` | unchanged |
   | `password: ""` | unchanged |

   A multi-line value after a key that is the line's first token: when the
   value is a YAML block scalar indicator (`|` or `>`, with an optional
   chomping and indent indicator, and an optional ` #` comment), the
   indicator stays and the lines after it indented deeper than the key
   line (blank lines between them included) become one `<redacted>` line at
   the first one's indent; blank lines after the block are kept. When the
   value opens a quote it does not close, the value on the key line is
   `<redacted>` as above and the lines after it, up to and including the
   one holding the closing quote, become one `<redacted>` line, the rest of
   the closing line kept after it; with no closing quote, they end before
   the first blank line or code fence (kept) or at the end of the file. A
   block that is already one `<redacted>` line is left as it is;

3. a vendor prefix (`SECRET_VENDOR`, other than `private-key`) and its
   token characters `[A-Za-z0-9_/+=.-]*` → `<redacted>`; a leading non-word
   character of the match is kept;
4. a line the scan's `secret_line_rule` still matches → `<redacted>`.

The file is written only when the count is not 0 (temp file in the same
directory, then `mv -f`), so a file with nothing secret stays
byte-identical; the final newline (or its absence) and `\r` line ends are
kept. A second run prints `0`. After `redact`, `secret-scan.sh worktree
<file>` finds nothing (FR-012).
