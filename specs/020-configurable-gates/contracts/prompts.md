# Contract: skills, harness and docs

What each prose file says after this feature. The coordinators gain one
value to carry (`gates:` → `Gates=`) and one line to show; they never read
`.logistics.yml` (FR-017).

## `.apm/skills/feat/references/harness.md`

No `/feat`-only word (`mise run lint` greps `specifier|planner|tasker|
spec.md|brief|phase [0-9]|/feat`).

- **Gates in force** (a short paragraph under `## Gates`): setup's
  `gates:` line other than `none` is shown in one line as `Gates in force
  (from origin/<default>:.logistics.yml): <value>`, `<default>` being
  setup's `default:` value; that value goes to `S init` as
  `'Gates=<value>'` (`none` when the line said so). The gates are fixed
  for the run: an edit of the file takes effect on the next run, once
  pushed. A `gates: hard` reason (`<story>: gates: hard`, `gates: hard;
  verdict: <v>`) means the repository sets this gate to stop: wherever the
  skill renders a gate differently for `large` (the title, the findings
  listed, a story's list), it reads "`large` or `gates: hard`" (the lines
  are named below, per skill). A `gates: soft` segment on a soft line
  means the repository softened a size gate.
- **State file**: the header template gains `- Gates: <the setup's
  gates: value>`; `S set`'s field list unchanged (it does not take
  `Gates`).
- **Board moves**: "only when setup's `board:` line is not `off` (on
  resume: when `check` exits 0 and its line does not start with `tracker:
  off`)" in place of "only when `<repo root>/.logistics.yml` exists".
  Resume prints no `board:` line, so the clause names the raw `check`
  line the coordinator holds then (`tracker: off (no .logistics.yml)` or
  `tracker: off (no tracker: in .logistics.yml)`: no move, no `[!]` line).

## `.apm/skills/feat/SKILL.md`

- Setup step 1, `kind: brief`: keep `gates:` and `default:` too (harness,
  Gates in force).
- Setup step 4: a `gates:` line other than `none`: show it (harness, Gates
  in force). Its resume sentence: "On resume, run `check` here: exit ≠ 0 →
  stop and show its line; a line starting `tracker: off` → no board moves
  this run (harness, Board moves)".
- Phase 2 step 1: `S init` gains `'Gates=<gates:>'`.
- Phase 3: "No gate here unless `step.sh` stops (large by default, or the
  repository's gates)" in place of the small/medium vs large split; the
  hard gate's content is unchanged.
- Phase 4, hard gate (the `**Hard**` paragraph of the design review): the 3–4 combined title "when phase 3 had no gate", the `Phase 4:
  Design review` title and the `note: plan amended after gate 3` line
  "after a gate 3", in place of "small and medium" / "large"; "every other
  finding with its `rec` (on large too, even when none is `user`)" reads
  "(when the reasons hold `large` or `gates: hard`, even when none is
  `user`)".
- Phase 6: "hard after each one on large by default, or as the repository's
  gates say" in place of "(hard after each one for large)"; "for large,
  the per-story gate shows that story's list" reads "at a story gate
  (`US<n>: large` or `US<n>: gates: hard`), it shows that story's list".
- Phase 7, hard gate: "every finding with its `rec` (on large too)" reads
  "(with `large` or `gates: hard` too)".
- Resume paragraph (`phase2-mode:`): unchanged wording; the gate number
  comes from `step.sh`.

## `.apm/skills/fix/SKILL.md`

- Setup step 2, `kind: issue` or `symptom`: keep `gates:` and `default:`
  too.
- Setup step 5: a `gates:` line other than `none`: show it (harness, Gates
  in force).
- Setup step 6: `S init` gains `'Gates=<gates:>'`.
- *Board-check step* (Harness values): "(on resume, run `check` yourself:
  exit ≠ 0 → stop and show its line; a line starting `tracker: off` → no
  board moves this run)".
- Resume, **Board** bullet: "run `check` after `T resume`; exit ≠ 0 →
  stop; a line starting `tracker: off` → no board moves. The building move
  only once it printed `assess gate: passed`."
- Phase 1 reasons list: the `proposed size` line unchanged; `gates: hard`
  is covered by the harness paragraph.
