#!/usr/bin/env bash
# Offline tests for .apm/skills/feat/scripts/state.sh (mise run test:state).
#
# Fixtures: frozen copies of real state files (feat-011-size-data,
# fix-10-agents-report-files, fix-22-secret-scan-blocks) and synthetic ones
# under fixtures/; golden outputs under expected/. `find` runs against
# throwaway repos and worktrees, with the stub tests/state/bin/gh first on
# PATH; nothing reaches GitHub. Every run checks that stderr is empty.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(cd "$here/../.." && pwd -P)"
script="$root/.apm/skills/feat/scripts/state.sh"
harness="$root/.apm/skills/feat/references/harness.md"
fx="$here/fixtures"
ex="$here/expected"

current="setup"
fail() {
  printf 'FAIL %s: %s\n' "$current" "$1"
  if [ -n "${out+x}" ]; then printf '  output: %s\n' "$out"; fi
  exit 1
}

work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'command rm -rf -- "$work"' EXIT

# Commits here must not depend on the user's git config (signing, hooks).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

gh_case="$work/gh-case"
mkdir -p "$gh_case"

new_case() {
  current="$1"
  unset out
}

# run <args>: runs the script in $in_dir (default $work); sets $out and $rc,
# checks stderr is empty.
run() {
  rc=0
  out="$(cd "${in_dir:-$work}" && PATH="$here/bin:$PATH" STATE_GH_CASE="$gh_case" \
    bash "$script" "$@" 2>"$work/stderr")" || rc=$?
  [ ! -s "$work/stderr" ] || fail "stderr not empty: $(head -n 1 "$work/stderr")"
}

expect_rc() { [ "$rc" = "$1" ] || fail "exit $rc, want $1"; }
expect_out() { [ "$out" = "$1" ] || fail "want output: $1"; }
expect_ok() { expect_rc 0; expect_out "$1"; }
expect_file() { [ "$out" = "$(cat "$1")" ] || fail "output differs from $1"; }
# expect_error <fragment>: exit 1, one state: error: line holding fragment.
expect_error() {
  expect_rc 1
  [ "$(printf '%s\n' "$out" | wc -l)" = 1 ] || fail "not one line"
  [[ "$out" == "state: error: "*"$1"* ]] || fail "want error with: $1"
}
# expect_usage: exit 2, one state: usage: line.
expect_usage() {
  expect_rc 2
  [ "$(printf '%s\n' "$out" | wc -l)" = 1 ] || fail "not one line"
  [[ "$out" == "state: usage: "* ]] || fail "want a usage line"
}
# same <a> <b>: the two files are byte for byte equal.
same() { cmp -s "$1" "$2" || fail "$1 changed"; }
last_line() { tail -n 1 "$1"; }
ok() { printf 'ok %s\n' "$current"; }

# copy <fixture> <name>: a writable copy of a fixture; prints nothing, sets $f.
copy() {
  mkdir -p "$work/c"
  f="$work/c/$2"
  command cp -f "$fx/$1" "$f"
}

# --- foundational ---------------------------------------------------------------

new_case "usage errors"
run
expect_usage
run bogus
expect_usage
run init
expect_usage
run init feat "$work/x/feat-state.md"
expect_usage
run init other "$work/x/feat-state.md" a
expect_usage
run init fix "$work/x/feat-state.md" title
expect_usage
run set "$fx/fix-cycles.md" Size
expect_usage
run log "$fx/fix-cycles.md"
expect_usage
run cycle
expect_usage
run cycle "$fx/fix-cycles.md" extra
expect_usage
run review-summary "$fx/fix-cycles.md"
expect_usage
run review-summary "$fx/fix-cycles.md" seven
expect_usage
run find
expect_usage
run find other
expect_usage
run find feat extra
expect_usage
run restore-phase
expect_usage
run report-path "$work/x/feat-state.md"
expect_usage
run inputs "$work/x/feat-state.md" "$work/x/reports/a.md"
expect_usage
run record "$work/x/feat-state.md"
expect_usage
run snapshot
expect_usage
run unchanged "$fx/fix-cycles.md"
expect_usage
run unchanged "$fx/fix-cycles.md" abc
expect_usage
run unchanged "$fx/fix-cycles.md" ABCDEF012345
expect_usage
ok

new_case "not a state file"
for q in cycle retry-used shipped-verdict phase2-mode refused-base; do
  run "$q" "$fx/not-state.md"
  expect_error "is not a state file"
  run "$q" "$work/missing.md"
  expect_error "is not a state file"
done
copy not-state.md ns.md
run set "$f" Size small
expect_error "is not a state file"
run log "$f" '- [x] a'
expect_error "is not a state file"
same "$fx/not-state.md" "$f"
ok

new_case "argument holding a newline or a carriage return"
copy fix-cycles.md nl.md
run log "$f" '- [x] fine' $'- [x] two\nlines'
expect_error "argument 3 holds a newline"
run log "$f" $'- [x] cr\r'
expect_error "argument 2 holds a newline"
run set "$f" title $'a\nb'
expect_error "argument 3 holds a newline"
run init fix "$work/nl/feat-state.md" t $'line one\nline two' Branch=b Size=small 'Current phase=1 Assess'
expect_error "argument 4 holds a newline"
same "$fx/fix-cycles.md" "$f"
[ ! -e "$work/nl" ] || fail "init created something"
ok

new_case "-- after the subcommand is dropped"
run cycle "$fx/fix-cycles.md"
a="$out"
run cycle -- "$fx/fix-cycles.md"
expect_ok "$a"
ok

new_case "bash 3.2 constructs only"
if grep -nE -- 'declare -A|mapfile|readarray|,,\}|\^\^\}|declare -n|local -n|\[\[ -v|\[-[0-9]+\]|;;&|\|&' "$script"; then
  fail "state.sh uses a construct bash 3.2 lacks"
fi
ok

# --- writes ---------------------------------------------------------------------

new_case "init feat: golden"
# shellcheck disable=SC2016
run init feat "$work/i1/specs/state-script/feat-state.md" "$fx/brief.md" \
  'Branch=state-script' 'Worktree=/tmp/wt/state-script' 'Size=small' 'Current phase=2 Specify' \
  'Conventions=conventional commits; it'\''s `type(scope)`' 'Issue=#27'
expect_ok ""
out="$(cat "$work/i1/specs/state-script/feat-state.md")"
expect_file "$ex/init-feat.md"
ok

