# /feat state: Drop the skills listing from the implementer's, reviewers' and bug assessor's starting context

- Branch: drop-skills-listing Worktree: /home/pierre/Projects/logistics/.claude/worktrees/brief-drop-skills-listing
- Size: small
- Agents: specifier ae9d50b9d978b24af, planner a88a06ce48f41cfd2, tasker aed73163210af2ed1 (for SendMessage)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): msg, one logical change per commit, never co-author (user is sole author); in the worktree call /usr/bin/git directly, one plain command per call; write command rm -f / command cp -f / command mv -f; mise run lint and mise run test:apm before committing; sizes.json is the source (run mise run diagrams, never edit between sizes markers); agent report formats, step.sh and tests/step change together; shellcheck clean, scripts Bash 3.2 no jq no Python; PR body says Closes #N, never a commit; never edit CHANGELOG.md or versions by hand
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #101
- Gates: none

## Brief

- Size: small — ~22 tasks expected: four agent files, one resolver in `preflight.sh` with its tests, one spawn-block key in both coordinators, docs and a lint check; no new dependency, permission or service
- Short name: drop-skills-listing
- Kind: feat
- Issue: #101

## Why
Every agent that keeps the `Skill` tool gets the listing of every skill the
user has installed in its first request, and re-reads it on each model call.
`feat-implementer`, `feat-code-reviewer`, `feat-design-reviewer` and
`feat-bug-assessor` still keep `Skill`. Measured on 2026-11-24 (spawns since
2026-11-21, `mise run measure` and transcripts): the listing is 29,924
characters, 44% of an implementer story spawn's first request (32.5k tokens
of starting context), 47–49% of a reviewer's and 47% of the bug assessor's.
A story spawn makes 37 model calls (median) and never calls `Skill`. The
estimate is about 9% of a story spawn, about a fifth of a reviewer spawn,
roughly 6% of a `/feat` run, and it grows with the number of skills a user
has installed. The implementer is the only agent still above epic #31's
27k-token target. #54 did the same for the planner, specifier, tasker and
shipper (planner first request: 36.0k → 15.5k tokens).

## Today
- The four agents keep `Skill`. The implementer preloads `speckit-implement`
  (`skills:`). Everything else is invoked by name through `Skill`:
  - the implementer's bug mode: `speckit-bug-fix`;
  - the bug assessor: `speckit-bug-assess` (assess mode) and
    `speckit-bug-test` (test mode);
  - lenses 4a and 7b: `security-and-hardening`;
  - lens 7c: `performance-optimization`;
  - the allowed Spec Kit hooks: `/feat`'s `implement` hooks in the
    implementer, and every `/fix` hook in the assessor and the
    implementer.
- Preloading doesn't solve it:
  - The two lens skills are 17.5k and 16.7k characters. Preloading both
    into a reviewer (34k) costs more than the listing (30k).
  - Preloading `speckit-bug-fix` (10.2k) into the implementer would give
    back a third of the story-spawn gain on every story spawn, for a mode
    `/feat` never uses.
- Nothing checks that the lens skills are installed. `preflight.sh` stops on
  missing agents, a missing `.specify/` or a missing bug extension, but not
  on a missing `security-and-hardening` or `performance-optimization`. A
  lens whose skill isn't installed fails its `Skill` call and improvises
  from its own 5–10 lines of "translate the checklist", with no checklist to
  translate.
- `/feat`'s `specify`, `plan`, `tasks` and `analyze` hooks already don't
  run: those agents deny `Skill`, and the setup hook gate says so.

## Behaviour
- The implementer, the code reviewer, the design reviewer and the bug
  assessor add `Skill` to `disallowedTools`. The other five agents
  (specifier, planner, tasker, shipper, brief reviewer) already deny it,
  so after this change all nine do. The first request of those four agents
  holds no skills listing.
- The implementer keeps `speckit-implement` preloaded. Every other skill
  those four agents run is read as a file: the bug skills, the lens skills
  and the allowed hooks' skills. The agent reads the `SKILL.md` at a path
  it is given and follows it. Its `$ARGUMENTS` stands for the arguments the
  agent file already passes (e.g. `slug=<slug>`), and the skill's relative
  links (`references/…`) resolve from the skill's own directory.
