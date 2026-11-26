# Changelog

## [1.1.0](https://github.com/pdemagny/logistics/compare/v1.0.0...v1.1.0) (2026-11-26)


### Features

* **skills:** read skills by path so agents start without the skills listing ([c49f79b](https://github.com/pdemagny/logistics/commit/c49f79b4d413b337bed4f3c7c62051973be3240f))


### Bug Fixes

* **agents:** say preloaded skills run without the Skill tool ([b0f9c82](https://github.com/pdemagny/logistics/commit/b0f9c82c83d3d3eebcd767a9867ce77e2c0d7d68))
* **skills:** accept "Analyze: ran" in /feat phase 5 only with analyze's saved report ([ab3a81d](https://github.com/pdemagny/logistics/commit/ab3a81d5a018765d215f493c83b1cc71cf3ffae6))

## [1.0.0](https://github.com/pdemagny/logistics/compare/v0.14.0...v1.0.0) (2026-11-24)


### Features

* **agents:** deny the feat agents the tools they never use ([3b3d0e4](https://github.com/pdemagny/logistics/commit/3b3d0e4523d342044d8d94e1ec1050831bf4f03f))
* **feat:** give the implementer its story's tasks and files up front ([28f5e3e](https://github.com/pdemagny/logistics/commit/28f5e3ed18f362a1a7f8666d5156f814ba4fed4f))
* **feat:** stop the design review gate only on findings that need you ([7e30abc](https://github.com/pdemagny/logistics/commit/7e30abc26ccf1bba7f9f5e9feaa7c6aaf934620b))
* **harness:** ask the user before leaving a security finding unfixed ([6482b6e](https://github.com/pdemagny/logistics/commit/6482b6e8f169dc989324e5d4933a84f655c88349))
* **measure:** report what /feat and /fix runs cost ([2e9a682](https://github.com/pdemagny/logistics/commit/2e9a682ee9ff7db371da25b478b005d78aee0756))
* **measure:** show text-only turns right after a spawn ([76a8ad5](https://github.com/pdemagny/logistics/commit/76a8ad5220f63f1aaf828ef52ff623078a54f65d))
* **secret-scan:** flag bearer headers, JWTs and URL credentials ([48b9de2](https://github.com/pdemagny/logistics/commit/48b9de2ab26139b84b043777755355e9b561b631))
* **ship:** run the shipper's git and gh steps in ship.sh ([2e6d34a](https://github.com/pdemagny/logistics/commit/2e6d34a1190346ec628c21ce41ed7ea8704f7015))
* **sizes:** set each agent's model and effort per size from one data file ([6fc28c9](https://github.com/pdemagny/logistics/commit/6fc28c9cc7c3bb1fc6b95e351c8a9a5db7d99732))
* **skills:** let agents run the step call that closes their boundary ([7e63f63](https://github.com/pdemagny/logistics/commit/7e63f63a8f4817d1d5ec081955c8120774231f50))
* **skills:** let each gate of /feat and /fix be soft, hard or auto in .logistics.yml ([a90bd9f](https://github.com/pdemagny/logistics/commit/a90bd9f16be28bcaefdca31fa0dfe60c18b49fc5))
* **skills:** script setup checks, bug-trail chores and review diff ([708d407](https://github.com/pdemagny/logistics/commit/708d40761ae29319c9b9e2b386eabcaa13356508))
* **skills:** wait for agents in the foreground when fork mode is off ([fa01276](https://github.com/pdemagny/logistics/commit/fa01276f69fe99df85ea27f32f87f85a523584df))
* **state:** agent reports go to files, state file edited by state.sh ([78389e5](https://github.com/pdemagny/logistics/commit/78389e5597454210b5aab928ed9fc7e5dcd117c9))
* **step:** hand each agent its spawn lists from an inputs file ([3e8fba8](https://github.com/pdemagny/logistics/commit/3e8fba85c9ca0e0b5bbc95216a47a359a68ba02a))
* **step:** one step.sh call per /feat and /fix phase boundary ([a9e5817](https://github.com/pdemagny/logistics/commit/a9e58177a7923476837059b2d998d415deba84d7))


### Bug Fixes

* **agents:** have the implementer list tasks.md and fix.md on Wrote: even when only modified ([f226155](https://github.com/pdemagny/logistics/commit/f2261554f00226bf9fc9df6028733982ca382b5f))
* **feat:** stop agent report slips and unwritten implementer reports ([184a738](https://github.com/pdemagny/logistics/commit/184a7383730433d4522c5b584117e352a3e049c3))
* **feat:** stop unwritten reviewer reports from costing a full phase 7 re-run ([43411b2](https://github.com/pdemagny/logistics/commit/43411b28bb425ce0b7fed46fa0e14d7f98e4db6a))
* **measure:** count agent reports and end notices as agents working ([71cbf4e](https://github.com/pdemagny/logistics/commit/71cbf4e560231b2f909efce8b3d9433e40649991))
* **skills:** hard-gate /feat phase 5 when analyze says it ran without its metrics ([25c886a](https://github.com/pdemagny/logistics/commit/25c886acad7dd090caf8db3b9272ff0ea8d29988))
* **skills:** name a reviewer section for a lens it was not given ([39d9da3](https://github.com/pdemagny/logistics/commit/39d9da33dc524949790f3a61c9b882eac8ce1f2c))
* **skills:** stop step.sh wedging on a boundary call made before its report ([db0d8ec](https://github.com/pdemagny/logistics/commit/db0d8ec123c7f526dbc41cdd0de513ddbb03ce2f))
* **state:** stop state-file log lines from hardening the review gate ([314e49c](https://github.com/pdemagny/logistics/commit/314e49ca9445b7574eedba9d08f577b47d837eb1))
* **step:** read a lone "- none" item as an empty review lens ([a9496ae](https://github.com/pdemagny/logistics/commit/a9496ae5360d6f48dd0322d4fbdbee95927f8a66))


### Miscellaneous Chores

* **release:** release 1.0.0 and drop bump-minor-pre-major ([96cc3e3](https://github.com/pdemagny/logistics/commit/96cc3e35ab826296fce87b6440256c427b3e1338))

## [0.14.0](https://github.com/pdemagny/logistics/compare/v0.13.0...v0.14.0) (2026-11-18)


### Features

* **brief:** grow a tiny brief into a full one with /brief &lt;path&gt; ([cd08510](https://github.com/pdemagny/logistics/commit/cd085100d1f43a2cf6a1d689d162560edd58a480))
* **tracker:** label issues created from a brief with its Kind line ([ab0d38a](https://github.com/pdemagny/logistics/commit/ab0d38aaed0bd4d4b05cdb67b49613f91cf94592))


### Bug Fixes

* **brief:** save the brief in the repo so /feat can find it by name ([f025802](https://github.com/pdemagny/logistics/commit/f02580250e5b28b3c86d829fb2e715ff7a2f9e24))
* **feat:** run speckit-analyze on unnumbered spec dirs ([0a2be2d](https://github.com/pdemagny/logistics/commit/0a2be2d07da227a034c4a0d383b13aacce80443d))
* **feat:** stop /feat resume offering runs that already shipped ([da6fa6f](https://github.com/pdemagny/logistics/commit/da6fa6f5f63b43b086cf56adfec6f368fa456acc))

## [0.13.0](https://github.com/pdemagny/logistics/compare/v0.12.0...v0.13.0) (2026-11-18)


### Features

* **feat:** rebase shipped PRs onto main with /feat rebase and /fix rebase ([2f7a034](https://github.com/pdemagny/logistics/commit/2f7a034d7f0051e11794e5433b661ed963d6c64c))
* **feat:** stop the code review gate only for findings that need you ([9a7d55f](https://github.com/pdemagny/logistics/commit/9a7d55f0c6d39fde89aa3bad2df63ac06dd21aea))
* **tiny:** add /tiny for trivial changes in one session ([17c919f](https://github.com/pdemagny/logistics/commit/17c919f2e051d92034bfef01290370bce6a524ae))


### Bug Fixes

* **assessor:** redact passwd and api key values the secret scan catches ([e4181b4](https://github.com/pdemagny/logistics/commit/e4181b4615b4df5bdf229cdee231e932567d1e47))
* **shipper:** scan only added lines and require a literal secret value ([8bf1ef0](https://github.com/pdemagny/logistics/commit/8bf1ef0a9faa88258742d6680a5e4e8084d3d6b2))

## [0.12.0](https://github.com/pdemagny/logistics/compare/v0.11.0...v0.12.0) (2026-11-17)


### ⚠ BREAKING CHANGES

* **package:** rename .feat-agent.yml to .logistics.yml. Plugin users: remove the feat-agent plugin and marketplace, then install logistics from pdemagny/logistics. APM users: reinstall from pdemagny/logistics.

### Features

* **package:** rename feat-agent to logistics ([287fd24](https://github.com/pdemagny/logistics/commit/287fd247c707c7941d1dcb16d2d2b6983f409f3c))

## [0.11.0](https://github.com/pdemagny/feat-agent/compare/v0.10.0...v0.11.0) (2026-11-17)


### Features

* **feat:** list checks that did not run as Not verified, from the implementer to the PR ([7e09e0a](https://github.com/pdemagny/feat-agent/commit/7e09e0ad8e7c4d36faf0593dab57dd91958cb566)), closes [#11](https://github.com/pdemagny/feat-agent/issues/11)


### Bug Fixes

* **agents:** check that reported files exist before accepting a report ([e56bd33](https://github.com/pdemagny/feat-agent/commit/e56bd33f25ce6c7a2d834aa0d81d24a646651e2b)), closes [#10](https://github.com/pdemagny/feat-agent/issues/10)
* **agents:** keep closing keywords out of commit messages so released issues stay Done ([edc950b](https://github.com/pdemagny/feat-agent/commit/edc950b279e9e163445493504a17418a02851781))

## [0.10.0](https://github.com/pdemagny/feat-agent/compare/v0.9.0...v0.10.0) (2026-11-16)


### Features

* **feat:** stop at the spec gate only when the spec leaves a question open ([c34dcd9](https://github.com/pdemagny/feat-agent/commit/c34dcd9b093d6c4ec52c9ddb10ca87c663a8b91d))

## [0.9.0](https://github.com/pdemagny/feat-agent/compare/v0.8.0...v0.9.0) (2026-11-16)


### Features

* **fix:** add the /fix bugfix workflow on Spec Kit's bug extension ([1cf7e50](https://github.com/pdemagny/feat-agent/commit/1cf7e5082676b4cb1301f38021c1c3718eca0959))


### Bug Fixes

* **agents:** scope slow suites and rerun only failing tests ([a4177b7](https://github.com/pdemagny/feat-agent/commit/a4177b767bb093605861976477d4f4a4c7e92130))
* **install:** install the same agent-skills version as APM ([92fae1d](https://github.com/pdemagny/feat-agent/commit/92fae1d78f0bdd9eed0e43e27601242fc34b8136))
* **install:** point check at the right fix for plugin and clone installs ([6b7bd4a](https://github.com/pdemagny/feat-agent/commit/6b7bd4a8b7b41be2c0552b74d40ad0f93bc6f0fb))
* **shipper:** number specs from open PRs' files, not branch names ([d11e1ac](https://github.com/pdemagny/feat-agent/commit/d11e1ac6ebe801fd07155d736743d55710914bfb))

## 0.8.0 — 2026-11-02

- Renamed the project from feat-agents to feat-agent. The repository, APM
  package and plugin move to `pdemagny/feat-agent`, and plugin commands
  become `/feat-agent:feat` and `/feat-agent:brief`. Uninstall the old
  name before installing the new one.
- The `/feat-brief` skill is now `/brief`. The `feat-*` agents keep their
  names.
- Optional GitHub Projects board tracking, off unless the repo commits a
  `.feat-agent.yml` (board URL and the three status names). `/brief` and
  `/feat` check the board at the start of each run and move the issue to
  Brief, In progress (setup, resume, send-back) and In review (phase 7);
  the board's "Item closed" workflow sets Done. `/brief` can create the
  issue after the gate. Needs `gh auth refresh -s project`; setup in
  docs/install.md. `gh` is now pinned to 2.103.3, and `mise run
  test:tracker` runs the script's offline tests.

## 0.7.0 — 2026-10-29

- `/feat-brief #N` (or an issue URL) starts the brief from a GitHub issue,
  read with `gh`: its title and body are the idea, its unchecked checklist
  items are questions to answer, and a bug issue is refused. The brief and
  the state file record the issue, and the shipper's PR says `Closes #N`.
  `/feat #N` points to `/feat-brief #N`.

## 0.6.1 — 2026-10-29

- `mise run release` dates the `## Unreleased` section itself and opens a
  new empty one in the same commit; it refuses to release when Unreleased
  has no entries. Write changes there; no hand-written version heading.

## 0.6.0 — 2026-10-29

- `/feat-brief` has every brief read by a fresh agent before you confirm
  it: `feat-brief-reviewer` (phase 1, sonnet · medium, opus · medium for
  large) never sees the interview. It paraphrases the brief (the gate shows
  it), asks whether existing code, a dependency or a smaller version would
  do, flags undecided failure and edge cases, uncheckable acceptance and
  effects on existing data, and estimates the size on its own. Adapted from
  google/elephant-goldfish-model's brainstorm (Apache-2.0).
- The interview pushes back: each decision gets its strongest
  counter-argument before it is written down, and it asks how the problem
  is handled today.
- Briefs gain "Today" and "Alternatives rejected". The specifier treats
  rejected alternatives as binding, the planner doesn't bring them back,
  and reviewers get them with the rejected findings. Older briefs still
  work.

## 0.5.0 — 2026-10-29

- An agent is continued with `SendMessage` only while it is warm (no stop
  for the user since its report); after a hard gate you answered, it is
  spawned fresh in amend mode. Subagent caches last 5 minutes, and a cold
  planner rewrote 150–200k of context on Opus in 7 of 15 runs. Implementers
  are never continued into the next story.
- Agents write files with Write/Edit instead of shell heredocs and
  redirections, which the worktree guard refused 190 times in 15 runs, and
  report only once their writes have returned: 4 of 15 specifiers reported
  a spec.md that wasn't written.
- New design reviewer in phase 4 (4c clarity and fit, `feat-design-reviewer`),
  next to security and cost. It reads spec and plan as someone new to the
  project: it paraphrases them (the gate shows it, so you can check it against
  what you meant), and flags undefined terms, statements the code contradicts,
  references to things that don't exist, helpers the codebase already has,
  speculative abstractions, and decisions left to the implementer. Adapted
  from google/elephant-goldfish-model's review (Apache-2.0).
- Phase 4 is one agent with lenses, like phase 7: `feat-design-reviewer`
  runs 4a security, 4b cost and 4c clarity and fit. A small feature gets one
  reviewer with all three lenses (one cold start instead of three); medium
  and large keep one per lens in
  parallel. `feat-sec-reviewer` and `feat-cost-reviewer` are removed: after
  `./install.sh`, delete their dangling links in `~/.claude/agents/`.
- docs/workflow.md listed the large-size phase 5 row as sonnet · high; it
  is opus · high, as in the skill.

## 0.4.0 — 2026-10-28

- Fewer stops on small and medium features: questions are asked only at
  the spec gate (the planner reports assumptions instead of asking), and
  plan and design review share one gate that is hard only on a real
  finding, an assumption needing your call, a blocker or a size increase.
  The tasks gate is soft unless analyze finds CRITICAL/HIGH issues, the
  size grows or a checklist item is unanswered. Large keeps its gates.
- A size increase is always a hard gate, in any phase; a decrease is
  applied and logged.
- The specifier, planner and tasker are continued with `SendMessage` for
  amendments instead of being spawned cold again (their agent ids go in the
  state file).
- Size thresholds follow the task count: small up to ~30, medium ~31–60, large
  over ~60 (were 25 / 50).
- Claude Code is the only supported harness. The install docs, README and
  `mise run test:apm` no longer cover Codex, OpenCode, Gemini or
  Antigravity: `/feat` never ran there, so they only got a partial install.
  APM stays as the Claude installer because it also installs the
  third-party skills.
- The shipper commits less: numbering happens before the first commit (no
  `number … as NNN` commit), and docs go in the feat commit instead of
  trailing `docs` commits. Usually two commits: specs, then feat.

## 0.3.3 — 2026-10-27

- The spec dir is numbered in phase 8, not phase 2. Features started in
  parallel worktrees can't see each other's numbers and picked the same
  `NNN`. The branch and `specs/<short-name>/` stay unnumbered; the shipper
  takes the next free number from `origin/<default>` and the open PRs,
  renames the dir and the branch, and commits that on its own before the
  push.

## 0.3.2 — 2026-10-24

- Efforts lowered for medium and large features.

## 0.3.1 — 2026-10-23

- Sizes follow the expected task count: small up to ~25, medium ~26–50,
  large over ~50. Spreading over several packages no longer makes a
  feature large, and medium is no longer the fallback. A new service,
  permissions, exposure or dependency raises small to medium; docs-only
  work is small. Phase 5 proposes a smaller size as well as a bigger one.

## 0.3.0 — 2026-10-22

- Sizes renamed: small / medium / large / huge (were small / normal / big /
  huge). `/feat` still reads "normal" and "big" in older briefs and state
  files.
- `mise.toml`: pinned tools (claude, gh, specify-cli, apm, node, uv,
  shellcheck) and tasks: `lint`, `check`, `test:apm`, `dev:install`,
  `dev:uninstall`, `release <version>`, `pin <tag>`.

## 0.2.0 — 2026-10-22

- Docs say what works where: `/feat` runs only in Claude Code (and now
  stops with a message elsewhere); `/feat-brief` and the agents on their
  own can be installed for Codex, OpenCode and other harnesses.
- The third-party skills are pinned to addyosmani/agent-skills `0.6.13` in
  `apm.yml`.
- Install with one command for any harness: `apm install -g
  pdemagny/feat-agents` (APM) installs the skills, the agents (converted for
  Codex, copied for OpenCode) and the three third-party skills, declared in
  the new `apm.yml`. Claude Code users can install it as a plugin instead:
  `/plugin install feat-agents --marketplace pdemagny/feat-agents`.
- Skills and agents moved to `.apm/skills/` and `.apm/agents/*.agent.md`,
  the layout both APM and the plugin read. `./install.sh` follows; rerun it
  to update existing links.
- Agent frontmatter is harness-neutral: no `model`, `effort` or `color`, and
  `disallowedTools` instead of `tools`. `/feat` already passed model and
  effort on every spawn.
- `/feat` accepts plugin-namespaced agent names (`feat-agents:feat-planner`).
- `./install.sh deps` installs the three skills in one `npx skills add`;
  `./install.sh check` recognises a plugin install.
- The repo's `CLAUDE.md` moved to `.claude/CLAUDE.md` (plugins don't load a
  root `CLAUDE.md`, and the validator warns about it).
- `code-simplification` is no longer a dependency: its behaviour-preserving
  rule, readability signals and over-simplification traps are inlined in
  `feat-code-reviewer` lens 7e (Addy Osmani, MIT, credited).
- Matt Pocock's `code-review` is no longer downloaded: its standards and
  spec axes and smell baseline are inlined in `feat-code-reviewer` lens 7a
  (MIT, credited), run as passes in the reviewer's own context instead of
  two sub-agents. `install.sh` no longer vendors anything;
  `~/.claude/feat-agents/` is gone. No feat agent spawns agents.
- `ponytail-review` is no longer a dependency: Ponytail 5 made it a general
  review overlapping the other lenses. Its earlier over-engineering
  checklist is inlined in `feat-code-reviewer` lens 7d (MIT, credited).
- `install.sh` keeps backups in `~/.claude/feat-agents-backups/`, out of
  `skills/` and `agents/`.
- Fewer tokens per run:
  - Phase 1 is a separate `/feat-brief` skill that writes
    `specs/briefs/<name>.md` (or the capability map); `/feat <brief>` then
    starts from a cleared context.
  - `/feat` is a thin coordinator: it reads reports and keeps the state
    file; gate changes go back to the owning agent (amend modes for the
    specifier and planner), reviewers verify their own findings.
  - New `feat-shipper` (Haiku) for phase 8; picked review fixes are applied
    by `feat-implementer` in fix mode.
  - One implementer per user story at every size.
  - Phase 7 reviewers merged into one `feat-code-reviewer` with lenses;
    small runs two of them (7a+7b, 7c+7d+7e). Removed `feat-bug-reviewer`, `feat-perf-reviewer`,
    `feat-cut-reviewer`, `feat-simplifier`; `feat-sec-reviewer` is design
    only.
  - Medium effort on small for design security, implementation and code
    review.
- `install.sh` installs every skill in `skills/`.
- Phase 7 correctness review uses Matt Pocock's `code-review` (standards and
  spec axes) instead of the built-in one; `feat-bug-reviewer` adds its own
  bug pass. `install.sh deps` saves it outside `skills/` so it doesn't
  replace `/code-review`.
- README: mermaid flow diagram.
- Huge features: the capability-map rules are inlined in `SKILL.md`
  (adapted from addyosmani/agent-skills' `spec-driven-development`, MIT);
  that skill is no longer a dependency.
- Dropped `incremental-implementation`: its commit-per-slice workflow
  conflicted with the harness.
- New `feat-perf-reviewer` in phase 7 (performance-optimization's measure
  and identify steps on the built code); the orchestrator applies picked
  fixes with before/after measurement, keeps or reverts them, and commits
  kept ones as `perf(scope)`.
- Overrides for the remaining skills' standalone behaviour (interview-me
  hand-offs, code-simplification applying fixes, speckit checklist and
  remediation prompts, Spec Kit hooks that branch or commit).
- Fixed: phase 7 reviewed an empty `...HEAD` diff, since nothing is
  committed before phase 8; reviewers now get `git diff <merge-base>` after
  `git add -N`.
- Big features implement stories one after the other (parallel worktrees
  couldn't see uncommitted work). EnterWorktree's branch is renamed to match
  the spec directory.

## 0.1.0 — 2026-10-22

- `feat` skill moved out of `~/.claude/skills` into its own project.
- Phases 2–7 run in dedicated `feat-*` subagents; model and effort per
  phase follow the feature's size (small, normal, big), from one size table.
- New sizes: big (one implementer per user story, gate after each) and huge
  (split into a capability map, one `/feat` run and PR per capability).
- Agent defaults equal the small size (Sonnet medium/high, Opus high for
  planning).
- `install.sh`: install (link or copy), deps, check, uninstall.
