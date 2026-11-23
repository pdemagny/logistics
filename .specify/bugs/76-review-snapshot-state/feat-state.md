# /fix state: Review gate goes hard when the coordinator logs to the state file during a review

- Branch: fix-76-review-snapshot-state Worktree: /home/pierre/Projects/logistics/.claude/worktrees/fix-76-review-snapshot-state
- Size: medium
- Agents: none (every spawn is fresh)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): msg, one logical change per commit, never co-author; git as /usr/bin/git, one plain command per call; step.sh/ship.sh Bash 3.2, no jq/Python, shellcheck clean; change agent+step.sh+tests/step together; mise run lint and mise run test:step (and test:apm) before committing; CHANGELOG generated, never edit; never edit versions by hand
- Allowed Spec Kit hooks: none
- Map: none
- Issue: pdemagny/logistics#76

## Report

#76

## Log

- [x] 0 Setup — tracker: ok users/pdemagny/projects/2; slug 76-review-snapshot-state; bug extension 1.0.2; report author OWNER
- [x] 1 Assess [hard] — open questions: 1; proposed size medium; remediations: 3; public behaviour change
    - answer: approved (user: "ok, every change, go with medium")
    - passed: gate: valid, high confidence, reproduced, 3 remediation(s); size medium; risk area none; performance bug no
- [x] 1 Assess — answer: Should the snapshot ignore every state-file change, or only appended log lines? → every change
- [x] tracker: pdemagny/logistics#76 set to "In progress"
- [x] 2 implementer — not verified: none
    - wrote: .specify/bugs/76-review-snapshot-state/fix.md
- [x] 2 Fix [soft] — applied; no deviations; checks pass
- [x] 3 Test [soft] — verified
- [x] 4 Code review [soft] — auto-applied none
- [x] 5 Ship
- [x] tracker: pdemagny/logistics#76 set to "In review" (logged after the phase 4 boundary: the installed state.sh still has bug #76)