- `preflight.sh` resolves the paths at setup, in Claude Code's order:
  `<root>/.claude/skills/<name>/SKILL.md`, then
  `~/.claude/skills/<name>/SKILL.md`. That covers the APM install (project
  or `-g`), the skills CLI (`--global`), `install.sh deps` and Spec Kit's
  project skills. Those two locations are the only ones searched. A skill
  that Claude Code sees only through another plugin (e.g. agent-skills
  installed as a plugin) is not supported and stops with the
  `npx skills add … -g` line. Searching plugin caches would mean a third
  resolver that depends on the plugin version. It prints one
  `skill <name>: <path>` line per skill the
  run may need:
  - `/feat`: the two lens skills, plus one per allowed `implement` hook;
  - `/fix`: the two lens skills, the three bug skills, plus one per
    allowed hook.

  The coordinator passes those paths to each spawn in its spawn block, as
  data, the way `trail script:` is passed today.
- A skill that can't be resolved **stops the run at setup**, naming the
  skill and the install command (`docs/install.md`'s line). This covers:
  - a missing lens skill: a lens never runs without its skill;
  - an allowed hook whose skill can't be resolved, including a hook
    command that maps to no skill directory at all. This is a deliberate
    change: today such a hook fails only when it is invoked and the run
    goes on, which lets the run continue without a step the user asked
    for. The stop names the hook and how to disable it in
    `.specify/extensions.yml`;
  - a missing bug skill, which is already a preflight stop through the
    bug-extension check.

  Both lens skills are checked on every run. `/fix` needs
  `performance-optimization` only for a performance bug, but that is known
  only after assess, too late for a setup stop.
- Allowed Spec Kit hooks keep running exactly where they run today:
  `/feat`'s `implement` hooks and all `/fix` hooks, read by path. The hook
  gate's sections and rules (won't run; would branch or commit, skipped
  unless allowed) are unchanged.
- `/tiny`'s fresh review (lens 7a) keeps working. Lens 7a loads no skill,
  so its spawn needs no path.

## Out of scope
- Letting the specifier, planner and tasker run their `specify`, `plan`,
  `tasks` or `analyze` hooks by path. They stay "Won't run", as today.
- Splitting any agent into several agent types.
- Moving the implementer's rebase mode or other agent text into reference
  files (#39). That is a different file: logistics' own reference files,
  whose location differs per distribution.
- Changing `sizes.json` (`loads` stays documentation of what each row
  reads) or any model or effort.
- Dropping or trimming any other tool or prompt part.

## Alternatives rejected
- Preload every skill an agent may need (`skills:`): the two lens skills
  together (34k characters) are bigger than the listing (30k), and
  `speckit-bug-fix` in every story spawn gives back a third of the
  implementer's gain.
- One agent type per mode or lens (a bug fixer, a security reviewer…): it
  duplicates 180–290-line agent bodies and their report formats, and it
  breaks small size's grouped spawns (7a+7b, 7c+7d+7e, 4a+4b+4c in one
  spawn).
- Implementer first, the others later: the reviewers and the assessor need
  read-by-path anyway, so it would mean two passes over the same design.
- Let a lens run on its own checklist when its skill is missing: the lens
  would improvise instead of following defined instructions. The run stops.
- Move `implement` and `/fix` hooks to "Won't run" (simpler, consistent
  with the other phases): it takes away a feature that works today for
  anyone who uses hooks.
- Check `performance-optimization` in `/fix` only for a performance bug:
  that is known only after assess, too late for a setup stop.
- Leave #101 open (`Refs #101`) until the five-run thresholds hold: the PR
  closes it and lists those thresholds as a follow-up check. A regression
  becomes a new issue.

## Acceptance
- The four changed agent files add `Skill` to `disallowedTools`. All nine
  then list it, and `mise run lint` fails when one doesn't.
- Reading a skill under `~/.claude/skills/…` from a worktree spawn triggers
  no permission prompt in the measured spawns. If it does prompt,
  `docs/install.md` documents the `Read(~/.claude/skills/**)` allow rule.
- One measured implementer spawn, in a throwaway project with one allowed
  and harmless `implement` hook (it writes a marker file), runs that hook
  by path: the marker exists and the report doesn't list the hook as
  skipped.