new_case "init fix: golden, defaults"
# shellcheck disable=SC2016
run init fix "$work/i2/feat-state.md" "It's broken" 'it crashes; then $(nothing) runs' \
  'Branch=fix-1-x' 'Size=not set' 'Current phase=1 Assess' 'Agents=none (every spawn is fresh)'
expect_ok ""
out="$(cat "$work/i2/feat-state.md")"
expect_file "$ex/init-fix.md"
ok

new_case "init: header field names equal the harness template's"
names() {
  # field names of the `- <Field>: ` lines of a header, Worktree included
  sed -n "$2" "$1" | while IFS= read -r l; do
    case "$l" in
      '- '*': '*)
        n="${l#- }"
        printf '%s\n' "${n%%:*}"
        case "$l" in *' Worktree: '*) printf 'Worktree\n' ;; esac
        ;;
    esac
  done
}
tmpl="$(names "$harness" '/^```markdown$/,/^## /p')"
init_names="$(names "$work/i2/feat-state.md" '1,/^## /p')"
[ -n "$tmpl" ] || fail "no template in harness.md"
[ "$tmpl" = "$init_names" ] || fail "harness template fields: $(echo "$tmpl" | tr '\n' ,) init: $(echo "$init_names" | tr '\n' ,)"
ok

new_case "init refusals"
run init fix "$work/i2/feat-state.md" t r Branch=b Size=small 'Current phase=1 Assess'
expect_error "exists"
run init feat "$work/i3/feat-state.md" "$fx/fix-cycles.md" Branch=b Size=small 'Current phase=2 Specify'
expect_error "does not start with # Brief: <title>"
run init feat "$work/i3/feat-state.md" "$work/no-brief.md" Branch=b Size=small 'Current phase=2 Specify'
expect_error "cannot read"
run init fix "$work/i3/feat-state.md" t r Branch=b Size=small 'Current phase=1 Assess' 'Colour=red'
expect_usage
run init fix "$work/i3/feat-state.md" t r Branch=b Size=small 'Current phase=1 Assess' 'Issue'
expect_usage
run init fix "$work/i3/feat-state.md" t r Branch=b 'Current phase=1 Assess'
expect_error "Size"
run init fix "$work/i3/feat-state.md" t r Size=small 'Current phase=1 Assess'
expect_error "Branch"
run init fix "$work/i3/feat-state.md" t r Branch=b Size=small
expect_error "Current phase"
run init fix "$work/i3/feat-state.md" t r Branch=b Size=huge 'Current phase=1 Assess'
expect_error "Size must be"
[ ! -e "$work/i3" ] || fail "a refused init created something"
ok

new_case "set: one field, nothing else"
copy feat-old-normal.md set.md
for c in "Size|medium|- Size: medium" \
  "Current phase|5 Tasks|- Current phase: 5 Tasks" \
  "Agents|specifier a1, planner a2, tasker a3 (for SendMessage)|- Agents: specifier a1, planner a2, tasker a3 (for SendMessage)" \
  "Issue|owner/repo#12|- Issue: owner/repo#12" \
  "Conventions|it's \`x\`; \$(no)|- Conventions: it's \`x\`; \$(no)" \
  "Allowed Spec Kit hooks|after_implement: x|- Allowed Spec Kit hooks: after_implement: x" \
  "Map|specs/map.md cap-2|- Map: specs/map.md cap-2" \
  "Branch|renamed|- Branch: renamed Worktree: /tmp/nowhere/old-normal" \
  "Worktree|/tmp/other wt|- Branch: renamed Worktree: /tmp/other wt" \
  "title|a new title|# /feat state: a new title"; do
  fld="${c%%|*}" rest="${c#*|}"
  command cp -f "$f" "$work/before"
  run set "$f" "$fld" "${rest%%|*}"
  expect_ok ""
  grep -qxF -- "${rest#*|}" "$f" || fail "$fld: no line ${rest#*|}"
  [ "$(diff "$work/before" "$f" | grep -c '^[<>]')" = 2 ] || fail "$fld: more than one line changed"
done
grep -qxF -- '- Size: large — the brief'\''s own size line, never the header'\''s' "$f" || fail "the brief's Size line changed"
grep -qxF -- '- [x] 4 Design review — a brief line shaped like a Log line' "$f" || fail "the brief changed"
ok

new_case "set: a field missing from an older file is inserted"
copy no-log.md missing.md
run set "$f" Issue '#4'
expect_ok ""
[ "$(sed -n 6p "$f")" = "- Issue: #4" ] || fail "Issue not after the last field line"
[ "$(sed -n 5p "$f")" = "- Current phase: 1 Assess" ] || fail "header reordered"
run set "$f" Agents none
expect_ok ""
[ "$(sed -n 7p "$f")" = "- Agents: none" ] || fail "Agents not inserted"
[ "$(sed -n 9p "$f")" = "## Report" ] || fail "the input section moved"
ok

new_case "set: refusals"
copy fix-cycles.md setr.md
run set "$f" Size huge
expect_error "Size must be"
run set "$f" Colour red
expect_usage
run set "$f" Size 'not set'
expect_ok ""
grep -qxF -- '- Size: not set' "$f" || fail "not set refused"
ok

new_case "log: order, sub-lines, final newline"
copy fix-cycles.md log.md
command cp -f "$f" "$work/before"
run log "$f" '- [x] 3 Test — verified' '    - a sub-line' '    - another' '- [!] tracker: error: x' '- [ ] 4 Code review'
expect_ok ""
[ "$(diff "$work/before" "$f" | grep -c '^<')" = 0 ] || fail "an earlier line changed"
[ "$(tail -n 5 "$f")" = "$(printf '%s\n' '- [x] 3 Test — verified' '    - a sub-line' '    - another' '- [!] tracker: error: x' '- [ ] 4 Code review')" ] || fail "lines not appended in order"
run log "$f" '    - follows the open line'
expect_ok ""
last="$(last_line "$f")"
[ "$last" = '    - follows the open line' ] || fail "sub-line after the Log's last line refused"
printf '%s' '- [x] no final newline' >>"$f"
run log "$f" '- [x] next'
expect_ok ""
[ "$(tail -n 2 "$f")" = "$(printf '%s\n' '- [x] no final newline' '- [x] next')" ] || fail "missing final newline not added"
ok