- Phase 4, hard reasons list: the bullet "`large`, `<ids> need you`,
  `S<n> security`: list every finding with its `rec`, `user` first" gains
  `gates: hard` (`large`, `gates: hard`, `<ids> need you`, …).

## `.apm/skills/brief/SKILL.md`, `.apm/skills/tiny/SKILL.md`

- `/brief`: "**Board tracking**, when `<root>/.logistics.yml` exists: run
  its `check` first; `tracker: off …` means the file has no `tracker:` key:
  no board move here."
- `/tiny` step 2 the same; step 6: "With board tracking and no `tracker:`
  key in the worktree's `.logistics.yml`: say …". Length stays under the
  lint's cap (200 lines).

## Docs

- `docs/workflow.md`:
  - `## Configuring the gates` (new, before `## Phase details`): where the
    section goes (`.logistics.yml` at the repo root, beside or without
    `tracker:`), the two accepted forms (plain value; one-line `{ <size>:
    <value>, … }`), the three values, that each gate can be set for every
    size or per size, the matrix of [gates.md](gates.md#the-matrix-docsworkflowmd)
    and its footnote, the setup line, the `Gates:` field fixed for the run
    (read from `origin/<default>` at setup, so a setting takes effect once
    pushed), `; gates: soft` on a softened line, and the link to the
    contract (`https://github.com/pdemagny/logistics/blob/main/specs/020-configurable-gates/contracts/gates.md`,
    rewritten by the shipper when it numbers the dir).
  - `### 0 Setup`: setup reads `origin/<default>`'s `gates:` with the
    hooks and shows the gates in force.
  - `### 2 Specify`: the worktree check reads the `tracker:` key ("checks
    the worktree's `.logistics.yml` has a `tracker:` key").
  - The sentences that tie a gate to a size. This list is the whole
    checklist (line numbers as of `39d9da3`); each reads "by default" or
    links [Configuring the gates](#configuring-the-gates):
    - `## Phases at a glance`: the Gate column of rows 3–7 where it
      states a size rule (row 3: "none by default (hard for large, opening
      with the spec summary after a soft phase 2)"); the paragraph under
      the table ("the gates are the ones the column says") adds "unless
      `.logistics.yml` sets them ([Configuring the
      gates](#configuring-the-gates))".
    - Line 97, the soft-phase-2 sentence: "the next gate (3/4, or 3 when
      gate 3 stops: on large by default)".
    - `### How the sizes differ beyond model and effort`, Hard gates row
      (line 180): a note "by default; see Configuring the gates".
    - Line 330, `### 3 Plan`: "Small and medium go straight to phase 4;
      large stops here" gains "by default".
    - Line 364, `### 4 Design review`: "Large: always hard" reads "Large:
      hard by default".
    - Line 412, `### 6 Implement`: "**Large:** a gate after each story"
      gains "by default".
    - Line 468, `### 7 Code review`: "Large always stops" reads "Large
      stops by default".
    - Line 775, `/fix`'s `### Gates`, the code-review bullet: "`Size:
      large` is hard" gains "by default"; the section links Configuring
      the gates (below).
  - `## Board tracking`: "off unless the repo's `.logistics.yml` has a
    `tracker:` section".
  - `## The state file`: the `Gates:` field (written once at setup, like
    `Size:` trusted as written: nothing guards it against an edit of the
    state file).
  - `/fix`'s `### Phases at a glance` (rows 1 and 4: "by default") and
    `### Gates` (a link to Configuring the gates).
- `docs/install.md`: `## 7. Configure the gates (optional)`: the example
  with both forms, "comments and quoted values are fine, anything else is
  refused with its line", commit and push it (read from `origin/<default>`
  at setup), the link to the matrix; section 5: "off unless it has a
  `tracker:` section"; "Repos you didn't write": a repo's file can soften
  its size gates (never a safety reason), and setup shows the gates in
  force with where they came from: check that line as you check the
  tracker line.
- `docs/usage.md`: line 72, "with a `tracker:` section in `.logistics.yml`
  at the repo root"; the `tracker: error: …` troubleshooting row also
  covers a `gates:` error at setup; line 301, the sizes table's large row:
  "gates at 3, 4, 5 and after each story by default".
- README: does not list the file; line 83, "A large feature also stops
  after the plan, …" gains "by default".
- `docs/diagrams/gates.d2`, `chain.d2`: unchanged (research R14).
