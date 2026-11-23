# Contributing

Thanks for your interest. logistics is a personal project: issues are
welcome, and pull requests too once we've agreed on the change in an issue.

## Issues

- **Bug**: use the Bug template. Include the skill or agent, what it did,
  the smallest brief or run that shows it, and your versions (logistics,
  Claude Code, Spec Kit).
- **Idea or feature**: use the Feature template. Say what problem it solves
  before how.
- **Security**: never in an issue; see [SECURITY.md](SECURITY.md).

What's planned is on the [roadmap](https://github.com/users/pdemagny/projects/2).

## Working on it

You need Claude Code, [mise](https://mise.jdx.dev) and the
[prerequisites](docs/install.md#prerequisites).

```sh
git clone https://github.com/pdemagny/logistics
cd logistics
mise install            # the pinned tools
mise run dev:install    # symlink the skills and agents into ~/.claude, add the third-party skills
```

Edits apply in the next Claude Code session. `mise run dev:uninstall`
removes the links. `mise tasks` lists the rest.

Where things are:

```
.apm/skills/feat/             the orchestrator: phases and gate messages (no size table); sizes.json (the source of models, efforts, loads, reviewer groups), sizes.tsv (generated from it, read by step.sh)
.apm/skills/feat/scripts/     step.sh (the one call at each phase boundary: checks reports, decides gates, logs, prints the next spawn), tracker.sh (board moves), spec-number.sh (numbers the spec dir), story.sh (a story's tasks), state.sh (writes and queries the state file, report paths), ship.sh (the shipper's git and gh steps), preflight.sh (setup checks, hooks read as data, the /fix slug, the worktree's branch rename), trail.sh (rotate, sections, slug and redact for the bug trail), secret-scan.sh, measure.py (run cost)
.apm/skills/feat/references/  harness.md: the coordinators' share of the rules /feat and /fix share (step script, gates, state file, board, resume); move.md (when main moved); rebase.md (the rebase entry point)
.apm/skills/fix/              the bugfix orchestrator: assess, fix, test, review, ship (no size table)
.apm/skills/brief/            phase 1: interview, size, brief or capability map
.apm/skills/tiny/             a trivial change in one session: tiny brief, edit, checks, PR
.apm/agents/*.agent.md        one subagent per phase role
apm.yml                       APM package: metadata and the third-party skill dependencies
.claude-plugin/               Claude Code plugin and marketplace manifests
install.sh                    developer install (symlinks), deps, check, uninstall
tests/                        offline tests for the scripts (stub gh, fake GraphQL endpoint, scratch repos)
specs/, .specify/bugs/        records of the /feat and /fix runs that built this repo
mise.toml                     pinned tools and tasks (lint, check, test:*, docs, diagrams, dev:*)
docs/                         the user documentation, published with README.md as the website
hugo.toml, go.mod             the website's Hugo config and theme (`mise run docs:serve` previews it)
```

The rules for changing the skills and agents are in
[`.claude/CLAUDE.md`](.claude/CLAUDE.md), which Claude Code loads when you
work in this repo. The ones that bite most:

- `.apm/skills/feat/sizes.json` is the source of models, efforts and both
  skills' reviewer groups: edit it and run `mise run diagrams`, which
  regenerates `.apm/skills/feat/sizes.tsv` (what `step.sh` reads) and the
  tables in [docs/workflow.md](docs/workflow.md). Lint fails on drift.
- The diagrams in the README and docs are drawn from `docs/diagrams/` by
  `mise run diagrams` (the model grid from `sizes.json`): re-render and
  commit `docs/img` when you change the sizes, the phases or the gates.
- Every agent prompt ends with a fixed report format that `step.sh`
  parses and `/feat` or `/fix` reads as a digest (and `/tiny`, for
  `feat-code-reviewer`): change the agent, `step.sh` with its
  `tests/step` cases, and the skills together.
- `/feat` and `/fix` only coordinate. New work goes into an agent or
  `step.sh`, not the coordinator. `/tiny` is the exception: one session doing the work itself,
  kept under 200 lines by `mise run lint`.

## Before you open a pull request

- `mise run lint`, `mise run test:apm`, `mise run test:tracker`,
  `mise run test:spec-number`, `mise run test:story`,
  `mise run test:state`, `mise run test:sizes`, `mise run test:step`,
  `mise run test:ship` and `mise run test:measure` pass. The `check`
  workflow runs the same on every pull request.
- For a change to a skill or agent prompt, run it on a scratch project and
  say in the PR what you ran and what happened. There is no automated test
  for prompts.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org)
  (`type(scope): short message`), one logical change per commit.
  [CHANGELOG.md](CHANGELOG.md) is generated from them: `feat` and `fix`
  subjects become its entries, so write those for users. A `!` after the
  type (`feat!:`) marks a breaking change.
- The PR says `Closes #N` for its issue.

By contributing, you agree that your contribution is licensed under the
[MIT License](LICENSE).

## Releases

[release-please](https://github.com/googleapis/release-please) keeps a
release pull request open with the next version and its CHANGELOG section,
from the commits merged since the last release. Merging it (maintainer
only) bumps the versions, tags the release and publishes it on GitHub.
