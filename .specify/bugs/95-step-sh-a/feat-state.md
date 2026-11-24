# /fix state: step.sh wedges on a boundary call made before its report exists

- Branch: fix-95-step-sh-a Worktree: /home/pierre/Projects/logistics/.claude/worktrees/95-step-sh-a
- Size: medium
- Agents: none (every spawn is fresh)
- Current phase: done (shipping)
- Conventions: Conventional commits type(scope): short message, one logical change per commit, never co-authored; stage only files of this task; in the worktree call /usr/bin/git directly, one plain command per call; step.sh is Bash 3.2, no jq, no Python, shellcheck-clean, tested by tests/step (mise run test:step); mise run lint and the mise run test:* tasks before committing; rm/cp/mv are interactive aliases: use command rm -f etc.; a PR says Fixes #N in its body, never in a commit message; CHANGELOG is generated, never edited
- Allowed Spec Kit hooks: none
- Map: none
- Issue: #95

## Report

#95

## Log

- [x] 0 Setup — board users/pdemagny/projects/2; slug 95-step-sh-a; bug extension 1.0.2; report author OWNER
- [x] 1 Assess [hard] — open questions: 2; proposed size medium; remediations: 3; public behaviour change
    - answer: approved (user: "ok, go with your recommendations")
    - passed: gate: valid, high confidence, reproduced, 3 remediation(s); size medium; risk area none; performance bug no
- [x] 1 Assess — answer: Should an empty (zero-byte) report be refused like an absent one, or stay a hard failed check? → refuse both, as check_report already treats them alike
- [x] 1 Assess — answer: On resume with an unanswered hard gate, show it or restart the phase and log the drop? → show it, as harness.md Resume already says
- [x] 2 implementer — not verified: none
    - wrote: .specify/bugs/95-step-sh-a/fix.md
    - wrote: tests/step/expected/fix2-missing.log
    - wrote: tests/step/expected/fix2-missing.out
    - wrote: tests/step/expected/fixes-missing.log
    - wrote: tests/step/expected/fixes-missing.out
    - wrote: tests/step/expected/missing-record-reprint.log
    - wrote: tests/step/expected/missing-record-reprint.out
    - wrote: tests/step/expected/resume-open-gate.log
    - wrote: tests/step/expected/resume-open-gate.out
    - wrote: tests/step/expected/resume-open-gate-no-record.log
    - wrote: tests/step/expected/resume-open-gate-no-record.out
- [x] 2 Fix [hard] — size increase: medium → large (deviations)
    - answer: approved (user: "ok, go on at medium")
- [x] 3 Test [soft] — verified
- [x] 4 Code review [hard] — B1 need you
    - B1 .apm/skills/feat/references/harness.md:97-98 — An agent that truly cannot write its report (Write failed twice, which its Last step still says to call after) used to get a logged hard "report missing" gate with `back to <N>` (a fresh spawn). Now it gets `refused:`, the coordinator's own call is refused again, and harness sends that to *Errors*: a gate whose `retry` answer is refused forever, leaving `stop` then resume as the only way out. No logged gate means no `back to` — rec: user (choosing the recovery path for a genuinely unwritable report is a workflow decision the fix gate did not cover)
    - B2 .apm/skills/feat/scripts/step.sh:4340-4342 — The known residual is wider than test.md says ("legacy state files only"): any open hard gate shown by resume rewrites last-step.md with no `call:` line (show_gate output, CALL_KIND resume). So making that gate's boundary call again after a resume dies with `no boundary is open (hard:)` on new state files too — rec: skip (no caller makes a boundary call after a resume; the gate's answer call works)
    - [std]1 .apm/skills/feat/scripts/step.sh:4295 — judgement: the RENUM fallback (`[[ ! -e $p && -n $RENUM && ${RENUM##*/} == "$f" ]] && p=$RENUM`) is now written a third time, in do_boundary beside check_report and record_sums — rec: skip (three one-line copies whose neighbours differ, e.g. record_sums' extra reports/ fallback; a helper saves little)
    - [std]2 .apm/skills/feat/scripts/step.sh:4352-4355 — judgement: show_gate re-implements the "; "-segment split loop that seg() already holds — rec: skip (different purposes; a shared iterator would cost more than four lines)
    - answer: approved (user: "ok, fix B1 with the re-spawn once")
    - answer: fix B1 (user: "ok, fix B1 with the re-spawn once")
    - outcome: picked B1; rejected B2 (as recommended), [std]1 (as recommended), [std]2 (as recommended)
- [x] 4 implementer — B1 → applied (harness rule only; step.sh and tests/step need no change: the re-spawn count lives in the coordinator's turn, as for a reviewer batch); performance: none; checks: mise run lint → pass, mise run test:step → pass, mise run test:state → pass; not verified: none
- [x] 3 Test [soft] — verified
- [x] 5 Ship
