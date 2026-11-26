# /fix state: Spec Kit agents never say their preloaded skills run without the Skill tool

- Branch: fix-103-fix-agents-say Worktree: /home/pierre/Projects/logistics/.claude/worktrees/fix-103-fix-agents-say
- Size: small
- Agents: none (every spawn is fresh)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): short message, one logical change per commit, concise; never co-author commits (no Co-Authored-By); stage only files of this task; PR body says Fixes #N, never a commit message; in the worktree call /usr/bin/git directly, one plain command per call; mise run lint and mise run test:apm before committing; never name orleus anywhere; sizes.json is the source of models/efforts/loads (mise run diagrams regenerates, never edit between sizes-start/end markers); agent frontmatter has no model/effort/tools/color (use disallowedTools); agent report formats change together with step.sh and tests/step; shellcheck clean; CHANGELOG generated, never edited
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #103
- Gates: none

## Report

#103

## Log

- [x] 0 Setup — tracker: ok users/pdemagny/projects/2 (Brief, In progress, In review); slug 103-fix-agents-say; bug extension 1.0.2; report author OWNER
- [x] 1 Assess [hard] — open questions: 1
    - answer: approved (user: "ok, no lint check")
    - passed: gate: valid, high confidence, reproduced, 1 remediation(s); size small; risk area none; performance bug no
- [x] 1 Assess — answer: Should a lint check enforce the preload sentence in every agent with `skills:` that denies Skill? → no lint check for this fix
- [x] 2 implementer — not verified: none
    - wrote: .specify/bugs/103-fix-agents-say/fix.md
- [x] 2 Fix [soft] — applied; no deviations; checks pass
- [x] 3 Test [soft] — verified
- [!] 4 Code review — report missing: 4-7a+7b+7d.md; fresh spawn 1 of 1
- [x] 4 Code review [soft] — auto-applied none; skipped C1 (reviewer: "small, adds clarity against the exact misreading this fix targets")
    - C1 .apm/agents/feat-tasker.agent.md:65-67 — shrink: the sentence "This doesn't touch your preloaded skills above." repeats the preload paragraph in all three agents — rec: skip (small, adds clarity against the exact misreading this fix targets)
- [x] 5 Ship
