# Bug Fix: Review merge turns a `- none` item into a finding the user must answer

- **Slug**: 73-review-none-finding
- **Fixed**: 2026-11-23
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

step.sh's parser now reads a list field written as a bare header plus one `- none` item (`- n/a` too for `A` fields) as `<Key>: none` with no item, so a review lens with nothing to report yields no finding and no hard gate. The code and design reviewers' format now says an empty section is `<Key>: none` on its header line.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `.apm/skills/feat/scripts/step.sh` | modified | `pclose`: for `L`, `A`, `W` fields with an empty header and exactly one item reading `none` (or `n/a` for `A`), set the header value to it, the item count to 0 and drop the item from `PI`. Applies to every caller (review merges, schema checks, other agents' lists). |
| `tests/step/run.sh` | modified | two cases: `design-dash-none` (phase 4) and `code-dash-none` (phase 7), each asserting stdout equals the all-`none` reports' and, at 7, no `finding:` line and no hard gate. |
| `tests/step/fixtures/agents/code-reviewer/7a+7b-dash-none.md` | added | Bugs, Spec and Security as a header plus `- none`. |
| `tests/step/fixtures/agents/design-reviewer/4a+4b+4c-dash-none.md` | added | `Findings:` plus `- none`. |
| `tests/step/expected/code-dash-none.{out,log}`, `design-dash-none.{out,log}` | added | goldens. |
| `.apm/agents/feat-code-reviewer.agent.md` | modified | one sentence: an empty section is `<Key>: none` on its header line, never a `- none` item. |
| `.apm/agents/feat-design-reviewer.agent.md` | modified | the same sentence. |

## Diff Highlights (optional)

```bash
  # a bare header and one `- none` item (`- n/a` for A) reads as `<Key>: none`
  if [[ -z $v ]] && (( n == 1 )); then
    case $t:${PI[${#PI[@]}-1]} in
      [LAW]:none | A:n/a)
        v=${PI[${#PI[@]}-1]} n=0
        PV[f]=$v PIN[f]=0
        PI=("${PI[@]:0:${#PI[@]}-1}") ;;
    esac
  fi
```

## Tests Added or Updated

- `tests/step/run.sh` case `code-dash-none` — a 7a+7b report with Bugs, Spec and Security as `- none` items merges to 0 findings, soft gate, same output as `7a+7b-zero`.
- `tests/step/run.sh` case `design-dash-none` — a design report with `Findings:` + `- none` gives the same output as `merge-zero`; the new fixture is also checked by the format loop ("every gate-row fixture parses").

## Local Verification

- Commands run: `UPDATE=1 bash tests/step/run.sh` → only the four new golden files written, no existing golden changed.
- `bash tests/step/run.sh` with step.sh reverted → fails (`design-reviewer/4a+4b+4c-dash-none.md: fmt.md: line 5 (Findings)`); restored → passes.
- `mise run lint` → pass; `mise run test:step` → pass (all cases); `mise run test:apm` → pass.

## Deviations from Assessment

None. A list mixing `- none` with real items is left as is (user's answer).

## Follow-ups

- The "write `none` for an empty field or section" wording is shared by every agent's format; the other agents were not tightened (out of scope, step.sh now tolerates the form for all of them).