new_case "log: refusals write nothing"
copy fix-cycles.md logr.md
command cp -f "$f" "$work/before"
run log "$f" '- [x] fine' 'not a log line'
expect_error "argument 3: not a Log line"
run log "$f" '- [x] fine' '- [x]'
expect_error "argument 3: not a Log line"
run log "$f" '- [y] x'
expect_error "argument 2: not a Log line"
run log "$f" '  - two spaces'
expect_error "argument 2: not a Log line"
same "$work/before" "$f"
run init fix "$work/l2/feat-state.md" t r Branch=b Size=small 'Current phase=1 Assess'
run log "$work/l2/feat-state.md" '    - first'
expect_error "argument 2: sub-line with no Log line before it"
copy no-log.md nolog.md
run log "$f" '- [x] a'
expect_error "has no ## Log"
same "$fx/no-log.md" "$f"
ok

new_case "log: quotes, \$(…), backticks and ; appended byte for byte"
copy fix-cycles.md inj.md
# The command as the coordinator writes it: every argument single-quoted,
# a ' inside written '\''.
# shellcheck disable=SC2016
line='- [x] 4 Code review — rejected S1 (user: "it'\''s fine; $(touch '"$work"'/pwned1) `touch '"$work"'/pwned2`")'
cmd="bash '$script' log '$f' '- [x] 4 Code review — rejected S1 (user: \"it'\\''s fine; \$(touch $work/pwned1) \`touch $work/pwned2\`\")'"
rc=0
out="$(bash -c "$cmd" 2>"$work/stderr")" || rc=$?
[ ! -s "$work/stderr" ] || fail "stderr not empty"
expect_ok ""
[ "$(last_line "$f")" = "$line" ] || fail "line not appended as is"
[ ! -e "$work/pwned1" ] && [ ! -e "$work/pwned2" ] || fail "something ran"
ok

new_case "writes refuse a symlinked state file"
mkdir -p "$work/sl"
command cp -f "$fx/fix-cycles.md" "$work/sl/target.md"
ln -s "$work/sl/target.md" "$work/sl/feat-state.md"
ln -s "$work/sl/absent.md" "$work/sl/dangling.md"
run init fix "$work/sl/dangling.md" t r Branch=b Size=small 'Current phase=1 Assess'
expect_error "$work/sl/dangling.md is a symlink"
[ ! -e "$work/sl/absent.md" ] || fail "init wrote through a dangling symlink"
run set "$work/sl/feat-state.md" Size large
expect_error "$work/sl/feat-state.md is a symlink"
run log "$work/sl/feat-state.md" '- [x] x'
expect_error "is a symlink"
run restore-phase "$work/sl/feat-state.md"
expect_error "is a symlink"
same "$fx/fix-cycles.md" "$work/sl/target.md"
[ -L "$work/sl/feat-state.md" ] || fail "the symlink was replaced"
ok

new_case "restore-phase"
rp="$work/rp"
git init -q -b main "$rp"
mkdir -p "$rp/specs/x"
command cp -f "$fx/feat-soft-review.md" "$rp/specs/x/feat-state.md"
git -C "$rp" add specs
git -C "$rp" commit -q -m state
run set "$rp/specs/x/feat-state.md" 'Current phase' 'done (PR #5)'
run log "$rp/specs/x/feat-state.md" '- [x] move — 1111111 → 2222222 (PR #5): checks pass; not verified: none'
command cp -f "$rp/specs/x/feat-state.md" "$work/before"
in_dir="$rp/specs" run restore-phase x/feat-state.md
expect_ok ""
grep -qxF -- '- Current phase: 8 Ship' "$rp/specs/x/feat-state.md" || fail "phase not restored"
[ "$(diff "$work/before" "$rp/specs/x/feat-state.md" | grep -c '^[<>]')" = 2 ] || fail "more than the phase changed"
command cp -f "$rp/specs/x/feat-state.md" "$work/before"
run restore-phase "$rp/specs/x/feat-state.md"
expect_ok ""
same "$work/before" "$rp/specs/x/feat-state.md"
command cp -f "$fx/fix-cycles.md" "$rp/specs/x/new.md"
run restore-phase "$rp/specs/x/new.md"
expect_error "is not in HEAD"
printf '# /fix state: no phase\n\n## Log\n' >"$rp/specs/x/odd.md"
git -C "$rp" add specs/x/odd.md
git -C "$rp" commit -q -m odd
run restore-phase "$rp/specs/x/odd.md"
expect_error "has no Current phase: line"
mkdir -p "$work/nogit"
command cp -f "$fx/fix-cycles.md" "$work/nogit/feat-state.md"
run restore-phase "$work/nogit/feat-state.md"
expect_error "not in a git repo"
ok

# --- queries --------------------------------------------------------------------

new_case "cycle and retry-used"
for c in "fix-10-agents-report-files.md|after review fixes|no" \
  "fix-22-secret-scan-blocks.md|after review fixes|no" \
  "fix-cycles.md|retry|yes" \
  "fix-retry-before-back.md|first|no" \
  "fix-testmd/feat-state.md|first|no" \
  "feat-011-size-data.md|first|no"; do
  file="${c%%|*}" rest="${c#*|}"
  run cycle "$fx/$file"
  expect_ok "${rest%%|*}"
  run retry-used "$fx/$file"
  expect_ok "${rest#*|}"
done
ok

new_case "shipped-verdict from each source"
run shipped-verdict "$fx/fix-10-agents-report-files.md"
expect_ok 'partial — ship with partial (user: "go on")'
run shipped-verdict "$fx/fix-22-secret-scan-blocks.md"
expect_ok "verified"
run shipped-verdict "$fx/fix-cycles.md"
expect_ok "failed"
run shipped-verdict "$fx/fix-retry-before-back.md"
expect_ok "partial"
run shipped-verdict "$fx/fix-testmd/feat-state.md"
expect_ok "verified (test.md)"
run shipped-verdict "$fx/feat-011-size-data.md"
expect_ok "none"
ok

new_case "phase2-mode"
for c in "feat-011-size-data.md|soft 4 closed" \
  "feat-old-normal.md|soft 4 open" \
  "feat-old-big.md|soft 3 closed" \
  "feat-soft-review.md|hard" \
  "fix-cycles.md|none"; do
  run phase2-mode "$fx/${c%%|*}"
  expect_ok "${c#*|}"
