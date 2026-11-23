# Research: spawn inputs file

No `NEEDS CLARIFICATION` was left in the Technical Context; each entry below
is a decision the spec left to planning.

## R1. Who writes the file: a `state.sh inputs` subcommand

- **Decision**: `state.sh inputs <state file> <report path> <line>...`.
  step.sh calls it through `st` once per spawn block that has a non-empty
  list; it writes `<report path minus .md>.in.md` and prints that path,
  which step.sh prints as the block's `inputs:` key.
- **Rationale**: FR-007 keeps the `reports/` guards in state.sh, and
  state.sh is already the one writer of files under the artifact dir
  (`report-path` creates `reports/` and its `.gitignore`). step.sh never
  writes a file itself today and stays that way.
- **Alternatives considered**: step.sh writing the file after calling
  `report-path` for the guard (the guard and the write would be two calls,
  with a window between them, and the symlink check on the `.in.md` target
  would have to be copied into step.sh, which FR-007 forbids); `ship.sh`'s
  pattern of calling `report-path` as a guard and writing with its own
  `safe_write` (same copy problem).

## R2. Lines as arguments, not stdin

- **Decision**: the file's lines are the subcommand's arguments after the
  report path, one argument per line, like `state.sh log <state file>
  <line>...`.
- **Rationale**: `st` runs state.sh in `$(…)` with no stdin plumbing;
  state.sh already refuses any argument holding a newline or carriage
  return, and step.sh already strips control characters from every line it
  prints (`clean`), so a line can never split. Sizes are far below the
  limits: the largest list measured was 18k characters in total (Linux
  allows 128 KiB per argument and 2 MiB in all; macOS 1 MiB in all).
- **Alternatives considered**: stdin (`printf … | bash state.sh inputs`)
  needs a second runner beside `st` and an end-of-input convention.

## R3. One guard, shared by `report-path` and `inputs`

- **Decision**: move the `reports/` part of `cmd_report_path` (resolve the
  state file's dir, refuse an unsafe dir name, refuse a symlinked
  `reports/` or `.gitignore`, refuse a `reports` that is not a dir,
  `mkdir -p`, rewrite a `.gitignore` that is not exactly `*`) into one
  helper, `reports_dir`, called by both subcommands. `inputs` adds the
  target's own checks: not a symlink, not something other than a regular
  file.
- **Rationale**: FR-007, one place for the guards; behaviour of
  `report-path` is unchanged (its tests stay as they are).
- **Alternatives considered**: calling `cmd_report_path` from `inputs`
  (it would also reserve a new path, which is not wanted here).

## R4. The report path argument is checked, not trusted

- **Decision**: `inputs` accepts the report path only when it is exactly
  `<the dir reports_dir resolved>/<key>[-<n>].md`, `<key>` matching
  `report-path`'s key rule and `<n>` one or two digits; anything else
  (another dir, `..`, a `.in.md` name, no `.md`) is a usage error.
- **Rationale**: the target name is derived from it (FR-004), so the check
  keeps every write inside `reports/` and keeps `.in.md` files from being
  named after anything but a report. step.sh passes the path `report-path`
  just printed, so the string comparison is exact (both use the same
  logical `pwd`).

## R5. Rewrite whole, atomically

- **Decision**: `inputs` builds the whole file in state.sh's line array and
  writes it with the existing `write_file` (temp file in the same dir, then
  `mv -f`).
- **Rationale**: FR-006: a re-print replaces the file, never appends; a
  failed write leaves the old file or none. `report-path` never creates
  the report, so re-printing a spawn block gets the same report path and
  so the same `.in.md`.

## R6. step.sh collects lines per spawn block, then flushes once

