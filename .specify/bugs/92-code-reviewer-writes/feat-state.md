# /fix state: Code reviewer writes sections of lenses it was not given; parser and reformat name the wrong line

- Branch: fix-92-code-reviewer-writes Worktree: /home/pierre/Projects/logistics/.claude/worktrees/fix-92-code-reviewer-writes
- Size: medium
- Agents: none (every spawn is fresh)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): msg, one logical change per commit, never co-author (no Co-Authored-By); in worktrees call /usr/bin/git directly, one plain command per call; mise run lint and mise run test:apm before committing; agent report format changes go with step.sh and tests/step together; step.sh/ship.sh/preflight.sh/trail.sh are Bash 3.2, no jq, no Python, shellcheck clean; sizes.json is the source, regenerate with mise run diagrams, never hand-edit between sizes-start/sizes-end; never name the private project orleus anywhere
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #92

## Report

#92

## Log

- [x] 0 Setup — board users/pdemagny/projects/2; slug 92-code-reviewer-writes; bug extension 1.0.2; report author OWNER
- [x] 1 Assess [hard] — open questions: 1; proposed size medium
    - answer: approved (user: "ok")
    - passed: gate: valid, high confidence, reproduced, 1 remediation(s); size medium; risk area none; performance bug no
- [x] 1 Assess — answer: Should a stray <Key>: none section be accepted silently instead of reported? → no, report it with the new reason; the parser stays fail-closed and one reformat suffices
- [x] 2 implementer — not verified: none
    - wrote: .specify/bugs/92-code-reviewer-writes/fix.md
    - wrote: tests/step/fixtures/agents/code-reviewer/bad-stray-7c.md
    - wrote: tests/step/fixtures/agents/code-reviewer/bad-stray-net.md
    - wrote: tests/step/expected/fmt-review-bad-stray-7c.out
    - wrote: tests/step/expected/fmt-review-bad-stray-7c.log
    - wrote: tests/step/expected/fmt-review-bad-stray-7c-hard.out
    - wrote: tests/step/expected/fmt-review-bad-stray-7c-hard.log
    - wrote: tests/step/expected/fmt-review-bad-stray-net.out
    - wrote: tests/step/expected/fmt-review-bad-stray-net.log
    - wrote: tests/step/expected/fmt-review-bad-stray-net-hard.out
    - wrote: tests/step/expected/fmt-review-bad-stray-net-hard.log
- [x] 2 Fix [soft] — applied; no deviations; checks pass
- [x] 3 Test [soft] — verified
- [x] 4 Code review [soft] — auto-applied none; skipped [std]1 (reviewer: "ten fixed keys that change with the agent format, which already changes step.sh and tests/step together; deriving it needs SCH_* saved and restored around parse")
    - [std]1 .apm/skills/feat/scripts/step.sh:988-1005 — judgement: pstray() repeats the code-reviewer key list that schema() already holds, so a lens key added or renamed in schema() must be changed in pstray() too or a stray section falls back to the old misattributed reason — rec: skip (ten fixed keys that change with the agent format, which already changes step.sh and tests/step together; deriving it needs SCH_* saved and restored around parse)
- [x] 5 Ship
