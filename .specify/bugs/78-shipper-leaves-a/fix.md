# Bug Fix: Shipper leaves a Monitor running after its report

- **Slug**: 78-shipper-leaves-a
- **Fixed**: 2026-11-26
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

The shipper (step 4) and implementer (step 2) now say how to run a long check: foreground with a Bash timeout up to 600000 ms, else a background Bash command, never Monitor, and stop every background task before the report. Monitor is added to both agents' `disallowedTools`.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `.apm/agents/feat-shipper.agent.md` | modified | step 4 rule; `Monitor` in disallowedTools |
| `.apm/agents/feat-implementer.agent.md` | modified | step 2 rule; `Monitor` in disallowedTools |

## Tests Added or Updated

- none: per the user's answer Monitor is denied only in these two agents, so the `mise.toml` lint loop is not extended.

## Local Verification

- Commands run: `mise run lint` → pass; `mise run test:apm` → pass

## Deviations from Assessment

None.

## Follow-ups

- Claude Code's own re-wake on leftover Monitor events stays (reported upstream).
