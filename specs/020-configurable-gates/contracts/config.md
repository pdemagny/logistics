# Contract: `.logistics.yml`, `tracker.sh`, `preflight.sh`, `state.sh`

## `.logistics.yml`

```yaml
tracker:                      # optional: board tracking is on only with it
  provider: github
  project: https://github.com/users/<login>/projects/<number>
  statuses:
    brief: Brief
    building: In progress
    review: In review
gates:                        # optional: each gate of /feat and /fix
  feat:
    3: hard                          # always stop after the plan
    6: { large: soft }               # no stop between stories on large
    4: { small: hard, large: soft }
  fix:
    1: "soft"
```

- Top-level keys `tracker` and `gates`, each at most once, in any order;
  either may be absent; a file with neither (empty, or comments only) is
  valid: tracking off, all gates `auto`.
- `tracker` keeps today's shape and checks; its completeness checks
  (`missing tracker.<key>`, `bad project number`) run only when `tracker`
  is present.
- `gates` takes no value; its children at two spaces are `feat` or `fix`
  (no value); their children at four spaces are a phase number with:
  - a plain value `soft`, `hard` or `auto`, bare or quoted: every size; or
  - a one-line flow mapping `{ <size>: <value>[, <size>: <value>]… }`,
    `<size>` `small`, `medium` or `large`, each value bare or quoted,
    spaces around `{`, `}`, `,` and after `:` optional, at least one pair;
    a size not named is `auto`.

  A trailing ` # comment` is allowed after either. Settable: `feat` 2–7,
  `fix` 1–4. An empty `gates:` or skill section is valid (no settings).
- Comment and blank lines skipped, CR stripped, a tab in a key line
  refused (as today). A nested block mapping of sizes is not accepted.

### Errors

`tracker: error: .logistics.yml line <n>: <why>`, exit 1, before any `gh`
call:

| Case | `<why>` |
| ---- | ------- |
| indent not 0, 2 or 4 (a block mapping's size lines included) | `bad indentation (0, 2 or 4 spaces)` |
| a `gates` child not `feat`/`fix` | `unknown skill <k> (feat or fix)` |
| a phase outside the settable ones (`feat.1`, `feat.8`, `fix.5`, `fix.0`, `03`, …) | `<skill>.<n> is not settable (feat 2-7, fix 1-4)` |
| a plain value other than `soft`, `hard`, `auto`; an empty value (a block mapping's first line); a `{` with no `}` on the line | `gates.<skill>.<n> must be soft, hard, auto or { <size>: <value>, ... } on one line` |
| `{}` or `{ }` | `empty size mapping in gates.<skill>.<n>` |
| a pair that is not `<key>: <value>`, a pair key that does not match `^[a-z]+$` (empty, spaces, digits, any other character: `{ ignore this: soft }`), or junk after `}` other than a comment | `bad size mapping in gates.<skill>.<n>` (nothing from the mapping echoed) |
| a pair key matching `^[a-z]+$` other than `small`, `medium`, `large` | `unknown size <k> in gates.<skill>.<n> (small, medium or large)` |
| a size value other than `soft`, `hard`, `auto` | `gates.<skill>.<n>.<size> must be soft, hard or auto` |
| the same size twice in one mapping | `duplicate gates.<skill>.<n>.<size>` |
| the same phase twice (a plain value and a mapping included), the same skill or `gates` twice | `duplicate gates.<skill>.<n>` (`duplicate gates.feat`, `duplicate gates`) |
| a skill key with no `gates` above it | `<k> outside gates` |
| a phase key with no skill above it (under `tracker`, or right under `gates`) | `<n> outside gates.feat or gates.fix` |
| a tracker key under `gates` | `<key> outside tracker` / `<key> outside statuses` (today's wording) |
| `gates:` or a skill key with a value | `<path> takes no value` |
| any other key at 0, 2 or 4 | `unknown key` |

The messages use ASCII only (`2-7`, not an en dash). No value from the
file is echoed but the key names the grammar already allows: a line key
only once it matched `RE_KEY`, a size key only once it matched
`^[a-z]+$` (the pair key is checked against it before it is named), so no
repo text other than a short lowercase word reaches preflight's `stop:`
line.

## `tracker.sh`

```text
tracker.sh check | read-issue <ref> | create-issue <file> <owner/repo> | set-status <brief|building|review> <ref>
tracker.sh gates <feat|fix>        # the config text on stdin
```

- `gates <skill>`: parses stdin with `parse_config`; prints `tracker:
  gates <tokens>` (that skill's non-`auto` cells, canonical: phases
  ascending, a plain token `<skill>.<n>=<v>` or size tokens
  `<skill>.<n>.<size>=<v>` in `small`, `medium`, `large` order) or
  `tracker: gates none`; exit 0. A malformed text (anywhere, the other
  skill's section included): the error line above, exit 1. Reads no repo,
  calls no `gh`, never needs `tracker`. Wrong arguments: usage, exit 2.
- Every other subcommand: no file → `tracker: off (no .logistics.yml)`
  (today); a file without a `tracker` key → `tracker: off (no tracker: in
  .logistics.yml)`, exit 0, no `gh` call; else as today (a `gates`
  section beside it is parsed and ignored).
- Bash 3.2: no `declare -A`, no `${x,,}`, every possibly empty array
  expansion guarded; `tests/tracker/run.sh` greps for the constructs
  `tests/step/run.sh` greps for.

Tests (`tests/tracker`): a valid `gates` (comments, quoted values, both
forms, both skills) → each skill's line; `gates` before and after
`tracker`, both read; a mapping of all three sizes → three tokens; `auto`
cells left out, a section of `auto` only → `none`; each error row with its
line number (one case per row), plus a pair key with spaces (`6: { ignore
this: soft }`) → `bad size mapping in gates.feat.6`, the words not in the
message; an empty `gates:`; `gates` on a text with
`tracker` only → `none`; `gates` with no or a bad skill argument → usage;
a gates-only file: `check`, `read-issue`, `create-issue`, `set-status` →
`off (no tracker: in .logistics.yml)`, no `gh` call; tracker plus gates:
`check` as today; the Bash 3.2 construct grep.

## `preflight.sh`

Mode 1, kinds `brief`, `issue`, `symptom`: a step `step_gates` after
`step_base` (it needs `<default>`):

1. `git -C <top> cat-file -e refs/remotes/origin/<default>:.logistics.yml`
   fails → `gates: none`.
2. Else `git show` that blob into `bash <tracker.sh> gates <skill>`
   (stdin). Exit ≠ 0 → `stop: origin/<default>:<its line without
   "tracker: error: ">` (exit 1). Else `gates: <the tokens after "tracker:
   gates ">`.

Output key order: `…, board, gates, default, fetch, …` (the `gates` slot
right after `board`; the slots after it shift by one). Kinds resume and
rebase print no `gates:` line.

`step_board`: runs `check` whenever `<top>/.logistics.yml` exists; a first
line starting `tracker: off` → `board: off`.

Worktree mode, `on`: the flag when the worktree's `.logistics.yml` is
missing (today's line) or has no `tracker:` key (`has_tracker_key`): `- [!]
tracker: .logistics.yml in the worktree has no tracker: key; commit and
push it (board moves skipped)`.

Tests (`tests/preflight`; the stub tracker answers `gates` from a case file
and records its stdin and arguments): origin with a gates section →
`gates:` with the stub's tokens, the stdin is origin's blob (not the
checkout's file, which says otherwise) and the argument the skill; no file
on origin → `gates: none`; the stub's error → the stop line; resume and
rebase print no `gates:`; `board: off` for a `tracker: off …` check line;
the worktree flag for a gates-only worktree file. The fixtures that wrote
`project: x` as "the file exists" stay valid (the stub decides `check`'s
line); their comments say so, and the worktree-flag fixture writes a
`tracker:` line.

## `state.sh`

```text
state.sh init feat <state file> <brief file> [<Field>=<value>]...   Field adds Gates
state.sh init fix <state file> <title> <report> [<Field>=<value>]...
state.sh phase2-mode <state file> [<3|4>]
```

- `Gates=<value>`: `none` (default when not given) or the canonical tokens
  of the init's skill ([data-model.md](../data-model.md#gates-field));
  else `state: error: Gates must be none or canonical <skill> gate tokens,
  not: <value>`. Written `- Gates: <value>` after `- Issue:`.
- `set` does not take `Gates` (its usage lists the fields it takes, as
  today): the gates are fixed for the run.
- Trust: the field, like `Size:`, is written only through `state.sh` and
  read as is; `step.sh` refuses a non-canonical value, and nothing guards
  it against an edit of the state file (a guard for both fields is a
  follow-up issue).
- `phase2-mode <state file> <g>`: `<g>` (3 or 4) is the gate that carries
  a soft phase 2's summary; anything else is usage. Without it: today's
  Size rule, kept only for callers and tests that pass no gate (it equals
  `step.sh`'s rule on a state file with no `feat.3` cell). `step.sh` always
  passes it. The `tests/step` oracles that call it with no gate
  (`log-readers-agree` over `fixtures/logs/*.md`, and `queries` in
  `full_end`) keep fixtures with no `Gates:` cell; a case whose state file
  carries one passes the gate from
  [data-model.md](../data-model.md#the-gate-after-a-soft-phase-2-phase2-mode)
  to the oracle.

Tests (`tests/state`): init with and without `Gates=` (plain and size
tokens), a bad token, the other skill's token, a duplicate, an
out-of-order value, plain and sized for one phase; `set … Gates …`
refused; `phase2-mode` with `3` on a small state (`soft 3 open`, then
`closed` after an answered gate 3), with `4` on a large state (`soft 4
open`), with a bad gate (usage), and without it (today's answers, the
existing cases).