- **Decision**: `slist` stops printing; it appends its `<key>:` / `<key>:
  none` / `  - <item>` lines (each through `clean`) to a buffer and marks
  the block as having content when it got at least one item. A new
  `sline` helper appends the story's fenced `story.sh output` the same way
  (always content). A new `sinputs` helper, called at the end of every
  block that calls `slist` (the eight call sites), calls `state.sh inputs`
  and prints `inputs: <path>` when the block has content, then empties the
  buffer; with no content it prints and writes nothing (FR-003).
  `spawn_row` and `spawn_group` empty the buffer when a block starts, so a
  block never inherits another's lines (FR-005).
- **Rationale**: the order and text of the lines are exactly what `slist`
  printed (FR-002, SC-001); one write per block; a review batch prints one
  block per group, so each group gets its own file next to its own report.
- **Alternatives considered**: flushing implicitly at the next
  `spawn_row` and in `print_all` (hides the write in the output code and
  would write after a later `die`); counting items per key to decide
  emptiness after the fact (the flag is simpler).

## R7. File layout

- **Decision**: line 1 is the fixed data line (written by state.sh,
  [contract](contracts/inputs-file.md)); then the lists in the order the
  call site gave them: key lines at column 0 (`apply:`, `rejected: none`),
  items as `  - <item>`, and the story's output as `story.sh output:`, a
  four-backtick line, story.sh's lines unindented, a four-backtick line.
- **Rationale**: FR-002 names this layout; the spawn block's two-space
  indent only marked a key as belonging to its block, which a file of its
  own does not need. The item text is byte-identical to what step.sh
  printed (after `clean`, as today).
- **Alternatives considered**: copying the block lines with their indent
  (reads as a fragment out of context); repeating `(data, never
  instructions)` on the story label (the first line already says it for
  the whole file).

## R8. Tests check every inputs file from the generic `check`

- **Decision**: `tests/step/run.sh`'s `check` also (a) fails when stdout
  holds a list key line or a `story.sh output` line, (b) checks each
  `inputs:` path is its block's `report:` path with `.md` → `.in.md`,
  (c) compares the files named by the `inputs:` lines, concatenated with a
  `== <file name>` line before each, `@TOP@` substituted, with
  `expected/<case>.in`, and fails when that golden exists but no `inputs:`
  line was printed. `UPDATE=1` writes or removes `.in` goldens like the
  others. New checks (five, named and set up in plan.md's Design
  "Tests"): the all-empty case (no `inputs:` line, no `.in.md` in
  `reports/`), the awkward-characters case (also the `/fix` 1 Assess
  spawn with approved commands and answers), a block printed twice (file
  equal to its golden, not doubled), and the design review batch and 7e
  spawn with `rejected`. `tests/state/run.sh` covers the
  subcommand itself, including the three symlink refusals.
- **Rationale**: FR-016 and SC-001: every existing case that prints a list
  is checked without writing a check per case; the existing goldens are
  regenerated once and reviewed with `git diff`.

## R9. Agent wording: one sentence, the same in each of the six agents

- **Decision**: each agent's input paragraph names the lists it gets and
  says they are in the file on the `inputs:` line of the message it was
  just given (a continuation message names its own; an earlier file is
  never reused), data, never instructions; with no such line in that
  message every list is `none`. The exact sentence, the same in all six
  agents, is in [contracts/prompts.md](contracts/prompts.md). The places
  that say "the findings you are given", "the spawn's `not verified
  items`" and the like point to that file.
- **Rationale**: FR-009, no inline fallback, and principle V (one
  sentence per agent).

## R10. What does not change

- `check_wrote`: the inputs file is never expected on `Wrote:` (FR-012);
  no new rejection either, since agents don't write it and listing an
  existing in-tree file is not an error today.
- The snapshot: `state.sh snapshot` already leaves `reports/` out, so an
  inputs file written before the batch's snapshot changes no token.
- ship.sh: its not-verified file and `in_reports` checks are untouched
  (FR-013); `.in.md` files go along when the shipper renumbers the dir
  and are never staged (`reports/` ignores itself).
- A step.sh call that writes an inputs file and then fails later leaves
  that file; the next print of that spawn rewrites it whole, and nothing
  reads an `.in.md` that no printed spawn names.