done
copy feat-old-big.md p2.md
printf '%s\n' '- [x] back to 2 — reworded' '- [x] 2 Specify — soft' >>"$f"
run phase2-mode "$f"
expect_ok "soft 3 open"
printf '%s\n' '- [x] 2 Specify — softly worded, neither word' >>"$f"
run phase2-mode "$f"
expect_ok "hard"
printf '%s\n' '- [!] 2 Specify — soft' >>"$f"
run set "$f" Size large
run phase2-mode "$f"
expect_ok "soft 3 open"
run set "$f" Size 'not set'
run phase2-mode "$f"
expect_error "no valid Size: line"
ok

new_case "refused-base"
run refused-base "$fx/feat-011-size-data.md"
expect_ok ""
copy feat-soft-review.md rb.md
sed '$d' "$fx/feat-soft-review.md" | sed '$d' >"$f"
run refused-base "$f"
expect_ok "0123456789abcdef0123"
run refused-base "$fx/feat-soft-review.md"
expect_ok ""
printf '%s\n' '- [x] move — stayed on 3333333, refused ABCDEF1 (user: "x")' >>"$f"
run refused-base "$f"
expect_ok ""
printf '%s\n' '- [x] move — stayed on 3333333, refused abc12 (user: "x")' >>"$f"
run refused-base "$f"
expect_ok ""
printf '%s\n' '- [x] move — stayed on 4444444, refused abcdef1234567 (user: "x")' '- [x] move — 4444444 → 5555555 (before 7 Code review): checks pass' >>"$f"
run refused-base "$f"
expect_ok "abcdef1234567"
ok

new_case "review-summary: golden outputs"
for c in "feat-011-size-data.md|7|rs-feat-011.txt" \
  "feat-soft-review.md|7|rs-feat-soft-review.txt" \
  "feat-old-big.md|7|rs-feat-old-big.txt" \
  "fix-10-agents-report-files.md|4|rs-fix-10.txt" \
  "fix-22-secret-scan-blocks.md|4|rs-fix-22.txt"; do
  file="${c%%|*}" rest="${c#*|}"
  run review-summary "$fx/$file" "${rest%%|*}"
  expect_rc 0
  expect_file "$ex/${rest#*|}"
done
ok

new_case "review-summary: groups, prefixes, none picked"
copy feat-old-big.md rs.md
printf '%s\n' '- [x] back to 7 — again' \
  '- [x] 7 Code review — hard gate: none picked; rejected B5 (user: "leave it, it'\''s fine"), C2 (as recommended)' \
  '    - B5 a.sh:1 — x — rec: user (why)' \
  '    - C2 b.sh:2 — y — rec: skip (churn)' >>"$f"
