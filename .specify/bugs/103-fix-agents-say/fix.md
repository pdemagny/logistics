# Bug Fix: Agents say their preloaded skills run without the Skill tool

- **Slug**: 103-fix-agents-say
- **Fixed**: 2026-11-26
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

feat-tasker, feat-specifier and feat-planner now say their `skills:` entries are preloaded and run by following their steps directly, with no Skill tool. The hooks sentence no longer reads as "Spec Kit commands can't run". The tasker's `Analyze: not run (<why>; …)` must name the real failure.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `.apm/agents/feat-tasker.agent.md` | modified | preload paragraph; `<why>` names command and error, never a choice to skip; hooks sentence reworded |
| `.apm/agents/feat-specifier.agent.md` | modified | preload paragraph; hooks sentence reworded |
| `.apm/agents/feat-planner.agent.md` | modified | preload paragraph; hooks sentence reworded |

## Tests Added or Updated

- None: prompt-only change, no report format change; no lint check (user answer).

## Local Verification

- `mise run lint` → pass
- `mise run test:step` → pass
- `mise run test:apm` → pass

## Deviations from Assessment

None.

## Follow-ups

- A lint for the preload sentence can follow if skips recur.
