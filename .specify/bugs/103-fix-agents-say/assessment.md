# Bug Assessment: Spec Kit agents never say their preloaded skills run without the Skill tool

- **Slug**: 103-fix-agents-say
- **Created**: 2026-11-26
- **Source**: pasted text (GitHub issue pdemagny/logistics#103, fetched with `gh issue view`)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

Title: fix(agents): say preloaded skills run without the Skill tool

`feat-tasker.agent.md` says "Run `speckit-analyze`" while its frontmatter puts `Skill` in `disallowedTools`. Nothing says the skill is preloaded (through `skills:`) and is run by following its steps directly, so a model can read the instruction as one it cannot carry out and fall back to a hand check. The tasker skipped analyze this way in several downstream runs; other runs ran it. The prerequisite script works on an unnumbered feature dir and no analyze hooks are registered, so the tooling is not the cause.

Proposed fix in the report: say in `feat-tasker.agent.md` that `speckit-tasks` and `speckit-analyze` are preloaded and need no Skill tool; say that `Analyze: not run (<why>; …)` must name the real failure (the command and its error), never a choice to skip; check the same wording in `feat-specifier` and `feat-planner`.

(A downstream project name in the issue is left out here, per the repo's convention.)

## Symptom

The tasker (and potentially the specifier and planner) is told to "Run `speckit-…`" while `Skill` is denied in its frontmatter and its prompt says "you can't run them (`Skill` is denied …)" about hooks; nothing tells it the named skills are already loaded and are run by following their steps. Observed: the tasker sometimes reports `Analyze: not run (…; cross-checked by hand)` and skips analyze. Expected: it follows the preloaded `speckit-analyze` steps to its report, and reports `not run` only for a real failure.

## Reproduction

1. `grep -rn -i preload .apm/agents/` → no match: no agent prompt mentions that `skills:` preloads its skills.
2. `sed -n 1,8p .apm/agents/feat-tasker.agent.md` → `disallowedTools: … Skill` with `skills: [speckit-tasks, speckit-analyze]`; lines 21-22 say "Run `speckit-tasks`" / "Run `speckit-analyze`".
3. `.apm/agents/feat-tasker.agent.md:59` → "Spec Kit hooks: you can't run them (`Skill` is denied; …)": the only mention of `Skill` ties it to being unable to run Spec Kit commands.
4. Same frontmatter and same "Run `speckit-specify`" / "Run `speckit-plan`" wording in `feat-specifier.agent.md` (lines 4-6, 13, 53) and `feat-planner.agent.md` (lines 4-6, 15, 57).

The behavioural skip itself depends on the model's reading of the prompt and was not re-run here; the missing wording is confirmed statically.

## Suspected Code Paths

- `.apm/agents/feat-tasker.agent.md:4-7,21-33,59-60` — denies `Skill`, says "Run `speckit-analyze`", allows `Analyze: not run (<why>; …)` with any reason, and links `Skill` denial to not running Spec Kit commands.
- `.apm/agents/feat-specifier.agent.md:4-6,13,53-54` — same frontmatter and hooks sentence, "Run `speckit-specify`".
- `.apm/agents/feat-planner.agent.md:4-6,15,57-58` — same frontmatter and hooks sentence, "Run `speckit-plan`".
- `docs/design.md:62-64` — documents that `skills:` preloads a skill's full content; the agents never say so.

## Root Cause Hypothesis

The prompts name the preloaded skills as things to "run" without saying how, in agents whose `Skill` tool is denied and whose only sentence about `Skill` says they "can't run" Spec Kit hooks. A model can conclude it cannot invoke `speckit-analyze` and take the allowed `not run (<why>; cross-checked by hand)` path, whose `<why>` is unconstrained. Confidence: high (the gap is in the text; the intermittent skips match a reading choice, and the tooling was ruled out by the report).

## Proposed Remediation

**Preferred**: In `feat-tasker.agent.md`, add a sentence near the top (before step 1) saying `speckit-tasks` and `speckit-analyze` are preloaded through `skills:`, their full steps are already in context, and running one means following those steps directly with Read, Bash and Write: no Skill tool is needed, and `Skill` being denied concerns hooks and other skills only. In step 2, say `Analyze: not run (<why>; …)` names the real failure (the command run and its error, or where it stopped), never a choice to skip. Reword the hooks sentence (line 59) so it does not read as "Spec Kit commands can't run". Apply the same preload sentence and hooks rewording to `feat-specifier.agent.md` (`speckit-specify`) and `feat-planner.agent.md` (`speckit-plan`). The report format and `step.sh` parsing stay unchanged.

**Alternatives** (optional):
- Allow the `Skill` tool in these agents — rejected: it would let them run hooks and other skills, which the hook policy (`docs/design.md:102`) denies on purpose.
- Put the wording once in a shared reference — the agents have no shared include; a sentence in each of three prompts is simpler.

**Files likely to change**:
- `.apm/agents/feat-tasker.agent.md`
- `.apm/agents/feat-specifier.agent.md`
- `.apm/agents/feat-planner.agent.md`

**Tests to add or update**:
- None needed for `step.sh` (no format change). Optionally a `mise run lint` grep that each agent with `skills:` and `Skill` denied says its skills are preloaded; `mise run lint` and `mise run test:step` must stay green.

## Risks & Considerations

- Prompt-only change; no report key or format changes, so `step.sh`, `tests/step` and the skills are untouched.
- The fix lowers but cannot prove away the skip; the companion issue (making `Analyze: ran` verifiable) covers detection.
- Keep `/feat`-only wording out of shared references (`harness.md` etc.) — not touched here.

## Open Questions

- Should a lint check enforce the preload sentence in every agent that has `skills:` and denies `Skill`? Recommended: no for this fix; the wording change suffices, a lint can follow if skips recur.