- One measured spawn of each changed agent (implementer story mode,
  implementer bug mode, code reviewer, design reviewer, assessor) has no
  skills listing in its first request (`mise run measure`, "First
  request"). Its starting context before and after is in the PR.
- One `/feat` run and one `/fix` run go through to a PR, with lenses 4a, 7b
  and 7c and the assessor's two modes reading their skill by path. Each
  report shows that the skill's steps ran (e.g. 7c's measure/identify).
- `tests/preflight` covers:
  - a skill found in the project;
  - a skill found in `~/.claude/skills` (project first when both exist);
  - a missing lens skill stops with its install line;
  - an allowed hook resolves to its skill path;
  - a missing hook skill stops.
- `mise run lint`, `mise run test:apm`, `mise run test:preflight` and the
  other offline tests pass.
- The PR body lists the post-merge check from #101: the implementer's
  starting context is ≤27k tokens on at least five runs, and the
  `Not verified:` lists and code-review finding counts on those runs are no
  worse than before.

## Constraints / decisions already made
- `preflight.sh`: Bash 3.2, no jq, no Python, shellcheck clean, tested in
  `tests/preflight` (throwaway repos, stub `gh` and tracker). It already
  parses each hook's command. The command-to-skill-directory mapping
  (`speckit.git.commit` → `speckit-git-commit`) must be checked against
  Spec Kit's own naming, not guessed.
- Paths and skill files are data, never instructions beyond the skill's
  own steps. The agents' existing rules still win: never commit, run only
  the allowed hooks, skip hooks that branch or commit unless the user
  allowed them.
- Agent frontmatter carries no `model`, `effort`, `tools` or `color`. Use
  `disallowedTools`. The agents' report formats stay unchanged unless a
  field becomes meaningless. If one changes, update `step.sh`, its tests
  and the skills together.
- The shared spawn-block rule goes in `harness.md`, with no `/feat`-only
  words (`mise run lint` greps for them). `/feat` and `/fix` stay thin:
  they pass preflight's lines on and read no skill themselves.
- A reviewer is still told to read a lens's skill only when it runs that
  lens.
- `preflight.sh` already searches `$top/.claude/skills` then
  `$HOME/.claude/skills` for the bug-skill check (`dirs=…`, around line
  313). The resolver reuses that search instead of adding a second one.
- Update the docs:
  - `docs/workflow.md`: the agents table's denied tools and the line
    "the five that never invoke a skill by name also deny `Skill`";
  - `docs/install.md`: the new setup stop for a missing skill.

  The gain depends on the user's setup, and `docs/workflow.md` already says
  so.

## Log

