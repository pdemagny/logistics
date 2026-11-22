# logistics

Four skills (`.apm/skills/brief/SKILL.md` writes the brief,
`.apm/skills/feat/SKILL.md` coordinates the build, `.apm/skills/fix/SKILL.md`
coordinates a bugfix, `.apm/skills/tiny/SKILL.md` makes a trivial change in
one session) and the phase subagents
(`.apm/agents/*.agent.md`), distributed three ways from one source, for Claude Code only: an APM
package (`apm.yml`), a Claude Code plugin (`.claude-plugin/`), and
`install.sh` for development. See README.md and docs/install.md.

When changing it:
- `.apm/skills/feat/sizes.json` is the source of models, efforts, loads and
  both skills' reviewer groups (`/feat` phases 4 and 7, `/fix` phase 4).
  Edit it and run `mise run diagrams`: that regenerates
  `.apm/skills/feat/sizes.tsv` (what `step.sh` reads; never edit it in the
  repo), the matrices and agents table in `docs/workflow.md`, and row 1's
  sentence in `.apm/skills/brief/SKILL.md`. Neither `/feat` nor `/fix`
  holds a size table. Never edit between a `sizes-start`/`sizes-end`
  marker pair by hand; `mise run lint` fails on drift. The reviewer-group
  prose in `docs/workflow.md` stays hand-written and changes with the
  groups.
  Agent frontmatter carries no `model`, `effort`, `tools` or `color`
  (`/feat` and `/fix` pass the model and effort `step.sh` prints per
  spawn); use `disallowedTools`.
- The diagrams are D2 sources in `docs/diagrams/`, rendered to `docs/img/`
  by `mise run diagrams`; commit both. `models.svg` is drawn from
  `sizes.json` by `docs/diagrams/sizes.py --d2`, so a change to the data
  needs a re-render (`mise run diagrams` does both). A change to `/feat`'s phases or
  gates updates `gates.d2` and `chain.d2`. The `check` workflow fails when
  `docs/img` differs from a fresh render.
- The rules `/feat` and `/fix` share live once: the coordinators' part in
  `.apm/skills/feat/references/harness.md` and the references it points to
  (`rebase.md`, the `rebase` entry point, and `move.md`, read when main
  moved), written with named values that each skill's `## Harness values`
  block fills; the rules `step.sh` applies (gates, merge rules, the base
  check, model and effort) in `.apm/skills/feat/scripts/step.sh`. Keep
  `/feat`-only words out of `harness.md`, `rebase.md` and `move.md`:
  `mise run lint` greps them.
- Adding or removing a third-party skill: update `dependencies` in
  `apm.yml`, `deps` in `install.sh`, the `npx skills add` line in
  `docs/install.md` and its table, and the agent's `skills:` (or the lens in
  `feat-code-reviewer.md`) and `loads` in `sizes.json`.
- Agent prompts end with a fixed report format; `step.sh` parses it and
  the coordinators read its digest. Change the agent, `step.sh` (and
  `tests/step`) and the skills together. `/feat` and `/fix` stay thin:
  they never read code or edit artifacts; new work goes into an agent or
  `step.sh`, not the coordinator.
- `/tiny` is the opposite: one session that does the work itself, with no
  size table and no `harness.md`; `mise run lint` caps its length. Its
  fresh review spawns `feat-code-reviewer` (lens 7a, the tiny brief as the
  spec), so a change to that agent's inputs or report updates `/tiny` too.
  Its brief is `/brief`'s format with fewer sections: `tracker.sh
  create-issue` reads both, so keep `# Brief:`, `## Why` and `## Behaviour`.
- Adding or removing an agent: list it in `.claude-plugin/plugin.json`
  (`agents` is an explicit list).
- Releases are made by release-please (`.github/workflows/release.yml`,
  `release-please-config.json`): it keeps a release PR open; merging it bumps
  `apm.yml`, `.claude-plugin/plugin.json` and the README's version line
  (each marked for it), tags and publishes the GitHub Release. Never edit
  those versions or `.release-please-manifest.json` by hand (plugin users
  stay on the version they have until it changes).
- Shell: `shellcheck` must stay clean on `install.sh`, the scripts
  (`.apm/skills/feat/scripts/`) and their bash tests (`tests/`);
  `mise run lint` runs them all and `actionlint` on `.github/workflows/`,
  `mise run test:tracker`, `mise run test:spec-number`,
  `mise run test:story`, `mise run test:state`, `mise run test:sizes`,
  `mise run test:step` and `mise run test:ship` the offline tests.
  `step.sh` is the one call a coordinator makes at each boundary: Bash
  3.2, no jq, no Python; its tests are `tests/step` (fixtures in,
  expected output out). `ship.sh` runs the shipper's git and gh steps
  (two calls, three modes), under the same rules: Bash 3.2, no jq, no
  Python; its tests are `tests/ship` (throwaway repos, a stub `gh`).
  `measure.py` is the one shipped Python script and
  `docs/diagrams/sizes.py` the repo-only one: Python 3.11 or later,
  standard library only (constitution principle V); `mise run lint`
  compiles both and checks their syntax against 3.11,
  `mise run test:measure` tests `measure.py`.
- CHANGELOG.md is generated from commit messages: `feat` and `fix`
  subjects become its entries, so write them for users; `!` marks a
  breaking change. Don't edit it by hand.
- The roadmap is the GitHub Project https://github.com/users/pdemagny/projects/2:
  one issue per item, label `feat` or `bug`, fields Priority (P1/P2/P3), Size
  (small/medium/large), Status. A PR says `Closes #N` in its body, never
  in a commit message (release-please would copy it into the release PR
  and move the closed card back to In review); follow-ups are new issues.
- The website (GitHub Pages, `.github/workflows/docs.yml`) is Hugo with the
  hugo-book theme over README.md and `docs/` (`hugo.toml` mounts them). A
  new page in `docs/` needs `title` and `weight` front matter; link repo
  files outside `docs/` with absolute GitHub URLs, pages with relative ones.
- Tools and tasks are in `mise.toml`: `mise run lint` and `mise run
  test:apm` before committing. Bump the tool pins there when you test on
  newer versions.
