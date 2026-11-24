# Bug Fix: Code reviewer writes sections of lenses it was not given; parser and reformat name the wrong line

- **Slug**: 92-code-reviewer-writes
- **Fixed**: 2026-11-24
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

`parse()` now names a code-reviewer section of a lens outside the report's group as such (`line <n> (<Key>) — a section of a lens not given (<lens>)`) instead of blaming the open field, and the agent prompt tells the reviewer to omit other lenses' sections (with a `7a+7b` example) and, in reformat mode, to remove every section outside the spawn's `lenses:`. The parser stays fail-closed (user's answer at the assess gate).

## Changes

| File | Change | Notes |
|------|--------|-------|
| `.apm/skills/feat/scripts/step.sh` | modified | new `pstray()` (the code-reviewer keys of every lens, `net` mapped to 7d); `parse()` calls it for `code-reviewer` on a line that starts no field of the schema and reports it on that line |
| `.apm/agents/feat-code-reviewer.agent.md` | modified | report rule: omit the sections of lenses not given, `net:` included, never as `none`; a `7a+7b` example after the format block; reformat mode: remove every section outside `lenses:` |
| `tests/step/run.sh` | modified | the code reviewers' fail-closed loop gains `bad-stray-7c` and `bad-stray-net` |
| `tests/step/fixtures/agents/code-reviewer/bad-stray-7c.md` | added | the issue's report: a `7a+7b` report with 7c, 7d, `net:` and 7e sections as `none` |
| `tests/step/fixtures/agents/code-reviewer/bad-stray-net.md` | added | a `7a+7b` report with a stray `net:` line |
| `tests/step/expected/fmt-review-bad-stray-{7c,net}{,-hard}.{out,log}` | added | goldens: the reformat turn, then hard on a second slip |

## Diff Highlights (optional)

```bash
if [[ $2 == code-reviewer ]]; then
  pstray "$line" "${3-}"
  if [[ -n $SL ]]; then pbad "$n" "$SK" "$line" "a section of a lens not given ($SL)"; break; fi
fi
```

## Tests Added or Updated

- `tests/step/run.sh` "format: code reviewer bad-stray-7c" — gives `reformat` with `unparsable: 7-7a+7b.md: line 7 (Performance (7c)) — a section of a lens not given (7c)` and that line on `unparsable line:`; a second slip is hard.
- `tests/step/run.sh` "format: code reviewer bad-stray-net" — `unparsable: 7-7a+7b.md: line 7 (net) — a section of a lens not given (7d)`.
- Existing code-reviewer cases (including `/fix` 4's `4-7a+7b`, `bad-7c-slip`, the 7c+7d+7e ones and the every-fixture-parses check) stay green.

## Local Verification

- Commands run: `bash tests/step/run.sh` (`mise run test:step`) → all cases pass; `mise run lint` → exit 0 (shellcheck clean).
- Manual checks: reviewed the new goldens; the reason is fixed words and never quotes the line (`P_WHY` contract); `/tiny`'s Fresh review paragraph does not quote the report rule, so it is unchanged.

## Deviations from Assessment

None. The goldens were generated with `UPDATE=1`; only the eight new files were written.

## Follow-ups

- none
