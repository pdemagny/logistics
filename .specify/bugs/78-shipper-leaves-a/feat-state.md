# /fix state: Shipper leaves a Monitor running after its report

- Branch: fix-78-shipper-leaves-a Worktree: /home/pierre/Projects/logistics/.claude/worktrees/fix-78-shipper-leaves-a
- Size: small
- Agents: none (every spawn is fresh)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): msg, one logical change per commit, concise; never co-author commits (user is sole author); in worktrees call /usr/bin/git directly, one plain command per call; mise run lint and mise run test:apm before committing; shellcheck clean; step.sh/ship.sh/preflight.sh/trail.sh are Bash 3.2, no jq, no Python, tests in tests/<name>; agent prompt report format, step.sh and tests/step change together; coordinators stay thin; PR body says Fixes #N, never a commit message; zsh: rm/cp/mv aliased to -i, use command rm -f etc.
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #78
- Gates: none

## Report

#78

## Log

- [x] 0 Setup — tracker: ok users/pdemagny/projects/2 (Brief, In progress, In review); slug 78-shipper-leaves-a; bug extension 1.0.2; report author OWNER
- [x] 1 Assess [hard] — open questions: 1; not reproducible here; remediations: 2
    - answer: approved (user: "ok, go on with the recommendations")
    - passed: gate: valid, high confidence, not reproducible here, 2 remediation(s); size small; risk area none; performance bug no
- [x] 1 Assess — answer: Deny Monitor in all agents with a lint check, or only in the shipper and implementer? → only the shipper and implementer, the two that run long suites
- [x] 2 implementer — not verified: none
    - wrote: .specify/bugs/78-shipper-leaves-a/fix.md
- [x] 2 Fix [soft] — applied; no deviations; checks pass
- [x] 3 Test [hard] — partial: a live /feat or /fix ship phase against a multi-minute suite showing no Monitor and no re-wake
    - answer: ship with partial (user: "ship with partial")
- [x] 4 Code review [soft] — auto-applied none; skipped C1 (reviewer: "needed in each agent's prompt")
    - C1 .apm/agents/feat-shipper.agent.md:90-93 — shrink: the two added prose rules are identical in intent and both short — rec: skip (needed in each agent's prompt)
- [x] 5 Ship
