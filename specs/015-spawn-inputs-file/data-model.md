# Data model: spawn inputs file

## Spawn block

What step.sh prints for one spawn: `spawn: <agent>`, then two-space
indented single-line keys (`row`, `mode`, `lenses`, `model`, `effort`,
`report`, `continue`, `who`, `story`, `diff`, `cuts`, `cycle`, `test
report`, `still failing`, `security bug`, `ship script`, `from`,
`unparsable`, …), unchanged (FR-011). New: one `inputs: <absolute path>`
key when at least one of the block's lists is non-empty, and no list key
or item line in any case (FR-001).

## Inputs file

- **Path**: the block's `report:` path with its final `.md` replaced by
  `.in.md` (`reports/7-fixes-2.md` → `reports/7-fixes-2.in.md`), so always
  inside the state file dir's `reports/` (FR-004). `report-path` only
  hands out `<key>.md` and `<key>-<n>.md` with keys free of `.`, so no
  report name ends in `.in.md`.
- **Writer**: `state.sh inputs`, called by step.sh only (FR-012).
- **Reader**: the spawned agent only; the coordinator relays the path
  (FR-010).
- **Content**: [contracts/inputs-file.md](contracts/inputs-file.md).
- **Lifecycle**: written (whole, atomically) each time step.sh prints the
  block, so a re-print or a retry replaces it (FR-006); a new spawn,
  fresh or continued, has a new report path and so a new file (FR-005);
  never committed (`reports/` ignores itself); carried along when the
  shipper renumbers the artifact dir.
- **Validation** (state.sh): the report path must be `<reports dir>/<key>[-<n>].md`;
  `reports/`, its `.gitignore` and the target must not be symlinks, the
  target must be a regular file when it exists (FR-007).

## List

A named group of items an agent acts on. Empty: one `<key>: none` line;
otherwise `<key>:` then one `  - <item>` line per item. `story.sh output`
is the one fenced list. Lines pass through step.sh's `clean` (control
characters become spaces), as they did when printed; nothing else changes
them (FR-008).

## Lists per spawn

The lists of each call site, in file order (today's print order). "Can be
all empty" means the block may get no `inputs:` line.

| Spawn | step.sh function | Lists, in order | Can be all empty |
| ----- | ---------------- | --------------- | ---------------- |
| `/feat` 6 story implementer | `next_story` | `story.sh output`; `failures` (retry only) | no |
| `/feat` 4 design-review group | `review_batch` | `rejected` | yes |
| `/feat` 7, `/fix` 4 code-review group | `review_batch` | `rejected`; `accepted sec` (groups with lens 7b; always `none` in `/fix`) | yes |
| `/feat` 7e | `spawn_7e` | `rejected` | yes |
| `/feat` 7 review fixes, `/fix` 4 fixes | `spawn_fixes` | `apply`; `failures` (retry only) | yes (`apply` is non-empty on every path but two answer paths) |
| `/feat` 3 planner amend after gate 4 | `amend_spawn` | `apply` | yes (`changed` with no findings) |
| `/fix` 1 assessor | `next_step` | `approved commands`; `answers` | yes |
| `/fix` 2 implementer | `next_fix` | `approved commands`; `answers` | yes |
| `/fix` 3 assessor, test mode | `next_step` | `not verified items`; `approved commands` | yes |
| `/feat` 8, `/fix` 5 shipper | `enter_ship` | `not verified items` | yes |

Spawns with no list (specifier, planner first and `changed` amend at gate
3, tasker, rebase, move, repair, reformat) are unchanged.

## step.sh's buffer (implementation state)

- `IN_L`: the current block's file lines, in order.
- `IN_ANY`: 1 once any list of the block has an item (the story output
  always counts).
- Emptied by `spawn_row` and `spawn_group` at a block's start and by
  `sinputs` after its write.
