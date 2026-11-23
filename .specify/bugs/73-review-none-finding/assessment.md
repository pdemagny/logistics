# Bug Assessment: Review merge turns a `- none` item into a finding the user must answer

- **Slug**: 73-review-none-finding
- **Created**: 2026-11-23
- **Source**: pasted text (pdemagny/logistics#73, https://github.com/pdemagny/logistics/issues/73, fetched with `gh issue view 73`; host github.com, allowlisted)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

pdemagny/logistics#73 — "Review gate turns a lens with no findings into a \"none\" finding the user must answer".

> At the `/feat` phase 7 gate, a code reviewer that found nothing under a lens still produced a finding for it. step.sh merged the 7a+7b report into:
>
> ```
> finding: B1 Bugs — none — rec: user (no valid recommendation)
> finding: B2 Spec — none — rec: user (no valid recommendation)
> finding: S1 Security — none — rec: user (no valid recommendation)
> ```
>
> and printed `hard:` with `- B1, B2, S1 need you` and `- S1 security`.

Why it hurts (summarized): an empty review turns a soft gate hard; the user must answer `leave B1`, `leave B2`, `leave S1` for lines that say nothing; a left `S` finding is published in the PR body and the state file. Expected: a lens with nothing to report yields no `finding:` line; with no other `user` finding the gate follows the remaining findings (soft there: 2 apply, 4 skip). Where to look: the reviewer's report format, or step.sh's merge; probably step.sh should tolerate it either way, with a `tests/step` case whose Bugs, Spec and Security entries read `none`. Seen on the spawn-inputs-file `/feat` run (#69), phase 7, size small.

## Symptom

When a code reviewer writes an empty lens as a list header followed by a `- none` item (`Bugs (7a):` then `- none`) instead of `Bugs (7a): none`, step.sh merges `none` as a real finding with an invalid rec, so the gate goes hard and refuses an approval until the user answers each one. Expected: such a lens yields no finding.

## Reproduction

1. In a scratch copy of the worktree (under the system temp dir), replace `tests/step/fixtures/agents/code-reviewer/7a+7b-zero.md` with a report whose `Bugs (7a):`, `Spec (7a):` and `Security (7b):` are each a bare header followed by `- none`.
2. Run `UPDATE=1 bash tests/step/run.sh` in that copy and diff its `tests/step/expected` against the worktree's.
3. Observed: only the `override-after-review` case changes. Its final call, `answer: approved (user: "ship it")`, which ships with the original fixture, now prints `refused: B1, B2, S1 need an answer`, and the state stays at `7 Code review`. The three `none` items became findings B1, B2, S1 with rec `user`, as in the report.

## Suspected Code Paths

- `.apm/skills/feat/scripts/step.sh:844-900` (`parse`) — an `L` list field with an empty header takes every `- ` line as an item; a lone `- none` is stored as an item, not read as the `none` value (`<Key>: none` would give zero items).
- `.apm/skills/feat/scripts/step.sh:2157-2194` (`merge_code`) — calls `madd` for every item of each lens section with no check for a `none` placeholder.
- `.apm/skills/feat/scripts/step.sh:2105-2117` (`merge_rules`, rule 5) — `none` has no `rec:`, so its rec becomes `user (no valid recommendation)`, which `mcount` (`:2249-2270`) counts under `MC_USER` and, for Security, `MC_SEC`; the gate reasons at `:2621` and `:2625` make it hard (`B1, B2, S1 need you`, `S1 security`).
- `.apm/skills/feat/scripts/step.sh:2196-2213` (`merge_design`) — the same gap for the design reviewers' `Findings:` (a `- none` item would become a design finding tagged `none`).
- `.apm/agents/feat-code-reviewer.agent.md:199-203` — the format says `<Key>: none` when empty, but the next sentence, "write `none` for an empty field or section", can be read as a `- none` item under the header. The same wording is in every agent's format (`feat-design-reviewer.agent.md:148` and others).

## Root Cause Hypothesis

step.sh's parser accepts a list written as a bare header plus a single `- none` item and hands `none` to the review merge as an item; the merge has no rule for a placeholder item, so it becomes a finding without a valid rec (`user`), which hardens the gate and, for Security, gets published. The reviewer slipping into the `- none` form is the trigger, made easier by the format's wording, but the report was otherwise valid and step.sh should not turn it into a finding. Confidence: high (reproduced with the project's own test runner).

## Proposed Remediation

**Preferred**: in step.sh's `parse`, when a list field (`L`, `A`, `W`) closes with an empty header and exactly one item that reads `none` (`n/a` too for `A`), treat it as the header value `none` with no item (in `pclose`: set `PV` to that value, `PIN` to 0). The shape is then the same as `<Key>: none` for every caller: the review merges, the schema checks and the other agents' lists. Add a `tests/step` case: a 7a+7b code-review fixture whose Bugs, Spec and Security entries are `Bugs (7a):` + `- none` (and so on), checking the gate is soft and has no `finding:` line for them. A design-review fixture with `Findings:` + `- none` would cover the design merge too.

**Alternatives**:
- Narrower: skip an item that reads exactly `none` in `merge_code` and `merge_design` only (before `madd`). It touches only the review path, but other list fields that may get the same `- none` form stay as they are.
- Also tighten the reviewer's prose (`feat-code-reviewer.agent.md`, maybe `feat-design-reviewer.agent.md`): "an empty section is `<Key>: none` on its header line, never a `- none` item". This lowers the chance the form is written again but does not replace step.sh's tolerance, which the report asks for.

**Files likely to change**:
- `.apm/skills/feat/scripts/step.sh`
- `tests/step/run.sh`
- `tests/step/fixtures/agents/code-reviewer/<new fixture>.md` (and maybe a design-reviewer one)
- `tests/step/expected/<new case>.out`, `tests/step/expected/<new case>.log`
- optionally `.apm/agents/feat-code-reviewer.agent.md`

**Tests to add or update**:
- A `tests/step` case for phase 7 (small, one batch) with a 7a+7b report whose Bugs, Spec and Security lists are `- none` items: no `finding:` line for them, no `need you`/`security` reasons, the gate soft (or following the other findings).
- Optionally a design-review case with `Findings:` + `- none`.
- `mise run test:step`, `mise run lint` (shellcheck), `mise run test:apm`.

## Risks & Considerations

- A parse-level change affects every agent's lists; it only folds a lone `none` into the existing `none` value, so the existing goldens should not change, but the whole `tests/step` suite must pass.
- A list with `- none` next to real items is a different, odd shape; the fix should not silently drop real items.
- If the reviewer prose changes, `/tiny` also spawns `feat-code-reviewer` (lens 7a), so its reading of the report has to stay consistent.
- step.sh stays Bash 3.2 with no jq or Python; shellcheck must stay clean.

## Open Questions

- Fold `- none` in `parse` for every list field, or only skip it in the review merges? Recommended: in `parse`, since it gives one shape for all callers.
- Should a list holding `- none` next to real items be refused as unparsable or have the `none` dropped? Recommended: leave it as it is now (out of scope; only the lone `- none` case is fixed).
- Also tighten the reviewer agents' wording? Recommended: yes, one sentence in `feat-code-reviewer.agent.md` (and `feat-design-reviewer.agent.md`), alongside the step.sh tolerance.