run review-summary "$f" 7
expect_rc 0
expect_out "$(printf '%s\n' "**Applied without asking (reviewer's recommendation)**" '- none' '**Picked by the user**' '- none' \
  '**Not applied**' '- B5 a.sh:1 — x — rejected (user: "leave it, it'\''s fine")' '- C2 b.sh:2 — y — rejected (as recommended)')"
printf '%s\n' '- [x] 7 Code review — ship go-ahead (user: "ok")' >>"$f"
run review-summary "$f" 7
[ "$(printf '%s\n' "$out" | tail -n 1)" = '**Ship go-ahead**: (user: "ok")' ] || fail "no go-ahead line"
run review-summary "$f" 4
expect_ok "Code review was skipped."
ok

new_case "review-summary: a performance number with no command stops at its segment"
copy feat-old-big.md rsp.md
printf '%s\n' '- [x] back to 7 — again' \
  '- [x] 7 Code review — hard gate: picked P1, P2' \
  '    - P1 f:2 — slow — rec: fix (hot loop)' \
  '    - P2 g:3 — slower — rec: fix (alloc)' \
  '- [x] 7 review fixes — P1 → applied, P2 → applied; performance: P1: 10ms → 5ms, P2: 8ms → 2ms; checks: lint ok — not verified: none' >>"$f"
run review-summary "$f" 7
expect_rc 0
expect_out "$(printf '%s\n' "**Applied without asking (reviewer's recommendation)**" '- none' '**Picked by the user**' \
  '- P1 f:2 — slow — 10ms → 5ms' '- P2 g:3 — slower — 8ms → 2ms' '**Not applied**' '- none')"
ok

new_case "review-summary: skipped review, no ## Log"
run review-summary "$fx/feat-old-normal.md" 7
expect_ok "Code review was skipped."
run review-summary "$fx/no-log.md" 4
expect_error "has no ## Log"
ok

# --- tagged gate lines (step.sh's Log lines) -----------------------------------

# Each tagged-*.md is a copy of an untagged fixture written the way step.sh
# writes: tagged gate lines, answer: and outcome: sub-lines, wrote: facts.
# Every query must answer on the copy as on the original.
tagged_pairs=(
  "feat-011-size-data.md|tagged-feat-011.md|7"
  "feat-old-big.md|tagged-feat-old-big.md|7"
  "feat-old-normal.md|tagged-feat-old-normal.md|7"
  "feat-soft-review.md|tagged-feat-soft-review.md|7"
  "fix-10-agents-report-files.md|tagged-fix-10.md|4"
  "fix-22-secret-scan-blocks.md|tagged-fix-22.md|4"
  "fix-cycles.md|tagged-fix-cycles.md|4"
  "fix-retry-before-back.md|tagged-fix-retry-before-back.md|4"
)

new_case "tagged copies: every query answers as on the original"
for c in "${tagged_pairs[@]}"; do
  orig="${c%%|*}" rest="${c#*|}"
  tagged="${rest%%|*}" phase="${rest#*|}"
  for q in phase2-mode cycle retry-used shipped-verdict refused-base; do
    run "$q" "$fx/$orig"
    want_rc="$rc" want="$out"
    run "$q" "$fx/$tagged"
    if [ "$rc" != "$want_rc" ] || [ "$out" != "$want" ]; then
      fail "$q on $tagged: '$out', want '$want' (as $orig)"
    fi
  done
  run review-summary "$fx/$orig" "$phase"
  want="$out"
  run review-summary "$fx/$tagged" "$phase"
  expect_rc 0
  [ "$out" = "$want" ] || fail "review-summary on $tagged differs from $orig"
done
ok

new_case "tagged: a soft phase 2 with an override: hard sub-line reads hard"
copy tagged-feat-old-normal.md ov.md
run phase2-mode "$f"
expect_ok "soft 4 open"
sed '/^    - Requirements: 3 FRs$/a\
    - override: hard — the user wants to read the spec' "$fx/tagged-feat-old-normal.md" >"$f"
run phase2-mode "$f"
expect_ok "hard"
ok

new_case "tagged: an override after a record that follows the soft gate still reads hard"
copy tagged-feat-old-normal.md ov2.md
sed '/^    - Requirements: 3 FRs$/a\
- [x] size medium — was normal (user)\
    - override: hard — the user wants to read the spec' "$fx/tagged-feat-old-normal.md" >"$f"
run phase2-mode "$f"
expect_ok "hard"
ok

new_case "tagged: gate G passes when answered, not when the answer is stop"
copy tagged-feat-old-normal.md g.md
printf '%s\n' '    - answer: stop (user: "later")' >>"$f"
run phase2-mode "$f"
expect_ok "soft 4 open"
copy tagged-feat-old-normal.md g.md
printf '%s\n' '- [!] step: step: error: boom' '    - answer: approved (user: "ok")' >>"$f"
run phase2-mode "$f"
expect_ok "soft 4 closed"
copy tagged-feat-old-normal.md g.md
printf '%s\n' '- [x] 4 Design review [soft] — auto-applied D1' >>"$f"
run phase2-mode "$f"
expect_ok "soft 4 closed"
copy tagged-feat-old-normal.md g.md
printf '%s\n' '- [!] 2 Specify — unparsable: 2-specify-2.md: line 4 (Stories); reformat 1 of 1' >>"$f"
run phase2-mode "$f"
expect_ok "soft 4 open"
ok

new_case "tagged: dropped ids left out, wrote: and answer: sub-lines are no findings"
copy tagged-feat-old-big.md dr.md
printf '%s\n' '- [x] back to 7 — again' \
  '- [x] 7 Code review [hard] — 3 findings to pick' \
  '    - P1 f.sh:2 — slow — rec: apply' \
  '    - C1 f.sh:2 — cut the loop — rec: apply' \
  '    - R1 g.sh:3 — rename — rec: apply' \
  '    - dropped: P1 (cut by C1)' \
  '    - wrote: f.sh' \
  '    - override: hard — want to see it' \
  '- [!] step: step: error: boom' \
  '    - answer: picked C1, R1 (user: "ok")' \
  '    - outcome: picked P1, C1, R1' >>"$f"
run review-summary "$f" 7
expect_rc 0
expect_file "$ex/rs-tagged-dropped.txt"
ok

new_case "tagged: answer: ship with partial is the shipped verdict"
copy tagged-fix-retry-before-back.md sw.md
# shellcheck disable=SC2016 # the words are literal on purpose
printf '%s\n' '    - answer: ship with partial (user: "it'\''s fine; $(x) `y`")' >>"$f"
run shipped-verdict "$f"
# shellcheck disable=SC2016 # the words are literal on purpose
expect_ok 'partial — ship with partial (user: "it'\''s fine; $(x) `y`")'
printf '%s\n' '- [x] back to 2 — redo' >>"$f"
run shipped-verdict "$f"
expect_ok 'none'
ok

# --- report files ---------------------------------------------------------------

new_case "report-path: first use, numbering, never an existing path"
rd="$work/rpath/specs/x"
mkdir -p "$rd"
run report-path "$rd/feat-state.md" 3-test
expect_ok "$rd/reports/3-test.md"
[ "$(cat "$rd/reports/.gitignore")" = '*' ] || fail ".gitignore does not hold *"
[ ! -e "$rd/reports/3-test.md" ] || fail "report-path created the report file"
run report-path "$rd/feat-state.md" 3-test
expect_ok "$rd/reports/3-test.md"
touch "$rd/reports/3-test.md"
run report-path "$rd/feat-state.md" 3-test
expect_ok "$rd/reports/3-test-2.md"
touch "$rd/reports/3-test-2.md"
run report-path "$rd/feat-state.md" 3-test
expect_ok "$rd/reports/3-test-3.md"
printf 'kept\n' >"$rd/reports/.gitignore"
run report-path "$rd/feat-state.md" 7-7a+7b
expect_ok "$rd/reports/7-7a+7b.md"
[ "$(cat "$rd/reports/.gitignore")" = '*' ] || fail ".gitignore not holding * left as is"
: >"$rd/reports/.gitignore"
run report-path "$rd/feat-state.md" 7-7a+7b
expect_ok "$rd/reports/7-7a+7b.md"
[ "$(cat "$rd/reports/.gitignore")" = '*' ] || fail "empty .gitignore left as is"
in_dir="$rd" run report-path feat-state.md 6-US2
expect_ok "$rd/reports/6-US2.md"
ok

new_case "report-path: bad keys, no dir, unsafe dir"
for k in '' '-x' 'a b' 'a/b' '../x' '.x' 'a.md' "$(printf 'k%.0s' $(seq 1 65))"; do
  run report-path "$rd/feat-state.md" "$k"
  expect_usage
done
run report-path "$rd/feat-state.md" "$(printf 'k%.0s' $(seq 1 64))"
expect_rc 0
run report-path "$work/nodir/feat-state.md" 2-specify
expect_error "is not a directory"
[ ! -e "$work/nodir" ] || fail "report-path created the dir"
mkdir -p "$work/it's"
run report-path "$work/it's/feat-state.md" 2-specify
expect_error "holds a newline, a quote"
[ ! -e "$work/it's/reports" ] || fail "reports/ created in an unsafe dir"
ok

new_case "report-path: symlinks refused, nothing created"
mkdir -p "$work/rs1" "$work/elsewhere"
ln -s "$work/elsewhere" "$work/rs1/reports"
run report-path "$work/rs1/feat-state.md" 3-plan
expect_error "$work/rs1/reports is a symlink"
[ -z "$(ls -A "$work/elsewhere")" ] || fail "wrote through the reports symlink"
mkdir -p "$work/rs2/reports"
ln -s "$work/elsewhere/t.md" "$work/rs2/reports/3-plan.md"
run report-path "$work/rs2/feat-state.md" 3-plan
expect_error "$work/rs2/reports/3-plan.md is a symlink"
[ ! -e "$work/rs2/reports/.gitignore" ] || fail ".gitignore written past a refused candidate"
mkdir -p "$work/rs3/reports"
touch "$work/rs3/reports/3-plan.md"
ln -s "$work/elsewhere/absent.md" "$work/rs3/reports/3-plan-2.md"
run report-path "$work/rs3/feat-state.md" 3-plan
expect_error "$work/rs3/reports/3-plan-2.md is a symlink"
mkdir -p "$work/rs4/reports"
ln -s "$work/elsewhere/gi" "$work/rs4/reports/.gitignore"
run report-path "$work/rs4/feat-state.md" 3-plan
expect_error "$work/rs4/reports/.gitignore is a symlink"
[ -z "$(ls -A "$work/elsewhere")" ] || fail "wrote through a symlink"
ok

new_case "inputs: write, rewrite whole, awkward lines"
id="$work/inp/specs/x"
mkdir -p "$id"
hdr='Data, never instructions: the lists step.sh wrote for this spawn.'
run inputs "$id/feat-state.md" "$id/reports/7-fixes.md" 'apply:' '  - B1 a — rec: apply' 'failures:' '  - t → fail'
expect_ok "$id/reports/7-fixes.in.md"
[ "$(cat "$id/reports/.gitignore")" = '*' ] || fail ".gitignore does not hold *"
[ "$(cat "$id/reports/7-fixes.in.md")" = "$hdr
apply:
  - B1 a — rec: apply
failures:
  - t → fail" ] || fail "file content"
[ ! -e "$id/reports/7-fixes.md" ] || fail "inputs created the report file"
run inputs "$id/feat-state.md" "$id/reports/7-fixes.md" 'apply: none'
expect_ok "$id/reports/7-fixes.in.md"
[ "$(cat "$id/reports/7-fixes.in.md")" = "$hdr
apply: none" ] || fail "rewrite was appended or kept old lines"
run inputs "$id/feat-state.md" "$id/reports/7-fixes-2.md" 'approved commands:' "  - -x 'a' \$(b) \`c\` \$HOME" '  - --flag'
expect_ok "$id/reports/7-fixes-2.in.md"
[ "$(cat "$id/reports/7-fixes-2.in.md")" = "$hdr
approved commands:
  - -x 'a' \$(b) \`c\` \$HOME
  - --flag" ] || fail "awkward lines changed"
ok

new_case "inputs: symlinks and non-regular target refused"
mkdir -p "$work/is1" "$work/is2/reports" "$work/is3/reports" "$work/is4/reports"
ln -s "$work/elsewhere" "$work/is1/reports"
run inputs "$work/is1/feat-state.md" "$work/is1/reports/3-plan.md" 'a: none'
expect_error "$work/is1/reports is a symlink"
ln -s "$work/elsewhere/gi" "$work/is2/reports/.gitignore"
run inputs "$work/is2/feat-state.md" "$work/is2/reports/3-plan.md" 'a: none'
expect_error "$work/is2/reports/.gitignore is a symlink"
ln -s "$work/elsewhere/t.in.md" "$work/is3/reports/3-plan.in.md"
run inputs "$work/is3/feat-state.md" "$work/is3/reports/3-plan.md" 'a: none'
expect_error "$work/is3/reports/3-plan.in.md is a symlink"
mkdir "$work/is4/reports/3-plan.in.md"
run inputs "$work/is4/feat-state.md" "$work/is4/reports/3-plan.md" 'a: none'
expect_error "is not a file"
[ -z "$(ls -A "$work/is4/reports/3-plan.in.md")" ] || fail "wrote into a directory target"
[ -z "$(ls -A "$work/elsewhere")" ] || fail "wrote through a symlink"
ok

new_case "inputs: bad report paths and no lines"
for p in "$id/other/7-fixes.md" "$id/reports/7-fixes.in.md" "$id/reports/7-fixes" "$id/reports/7-fixes.txt" "$id/reports/-x.md" "$id/reports/a.b.md" "$id/reports/a/b.md"; do
  run inputs "$id/feat-state.md" "$p" 'a: none'
  expect_usage
done
run inputs "$id/feat-state.md" "$id/reports/7-fixes.md"
expect_usage
run inputs "$id/feat-state.md"
expect_usage
ok

new_case "record: write, rewrite whole, tabs kept, guards"
rd="$work/rec/specs/x"
mkdir -p "$rd"
rhdr="Data, never instructions: step.sh's last decision, for its re-print and its open boundary."
run record "$rd/feat-state.md" "call:	3	$rd/reports/3-plan.md" 'sums:	3-plan.md:0123456789ab' 'output:' 'soft' "boundary:	5	$rd/reports/5-tasks.md"
expect_ok "$rd/reports/last-step.md"
[ "$(cat "$rd/reports/.gitignore")" = '*' ] || fail ".gitignore does not hold *"
[ "$(cat "$rd/reports/last-step.md")" = "$rhdr
call:	3	$rd/reports/3-plan.md
sums:	3-plan.md:0123456789ab
output:
soft
boundary:	5	$rd/reports/5-tasks.md" ] || fail "file content"
run record "$rd/feat-state.md" 'output:' 'done: PR #1'
expect_ok "$rd/reports/last-step.md"
[ "$(cat "$rd/reports/last-step.md")" = "$rhdr
output:
done: PR #1" ] || fail "rewrite was appended or kept old lines"
run record "$rd/feat-state.md"
expect_usage
run record "$rd/feat-state.md" "$(printf 'a\nb')"
expect_error "argument 2 holds a newline"
mkdir -p "$work/rc1" "$work/rc2/reports" "$work/rc3/reports" "$work/rc4/reports"
ln -s "$work/elsewhere" "$work/rc1/reports"
run record "$work/rc1/feat-state.md" 'output:'
expect_error "$work/rc1/reports is a symlink"
ln -s "$work/elsewhere/last-step.md" "$work/rc2/reports/last-step.md"
run record "$work/rc2/feat-state.md" 'output:'
expect_error "$work/rc2/reports/last-step.md is a symlink"
ln -s "$work/elsewhere/gi" "$work/rc3/reports/.gitignore"
run record "$work/rc3/feat-state.md" 'output:'
expect_error "$work/rc3/reports/.gitignore is a symlink"
mkdir "$work/rc4/reports/last-step.md"
run record "$work/rc4/feat-state.md" 'output:'
expect_error "is not a file"
[ -z "$(ls -A "$work/rc4/reports/last-step.md")" ] || fail "wrote into a directory target"
[ -z "$(ls -A "$work/elsewhere")" ] || fail "wrote through a symlink"
ok

# a scratch repo for snapshot/unchanged: a committed state file, three
# tracked files (a.txt already modified), an ignored *.log
sn="$work/snap"
git init -q -b main "$sn"
mkdir -p "$sn/specs/x"
command cp -f "$fx/feat-soft-review.md" "$sn/specs/x/feat-state.md"
printf '*.log\n' >"$sn/.gitignore"
for p in a b c; do printf '%s\n' "$p" >"$sn/$p.txt"; done
git -C "$sn" add -A
git -C "$sn" commit -q -m init
printf 'a, modified\n' >"$sn/a.txt"
printf 'untracked before\n' >"$sn/u.txt"
sf="$sn/specs/x/feat-state.md"
# snap: takes a snapshot, sets $tok
snap() {
  run snapshot "$sf"
  expect_rc 0
  [[ "$out" =~ ^[0-9a-f]{12}$ ]] || fail "not a 12-hex token"
  [ -f "$sn/.git/logistics/snapshots/$out" ] || fail "no manifest saved"
  tok="$out"
}

new_case "unchanged: no change, reports/, ignored files, same content, git add -N"
snap
run unchanged "$sf" "$tok"
expect_ok "unchanged"
[ ! -e "$sn/.git/logistics/snapshots/$tok" ] || fail "manifest left behind"
run report-path "$sf" 7-7b
snap
mkdir -p "$sn/specs/x/reports"
printf 'a report\n' >"$sn/specs/x/reports/7-7a.md"
printf 'a report\n' >"$sn/specs/x/reports/7-7b.md"
printf 'noise\n' >"$sn/build.log"
printf 'a, modified\n' >"$sn/a.txt"
git -C "$sn" add -N u.txt
run unchanged "$sf" "$tok"
expect_ok "unchanged"
git -C "$sn" status --porcelain | grep -q 'reports' && fail "reports/ does not ignore itself"
# reports/ is left out even when its .gitignore is gone
command mv -f "$sn/specs/x/reports/.gitignore" "$work/gi-saved"
snap
printf 'another\n' >"$sn/specs/x/reports/7-7c.md"
run unchanged "$sf" "$tok"
expect_ok "unchanged"
command mv -f "$work/gi-saved" "$sn/specs/x/reports/.gitignore"
ok

new_case "unchanged: edit to a modified file, new file, deleted file"
snap
printf 'a, modified again\n' >"$sn/a.txt"
run unchanged "$sf" "$tok"
expect_ok "$(printf '%s\n' changed '- a.txt')"
snap
printf 'new\n' >"$sn/n.txt"
run unchanged "$sf" "$tok"
expect_ok "$(printf '%s\n' changed '- n.txt')"
snap
command rm -f "$sn/b.txt"
printf 'x\n' >"$sn/c.txt"
run unchanged "$sf" "$tok"
expect_ok "$(printf '%s\n' changed '- b.txt' '- c.txt')"
[ ! -e "$sn/.git/logistics/snapshots/$tok" ] || fail "manifest left behind"
# the state file is left out: the coordinator logs to it mid-batch
snap
run log "$sf" '- [x] tracker: #73 set to "In review"'
run unchanged "$sf" "$tok"
expect_ok "unchanged"
snap
run set "$sf" Size large
printf 'beside\n' >"$sn/d.txt"
run unchanged "$sf" "$tok"
expect_ok "$(printf '%s\n' changed '- d.txt')"
snap
printf 'odd\n' >"$sn/odd"$'\t'"name"
run unchanged "$sf" "$tok"
expect_ok "$(printf '%s\n' changed '- odd?name')"
ok

new_case "unchanged: at most 10 paths, then a count; no manifest"
snap
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do printf '%s\n' "$i" >"$sn/f$i.txt"; done
run unchanged "$sf" "$tok"
expect_rc 0
[ "$(printf '%s\n' "$out" | wc -l)" = 12 ] || fail "not changed + 10 paths + a count"
[ "$(printf '%s\n' "$out" | sed -n 2p)" = '- f01.txt' ] || fail "paths not sorted"
[ "$(printf '%s\n' "$out" | sed -n 11p)" = '- f10.txt' ] || fail "not 10 paths"
[ "$(printf '%s\n' "$out" | tail -n 1)" = '- and 2 more' ] || fail "no count line"
run unchanged "$sf" 000000000000
expect_ok "$(printf '%s\n' changed '- paths unknown (no manifest for 000000000000); see git status')"
mkdir -p "$work/nogit2"
command cp -f "$fx/fix-cycles.md" "$work/nogit2/feat-state.md"
run snapshot "$work/nogit2/feat-state.md"
expect_error "not in a git repo"
run snapshot "$fx/not-state.md"
expect_error "is not a state file"
ok

# --- find -----------------------------------------------------------------------

# mkstate <path> <skill> <branch> <phase or "-" for none>
mkstate() {
  mkdir -p "$(dirname "$1")"
  {
    printf '# /%s state: %s\n\n' "$2" "$3"
    printf -- '- Branch: %s Worktree: none\n- Size: small\n' "$3"
    if [ "$4" != - ]; then printf -- '- Current phase: %s\n' "$4"; fi
    printf '\n## Log\n\n- [x] 0 Setup — ok\n'
  } >"$1"
}
stamp=10
# age <file>: each call makes the file newer than the previous one
age() { stamp=$((stamp + 1)); touch -t "2026010101$stamp" "$1"; }

fd="$work/find"
mkdir -p "$fd"
git init -q -b main "$fd/origin"
git -C "$fd/origin" commit -q --allow-empty -m init
git clone -q "$fd/origin" "$fd/repo"
repo="$fd/repo"
for b in b c d e f g h q; do
  git -C "$repo" worktree add -q -b "$b" "$fd/wt-$b"
done
git -C "$repo" worktree add -q -b qq "$fd/it's"
git -C "$repo" push -q -u origin d 2>/dev/null
mkstate "$repo/specs/main-run/feat-state.md" feat open-a '3 Plan'
mkstate "$fd/wt-b/specs/b/feat-state.md" feat b '6 Implement'
mkstate "$fd/wt-c/specs/c/feat-state.md" feat c 'done (shipping)'
mkstate "$fd/wt-d/specs/d/feat-state.md" feat d 'done (shipping)'
mkstate "$fd/wt-e/specs/e/feat-state.md" feat e 'done (PR #3)'
mkstate "$fd/wt-f/specs/f/feat-state.md" feat f '5 Tasks'
mkstate "$fd/wt-g/specs/g/feat-state.md" feat g '7 Code review'
mkstate "$fd/wt-h/specs/h/feat-state.md" feat h '4 Design review'
mkstate "$repo/specs/gone/feat-state.md" feat gone 'done (shipping)'
mkstate "$repo/specs/bad/feat-state.md" feat 'bad..name' '2 Specify'
mkstate "$repo/specs/nophase/feat-state.md" feat np -
mkstate "$fd/it's/specs/q/feat-state.md" feat qq '3 Plan'
mkdir -p "$repo/specs/junk"
printf 'hello\n' >"$repo/specs/junk/feat-state.md"
mkstate "$fd/wt-q/.specify/bugs/9-x/feat-state.md" fix fix-9-x '2 Fix'
mkstate "$fd/wt-q/.specify/bugs/8-y/feat-state.md" fix fix-8-y 'done (not a bug)'
printf 'MERGED\n' >"$gh_case/pr-f"
printf 'CLOSED\nOPEN\n' >"$gh_case/pr-g"
touch "$gh_case/fail-h"
for s in "$fd/wt-h/specs/h" "$repo/specs/bad" "$fd/wt-c/specs/c" "$repo/specs/nophase" \
  "$fd/wt-g/specs/g" "$repo/specs/main-run" "$fd/wt-b/specs/b"; do
  age "$s/feat-state.md"
done

new_case "find feat: done marker, shipping, shipped, gh failure, unsafe path"
: >"$gh_case/calls"
in_dir="$repo" run find feat
expect_ok "$(printf '%s\n' \
  "$fd/wt-b/specs/b/feat-state.md $fd/wt-b 6 Implement" \
  "$repo/specs/main-run/feat-state.md $repo 3 Plan" \
  "$fd/wt-g/specs/g/feat-state.md $fd/wt-g 7 Code review" \
  "$repo/specs/nophase/feat-state.md $repo none" \
  "$fd/wt-c/specs/c/feat-state.md $fd/wt-c done (shipping)" \
  "$repo/specs/bad/feat-state.md $repo 2 Specify" \
  "$fd/wt-h/specs/h/feat-state.md $fd/wt-h 4 Design review")"
for b in d e gone bad..name qq; do
  ! grep -q -- "--head $b " "$gh_case/calls" || fail "gh called for $b"
done
grep -q -- "--head f " "$gh_case/calls" || fail "gh not called for f"
ok

new_case "find feat from a worktree, find fix"
in_dir="$fd/wt-g" run find feat
[ "$(printf '%s\n' "$out" | wc -l)" = 7 ] || fail "not the same runs from a worktree"
in_dir="$fd/wt-b/specs" run find fix
expect_ok "$fd/wt-q/.specify/bugs/9-x/feat-state.md $fd/wt-q 2 Fix"
ok

new_case "find: no run, not a repo"
git init -q -b main "$fd/empty"
in_dir="$fd/empty" run find feat
expect_ok ""
in_dir="$fd/empty" run find fix
expect_ok ""
mkdir -p "$work/plain"
in_dir="$work/plain" run find feat
expect_error "not in a git repo"
ok

# rebase: branches on origin, each adding what its case needs
rb="$fd/rb-repo"
git clone -q "$fd/origin" "$rb"
# rbranch <branch> <path>...: a branch adding these files (each from $content), pushed
content=""
rbranch() {
  local b="$1" p
  shift
  git -C "$rb" checkout -q -b "$b" main
  for p in "$@"; do
    mkdir -p "$(dirname "$rb/$p")"
    printf '%s\n' "$content" >"$rb/$p"
    git -C "$rb" add -- "$p"
  done
  git -C "$rb" commit -q --allow-empty -m "$b"
  git -C "$rb" push -q origin "$b" 2>/dev/null
  git -C "$rb" checkout -q main
}
hdr() { printf '# /%s state: t\n\n- Branch: x Worktree: none\n- Size: %s\n- Current phase: %s\n\n## Log\n' "$1" "$2" "$3"; }
content="$(hdr feat normal 'done (shipping)')" rbranch r-ok specs/r-ok/feat-state.md
content="$(hdr feat small '8 Ship')" rbranch r-wt specs/r-wt/feat-state.md
content="x" rbranch r-none docs/x.md
content="$(hdr feat small '8 Ship')" rbranch r-two specs/a/feat-state.md specs/b/feat-state.md
content="$(hdr feat small '8 Ship')" rbranch r-deep specs/a/b/feat-state.md
content="$(hdr feat huge '8 Ship')" rbranch r-size specs/r-size/feat-state.md
content="$(hdr fix small '3 Test')" rbranch fix-open .specify/bugs/s1/feat-state.md
content="$(hdr fix big 'done (shipping)')" rbranch fix-done .specify/bugs/s2/feat-state.md
git -C "$rb" worktree add -q "$fd/wt-r-wt" r-wt

new_case "find rebase: each result"
for c in "feat r-ok|specs/r-ok/feat-state.md none medium done (shipping)" \
  "feat r-wt|specs/r-wt/feat-state.md $fd/wt-r-wt small 8 Ship" \
  "feat r-none|skip: no state file" \
  "feat r-two|skip: several state files" \
  "feat r-deep|skip: unexpected state-file path" \
  "feat r-size|skip: no valid size" \
  "fix fix-open|skip: not shipped" \
  "fix fix-done|.specify/bugs/s2/feat-state.md none large done (shipping)" \
  "fix r-ok|skip: no state file"; do
  args="${c%%|*}"
  in_dir="$rb" run find rebase "${args%% *}" main "${args#* }"
  expect_ok "${c#*|}"
done
ok

new_case "find rebase: fetch failure, bad arguments"
in_dir="$rb" run find rebase feat main no-such-branch
expect_error "git fetch failed"
in_dir="$rb" run find rebase feat main -x
expect_usage
in_dir="$rb" run find rebase feat 'ma in' r-ok
expect_usage
in_dir="$rb" run find rebase other main r-ok
expect_usage
in_dir="$rb" run find rebase feat main
expect_usage
ok

echo "all state tests passed"