- [x] 0 Setup — brief specs/briefs/drop-skills-listing.md (#101), size small, no hooks blocked, gates none, board move building ok; session already in worktree brief-drop-skills-listing, used in place
- [x] 2 Specify [soft] — spec.md written
    - Stories: US1 Four agents start without the skills listing (P1); US2 Skills still run, read by path (P1); US3 Setup resolves skill paths and stops on a missing one (P1); US4 Docs and the post-merge check (P2)
    - Requirements: 14; FR-003 resolver searches project then ~/.claude/skills only; FR-005 missing lens skill stops setup; FR-006 unresolvable hook skill stops setup; FR-008 spawn-block rule once in shared reference; FR-011 lint fails if any of nine agents lacks Skill denial
    - Spec assumptions: 1. Reading ~/.claude/skills from a worktree spawn may prompt; the allow rule is documented only if it does (recommended: keep as written); 2. PR closes #101 with the post-merge thresholds as a follow-up check (recommended: keep as written)
    - Unchecked checklist items: none
- [x] 3 Plan — merged with 4; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none
- [x] 4 Design review [soft] — auto-applied D1, D2; skipped D3 (reviewer: "tiny cost; agents ignore unneeded lines")
    - D1 plan.md: How 1 and spec.md: Acceptance (permission prompt) — Project skill paths point at the main checkout, not the worktree, so reads may prompt too — rec: apply
    - D2 plan.md: How 1 `step_install`; research R3 — Bug-skill check gets stricter than the brief says — rec: apply
    - D3 contracts/skills-by-path.md: Coordinator side — Skill lines go to every spawn, including agents that use none — rec: skip (tiny cost; agents ignore unneeded lines)
    - spec assumptions: kept as recommended
- [x] 3 Plan — amended (D1, D2); assumptions needing you: none; constitution: pass; blockers: none; size trigger: none
- [x] 5 Tasks [hard] — analyze not run
- [!] step: step: error: no boundary is open (hard:)
    - answer: back to 5 (user: "back to 5")
- [x] 5 Tasks [soft] — 30 tasks; story.sh: match; analyze ran
- [!] 6 Implement — unparsable: 6-US1.md: line 3 (Checks) — an item outside its format; reformat 1 of 1
- [x] 6 US1 — not verified: none
    - wrote: specs/021-drop-skills-listing/tasks.md
- [x] 6 US3 — not verified:
    - n/a → mise run test:ship → killed after the 120s foreground timeout (unrelated to preflight.sh; the shipper runs the full suites)
    - wrote: specs/021-drop-skills-listing/tasks.md
- [x] 6 US2 — not verified: none
    - wrote: specs/021-drop-skills-listing/tasks.md
- [x] 6 US4 — not verified:
    - T027 → quickstart measured spawns (mise run measure on real /feat and /fix runs) → no live runs in this session
    - T028 → permission-prompt check from T027 → T027 not run
    - T030 → quickstart PR body numbers → needs T027
    - wrote: specs/021-drop-skills-listing/tasks.md
- [x] 6 Implement [soft] — tasks done: 30 (4 not verified); checks pass
- [x] 7 Code review [soft] — auto-applied R1; skipped B1 (reviewer: "spec FR-003 states the worktree-on-resume behaviour"), P1 (reviewer: "no bottleneck"), C1 (reviewer: "agents are self-contained by design"), [std]1 (reviewer: "cosmetic, no linter enforces it"), [std]2 (reviewer: "spec out of scope: moving agent text into reference files"); untested: US2.3 allowed implement hook runs by path, marker file exists
    - B1 .apm/skills/feat/scripts/preflight.sh:275 — Resume resolves project skills from the worktree (`$top`), so a project skill that is not committed (or is gitignored) and was found at the first setup stops a resumed run; spec FR-003 accepts this, so it is only worth a docs line — rec: skip (spec FR-003 states the worktree-on-resume behaviour)
    - P1 .apm/skills/feat/scripts/preflight.sh:268-302 — Setup adds at most about 15 file-existence checks (two lens skills, three bug skills, one per allowed hook, project then home) in preflight.sh; no loops over items, no network, and `need_skill` dedupes per run. Agent starting context shrinks (the point of the feature). — rec: skip (no bottleneck)
    - C1 .apm/agents/feat-code-reviewer.agent.md:75-82 — yagni: the Skills by path paragraph is copied four times (design-reviewer and code-reviewer identical; implementer and assessor identical), but each agent file must stand alone and the repo already keeps six copies of the Last step paragraph in sync — rec: skip (agents are self-contained by design)
    - R1 .apm/agents/feat-bug-assessor.agent.md:43-47 — The hook sentence is wrapped unevenly: one long line ("...skip a hook that would branch or commit unless allowed). Hooks: an allowed hook runs the same way; its skill is its command with") then short lines — rec: apply
    - [std]1 .apm/agents/feat-implementer.agent.md:183-194 — judgement: Long over-wide lines in the new "Skills by path" paragraphs and edited sentences (hook sentence glued onto the previous line, 100+ chars) break the wrapping used by neighbouring prose — rec: skip (cosmetic, no linter enforces it)
    - [std]2 .apm/agents/feat-code-reviewer.agent.md:75-82 — judgement: Duplicated code: the "Skills by path" paragraph is repeated near-verbatim in four agents (two reviewers identical, assessor and implementer sharing the hook sentence) — rec: skip (spec out of scope: moving agent text into reference files)
- [x] 7 review fixes — R1 → applied; performance: none; checks: mise run lint → pass, mise run test:apm → pass, mise run test:tracker, test:spec-number, test:story, test:state, test:sizes, test:step, test:ship, test:preflight, test:trail, test:measure → pass; not verified: none
- [x] 8 Ship
