# /fix state: Review merge turns a `- none` item into a finding the user must answer

- Branch: fix-73-review-none-finding Worktree: /home/pierre/Projects/logistics/.claude/worktrees/fix-73-review-none-finding
- Size: medium
- Agents: none (every spawn is fresh)
- Current phase: done (shipping)
- Conventions: conventional commits type(scope): short message, one logical change per commit, never co-authored; in worktrees call /usr/bin/git directly, one plain command per call; shell is zsh, rm/cp/mv aliased -i (use command rm -f etc.); agent report format, step.sh and tests/step change together; step.sh is Bash 3.2, no jq, no Python; shellcheck clean; mise run lint, mise run test:step and mise run test:apm before committing
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #73

## Report

#73

## Log

- [x] 0 Setup — tracker: ok users/pdemagny/projects/2; slug 73-review-none-finding; bug extension 1.0.2; report author OWNER
- [x] 1 Assess [hard] — open questions: 3; proposed size medium; remediations: 3
    - answer: approved (user: "ok")
    - passed: gate: valid, high confidence, reproduced, 3 remediation(s); size medium; risk area none; performance bug no
- [x] 1 Assess — answer: Fold `- none` in parse for every list field, or only skip it in the review merges? → in parse, one shape for all callers
- [x] 1 Assess — answer: Should a list holding `- none` next to real items be refused or have the `none` dropped? → leave as is (out of scope; only the lone `- none` is fixed)
- [x] 1 Assess — answer: Also tighten the reviewer agents' wording? → yes, one sentence in feat-code-reviewer.agent.md and feat-design-reviewer.agent.md, alongside the step.sh tolerance
- [x] tracker: #73 set to "In progress"
- [x] 2 implementer — not verified: none
    - wrote: .specify/bugs/73-review-none-finding/fix.md
    - wrote: tests/step/fixtures/agents/code-reviewer/7a+7b-dash-none.md
    - wrote: tests/step/fixtures/agents/design-reviewer/4a+4b+4c-dash-none.md
    - wrote: tests/step/expected/code-dash-none.out
    - wrote: tests/step/expected/code-dash-none.log
    - wrote: tests/step/expected/design-dash-none.out
    - wrote: tests/step/expected/design-dash-none.log
- [x] 2 Fix [soft] — applied; no deviations; checks pass
- [x] 3 Test [soft] — verified
- [x] tracker: #73 set to "In review"
- [x] 4 Code review [hard] — files changed outside the reports; changed: .specify/bugs/73-review-none-finding/feat-state.md
    - B1 .apm/skills/feat/scripts/step.sh:823-830 — the fold matches the item exactly, so `- none ` (trailing blank) or `- None` still becomes a finding, since parse keeps `${line#- }` untrimmed — rec: skip (the agents write the exact token; the reported form is fixed and the parser trims nothing elsewhere)
    - answer: approved (user: "yes to both")
    - answer: leave B1 (user: "B1 leave")
    - outcome: none picked; rejected B1 (user: "B1 leave")
- [x] 5 Ship
