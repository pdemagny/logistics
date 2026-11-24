# Data model: configurable gates

| Entity | Where it lives | Written by | Read by |
| ------ | -------------- | ---------- | ------- |
| Gate setting | `.logistics.yml`, `gates.<skill>.<n>: <value>` or `gates.<skill>.<n>: { <size>: <value>, … }` | the user (committed, pushed to `origin/<default>`) | `tracker.sh gates <skill>` (stdin), at setup only |
| Setup line | `gates: <tokens> \| none` (preflight mode 1 output) | `preflight.sh` | the coordinator: shown when not `none`, passed as `Gates=` |
| Gates field | state file header, `- Gates: <tokens> \| none` | `state.sh init` (never `set`) | `step.sh` (every call) |
| Gate reason `gates: hard` | a hard gate line's reasons (`US<n>: gates: hard` at `/feat` 6; `gates: hard; verdict: <v>` at `/fix` 3) | `step.sh` | the coordinator (gate message), Log readers |
| Soft mark `gates: soft` | last segment of a soft gate line | `step.sh` | the user reading the Log; readers skip it |
| Board tracking switch | a `tracker:` key in `.logistics.yml` | the user | `tracker.sh` (all), `preflight.sh` (board check, worktree flag), `step.sh` (`/fix` 1); the coordinators through setup's `board:` line |

## Gate setting (the file)

One line per phase, under `gates:` → `feat:` / `fix:`:

```yaml
gates:
  feat:
    3: hard                          # every size
    6: { large: soft }               # large only; small and medium stay auto
    4: { small: hard, large: soft }  # two sizes, medium auto
  fix:
    1: "soft"
```

- A cell is (skill, phase, size). A plain value sets the three cells of
  its phase; a mapping sets the sizes it names; an unnamed size is `auto`.
- Settable: `feat` 2–7, `fix` 1–4. Values `soft`, `hard`, `auto`.
- Grammar and errors: [contracts/config.md](contracts/config.md).

## Gates field

```text
Gates: none
Gates: feat.3=hard feat.6.large=soft
Gates: feat.4.small=hard feat.4.large=soft
Gates: fix.1=soft fix.4.large=hard
```

- Token `<skill>.<n>=<v>` (a plain value) or `<skill>.<n>.<size>=<v>` (one
  size); `<skill>` the run's skill, `<n>` settable, `<v>` `soft` or `hard`.
  `auto` cells are left out; nothing left is `none`.
- Canonical: phases ascending; within a phase one plain token, or size
  tokens in `small`, `medium`, `large` order, each once; one space between.
  A mapping naming all three sizes with one value stays three tokens.
- Written once by `state.sh init` (value from setup's `gates:` line);
  `state.sh set` refuses it. Editing `.logistics.yml` later changes no
  running run (SC-006).
- Missing (a run started before this feature) or `none`: every gate
  `auto`. Not canonical: `state.sh init` and `step.sh` refuse it
  (`state: error: …`, `step: error: Gates: <value> is not a canonical
  <skill> gates value`).
- Trust: like `Size:`, the field is written only through `state.sh` and
  read as is; nothing guards it against an agent editing the state file
  (plan.md, Decisions for the user, 1).

## Applying a cell (`step.sh`)

State per call: `F_GATES` (the field), `GC` (the cell's value),
`SOFTENED` (0; set by `size_gate`), `TR_GATES` (0; `dec_fix_3` sets 1).

```text
gate_cfg <n> <size>          → GC = token <skill>.<n>.<size>, else <skill>.<n>, else auto
in_force <n> <holds>         → holds && GC != soft
size_gate <n> <holds> <r>    → holds && GC != soft:  reason <r>
                               holds && GC == soft:  SOFTENED=1
                               GC == hard:           reason "gates: hard" ("US<n>: gates: hard" at /feat 6)
gate3_stops                  → in_force 3 (SC == large) || GC(3) == hard
G3STOP                       → the latest tagged `3 Plan` line holds the reason `large` or `gates: hard`
```

`<size>`: `SC` (from `Size`); at `/fix` 1 the assessment's `Proposed
size`. `holds`: `SC` large (`/feat` 3–7, `/fix` 4), `Proposed size` not
small (`/fix` 1); `0` at `/feat` 2, `/fix` 2, `/fix` 3, which have no size
reason. Soft line suffix: `; gates: soft` when `SOFTENED` and the verdict
is soft.

## Log lines

New or changed forms (all others as
[013's data-model](../013-step-command/data-model.md#lines-stepsh-writes)):

| Line | When |
| ---- | ---- |
| `- [x] 3 Plan [hard] — gates: hard[; <reasons>]; <facts>` | `feat.3` hard for the run's size, small or medium |
| `- [x] 3 Plan [hard] — large; gates: hard[; <reasons>]; <facts>` | `feat.3` hard for large, large run |
| `- [x] 3 Plan — merged with 4; <facts>; gates: soft` | `feat.3` soft for large, large run |
| `- [x] <N> <phase> [soft] — <text>; gates: soft` | a soft gate whose size reason `soft` removed (`5 Tasks`, `4 Design review`, `7 Code review`, `4 Code review`, `1 Assess`) |
| `- [x] 6 Implement [soft] — tasks done: <n> (<k> not verified); checks pass; gates: soft` | `feat.6` soft for large, large run, last story |
| `- [x] 6 Implement [hard] — US<n>: gates: hard` | `feat.6` hard for the run's size, a story that passed |
| `- [x] 3 Test [hard] — gates: hard; verdict: <verified \| failed>` | `fix.3` hard for the run's size, a row that would be soft |
| `- [x] <N> <phase> [hard] — …; gates: hard…` | `hard` at any other settable gate for the run's size |

Readers: `plan_facts`, `assess_facts`, `log_apply`, `design_ids` and
`review-summary` read `; `-separated segments by prefix and skip `gates:
soft`; `shipped-verdict` reads a `3 Test` line's first word (`gates` is
not a verdict); `next_fix` and `cycle` match `failed (retry 1 of 1)` only;
`apply_answer feat:6` tests the `tasks done: ` prefix.

## The gate after a soft phase 2 (`phase2-mode`)

`step.sh` passes `gate3_stops`' gate to `state.sh phase2-mode <state file>
<3|4>`:

| Size | `feat.3` cell for that size | Gate carrying the summary |
| ---- | --------------------------- | ------------------------- |
| small, medium | `auto`, `soft` | 4 |
| small, medium | `hard` | 3 |
| large | `auto`, `hard` | 3 |
| large | `soft` | 4 |

## Board tracking switch

On when `.logistics.yml` (at the top level the script works in) has a
`tracker` key. `tracker.sh` decides it after a full parse; `step.sh` and
`preflight.sh`'s worktree mode use the line test `^tracker:( |#|$)` (CR
stripped), since setup already refused a malformed file; the coordinators
read setup's `board:` line, and on resume `check`'s exit and line (a line
starting `tracker: off`: no board moves).
