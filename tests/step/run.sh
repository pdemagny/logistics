#!/usr/bin/env bash
# Offline tests for .apm/skills/feat/scripts/step.sh (mise run test:step).
#
# Each run builds a scratch skill layout (copies of step.sh, state.sh and
# story.sh, the fixture sizes.tsv, a stub references/move.md) so spawn goldens
# never change with sizes.json, and a template repo with a bare origin. Each
# case copies that repo, writes a fixture state file and agent reports into it
# (`@TOP@` replaced by the case's top level, `@REPORT@` by the report's path)
# and checks the exit code, stdout against expected/<case>.out and the state
# file's Size, Current phase and Agents lines plus its new Log lines against
# expected/<case>.log, with the top level written `@TOP@` and hashes `@SUM@`.
# Every call checks that stderr is empty. `UPDATE=1 bash tests/step/run.sh`
# writes the actual outputs over expected/ and exits non-zero, so it never
# passes CI; review the change with `git diff tests/step/expected`.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(cd "$here/../.." && pwd -P)"
src="$root/.apm/skills/feat/scripts"
fx="$here/fixtures"
ex="$here/expected"
update="${UPDATE:-0}"
updated=0

current="setup"
fail() {
  printf 'FAIL %s: %s\n' "$current" "$1"
  if [ -n "${out+x}" ]; then printf '  output:\n%s\n' "$out"; fi
  exit 1
}

work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'command rm -rf -- "$work"' EXIT

# Commits here must not depend on the user's git config (signing, hooks).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'

# --- the scratch skill layout and the template repo ---------------------------------

skill="$work/skill/feat"
mkdir -p "$skill/scripts" "$skill/references"
for s in step.sh state.sh story.sh; do cp "$src/$s" "$skill/scripts/$s"; done
cp "$fx/sizes.tsv" "$skill/sizes.tsv"
printf '# move.md stub\n' >"$skill/references/move.md"
step="$skill/scripts/step.sh"

tmpl="$work/tmpl"
mkdir -p "$tmpl"
git init -q --bare "$tmpl/origin.git" 2>/dev/null
git -C "$tmpl/origin.git" symbolic-ref HEAD refs/heads/main
git clone -q "$tmpl/origin.git" "$tmpl/repo" 2>/dev/null
(
  cd "$tmpl/repo"
  git symbolic-ref HEAD refs/heads/main
  mkdir -p specs/x src tests
  for f in spec.md plan.md assessment.md test.md fix.md; do printf '# %s\n' "$f" >"specs/x/$f"; done
  cp "$fx/agents/tasker/tasks.md" specs/x/tasks.md
  printf 'echo a\n' >src/a.sh
  printf 'readme\n' >README.md
  git add -A
  git commit -q -m init
  git push -q origin main 2>/dev/null
  git remote set-head origin main
  # the run's work: an untracked file and a tracked change, so a code review
  # diff is never empty unless a case makes it so
  printf 'echo new\n' >src/new.sh
  printf 'echo b\n' >>src/a.sh
)

n=0
# Hashes a case names: sub_from[i] is written sub_to[i] in stdout and the Log
sub_from=()
sub_to=()
# name_sha <sha> <name>: the sha (and its 7-character cut) written @<name>@
name_sha() {
  sub_from+=("$1" "${1:0:7}")
  sub_to+=("@$2@" "@$2@")
}
# subst <text>: SUBST = the text with the case's named hashes replaced
subst() {
  local i
  SUBST="$1"
  for ((i = 0; i < ${#sub_from[@]}; i++)); do SUBST="${SUBST//"${sub_from[i]}"/${sub_to[i]}}"; done
}

# new_case <name> <state fixture>: a fresh repo copy with the state file
new_case() {
  current="$1"
  unset out
  sub_from=()
  sub_to=()
  n=$((n + 1))
  mkdir -p "$work/c/$n"
  cp -R "$tmpl/repo" "$work/c/$n/repo"
  top="$(cd "$work/c/$n/repo" && pwd -P)"
  sf="$top/specs/x/feat-state.md"
  rd="$top/specs/x/reports"
  sed "s#@TOP@#$top#g" "$fx/states/$2.md" >"$sf"
  mkdir -p "$rd"
  printf '*\n' >"$rd/.gitignore"
}

# put <agent>/<fixture> <key>: the fixture report as reports/<key>.md; R = its path
put() {
  R="$rd/$2.md"
  sed -e "s#@TOP@#$top#g" -e "s#@REPORT@#$R#g" "$fx/agents/$1.md" >"$R"
}

# put_analyze [<n tasks>]: analyze's own report (fixture tasker/analyze, its
# Total Tasks set to n when given) as reports/5-analyze.md; R is untouched
put_analyze() {
  sed -e "s/^- Total Tasks: .*$/- Total Tasks: ${1:-6}/" "$fx/agents/tasker/analyze.md" >"$rd/5-analyze.md"
}

# S <state.sh args>: adjusts the case's state file
S() { bash "$skill/scripts/state.sh" "$1" "$sf" "${@:2}" >/dev/null; }

# run <args>: runs step.sh; out, rc, raw (stdout as printed)
run() {
  rc=0
  before="$(grep -c '' "$sf")"
  raw="$(bash "$step" "$@" 2>"$work/stderr")" || rc=$?
  [ ! -s "$work/stderr" ] || fail "stderr not empty: $(head -n 1 "$work/stderr")"
  out="${raw//"$top"/@TOP@}"
  out="${out//"$skill"/@SKILL@}"
  subst "$out"
  out="$(printf '%s\n' "$SUBST" | sed -E 's/(sum=[^:	]*:)[0-9a-f]{12}/\1@SUM@/g; s/snapshot=[0-9a-f]{12}/snapshot=@SNAP@/g; s/[0-9a-f]{40}/@SHA@/g')"
}

# put_at <agent>/<fixture> <path>: the fixture report at that path; R = it
put_at() {
  R="$2"
  sed -e "s#@TOP@#$top#g" -e "s#@REPORT@#$R#g" "$fx/agents/$1.md" >"$R"
}

# own_origin: the case's repo gets a bare origin of its own, so moving its
# main touches no other case
own_origin() {
  git clone -q --bare "$tmpl/origin.git" "$work/c/$n/origin.git" 2>/dev/null
  git -C "$top" remote set-url origin "$work/c/$n/origin.git"
}

# move_main: a commit on the case's own origin main; OLD and NEW named
move_main() {
  git clone -q "$work/c/$n/origin.git" "$work/c/$n/other" 2>/dev/null
  printf 'main moved\n' >>"$work/c/$n/other/README.md"
  git -C "$work/c/$n/other" commit -qam 'main moved'
  git -C "$work/c/$n/other" push -q origin HEAD:main 2>/dev/null
  OLD="$(git -C "$top" rev-parse HEAD)"
  NEW="$(git -C "$work/c/$n/origin.git" rev-parse main)"
  name_sha "$OLD" OLD
  name_sha "$NEW" NEW
}

# call_line <key>: CALL = the words of raw's `boundary:` or `answer call:` line
call_line() {
  local line
  line="$(printf '%s\n' "$raw" | grep -m1 "^$1:" || true)"
  [ -n "$line" ] || fail "no $1 line"
  IFS=$'\t' read -r -a CALL <<<"${line#*:$'\t'}"
}

# case_log: LOG = the state file's Size, Current phase and Agents lines, its
# title and its new Log lines, as expected/<case>.log holds them
case_log() {
  LOG="$(awk '/^## /{exit} /^- (Size|Current phase|Agents): /' "$sf"; head -n 1 "$sf"; printf -- '--\n'; tail -n +"$((before + 1))" "$sf")"
  LOG="${LOG//"$top"/@TOP@}"
  subst "$LOG"
  LOG="$SUBST"
}

# inputs_check <golden name>: stdout holds no list line; each `inputs:` path is
# its block's `report:` path with .md replaced by .in.md. INS = the files they
# name, each after a `== <file name>` line ("" when there is none)
inputs_check() {
  local line rep='' p f
  INS=''
  if printf '%s\n' "$out" | grep -Eq '^  (apply|failures|rejected|accepted sec|approved commands|answers|not verified items):|^  story\.sh output'; then
    fail "$1: stdout still holds a list line"
  fi
  while IFS= read -r line; do
    case $line in
      'spawn: '*) rep='' ;;
      '  report: '*) rep=${line#'  report: '} ;;
      '  inputs: '*)
        p=${line#'  inputs: '}
        [ -n "$rep" ] && [ "$p" = "${rep%.md}.in.md" ] || fail "$1: inputs: $p is not the report path $rep with .in.md"
        [ -f "$p" ] || fail "$1: no inputs file $p"
        f=$(cat "$p")
        INS+="${INS:+
}== ${p##*/}
$f" ;;
    esac
  done <<<"$raw"
  INS="${INS//"$top"/@TOP@}"
  INS="${INS//"$skill"/@SKILL@}"
  if [ -n "$INS" ]; then subst "$INS"; INS="$SUBST"; fi
}

# check <golden name> <exit code>: exit code, stdout and the state file's changes
check() {
  local name="$1" log
  [ "$rc" = "$2" ] || fail "$name: exit $rc, want $2"
  case_log
  log="$LOG"
  inputs_check "$name"
  if [ "$update" = 1 ]; then
    printf '%s\n' "$out" >"$ex/$name.out"
    printf '%s\n' "$log" >"$ex/$name.log"
    if [ -n "$INS" ]; then printf '%s\n' "$INS" >"$ex/$name.in"; else command rm -f "$ex/$name.in"; fi
    updated=1
    return 0
  fi
  [ -f "$ex/$name.out" ] || fail "$name: no golden $ex/$name.out"
  if [ -n "$INS" ]; then
    [ -f "$ex/$name.in" ] || fail "$name: no golden $ex/$name.in"
    [ "$INS" = "$(cat "$ex/$name.in")" ] || { out="$INS"; fail "$name: inputs files differ from expected/$name.in"; }
  else
    [ ! -f "$ex/$name.in" ] || fail "$name: expected/$name.in exists but no inputs: line was printed"
  fi
  [ "$out" = "$(cat "$ex/$name.out")" ] || fail "$name: stdout differs from expected/$name.out"
  [ "$log" = "$(cat "$ex/$name.log")" ] || { out="$log"; fail "$name: state file differs from expected/$name.log"; }
}

# one_line <exit code> <prefix>: a single line starting with the prefix
one_line() {
  [ "$rc" = "$1" ] || fail "exit $rc, want $1"
  [ "$(printf '%s\n' "$out" | wc -l)" = 1 ] || fail "not one line"
  [[ "$out" == "$2"* ]] || fail "want a line starting: $2"
}

# --- bash 3.2 ------------------------------------------------------------------------

current="bash 3.2 constructs only"
if grep -nE -- 'declare -A|mapfile|readarray|,,\}|\^\^\}|declare -n|local -n|\[\[ -v|\[-[0-9]+\]|;;&|\|&' "$src/step.sh"; then
  fail "step.sh uses a construct bash 3.2 lacks"
fi

# --- usage and errors ------------------------------------------------------------------

new_case "usage: no form" feat
run
one_line 2 'step: usage: '
run feat "$sf"
one_line 2 'step: usage: '

new_case "usage: unknown argument" feat
put specifier/soft 2-specify
run feat "$sf" 2 "$R" 'bogus'
one_line 2 'step: usage: unknown argument: bogus'

new_case "usage: no snapshot on a reviewer batch" feat
S set 'Current phase' '7 Code review'
run feat "$sf" 7 "$rd/7-7a.md"
one_line 2 'step: usage: snapshot= missing'

new_case "error: skill not the title" feat
run fix "$sf" setup
one_line 1 "step: error: @TOP@/specs/x/feat-state.md is a /feat run"
[ "$(tail -n 1 "$sf")" = "- [!] step: step: error: $sf is a /feat run" ] || fail "error not logged"

new_case "error: Worktree another path" feat
S set Worktree /elsewhere
run feat "$sf" setup
one_line 1 "step: error: Worktree: /elsewhere is not the state file's top level"

new_case "error: tab in a report path" feat
run feat "$sf" 2 "$rd/a"$'\t'"b.md"
one_line 1 'step: error: a report path holds a tab'

new_case "error: symlinked state file" feat
ln -s "$sf" "$top/specs/x/link.md"
run feat "$top/specs/x/link.md" setup
one_line 1 'step: error: '
[[ "$out" == *' (not logged)' ]] || fail "want (not logged)"

new_case "error: token does not follow" feat
put specifier/soft 2-specify
run feat "$sf" 5 "$R"
check error-token 1

new_case "error: report key outside the token" feat
put planner/plain 3-plan
run feat "$sf" 2 "$R"
one_line 1 'step: error: report 3-plan.md is not a 2 report'

new_case "error: sizes.tsv row missing" feat
cp "$skill/sizes.tsv" "$work/sizes.keep"
grep -v $'^row\tfeat\t2\t.*\tmedium\t' "$work/sizes.keep" >"$skill/sizes.tsv"
run feat "$sf" setup
cp "$work/sizes.keep" "$skill/sizes.tsv"
check error-sizes-row 1

current="the real sizes.tsv names every row and group of sizes.json"
real_tsv="$root/.apm/skills/feat/sizes.tsv"
while IFS=$'\t' read -r kind sk id sz; do
  if [ "$kind" = row ]; then
    grep -q "^row	$sk	$id	[^	]*	[^	]*	$sz	" "$real_tsv" || fail "no row line for $sk $id $sz"
  else
    grep -q "^group	$sk	$id	$sz	" "$real_tsv" || fail "no group line for $sk $id $sz"
  fi
done < <(python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
for sk in ("feat", "fix"):
    for row in d[sk]["rows"]:
        for sz in ("small", "medium", "large"):
            print("row", sk, row["id"], sz, sep="\t")
    for ph, g in d[sk].get("groups", {}).items():
        for sz in ("small", "medium", "large"):
            print("group", sk, ph, sz, sep="\t")
' "$root/.apm/skills/feat/sizes.json")
(
  # shellcheck source=/dev/null
  source "$src/step.sh"
  # shellcheck disable=SC2034 # read by the sourced step.sh
  SDIR="$src" SKILL=fix F_SIZE=large
  row_get 4a
  [ "$R_LENS" = 7a ] || { echo "lens $R_LENS"; exit 1; }
  groups_get 4 performance
  [ "${#GR_ROWS[@]}" = 3 ] || { echo "groups ${#GR_ROWS[@]}"; exit 1; }
) || fail "step.sh's reader on the real sizes.tsv"

# --- log-readers-agree (research R6) ---------------------------------------------------
# step.sh's own Log reader (sourced behind its main guard) and state.sh's
# queries must read the same Logs the same way: the phase 2 gate's mode, the
# latest back to cut and the retry line, on today's untagged Logs and on
# their tagged copies.

for lf in "$fx"/logs/*.md; do
  current="log-readers-agree: ${lf##*/}"
  want="$(bash "$src/state.sh" phase2-mode "$lf") / $(bash "$src/state.sh" cycle "$lf") / $(bash "$src/state.sh" retry-used "$lf")"
  got="$(
    # shellcheck source=/dev/null
    source "$src/step.sh"
    # shellcheck disable=SC2034 # read by the sourced step.sh
    SF="$lf"
    read_state
    # shellcheck disable=SC2034
    SKILL="$F_TITLE"
    p2_facts
    if ((P2 < 0)); then p2=none; elif ((P2_SOFT)); then p2=soft; else p2=hard; fi
    back_cut
    review=0 retry=0
    for ((i = R0; i < ${#LG[@]}; i++)); do
      case "${LG[i]}" in
        '- [x] 4 Code review'*) review=1 ;;
        '- [x] 3 Test — failed (retry 1 of 1)'*) retry=1 ;;
      esac
    done
    if ((review)); then cyc='after review fixes'; elif ((retry)); then cyc=retry; else cyc=first; fi
    if ((retry)); then ru=yes; else ru=no; fi
    printf '%s / %s / %s\n' "$p2" "$cyc" "$ru"
  )"
  [ "${want%%[ /]*} / ${want#* / }" = "$got" ] || fail "state.sh: $want; step.sh: $got"
done

# --- setup, size, resume -------------------------------------------------------------------

new_case "setup feat" feat
run feat "$sf" setup
check setup-feat 0

new_case "setup fix: the small column while Size: not set" fix
run fix "$sf" setup
check setup-fix 0

new_case "size: a change, then the next spawn on the new column" feat
run feat "$sf" size large
check size-change 0
put specifier/soft 2-specify
run feat "$sf" 2 "$R"
check size-next-spawn 0

new_case "size: the same size logs nothing" feat
run feat "$sf" size medium
check size-same 0

new_case "size: refused while a hard gate is open" feat
S log '- [x] 2 Specify [hard] — open markers: 1'
run feat "$sf" size large
check size-refused 0

new_case "resume feat at 2 with a phase 2 line: amend" feat
S log '- [x] 2 Specify [hard] — open markers: 1' '    - answer: changed (user: "fix it")'
run resume "$sf"
check resume-feat-2 0

new_case "resume fix at 1" fix
run resume "$sf"
check resume-fix-1 0

# --- /feat 2 -------------------------------------------------------------------------------

new_case "feat 2 soft" feat
put specifier/soft 2-specify
run feat "$sf" 2 "$R"
check feat2-soft 0

new_case "feat 2 hard, then approved with open markers: amend" feat
put specifier/markers 2-specify
run feat "$sf" 2 "$R"
check feat2-markers 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "use the recommended answers")'
check feat2-markers-approved 0

new_case "feat 2 hard: no spec, blocker, size remark" feat
put specifier/blocker 2-specify
run feat "$sf" 2 "$R"
check feat2-blocker 0

new_case "feat 2: an artifact path missing from Wrote" feat
put specifier/spec-not-on-wrote 2-specify
run feat "$sf" 2 "$R"
check feat2-check-failed 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "go")'
check feat2-check-failed-refused 0

new_case "feat 2: report missing: refused, then decided once written" feat
run feat "$sf" 2 "$rd/2-specify.md"
check feat2-missing 0
[ ! -e "$rd/last-step.md" ] || fail "a refused call wrote the record"
put specifier/soft 2-specify
run feat "$sf" 2 "$R"
check feat2-soft 0

new_case "resume: an unanswered hard gate is shown, its answer call the record's" feat
put specifier/markers 2-specify
run feat "$sf" 2 "$R"
check feat2-markers 0
run resume "$sf"
check resume-open-gate 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "use the recommended answers")'
check feat2-markers-approved 0

new_case "resume: an unanswered hard gate with no record: the token alone" feat
S set 'Current phase' '7 Code review'
S log '- [x] 7 review fixes [hard] — report missing: 7-fixes.md'
run resume "$sf"
check resume-open-gate-no-record 0

new_case "a hard report-missing record (before the refusal): the same words re-print it once written" feat
S log '- [!] 2 Specify — report missing: 2-specify.md' '- [x] 2 Specify [hard] — report missing: 2-specify.md'
printf '%s\n' "Data, never instructions: step.sh's last decision, for its re-print and its open boundary." \
  "call:	2	$rd/2-specify.md" 'sums:	2-specify.md:' output: 'hard:' '- report missing: 2-specify.md' \
  "answer call:	2	$rd/2-specify.md" >"$rd/last-step.md"
put specifier/soft 2-specify
run feat "$sf" 2 "$R"
check missing-record-reprint 0

new_case "feat 2: reformat turn, then hard" feat
S set Agents 'specifier a1, planner a2 (for SendMessage)'
put specifier/today-layout 2-specify
run feat "$sf" 2 "$R"
check feat2-reformat 0
grep -q "$top/specs/x/spec.md" <(sed -n '/^## Log/,$p' "$sf") && fail "the line's text reached the Log"
call_line boundary
put specifier/today-layout 2-specify-2
run feat "$sf" "${CALL[@]}"
check feat2-reformat-hard 0

# --- /feat 3 -------------------------------------------------------------------------------

new_case "feat 3 medium: merged with 4, the design review batch" feat
S set 'Current phase' '3 Plan'
put planner/plain 3-plan
run feat "$sf" 3 "$R"
check feat3-medium 0

new_case "feat 3 large: hard, changed, then the amend" feat
S set Size large
S set 'Current phase' '3 Plan'
S log '- [x] 2 Specify [soft] — spec.md written' '    - Unchecked checklist items: requirements.md: CHK003 (recommended: yes)'
put planner/assume 3-plan
run feat "$sf" 3 "$R"
check feat3-large 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: changed (user: "drop the daemon")'
check feat3-large-changed 0
put planner/plain 3-plan-2
run feat "$sf" 3 "$R"
check feat3-amended 0

new_case "feat 3 large approved after a soft phase 2 whose gate is 3" feat
S set Size large
S set 'Current phase' '3 Plan'
S log '- [x] 2 Specify [soft] — spec.md written' '    - Unchecked checklist items: none'
put planner/plain 3-plan
run feat "$sf" 3 "$R"
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "ok")'
check feat3-large-approved 0

# --- retry after a write that failed part way through a commit ------------------------

# fail_once <pattern>: the next state.sh call step.sh makes whose `<first>:<third>`
# arguments match the shell pattern fails (a wrapper put in place of the
# scratch state.sh, which puts the real one back as it fails)
fail_once() {
  command cp -f "$skill/scripts/state.sh" "$skill/scripts/.state-real.sh"
  printf '%s\n' '#!/usr/bin/env bash' \
    "case \"\$1:\${3-}\" in $1)" \
    "  mv -f '$skill/scripts/.state-real.sh' '$skill/scripts/state.sh'" \
    "  echo 'state: error: injected failure'; exit 1 ;;" \
    'esac' \
    "exec bash '$skill/scripts/.state-real.sh' \"\$@\"" >"$skill/scripts/state.sh"
}
# unfail: the real state.sh back, whether or not the failure happened
unfail() {
  if [ -f "$skill/scripts/.state-real.sh" ]; then
    command mv -f "$skill/scripts/.state-real.sh" "$skill/scripts/state.sh"
  fi
}

# soft 3 → 4: the snapshot fails after the Log line and Current phase are
# written; the retry gets the same design review batch, the line once
new_case "retry: the snapshot failed after a soft 3 → 4 was written" feat
S set 'Current phase' '3 Plan'
put planner/plain 3-plan
fail_once "'snapshot:'*"
run feat "$sf" 3 "$R"
unfail
check retry-snapshot-failed 1
run feat "$sf" 3 "$R"
check retry-snapshot-retried 0
[ "$out" = "$(cat "$ex/feat3-medium.out")" ] || fail "the retry's spawns differ from feat3-medium's"
[ "$(grep -c '^- \[x\] 3 Plan — merged with 4' "$sf")" = 1 ] || fail "the 3 Plan line was logged twice"

# a soft gate line written, then a set failed: the retry logs it once (the
# Agents line put back on a failed set: "ids on an answer call" below)
new_case "retry: Current phase failed to set after a soft 2 gate line" feat
put specifier/soft 2-specify
fail_once "'set:Current phase'"
run feat "$sf" 2 "$R"
unfail
check retry-set-failed 1
run feat "$sf" 2 "$R"
check retry-set-retried 0
[ "$out" = "$(cat "$ex/feat2-soft.out")" ] || fail "the retry's output differs from feat2-soft's"
[ "$(grep -c '^- \[x\] 2 Specify \[soft\]' "$sf")" = 1 ] || fail "the 2 Specify gate was logged twice"

# --- /feat 5 -------------------------------------------------------------------------------

new_case "feat 5 soft on small: the first story" feat
S set Size small
S set 'Current phase' '5 Tasks'
S log '- [x] 2 Specify [soft] — spec.md written' '    - Unchecked checklist items: none' '- [x] 3 Plan — merged with 4; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none'
put_analyze
put tasker/match 5-tasks
run feat "$sf" 5 "$R"
check feat5-soft 0

new_case "feat 5 medium to small: a decrease" feat
S set 'Current phase' '5 Tasks'
S log '- [x] 2 Specify [soft] — spec.md written' '    - Unchecked checklist items: none' '- [x] 3 Plan — merged with 4; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none'
put_analyze
put tasker/match 5-tasks
run feat "$sf" 5 "$R"
check feat5-decrease 0

new_case "feat 5 hard: findings, analyze, story.sh groups, checklist, facts missing" feat
S set Size small
S set 'Current phase' '5 Tasks'
put tasker/mismatch 5-tasks
run feat "$sf" 5 "$R"
check feat5-hard 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: changed (user: "fix the groups")'
check feat5-changed 0

# #97: "Analyze: ran" is proven only by analyze's metrics; without them, or
# with "none", the gate is hard as if analyze had not run
new_case "feat 5 hard: analyze ran without its metrics" feat
S set Size small
S set 'Current phase' '5 Tasks'
S log '- [x] 2 Specify [soft] — spec.md written' '    - Unchecked checklist items: none' '- [x] 3 Plan — merged with 4; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none'
put tasker/ran-no-metrics 5-tasks
run feat "$sf" 5 "$R"
check feat5-no-metrics 0

new_case "feat 5 hard: analyze ran with metrics none" feat
S set Size small
S set 'Current phase' '5 Tasks'
S log '- [x] 2 Specify [soft] — spec.md written' '    - Unchecked checklist items: none' '- [x] 3 Plan — merged with 4; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none'
put_analyze
put tasker/match 5-tasks
sed -i 's/^Analyze metrics: .*$/Analyze metrics: none/' "$R"
run feat "$sf" 5 "$R"
check feat5-metrics-none 0
[ "$out" = "$(cat "$ex/feat5-no-metrics.out")" ] || fail "metrics none differs from metrics missing"

# #102: the metrics must be analyze's own, saved as reports/5-analyze.md: no
# file, a file without its Metrics block, or other numbers in it is hard
feat5_ran() {
  new_case "$1" feat
  S set Size small
  S set 'Current phase' '5 Tasks'
  S log '- [x] 2 Specify [soft] — spec.md written' '    - Unchecked checklist items: none' '- [x] 3 Plan — merged with 4; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none'
  put_analyze
  put tasker/match 5-tasks
}

feat5_ran "feat 5 hard: analyze ran with no analyze report"
command rm -f "$rd/5-analyze.md"
sed -i '/reports\/5-analyze\.md$/d' "$R"
run feat "$sf" 5 "$R"
check feat5-no-analyze 0

feat5_ran "feat 5 hard: analyze report without its Metrics block"
sed -i '/^\*\*Metrics:\*\*$/d' "$rd/5-analyze.md"
run feat "$sf" 5 "$R"
check feat5-analyze-no-block 0

feat5_ran "feat 5 hard: analyze report without one of the six metrics"
sed -i '/^- Duplication Count:/d' "$rd/5-analyze.md"
run feat "$sf" 5 "$R"
check feat5-analyze-short 0

feat5_ran "feat 5 hard: analyze metrics differ from the analyze report"
sed -i 's/^Analyze metrics: 8 requirements/Analyze metrics: 9 requirements/' "$R"
run feat "$sf" 5 "$R"
check feat5-analyze-differ 0

# analyze's block read loosely: bold labels, a table, 100.0%, a heading
feat5_ran "feat 5 soft: analyze metrics in another layout"
printf '%s\n' '# Report' '' '## Metrics' '' '| Metric | Value |' '|---|---|' '| **Total Requirements** | 8 |' \
  '| Total Tasks | 6 |' '| Coverage % (requirements with >=1 task) | 100.0% |' '| Ambiguity Count | 0 |' \
  '| Duplication Count | 0 |' '| Critical Issues Count | 0 |' '' '**Next Actions:** none' >"$rd/5-analyze.md"
run feat "$sf" 5 "$R"
check feat5-soft-layout 0
[ "${out%%$'\n'*}" = soft ] || fail "another layout is not soft"

# a note after the value may hold colons: the value follows the first one
feat5_ran "feat 5 soft: analyze metrics with notes holding colons"
sed -i -e 's/^- Total Requirements: 8$/- Total Requirements: 8 (FR: 6, SC: 2)/' \
  -e 's/^- Total Tasks: 6$/- Total Tasks: 6 (T001: setup)/' "$rd/5-analyze.md"
grep -q '^- Total Tasks: 6 (T001: setup)$' "$rd/5-analyze.md" || fail "the notes were not written"
run feat "$sf" 5 "$R"
check feat5-soft-layout 0

# a table's coverage cell without %: the value is the last cell, not the label's 1
feat5_ran "feat 5 soft: analyze coverage cell without %"
printf '%s\n' '**Metrics:**' '' '| Metric | Value |' '|---|---|' '| Total Requirements | 8 |' '| Total Tasks | 6 |' \
  '| Coverage % (requirements with >=1 task) | 100 |' '| Ambiguity Count | 0 |' '| Duplication Count | 0 |' \
  '| Critical Issues Count | 0 |' >"$rd/5-analyze.md"
run feat "$sf" 5 "$R"
check feat5-soft-layout 0

# --- /feat 6 -------------------------------------------------------------------------------

feat6() {
  new_case "$1" feat
  S set Size "$2"
  S set 'Current phase' '6 Implement'
  S log '- [x] 5 Tasks [soft] — 6 tasks; story.sh: match; analyze ran'
}

feat6 "feat 6 medium: story to story with no gate line" medium
put implementer/story-pass 6-US1
run feat "$sf" 6 "$R"
check feat6-next 0
put implementer/story-clean 6-US2
run feat "$sf" 6 "$R"
check feat6-last 0

feat6 "feat 6: a failed check, its retry, then hard" medium
put implementer/story-fail 6-US1
run feat "$sf" 6 "$R"
check feat6-retry 0
put implementer/story-fail 6-US1-2
run feat "$sf" 6 "$R"
check feat6-retry-hard 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "known flake")'
check feat6-retry-approved 0

feat6 "feat 6 large: a gate after each story" large
put implementer/story-pass 6-US1
run feat "$sf" 6 "$R"
check feat6-large 0

feat6 "feat 6: a design problem" small
put implementer/story-design 6-US1
run feat "$sf" 6 "$R"
check feat6-design 0

feat6 "feat 6: no Not verified line" small
put implementer/story-no-nv 6-US1
run feat "$sf" 6 "$R"
check feat6-no-nv 0

# the who-line without a Not verified line still logs the wrote: sub-lines
feat6 "feat 6: no Not verified line, wrote: sub-lines kept" small
put implementer/story-no-nv-wrote 6-US1
run feat "$sf" 6 "$R"
check feat6-no-nv-wrote 0

feat6 "feat 6: resume skips the done stories" small
S log '- [x] 6 US1 — not verified: none'
run resume "$sf"
check feat6-resume 0

# --- /feat 8 -------------------------------------------------------------------------------

feat8() {
  new_case "$1" feat
  S set 'Current phase' 'done (shipping)'
  S log '- [x] 6 US1 — not verified:' '    - T004 → manual run → no terminal' '    - wrote: src/new.sh' '- [x] 8 Ship'
  put "shipper/$2" 8-ship
  run feat "$sf" 8 "$R"
}

feat8 "feat 8: PR" pr
check feat8-pr 0
feat8 "feat 8: a command for the user" blocked-ok
check feat8-blocked 0
feat8 "feat 8: a quoted command for the user" blocked-quoted
check feat8-blocked-quoted 0
feat8 "feat 8: a command elsewhere" blocked-elsewhere
check feat8-elsewhere 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "ship again")'
check feat8-elsewhere-approved 0
feat8 "feat 8: a prefix of the top level" blocked-prefix
check feat8-prefix 0

new_case "feat 8: the shipper renumbered the dir" feat
S set 'Current phase' 'done (shipping)'
put shipper/pr 8-ship
sed -i "s#$top/specs/x/#$top/specs/012-x/#g" "$R"
mv "$top/specs/x" "$top/specs/012-x"
old_sf="$sf"
sf="$top/specs/012-x/feat-state.md"
run feat "$old_sf" 8 "$R"
check feat8-renumbered 0

# --- /fix 1 --------------------------------------------------------------------------------

new_case "fix 1 soft" fix
put bug-assessor/assess-soft 1-assess
run fix "$sf" 1 "$R" 'approved: bash tests/page.sh' 'question: which page? → the last'
check fix1-soft 0

new_case "fix 1 hard, security refused, then approved with security" fix
put bug-assessor/assess-hard 1-assess
run fix "$sf" 1 "$R"
check fix1-hard 0
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "go")'
check fix1-hard-refused 0
# shellcheck disable=SC2016 # the user's words, logged byte for byte
run fix "$sf" "${CALL[@]}" 'answer: size medium (user: "go, medium")' 'security: advisory (user: "advisory, it'\''s $(rm) `x`; ok")'
check fix1-hard-approved 0

new_case "fix 1: no approved command or answer, no inputs file" fix
run resume "$sf"
check fix1-no-inputs 0
[ -z "$(ls "$rd"/*.in.md 2>/dev/null)" ] || fail "fix1-no-inputs: an inputs file was written"

new_case "fix 1: awkward approved command and answer, the inputs file rewritten whole" fix
# shellcheck disable=SC2016 # the user's words, logged byte for byte
S log '- [x] 1 Assess — approved: -x it'\''s $(rm -rf x) and `id`; ok' '- [x] 1 Assess — answer: which page? → the last'
run resume "$sf"
check fix1-awkward-inputs 0
run resume "$sf"
check fix1-awkward-inputs-again 0
[ "$(cat "$ex/fix1-awkward-inputs.in")" = "$(cat "$ex/fix1-awkward-inputs-again.in")" ] || fail "the inputs file was not rewritten whole"

new_case "fix 1 stop: invalid" fix
put bug-assessor/assess-invalid 1-assess
run fix "$sf" 1 "$R"
check fix1-invalid 0

new_case "fix 1 stop: refactor" fix
put bug-assessor/assess-refactor 1-assess
run fix "$sf" 1 "$R"
check fix1-refactor 0

# fix1_reason <sed expression> <reason>: the soft report with one field
# changed gives exactly that hard reason
fix1_reason() {
  new_case "fix 1 hard: $2" fix
  put bug-assessor/assess-soft 1-assess
  sed -i -e "$1" "$R"
  run fix "$sf" 1 "$R"
  [ "$rc" = 0 ] || fail "exit $rc"
  [ "$out" = "hard:
- $2
answer call:	1	@TOP@/specs/x/reports/1-assess.md	sum=1-assess.md:@SUM@" ] || fail "want the one reason: $2"
  [ "$(tail -n 1 "$sf")" = "- [x] 1 Assess [hard] — $2" ] || fail "gate line not logged"
}
fix1_reason 's/^Sections: ok$/Sections: error: assessment.md lacks Symptom/' 'sections: assessment.md lacks Symptom'
fix1_reason 's/^Slug: ok$/Slug: mismatch (7-other)/' 'slug mismatch: 7-other'
fix1_reason 's/^Reproduction: reproduced$/Reproduction: needs approval/' 'needs approval'
fix1_reason 's/^Verdict: valid$/Verdict: likely valid, needs reproduction/' 'needs reproduction'
fix1_reason 's/^Several bugs: no$/Several bugs: yes — paging; sorting/' 'several bugs'
fix1_reason 's/^Public behaviour change: no$/Public behaviour change: yes (the last page grows by one)/' 'public behaviour change'
fix1_reason 's/^Risk area: none$/Risk area: security/' 'security risk area'

new_case "fix 1 hard: an untrusted report author" fix
sed -i 's/report author OWNER/report author NONE/' "$sf"
put bug-assessor/assess-soft 1-assess
run fix "$sf" 1 "$R"
check fix1-untrusted 0

new_case "fix 1 hard: an issue to create (board tracking, Issue: none)" fix
S set Issue none
printf 'tracker:\n  provider: github\n' >"$top/.logistics.yml"
put bug-assessor/assess-soft 1-assess
run fix "$sf" 1 "$R"
check fix1-issue 0

for v in 's/^Sections: ok$/Sections: error: test.md lacks Result/' 's/^Slug: ok$/Slug: mismatch (7-other)/'; do
  new_case "fix 3 hard: $v" fix
  S set Size small
  S set 'Current phase' '3 Test'
  S log '- [x] 1 Assess [soft] — gate: valid, high confidence, reproduced, 1 remediation(s); size small; risk area none; performance bug no' \
    '- [x] 2 implementer — not verified: none' '- [x] 2 Fix [soft] — applied; no deviations; checks pass'
  put bug-assessor/test-verified 3-test
  sed -i -e "$v" "$R"
  run fix "$sf" 3 "$R"
  [ "$rc" = 0 ] || fail "exit $rc"
  [ "$(printf '%s\n' "$out" | sed -n 1p)" = 'hard:' ] || fail "not hard"
  r2="$(printf '%s\n' "$out" | sed -n 2p)"
  [[ "$r2" == '- sections: test.md lacks Result' || "$r2" == '- slug mismatch: 7-other' ]] || fail "reason: $r2"
done

new_case "fix 1: a risk area outside its set is unparsable" fix
put bug-assessor/assess-bad-risk 1-assess
run fix "$sf" 1 "$R"
check fix1-bad-risk 0

new_case "fix 1: no report author on the setup line" fix-old
S set 'Current phase' '1 Assess'
put bug-assessor/assess-soft 1-assess
run fix "$sf" 1 "$R"
check fix1-no-author 0

# --- /fix 2, 3, 5 --------------------------------------------------------------------------

fix_at() {
  new_case "$1" fix
  S set Size small
  S set 'Current phase' "$2"
  S log '- [x] 1 Assess [soft] — gate: valid, high confidence, reproduced, 1 remediation(s); size small; risk area none; performance bug no'
}

fix_at "fix 2 soft" '2 Fix'
put implementer/bug-pass 2-fix
run fix "$sf" 2 "$R"
check fix2-soft 0

fix_at "fix 2 hard" '2 Fix'
put implementer/bug-hard 2-fix
run fix "$sf" 2 "$R"
check fix2-hard 0

fix_at "fix 2: report missing: refused, then decided once written" '2 Fix'
run fix "$sf" 2 "$rd/2-fix.md"
check fix2-missing 0
put implementer/bug-pass 2-fix
run fix "$sf" 2 "$R"
check fix2-soft 0

fix_at "fix 3 verified: phase 4" '3 Test'
S log '- [x] 2 implementer — not verified:' '    - n/a → live run → no credentials' '- [x] 2 Fix [soft] — applied; no deviations; checks pass'
put bug-assessor/test-verified 3-test
run fix "$sf" 3 "$R"
check fix3-verified 0

fix_at "fix 3 failed first: the retry" '3 Test'
S log '- [x] 2 implementer — not verified:' '    - n/a → live run → no credentials' '- [x] 2 Fix [soft] — applied; no deviations; checks pass'
put bug-assessor/test-failed 3-test
run fix "$sf" 3 "$R"
check fix3-retry 0
put implementer/bug-pass 2-fix
run fix "$sf" 2 "$R"
check fix3-retry-fix 0
put bug-assessor/test-failed 3-test-2
run fix "$sf" 3 "$R"
check fix3-failed-hard 0
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: ship with failed (user: "ship it")'
check fix3-ship-with 0

fix_at "fix 3 partial: approved refused, back to 1" '3 Test'
S log '- [x] 2 implementer — not verified:' '    - n/a → live run → no credentials' '- [x] 2 Fix [soft] — applied; no deviations; checks pass'
put bug-assessor/test-partial 3-test
run fix "$sf" 3 "$R"
check fix3-partial 0
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "fine")'
check fix3-partial-refused 0
run fix "$sf" "${CALL[@]}" 'answer: back to 1 (user: "re-assess")'
check fix3-back-to-1 0

fix_at "fix 3 unaccounted items, approved" '3 Test'
S log '- [x] 2 implementer — not verified:' '    - n/a → live run → no credentials' '- [x] 2 Fix [soft] — applied; no deviations; checks pass'
put bug-assessor/test-unaccounted 3-test
run fix "$sf" 3 "$R"
check fix3-unaccounted 0
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "checked it by hand")'
check fix3-unaccounted-approved 0

new_case "fix 3 verified after review fixes, risk area missing: hard into 5" fix-old
put bug-assessor/test-verified 3-test
run fix "$sf" 3 "$R"
check fix3-old-risk 0
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "ship as a security bug")'
check fix3-old-risk-approved 0

fix_at "fix 5: PR, security bug no" 'done (shipping)'
put shipper/pr 5-ship
run fix "$sf" 5 "$R"
check fix5-pr 0

# --- ship.sh's reports at the ship boundary ------------------------------------------------
# The reports ship.sh printed in tests/ship (its expected/ goldens) as the
# shipper's report: each gets the verdict of the shipper fixture it stands
# for, so the parser takes the script's report unchanged (FR-021, SC-004).

# ship_golden <golden> <its artifact dir> <the case's dir> <key>: the golden as
# <the case's dir>/reports/<key>.md, its artifact dir and report name written
# as the case's (rebase mode's r-ship.md is the ship boundary's 8-ship.md)
# and @H<n>@ as a 7-hex hash; R = its path
ship_golden() {
  R="$top/$3/reports/$4.md"
  sed -e "s#@TOP@/$2/#$top/$3/#g" -e "s#@TOP@#$top#g" -e 's/@H\([0-9]\)@/\1\1\1\1\1\1\1/g' \
    -e "s#/reports/[a-z0-9]*-ship\\.md\$#/reports/$4.md#" "$root/tests/ship/expected/$1.out" >"$R"
  grep -q '@' "$R" && fail "$1: a placeholder left in the report"
  return 0
}

# same_as <golden> [<sed expression>]: exit 0, stdout and the state file's
# changes those of expected/<golden>, the expression applied to it
same_as() {
  local sx="${2:-s#^##}"
  [ "$rc" = 0 ] || fail "exit $rc, want 0"
  [ "$out" = "$(sed "$sx" "$ex/$1.out")" ] || fail "stdout differs from expected/$1.out"
  case_log
  [ "$LOG" = "$(sed "$sx" "$ex/$1.log")" ] || { out="$LOG"; fail "state file differs from expected/$1.log"; }
}

# ship_numbered <golden> <key>: a /feat case at done (shipping), its dir
# numbered 001 as ship.sh numbers it and the golden put there, then the ship
# boundary on the report's old path
ship_numbered() {
  new_case "ship.sh $1 at the ship boundary" feat
  S set 'Current phase' 'done (shipping)'
  [ "$1" != ship-conflict ] || S log '- [x] 8 Ship'
  mv "$top/specs/x" "$top/specs/001-x"
  ship_golden "$1" specs/001-x specs/001-x "$2"
  old_sf="$sf"
  sf="$top/specs/001-x/feat-state.md"
  run feat "$old_sf" 8 "$top/specs/x/reports/$2.md"
}

ship_numbered ship-pr 8-ship
same_as feat8-renumbered 's#/specs/012-x/#/specs/001-x/#g'
ship_numbered rebase-pr 8-ship
same_as feat8-renumbered 's#/specs/012-x/#/specs/001-x/#g'
ship_numbered ship-conflict 8-ship
same_as ship-conflict 's#/specs/012-x/#/specs/001-x/#g'

fix_at "ship.sh fix-pr at the ship boundary" 'done (shipping)'
ship_golden fix-pr .specify/bugs/b specs/x 5-ship
run fix "$sf" 5 "$R"
same_as fix5-pr

new_case "ship.sh ship-blocked at the ship boundary" feat
S set 'Current phase' 'done (shipping)'
S log '- [x] 8 Ship'
ship_golden ship-blocked specs/x specs/x 8-ship
run feat "$sf" 8 "$R"
check ship-sh-blocked 0
[ "$(printf '%s\n' "$out" | head -n 2)" = "$(head -n 2 "$ex/feat8-elsewhere.out")" ] || fail "want the blocked verdict of feat8-elsewhere"
[ "$(tail -n 1 "$sf")" = '- [x] 8 Ship [hard] — ship blocked' ] || fail "want the blocked Log line"

# --- answers ------------------------------------------------------------------------------

new_case "answers: refusals leave the gate open" feat
put specifier/markers 2-specify
run feat "$sf" 2 "$R"
call_line 'answer call'
for a in 'answer: maybe (user: "x")' 'answer: approved (user: "x")|answer: changed (user: "y")' \
  'answer: back to 3 (user: "x")' 'answer: skip 2 (user: "x")' 'answer: stay (user: "x")' \
  'answer: ship with failed (user: "x")' 'answer: picked D1 (user: "x")'; do
  IFS='|' read -r -a extra <<<"$a"
  run feat "$sf" "${CALL[@]}" "${extra[@]}"
  [ "$rc" = 0 ] && [[ "$out" == 'refused: '* ]] && [ "$(printf '%s\n' "$out" | wc -l)" = 1 ] || fail "not refused: $a"
  [ "$(grep -c '' "$sf")" = "$before" ] || fail "logged on a refusal: $a"
done

new_case "answers: no gate open" feat
put specifier/soft 2-specify
run feat "$sf" 2 "$R" 'answer: approved (user: "x")' "sum=2-specify.md:0123456789ab"
one_line 0 'refused: no hard gate open'

new_case "answers: a report changed since checked" feat
put specifier/markers 2-specify
run feat "$sf" 2 "$R"
call_line 'answer call'
printf 'edited\n' >>"$R"
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "go")'
check answer-changed-report 0
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "go")'
one_line 0 'refused: report check failed'
run feat "$sf" "${CALL[@]}" 'answer: stop (user: "later")'
check answer-stop 0

new_case "answers: a missing sum= is usage" feat
put specifier/markers 2-specify
run feat "$sf" 2 "$R"
run feat "$sf" 2 "$R" 'answer: approved (user: "go")'
one_line 2 'step: usage: sum= missing'

new_case "answers: an overridden soft gate" feat
put specifier/soft 2-specify
run feat "$sf" 2 "$R"
call_line 'answer call'
S log '    - override: hard — the user asked to see the spec'
run feat "$sf" "${CALL[@]}" 'answer: back to 2 (user: "redo it")'
check answer-override 0

# an override appended after the records a soft verdict logs below its
# gate line (a Ship line, /fix 1's approved: and answer: lines) still
# belongs to that gate
fix_at "answers: an override after a soft fix 3 and its Ship line" '3 Test'
S log '- [x] 2 implementer — not verified: none' '- [x] 2 Fix [soft] — applied; no deviations; checks pass' \
  '- [x] 3 Test [soft] — verified' '- [x] 4 Code review [soft] — auto-applied B1' \
  '- [x] 4 implementer — B1 → applied; checks: pass; not verified: none'
put bug-assessor/test-verified 3-test
run fix "$sf" 3 "$R"
call_line 'answer call'
S log '    - override: hard — the user wants to read the test report'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "ship it")'
check override-after-ship 0

new_case "answers: an override after a soft fix 1 and its question line" fix
put bug-assessor/assess-soft 1-assess
run fix "$sf" 1 "$R" 'question: which page? → the last'
call_line 'answer call'
S log '    - override: hard — the fix changes the paging contract'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "go")'
check override-after-question 0

new_case "answers: skip 3 at gate 2" feat
put specifier/markers 2-specify
run feat "$sf" 2 "$R"
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: skip 3 (user: "plan later")'
check answer-skip 0

new_case "answers: size alone acts as approved" feat
put specifier/blocker 2-specify
run feat "$sf" 2 "$R"
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: size large (user: "it is large")'
check answer-size 0

# --- report checks -----------------------------------------------------------------------

# spec_report <Wrote: block lines...>: a specifier report with that Wrote: field
spec_report() {
  R="$rd/2-specify.md"
  {
    printf 'Spec: %s\n' "$top/specs/x/spec.md"
    printf '%s\n' 'Stories: US1 Run a step (P1)' 'Requirements: 3' 'Open markers: none' \
      'Blocker: none' 'Size remark: none' 'Assumptions: none' 'Unchecked checklist items: none' \
      'Skipped hooks: none'
    printf '%s\n' "$@"
  } >"$R"
}

check_rule() {
  new_case "report check: $1" feat
  shift
  spec_report "$@"
  run feat "$sf" 2 "$R"
  [ "$rc" = 0 ] || fail "exit $rc"
  [ "$(printf '%s\n' "$out" | head -n 1)" = 'hard:' ] || fail "not hard"
  printf '%s\n' "$out" | grep -q -- "^- 2-specify.md: $want_reason\$" || fail "no reason: $want_reason"
  grep -q -- "^- \[!\] 2 Specify — 2-specify.md: $want_reason\$" "$sf" || fail "not logged: $want_reason"
}

want_reason='Wrote item 1 is not absolute'
check_rule "a relative path" 'Wrote:' '- specs/x/spec.md' "- $top/specs/x/reports/2-specify.md"
want_reason='Wrote item 1 is outside the top level'
check_rule "a path outside the top level" 'Wrote:' "- $work" "- $top/specs/x/spec.md" "- $top/specs/x/reports/2-specify.md"
want_reason='Wrote item 1 is not on disk'
check_rule "a path not on disk" 'Wrote:' "- $top/nope.md" "- $top/specs/x/spec.md" "- $top/specs/x/reports/2-specify.md"
for ch in "'" '$' '`'; do
  want_reason='Wrote item 1 holds a forbidden character'
  check_rule "a path holding $ch" 'Wrote:' "- $top/a${ch}b.md" "- $top/specs/x/spec.md" "- $top/specs/x/reports/2-specify.md"
done
want_reason='Wrote: none with a note'
check_rule "Wrote: none with a note" 'Wrote: none (nothing written)'
want_reason='the report path is not on Wrote'
check_rule "the report path missing" 'Wrote:' "- $top/specs/x/spec.md"

new_case "report check: an empty report" feat
: >"$rd/2-specify.md"
run feat "$sf" 2 "$rd/2-specify.md"
check check-empty 0

new_case "report check: a failure and an unparsable line in the same call: hard at once" feat
spec_report 'Wrote:' "- $top/specs/x/spec.md"
grep -v '^Blocker:' "$R" >"$R.tmp"
mv "$R.tmp" "$R"
run feat "$sf" 2 "$R"
check check-and-unparsable 0

# --- missing facts on runs started before this feature -----------------------------------

new_case "feat 3 large: no phase 2 sub-line" feat
S set Size large
S set 'Current phase' '3 Plan'
S log '- [x] 2 Specify — spec.md written (soft)'
put planner/plain 3-plan
run feat "$sf" 3 "$R"
check fact-feat3 0

# --- more routing ---------------------------------------------------------------------------

feat6 "feat 6: story.sh failing" small
command rm -f -- "$top/specs/x/tasks.md"
put implementer/story-clean 6-US1
run feat "$sf" 6 "$R"
check feat6-story-sh 0

fix_at "fix 3 verified after review fixes: phase 5, security bug no" '3 Test'
S log '- [x] 2 implementer — not verified: none' '- [x] 2 Fix [soft] — applied; no deviations; checks pass' \
  '- [x] 3 Test [soft] — verified' '- [x] 4 Code review [soft] — auto-applied B1' \
  '- [x] 4 implementer — B1 → applied; checks: pass; not verified: none'
put bug-assessor/test-unaccounted 3-test
run fix "$sf" 3 "$R"
check fix3-to-5 0

fix_at "fix 3 failed after review fixes: hard" '3 Test'
S log '- [x] 2 implementer — not verified: none' '- [x] 2 Fix [soft] — applied; no deviations; checks pass' \
  '- [x] 3 Test [soft] — verified' '- [x] 4 Code review [soft] — auto-applied B1' \
  '- [x] 4 implementer — B1 → applied; checks: pass; not verified: none'
put bug-assessor/test-failed 3-test
run fix "$sf" 3 "$R"
check fix3-failed-after-review 0

new_case "resume feat 3 with an owed amend" feat
S set Size large
S set 'Current phase' '3 Plan'
S log '- [x] 3 Plan [hard] — large; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none' \
  '    - answer: changed (user: "drop the daemon")'
run resume "$sf"
check resume-feat3-amend 0

# --- report formats fail closed (US2) ------------------------------------------------------
# A slip in a report is unparsable: one reformat turn naming the file, the line
# and the key, never read as no risk or no item; the Log holds the reformat
# line and none of the unparsable line's text.

# reformat_on <Key>: the call printed a reformat turn for that key
reformat_on() {
  local t
  [ "$(printf '%s\n' "$out" | head -n 1)" = reformat ] || fail "not a reformat turn"
  printf '%s\n' "$out" | grep -qE "^  unparsable: [^ ]+: (line [0-9]+ \($1\)( — [^;]+)?|no $1: line)\$" || fail "no unparsable: line for $1"
  tail -n 1 "$sf" | grep -qE "^- \[!\] .* — unparsable: [^ ]+: (line [0-9]+ \($1\)( — [^;]+)?|no $1: line); reformat 1 of 1\$" || fail "reformat line not logged"
  t="$(printf '%s\n' "$raw" | sed -n 's/^unparsable line: [^:]*: //p')"
  if [ -n "$t" ] && grep -qF -- "$t" <(sed -n '/^## Log/,$p' "$sf"); then fail "the line's text reached the Log"; fi
}

new_case "format: Open markers 2 with one item" feat
put specifier/bad-markers 2-specify
run feat "$sf" 2 "$R"
check fmt-spec-markers 0
reformat_on 'Open markers'

new_case "format: a required field missing" feat
put specifier/soft 2-specify
sed -i '/^Blocker:/d' "$R"
run feat "$sf" 2 "$R"
check fmt-spec-no-blocker 0
reformat_on Blocker

new_case "format: Performance bug outside its set" fix
put bug-assessor/assess-bad-perf 1-assess
run fix "$sf" 1 "$R"
check fmt-assess-perf 0
reformat_on 'Performance bug'

new_case "format: Risk area missing is never no risk" fix
put bug-assessor/assess-soft 1-assess
sed -i '/^Risk area:/d' "$R"
run fix "$sf" 1 "$R"
check fmt-assess-no-risk 0
reformat_on 'Risk area'

new_case "format: Tasks holding more than its path" feat
S set 'Current phase' '5 Tasks'
put_analyze
put tasker/match 5-tasks
sed -i 's/^Tasks: \(.*\)$/Tasks: \1, 6 tasks/' "$R"
run feat "$sf" 5 "$R"
check fmt-tasker-tasks 0
reformat_on Tasks

for v in bad-indented:Checks bad-star:Checks bad-wrapped:'Not verified'; do
  feat6 "format: implementer ${v%%:*}" small
  put "implementer/${v%%:*}" 6-US1
  run feat "$sf" 6 "$R"
  check "fmt-impl-${v%%:*}" 0
  reformat_on "${v#*:}"
done

# reformat_why <words>: the reformat reason, on stdout and in the Log, says
# what is wrong with the line
reformat_why() {
  printf '%s\n' "$out" | grep -qF -- ") — $1" || fail "no reason \"$1\" on stdout"
  tail -n 1 "$sf" | grep -qF -- ") — $1; reformat 1 of 1" || fail "no reason \"$1\" in the Log"
}

# the slips of #74: an item under `Checks: none`, a count with a note, and a
# note after `Size trigger: none`
for v in bad-checks-none:Checks:'an item under none (write the header alone)' \
  bad-files-plus:'Files changed':'not a bare count or none'; do
  b=${v%%:*} k=${v#*:}
  feat6 "format: implementer $b" small
  put "implementer/$b" 6-US1
  run feat "$sf" 6 "$R"
  check "fmt-impl-$b" 0
  reformat_on "${k%%:*}"
  reformat_why "${k#*:}"
done

new_case "format: planner Size trigger none with a note" feat
S set 'Current phase' '3 Plan'
put planner/bad-trigger-note 3-plan
run feat "$sf" 3 "$R"
check fmt-plan-trigger-note 0
reformat_on 'Size trigger'
reformat_why 'a value outside its format'

new_case "format: Analyze metrics outside its format" feat
S set 'Current phase' '5 Tasks'
put_analyze
put tasker/match 5-tasks
sed -i 's/^Analyze metrics: .*$/Analyze metrics: looked fine/' "$R"
run feat "$sf" 5 "$R"
check fmt-tasker-metrics 0
reformat_on 'Analyze metrics'
reformat_why 'a value outside its format'

# today's layout (bare paths under Wrote:) is unparsable at its first bare path
new_case "format: planner in today's layout" feat
S set 'Current phase' '3 Plan'
put planner/today-layout 3-plan
run feat "$sf" 3 "$R"
check fmt-today-planner 0
reformat_on Wrote

new_case "format: tasker in today's layout" feat
S set 'Current phase' '5 Tasks'
put tasker/today-layout 5-tasks
run feat "$sf" 5 "$R"
check fmt-today-tasker 0
reformat_on Wrote

feat6 "format: implementer in today's layout" small
put implementer/today-layout 6-US1
run feat "$sf" 6 "$R"
check fmt-today-implementer 0
reformat_on Wrote

new_case "format: bug assessor in today's layout" fix
put bug-assessor/today-layout 1-assess
run fix "$sf" 1 "$R"
check fmt-today-assessor 0
reformat_on Wrote

feat8 "format: shipper in today's layout" today-layout
check fmt-today-shipper 0
reformat_on Wrote

# the rebase mode's report has no boundary before US4's move: its parser here
current="format: rebase mode, a Move value outside its set and no Not verified line"
grep -v '^Not verified:' "$fx/agents/implementer/rebase-moved.md" | grep -v '^- n/a → ' >"$work/rebase-no-nv.md"
msg="$(
  # shellcheck source=/dev/null
  source "$src/step.sh"
  for f in "$fx/agents/implementer/bad-move.md" "$work/rebase-no-nv.md" "$fx/agents/implementer/rebase-moved.md"; do
    parse "$f" implementer rebase
    validate implementer rebase
    if ((P_BAD)); then unparsable_reason; printf '%s\n' "$UR"; else printf '%s: parses\n' "${f##*/}"; fi
  done
)" || fail "parser exited: $msg"
[ "$msg" = 'bad-move.md: line 7 (Move (rebase mode)) — a value outside its format
rebase-no-nv.md: no Not verified: line
rebase-moved.md: parses' ] || fail "$msg"

current="format: every gate-row fixture parses"
fmt_files=("$fx"/agents/*/*.md)
msg="$(
  # shellcheck source=/dev/null
  source "$src/step.sh"
  for f in "${fmt_files[@]}"; do
    b=${f##*/} d=${f%/*}
    d=${d##*/} mode=
    case $b in today-layout.md | bad-* | *-bad-* | tasks.md | analyze.md) continue ;; esac
    case $d/$b in
      specifier/* | planner/* | tasker/* | shipper/*) agent=$d ;;
      implementer/story-*) agent=implementer mode=story ;;
      implementer/bug-*) agent=implementer mode=bug ;;
      implementer/rebase-*) agent=implementer mode=rebase ;;
      implementer/fix-*) agent=implementer mode=fix ;;
      code-reviewer/* | design-reviewer/*) agent=$d mode=${b%%-*} ;;
      bug-assessor/assess-*) agent=assess ;;
      bug-assessor/test-*) agent='test' ;;
      *) printf 'no schema for %s/%s\n' "$d" "$b"; continue ;;
    esac
    sed -e "s#@TOP@#$work/top#g" -e "s#@REPORT@#$work/top/r.md#g" "$f" >"$work/fmt.md"
    parse "$work/fmt.md" "$agent" "$mode"
    validate "$agent" "$mode"
    if ((P_BAD)); then unparsable_reason; printf '%s/%s: %s\n' "$d" "$b" "$UR"; fi
  done
)" || fail "parser exited: $msg"
[ -z "$msg" ] || fail "$msg"

# --- review gates (US3) --------------------------------------------------------------------
# The merged list's rules, every review gate's rows, the 7e call, review fixes
# and the reviewers' fail-closed formats. A batch's call is the boundary line
# a resume printed, so its snapshot is a real one.

P2_SOFT='- [x] 2 Specify [soft] — spec.md written'
P2_NONE='    - Unchecked checklist items: none'
P3_FACTS='- [x] 3 Plan — merged with 4; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none'
A1_PASS='- [x] 1 Assess [soft] — gate: valid, high confidence, reproduced, 1 remediation(s); size small; risk area none; performance bug no'

# review_case <name> <skill> <size> <phase> [<Log line>...]: a case at a
# review phase whose batch a resume printed; CALL = its boundary words
review_case() {
  new_case "$1" "$2"
  S set Size "$3"
  S set 'Current phase' "$4"
  shift 4
  if [ "$#" -gt 0 ]; then S log "$@"; fi
  run resume "$sf"
  [ "$rc" = 0 ] || fail "resume exit $rc"
  call_line boundary
}

# refused_all <want prefix> <answer>...: each answer call is refused, nothing logged
refused_all() {
  local want="$1" a
  shift
  for a in "$@"; do
    IFS='|' read -r -a extra <<<"$a"
    run "${CALL0[@]}" "${CALL[@]}" "${extra[@]}"
    [ "$rc" = 0 ] && [[ "$out" == "refused: $want"* ]] && [ "$(printf '%s\n' "$out" | wc -l)" = 1 ] || fail "not refused ($want): $a"
    [ "$(grep -c '' "$sf")" = "$before" ] || fail "logged on a refusal: $a"
  done
}

# /feat 4

review_case "merge-zero: 0 findings at /feat 4, soft" feat small '4 Design review' "$P2_SOFT" "$P2_NONE" "$P3_FACTS"
check feat4-small-batch 0
put design-reviewer/4a+4b+4c-zero 4-4a+4b+4c
run feat "$sf" "${CALL[@]}"
check merge-zero 0
zero_out="$out"

# a bare `Findings:` header with one `- none` item reads as `Findings: none`
review_case "dash-none at /feat 4: no finding, the same as merge-zero" feat small '4 Design review' "$P2_SOFT" "$P2_NONE" "$P3_FACTS"
put design-reviewer/4a+4b+4c-dash-none 4-4a+4b+4c
run feat "$sf" "${CALL[@]}"
[ "$out" = "$zero_out" ] || fail "design dash-none: stdout differs from merge-zero"
check design-dash-none 0

review_case "design rules 2 and 5, two tags on one spot, [sec] apply and skip" feat small '4 Design review' "$P2_SOFT" "$P2_NONE" "$P3_FACTS"
put design-reviewer/4a+4b+4c-rules 4-4a+4b+4c
run feat "$sf" "${CALL[@]}"
check design-rules 0
call_line 'answer call'
CALL0=(feat "$sf")
refused_all 'D5 need an answer' 'answer: approved (user: "go")' 'answer: picked D1 (user: "D1 only")'
refused_all 'D9 is not in the merged list' 'answer: approved (user: "go")|answer: fix D9 (user: "go")'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "fine, but leave D5")' 'answer: leave D5 (user: "defined in the glossary")'
check design-rules-approved 0
put planner/plain 3-plan
run feat "$sf" 3 "$R"
check design-rules-amended 0

review_case "design rule 3 and a paraphrase contradicting the brief (medium)" feat medium '4 Design review' "$P2_SOFT" "$P2_NONE" "$P3_FACTS"
check feat4-medium-batch 0
put design-reviewer/4a-rule3 4-4a
put design-reviewer/4b-rule3 4-4b
put design-reviewer/4c-contradicts 4-4c
run feat "$sf" "${CALL[@]}"
check design-rule-3 0

new_case "feat 4 soft with findings to apply: the planner continued, then lens 7b's accepted sec" feat
S set Size small
S set 'Current phase' '4 Design review'
S set Agents 'specifier s1, planner p1 (for SendMessage)'
S log "$P2_SOFT" "$P2_NONE" "$P3_FACTS"
run resume "$sf"
call_line boundary
put design-reviewer/4a+4b+4c-apply 4-4a+4b+4c
run feat "$sf" "${CALL[@]}"
check feat4-soft-apply 0
put planner/plain 3-plan
run feat "$sf" 3 "$R"
check feat4-soft-amended 0
S set 'Current phase' '7 Code review'
S log '- [x] 7 Code review [soft] — auto-applied none; skipped B1 (reviewer: "cosmetic")' '    - B1 src/a.sh:3 — a stray space — rec: skip (cosmetic)'
run resume "$sf"
check feat7-accepted-sec 0

# a skipped design finding of an earlier gate comes back on rejected:
SKIP_A1='- [x] 4 Design review [soft] — auto-applied none; skipped A1 (reviewer: "cosmetic")'
SKIP_A1_SUB='    - A1 spec.md: FR-001 — a stray word — rec: skip (cosmetic)'
review_case "feat 4: an earlier skipped finding on the rejected list" feat small '4 Design review' "$P2_SOFT" "$P2_NONE" "$P3_FACTS" "$SKIP_A1" "$SKIP_A1_SUB"
check feat4-rejected 0

review_case "feat 4 small: the 3 Plan facts and an open checklist item" feat small '4 Design review' \
  "$P2_SOFT" '    - Unchecked checklist items: requirements.md: CHK003 (recommended: yes)' \
  '- [x] 3 Plan — merged with 4; assumptions needing you: 2; constitution: II, IV; blockers: yes; size trigger: service'
put design-reviewer/4a+4b+4c-zero 4-4a+4b+4c
run feat "$sf" "${CALL[@]}"
check feat4-rows 0

review_case "feat 4 medium: facts missing on a run started before this feature" feat medium '4 Design review' '- [x] 2 Specify — spec.md written (soft)'
for l in 4a 4b 4c; do put design-reviewer/4a+4b+4c-zero "4-$l"; done
run feat "$sf" "${CALL[@]}"
check feat4-facts-missing 0

review_case "feat 4 large: always hard, the plan amended after gate 3" feat large '4 Design review' "$P2_SOFT" "$P2_NONE" \
  '- [x] 3 Plan [hard] — large; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none' \
  '    - answer: changed (user: "drop the daemon")' \
  '- [x] 3 Plan — amended; assumptions needing you: none; constitution: pass; blockers: none; size trigger: none'
for l in 4a 4b 4c; do put design-reviewer/4a+4b+4c-zero "4-$l"; done
run feat "$sf" "${CALL[@]}"
check feat4-large 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "go on")'
check feat4-large-approved 0

review_case "format: an untagged design finding" feat small '4 Design review' "$P2_SOFT" "$P2_NONE" "$P3_FACTS"
put design-reviewer/bad-untagged 4-4a+4b+4c
run feat "$sf" "${CALL[@]}"
check fmt-design-untagged 0
reformat_on Findings
call_line boundary
put design-reviewer/bad-untagged 4-4a+4b+4c-2
run feat "$sf" "${CALL[@]}"
check fmt-design-untagged-hard 0

# /feat 7: the merge rules on small (one batch)

merge_case() {
  review_case "$1" feat small '7 Code review'
  put "code-reviewer/$2" 7-7a+7b
  put code-reviewer/7c+7d+7e-zero 7-7c+7d+7e
}

merge_case "merge-rule-2: same spot, section, rec and fix: the first kept" 7a+7b-rule2
run feat "$sf" "${CALL[@]}"
check merge-rule-2 0
run feat "$sf" 7-fixes "$rd/7-fixes.md"
check fixes-missing 0
put implementer/fix-pass 7-fixes
run feat "$sf" 7-fixes "$R"
check fixes-pass 0

merge_case "merge-rule-3: two reviewers disagree on one spot" 7a+7b-rule3
put code-reviewer/7a-rule3 7-7a
# a third report the batch never issued: the record is dropped so the call is
# judged as on a run started before it (allowed_tokens alone)
command rm -f "$rd/last-step.md"
run feat "$sf" 7 "${CALL[1]}" "$rd/7-7a.md" "${CALL[2]}" "${CALL[3]}"
check merge-rule-3 0

merge_case "merge-rule-4: a high-confidence bug the reviewer would skip" 7a+7b-rule4
run feat "$sf" "${CALL[@]}"
check merge-rule-4 0

merge_case "merge-rule-5: a rec outside its set, missing or not last" 7a+7b-rule5
run feat "$sf" "${CALL[@]}"
check merge-rule-5 0

merge_case "merge-rule-6: a security finding the reviewer would skip" 7a+7b-rule6
run feat "$sf" "${CALL[@]}"
check merge-rule-6 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "fix it")' 'answer: fix S1 (user: "fix it")'
check merge-rule-6-fixed 0

# the override after a soft review gate whose call logged the Ship line
review_case "answers: an override after a soft 7 with nothing to apply" feat small '7 Code review'
put code-reviewer/7a+7b-zero 7-7a+7b
put code-reviewer/7c+7d+7e-zero 7-7c+7d+7e
run feat "$sf" "${CALL[@]}"
call_line 'answer call'
S log '    - override: hard — the user wants to read the diff first'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "ship it")'
check override-after-review 0

# lenses written as a bare header and one `- none` item: no finding, soft (#73)
review_case "dash-none at /feat 7: the zero reports, for comparison" feat small '7 Code review'
put code-reviewer/7a+7b-zero 7-7a+7b
put code-reviewer/7c+7d+7e-zero 7-7c+7d+7e
run feat "$sf" "${CALL[@]}"
zero_out="$out"
review_case "dash-none at /feat 7: Bugs, Spec and Security read none" feat small '7 Code review'
put code-reviewer/7a+7b-dash-none 7-7a+7b
put code-reviewer/7c+7d+7e-zero 7-7c+7d+7e
run feat "$sf" "${CALL[@]}"
[ "$out" = "$zero_out" ] || fail "code dash-none: stdout differs from the zero reports"
case $out in *finding:* | hard*) fail "code dash-none: a finding or a hard gate" ;; esac
check code-dash-none 0

# /feat 7 small: the rows, the outcome, then review fixes and rule 1 drops

review_case "feat 7 small: a user finding, a criterion not met, untested, cuts" feat small '7 Code review'
put code-reviewer/7a+7b-gate 7-7a+7b
put code-reviewer/7c+7d+7e-cuts 7-7c+7d+7e
run feat "$sf" "${CALL[@]}"
check feat7-rows 0
call_line 'answer call'
CALL0=(feat "$sf")
refused_all 'dropped: B1: only a P or R finding' 'answer: approved (user: "x")|answer: leave B2 (user: "x")|dropped: B1 (cut by C1)'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "go, keep the flag")' 'answer: leave B2 (user: "keep the flag")' 'dropped: P1 (cut by C1)'
check feat7-rows-approved 0
CALL=()
CALL0=(feat "$sf" 7-fixes)
refused_all 'dropped: ' 'dropped: B1 (cut by C1)' 'dropped: C1 (cut by C1)' 'dropped: R1 (cut by B1)' \
  'dropped: S1 (cut by C1)' 'dropped: [std]1 (cut by C1)' 'dropped: R9 (cut by C1)'
run feat "$sf" 7-fixes 'dropped: R1 (cut by C1)'
check fixes-dropped 0
put implementer/fix-fail 7-fixes
run feat "$sf" 7-fixes "$R"
check fixes-retry 0
put implementer/fix-fail 7-fixes-2
run feat "$sf" 7-fixes "$R"
check fixes-retry-hard 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: stop (user: "later")'
check fixes-stop 0

# diff_same <what>: reports/review.diff holds exactly `git diff <base>`
diff_same() {
  local base
  base="$(git -C "$top" merge-base origin/main HEAD)"
  [ -f "$rd/review.diff" ] && [ ! -L "$rd/review.diff" ] || fail "$1: no review.diff"
  git -C "$top" diff "$base" >"$work/want.diff"
  [ -s "$work/want.diff" ] || fail "$1: the case's diff is empty"
  cmp -s "$work/want.diff" "$rd/review.diff" || fail "$1: review.diff differs from git diff <base>"
  printf '%s\n' "$out" | grep -qx "  diff file: @TOP@/specs/x/reports/review.diff" || fail "$1: no diff file: line"
}

# /feat 7 medium and large: 7a-7d, then 7e

medium7() {
  review_case "$1" feat "$2" '7 Code review' "${@:3}"
  put code-reviewer/7a-plain 7-7a
  put code-reviewer/7b-sec 7-7b
  put code-reviewer/7c-zero 7-7c
  put code-reviewer/7d-zero 7-7d
  # the 7e call writes the review diff itself (a resumed 7e may have none)
  command rm -f "$rd/review.diff"
  run feat "$sf" "${CALL[@]}"
  call_line boundary
  put code-reviewer/7e-zero 7-7e
}

medium7 "feat 7 medium: 7e after 7a-7d, the gate, the answer" medium
check feat7-medium-first 0
diff_same "7e names the same file and writes it"
run feat "$sf" "${CALL[@]}"
check feat7-medium-gate 0
call_line 'answer call'
CALL0=(feat "$sf")
refused_all 'B2 need an answer' 'answer: approved (user: "go")'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "drop the flag too")' 'answer: fix B2 (user: "drop the flag too")'
check feat7-medium-approved 0

medium7 "feat 7 medium: a skipped finding of gate 4 reaches the 7e spawn" medium "$SKIP_A1" "$SKIP_A1_SUB"
check feat7e-rejected 0

medium7 "feat 7 medium: a 7a-7d report edited before the 7e call" medium
printf 'edited\n' >>"$rd/7-7a.md"
run feat "$sf" "${CALL[@]}"
check feat7-changed-report 0

medium7 "feat 7 medium: a file changed outside the reports" medium
printf 'more\n' >>"$top/README.md"
run feat "$sf" "${CALL[@]}"
check feat7-snapshot-changed 0

# the coordinator's board-move Log line, written while the reviewers run, is
# not a change outside the reports: the same output as without it
medium7 "feat 7 medium: a state-file log line between the 7e spawn and its boundary stays soft" medium
S log '- [!] tracker: #73 not set to "In review" (gh failed)'
run feat "$sf" "${CALL[@]}"
check feat7-medium-gate 0

medium7 "feat 7 large: always hard" large
run feat "$sf" "${CALL[@]}"
check feat7-large 0

# without <word>: CALL less the words holding it
without() {
  local w
  LESS=()
  for w in "${CALL[@]}"; do [[ $w == *"$1"* ]] || LESS+=("$w"); done
}
# usage_no_log <prefix>: a usage line starting so, and nothing logged
usage_no_log() {
  one_line 2 "step: usage: $1"
  [ "$(grep -c '' "$sf")" = "$before" ] || fail "logged on a usage error"
}

# every group of the batch reported, at the first call and at 7e
review_case "batch: the 7 call without lens 7d's report is usage" feat medium '7 Code review'
put code-reviewer/7a-plain 7-7a
put code-reviewer/7b-sec 7-7b
put code-reviewer/7c-zero 7-7c
without 7-7d.md
run feat "$sf" "${LESS[@]}"
usage_no_log 'boundary 7 takes a report for each of the batch'"'"'s groups, 7-7d missing'

medium7 "batch: the 7e call without lens 7b's report is usage" medium
without 7-7b.md
run feat "$sf" "${LESS[@]}"
usage_no_log 'boundary 7e takes a report for each of the batch'"'"'s groups, 7-7b missing'

# a report passed again needs its sum=: 7a-7d's at 7e
medium7 "batch: a 7a-7d report at 7e without its sum= is usage" medium
without sum=7-7a.md
run feat "$sf" "${LESS[@]}"
usage_no_log 'sum= missing for 7-7a.md'

# a group's missing report: one fresh spawn of that group, logged, with the
# other reports' reformat turns; a second miss of the group is hard; any
# other failed check in the call stays hard at once

review_case "batch: 7d's report missing and 7c's slip: 7d again, 7c reformatted" feat medium '7 Code review'
put code-reviewer/7a-plain 7-7a
put code-reviewer/7b-sec 7-7b
put code-reviewer/bad-7c-slip 7-7c
run feat "$sf" "${CALL[@]}"
check batch-missing-slip 0
call_line boundary
put code-reviewer/7c-zero 7-7c-2
put code-reviewer/7d-zero 7-7d
without sum=7-7a.md
run feat "$sf" "${LESS[@]}"
usage_no_log 'sum= missing for 7-7a.md'
run feat "$sf" "${CALL[@]}"
check batch-missing-slip-7e 0

review_case "batch: 7d's report missing twice: hard" feat medium '7 Code review'
put code-reviewer/7a-plain 7-7a
put code-reviewer/7b-sec 7-7b
put code-reviewer/7c-zero 7-7c
run feat "$sf" "${CALL[@]}"
check batch-missing 0
call_line boundary
run feat "$sf" "${CALL[@]}"
check batch-missing-twice 0

review_case "batch: 7d's report missing and a failed check: hard at once" feat medium '7 Code review'
put code-reviewer/7a-plain 7-7a
printf -- '- relative.md\n' >>"$R"
put code-reviewer/7b-sec 7-7b
put code-reviewer/7c-zero 7-7c
run feat "$sf" "${CALL[@]}"
check batch-missing-check 0

review_case "batch: 7d's report missing and a file changed outside the reports: hard at once" feat medium '7 Code review'
put code-reviewer/7a-plain 7-7a
put code-reviewer/7b-sec 7-7b
put code-reviewer/7c-zero 7-7c
printf 'more\n' >>"$top/README.md"
run feat "$sf" "${CALL[@]}"
check batch-missing-snapshot 0

medium7 "batch: 7e's report missing and a 7a-7d report edited: hard at once" medium
printf 'edited\n' >>"$rd/7-7a.md"
command rm -f "$rd/7-7e.md"
run feat "$sf" "${CALL[@]}"
check batch-missing-changed 0

medium7 "batch: 7e's report missing: 7e again, its cuts kept" medium
command rm -f "$rd/7-7e.md"
run feat "$sf" "${CALL[@]}"
check feat7e-missing 0
call_line boundary
put code-reviewer/7e-zero 7-7e
run feat "$sf" "${CALL[@]}"
check feat7-medium-gate 0

# the answer call's reports give back the list the gate logged
medium7 "answers: a call whose reports lose a logged finding is usage" medium
run feat "$sf" "${CALL[@]}"
call_line 'answer call'
without 7-7b.md
run feat "$sf" "${LESS[@]}" 'answer: approved (user: "go")' 'answer: fix B2 (user: "go")'
usage_no_log "the answer call's reports do not give back gate 7's findings"

# the code reviewers' formats fail closed

for v in bad-no-security:'Security \(7b\)' bad-indented:'Bugs \(7a\)' bad-star:'Security \(7b\)' \
  bad-stray-7c:'Performance \(7c\)' bad-stray-net:net; do
  review_case "format: code reviewer ${v%%:*}" feat small '7 Code review'
  put "code-reviewer/${v%%:*}" 7-7a+7b
  put code-reviewer/7c+7d+7e-zero 7-7c+7d+7e
  run feat "$sf" "${CALL[@]}"
  check "fmt-review-${v%%:*}" 0
  reformat_on "${v#*:}"
  call_line boundary
  put "code-reviewer/${v%%:*}" 7-7a+7b-2
  run feat "$sf" "${CALL[@]}"
  check "fmt-review-${v%%:*}-hard" 0
done

# after a reformat line, only the reformatted report may come without sum=
review_case "batch: after a reformat, another report without its sum= is usage" feat small '7 Code review'
put code-reviewer/bad-star 7-7a+7b
put code-reviewer/7c+7d+7e-zero 7-7c+7d+7e
run feat "$sf" "${CALL[@]}"
reformat_on 'Security \(7b\)'
call_line boundary
put code-reviewer/7a+7b-zero 7-7a+7b-2
without sum=7-7c+7d+7e.md
run feat "$sf" "${LESS[@]}"
usage_no_log 'sum= missing for 7-7c+7d+7e.md'
run feat "$sf" "${CALL[@]}"
[ "$rc" = 0 ] || fail "the full reformat call: exit $rc"

# /fix 4

review_case "fix 4 medium: the default groups" fix medium '4 Code review' "$A1_PASS"
check fix4-default-batch 0
review_case "fix 4 medium: the performance groups" fix medium '4 Code review' "${A1_PASS% no} yes"
check fix4-perf-batch 0
review_case "fix 4 medium: performance bug missing reads as yes" fix medium '4 Code review' \
  '- [x] 1 Assess [soft] — gate: valid, high confidence, reproduced, 1 remediation(s); size small; risk area none'
check fix4-perf-missing-batch 0

review_case "fix 4 medium: a group's report missing: that group again" fix medium '4 Code review' "$A1_PASS"
run fix "$sf" "${CALL[@]}"
check fix4-missing 0
call_line boundary
put code-reviewer/7a+7b-zero 4-7a+7b
run fix "$sf" "${CALL[@]}"
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | head -n 1)" != reformat ] || fail "the respawned group's report: exit $rc or reformat again"

review_case "fix 4 small: nothing found, phase 5" fix small '4 Code review' "$A1_PASS"
put code-reviewer/7a+7b+7d-zero 4-7a+7b+7d
run fix "$sf" "${CALL[@]}"
check fix4-soft-zero 0

review_case "fix 4 small: a state-file log line between the spawn and its boundary stays soft" fix small '4 Code review' "$A1_PASS"
put code-reviewer/7a+7b+7d-zero 4-7a+7b+7d
S log '- [x] tracker: #73 set to "In review"'
run fix "$sf" "${CALL[@]}"
check fix4-soft-zero 0

review_case "fix 4 medium: a fix to apply, then the implementer, then the test" fix medium '4 Code review' "$A1_PASS" \
  '- [x] 2 implementer — not verified: none' '- [x] 2 Fix [soft] — applied; no deviations; checks pass' '- [x] 3 Test [soft] — verified'
put code-reviewer/7a+7b-plain 4-7a+7b
run fix "$sf" "${CALL[@]}"
check fix4-fixes-spawn 0
put implementer/fix-pass 4-fixes
run fix "$sf" 4-fixes "$R"
check fix4-fixes-done 0

review_case "fix 4: a security bug, the go-ahead" fix medium '4 Code review' "${A1_PASS/risk area none/risk area security}"
put code-reviewer/7a+7b-plain 4-7a+7b
run fix "$sf" "${CALL[@]}"
check fix4-security 0
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "ship it after the fix")'
check fix4-security-approved 0

review_case "fix 4: risk area missing reads as security" fix small '4 Code review' \
  '- [x] 1 Assess [soft] — gate: valid, high confidence, reproduced, 1 remediation(s); size small'
put code-reviewer/7a+7b+7d-zero 4-7a+7b+7d
run fix "$sf" "${CALL[@]}"
check fix4-risk-missing 0

fix_at "fix: skip 4 on a security bug" '3 Test'
S log "${A1_PASS/risk area none/risk area security}" '- [x] 2 implementer — not verified: none' '- [x] 2 Fix [soft] — applied; no deviations; checks pass'
put bug-assessor/test-partial 3-test
run fix "$sf" 3 "$R"
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: skip 4 (user: "no review")'
check fix-skip4 0
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "ship it unreviewed")'
check fix-skip4-approved 0

# --- base, repair and diff checks; moves (US4) ---------------------------------------------
# Throwaway repos only: each case's origin is a bare repo under the scratch
# dir (its own one when main moves), never this checkout's remote.

new_case "base-same: main has not moved, nothing logged" feat
put specifier/soft 2-specify
run feat "$sf" 2 "$R"
check base-same 0

new_case "worktree-none: the top level from the state file's dir" feat
S set Worktree none
put specifier/soft 2-specify
run feat "$sf" 2 "$R"
check worktree-none 0

new_case "space-in-path: a worktree under a path holding a space" feat
git -C "$top" worktree add -q -b wt "$work/c/$n/with space" 2>/dev/null
top="$(cd "$work/c/$n/with space" && pwd -P)"
sf="$top/specs/x/feat-state.md"
rd="$top/specs/x/reports"
sed "s#@TOP@#$top#g" "$fx/states/feat.md" >"$sf"
mkdir -p "$rd"
printf '*\n' >"$rd/.gitignore"
put specifier/soft 2-specify
run feat "$sf" 2 "$R"
check space-in-path 0
call_line boundary
[ "${CALL[1]}" = "$top/specs/x/reports/3-plan.md" ] || fail "the spaced report path is not one word: ${CALL[1]}"

new_case "base-moved: the rebase spawn in place of the phase's" feat
own_origin
move_main
put specifier/soft 2-specify
run feat "$sf" 2 "$R"
check base-moved 0
call_line boundary
put_at implementer/rebase-moved "${CALL[1]}"
run feat "$sf" "${CALL[@]}"
check move-kept 0

new_case "fix: base moved before phase 3, the implement row is 2" fix
S set Size small
S set 'Current phase' '2 Fix'
S log '- [x] 1 Assess [soft] — gate: valid, high confidence, reproduced, 1 remediation(s); size small; risk area none; performance bug no'
own_origin
move_main
put implementer/bug-pass 2-fix
run fix "$sf" 2 "$R"
check fix-base-moved 0

new_case "base-refused: main still where the user refused it" feat
own_origin
move_main
S log "- [x] move — stayed on ${OLD:0:7}, refused ${NEW:0:7} (user: \"not now\")"
put specifier/soft 2-specify
run feat "$sf" 2 "$R"
check base-refused 0

new_case "base-fetch-failed: the phase goes on" feat
git -C "$top" remote set-url origin "$top/nope.git"
put specifier/soft 2-specify
run feat "$sf" 2 "$R"
check base-fetch-failed 0

new_case "default-branch-dash: a remote default branch named -x" feat
own_origin
git -C "$work/c/$n/origin.git" update-ref refs/heads/-x refs/heads/main
git -C "$work/c/$n/origin.git" symbolic-ref HEAD refs/heads/-x
git -C "$top" remote set-head origin -d >/dev/null
put specifier/soft 2-specify
run feat "$sf" 2 "$R"
check default-branch-dash 1

# move_case <name>: a case where main moved before phase 3; CALL = the move's
# boundary words
move_case() {
  new_case "$1" feat
  own_origin
  move_main
  put specifier/soft 2-specify
  run feat "$sf" 2 "$R"
  call_line boundary
}

move_case "move undone, then stay"
put_at implementer/rebase-undone "${CALL[1]}"
run feat "$sf" "${CALL[@]}"
check move-undone 0
call_line 'answer call'
CALL0=(feat "$sf")
refused_all 'skip 4 is not valid' 'answer: skip 4 (user: "x")'
run feat "$sf" "${CALL[@]}" 'answer: stay (user: "not now")'
check move-stay 0
[ "$(bash "$skill/scripts/state.sh" refused-base "$sf")" = 5d6e7f8 ] || fail "refused-base does not read the stayed line"

move_case "move undone, then approved: a fresh rebase spawn"
put_at implementer/rebase-undone "${CALL[1]}"
run feat "$sf" "${CALL[@]}"
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "take the recommendations")'
check move-undone-approved 0

move_case "move: nothing to do"
put_at implementer/rebase-nothing "${CALL[1]}"
run feat "$sf" "${CALL[@]}"
check move-nothing 0

move_case "move: no report and no repair due"
run feat "$sf" "${CALL[@]}"
check move-missing 0

move_case "move: no report, a pre-move ref: the repair spawn"
git -C "$top" update-ref refs/logistics/pre-move/feat-x HEAD
run feat "$sf" "${CALL[@]}"
check move-missing-repair 0

new_case "repair-ref: resume repairs first" feat
S set 'Current phase' '3 Plan'
S log '- [x] 2 Specify [soft] — spec.md written' '    - Unchecked checklist items: none'
git -C "$top" update-ref refs/logistics/pre-move/feat-x HEAD
run resume "$sf"
check repair-ref 0
call_line boundary
put_at implementer/rebase-repaired "${CALL[1]}"
run feat "$sf" "${CALL[@]}"
check repair-done 0

new_case "repair-wip: a logistics-wip commit" fix
S set Size small
S set 'Current phase' '2 Fix'
git -C "$top" commit -q --allow-empty -m 'logistics-wip: fix-7-page'
run resume "$sf"
check repair-wip 0

# diff_case <name>: /feat small at 7 Code review
diff_case() {
  new_case "$1" feat
  S set Size small
  S set 'Current phase' '7 Code review'
}

diff_case "diff-empty: no change since the base, no spawn"
git -C "$top" checkout -q -- src/a.sh
run resume "$sf"
check diff-empty 0
call_line 'answer call'
CALL0=(feat "$sf")
refused_all 'picked is not valid' 'answer: picked B1 (user: "x")'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "nothing to review")'
check diff-empty-approved 0

diff_case "diff-new-files: only the run's wrote: paths are marked"
S log '- [x] 6 US1 — not verified: none' '    - wrote: src/new.sh'
printf 'my notes\n' >"$top/notes.txt"
run resume "$sf"
check diff-new-files 0
git -C "$top" ls-files --error-unmatch src/new.sh >/dev/null 2>&1 || fail "src/new.sh not marked intent-to-add"
git -C "$top" ls-files --error-unmatch notes.txt >/dev/null 2>&1 && fail "notes.txt entered the index"
base="$(git -C "$top" merge-base origin/main HEAD)"
git -C "$top" diff --name-only "$base" | grep -qx src/new.sh || fail "src/new.sh not in the diff"
git -C "$top" diff --name-only "$base" | grep -qx notes.txt && fail "notes.txt in the diff"

diff_case "diff-wrote-dir: a directory on Wrote: marks nothing under it"
S log '- [x] 6 US1 — not verified: none' '    - wrote: src/new.sh' '    - wrote: src'
printf 'KEY=1\n' >"$top/src/.env.local"
run resume "$sf"
check diff-wrote-dir 0
git -C "$top" ls-files --error-unmatch src/new.sh >/dev/null 2>&1 || fail "src/new.sh not marked intent-to-add"
git -C "$top" ls-files --error-unmatch src/.env.local >/dev/null 2>&1 && fail "src/.env.local entered the index"
printf '%s\n' "$out" | grep -qx 'untracked, not in the diff: src/.env.local' || fail "src/.env.local not listed as untracked"

diff_case "diff-no-facts: nothing marked"
run resume "$sf"
check diff-no-facts 0
git -C "$top" ls-files --error-unmatch src/new.sh >/dev/null 2>&1 && fail "src/new.sh marked with no wrote: fact"

diff_case "diff-many: more than 20 other untracked files"
mkdir -p "$top/junk"
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do : >"$top/junk/f$i"; done
run resume "$sf"
check diff-many 0

diff_case "diff-file: the review boundary writes reports/review.diff"
run resume "$sf"
check diff-file 0
diff_same "first boundary"
[ "$(printf '%s\n' "$out" | grep -c '^  diff file: ')" = "$(printf '%s\n' "$out" | grep -c '^spawn: feat-code-reviewer')" ] || fail "a reviewer block lacks diff file:"
git -C "$top" check-ignore -q "$rd/review.diff" || fail "review.diff is not ignored by git"
git -C "$top" status --porcelain --untracked-files=all | grep -q 'review\.diff' && fail "review.diff shows in git status"
snap1="$(bash "$skill/scripts/state.sh" snapshot "$sf")"
printf 'stale\n' >>"$rd/review.diff"
snap2="$(bash "$skill/scripts/state.sh" snapshot "$sf")"
[ "$snap1" = "$snap2" ] || fail "review.diff is part of state.sh snapshot"
printf 'echo c\n' >>"$top/src/a.sh"
run resume "$sf"
[ "$rc" = 0 ] || fail "second boundary: exit $rc"
diff_same "a later boundary rewrites it"
for t in "$rd"/.review.diff.*; do [ ! -e "$t" ] || fail "a temp file was left in reports/: $t"; done

diff_case "diff-file-empty: an empty diff writes no review.diff"
git -C "$top" checkout -q -- src/a.sh
run resume "$sf"
[ "$rc" = 0 ] || fail "exit $rc"
printf '%s\n' "$out" | grep -q '^spawn: ' && fail "a reviewer was spawned on an empty diff"
[ ! -e "$rd/review.diff" ] || fail "review.diff written for an empty diff"

diff_case "diff-file-symlink: a symlink at reports/review.diff is an error"
ln -s "$work/elsewhere.diff" "$rd/review.diff"
run resume "$sf"
one_line 1 'step: error: review diff is a symlink: @TOP@/specs/x/reports/review.diff'
[ ! -e "$work/elsewhere.diff" ] || fail "the diff was written through the symlink"
[ -L "$rd/review.diff" ] || fail "the symlink was replaced"

new_case "ship conflict after a renumber: the move, then the ship again at the new path" feat
S set 'Current phase' 'done (shipping)'
S log '- [x] 8 Ship'
put shipper/conflict 8-ship
sed -i "s#$top/specs/x/#$top/specs/012-x/#g" "$R"
mv "$top/specs/x" "$top/specs/012-x"
old_sf="$sf"
sf="$top/specs/012-x/feat-state.md"
run feat "$old_sf" 8 "$R"
check ship-conflict 0
call_line boundary
[ "${#CALL[@]}" = 4 ] && [ "${CALL[0]}" = 8 ] || fail "want 8, the ship report, the move report, its sum"
put_at implementer/rebase-moved "${CALL[2]}"
run feat "$sf" "${CALL[@]}"
check ship-conflict-moved 0

new_case "ship conflict, the move undone, approved: the move again, then the ship" feat
S set 'Current phase' 'done (shipping)'
S log '- [x] 8 Ship'
put shipper/conflict 8-ship
run feat "$sf" 8 "$R"
call_line boundary
put_at implementer/rebase-undone "${CALL[2]}"
run feat "$sf" "${CALL[@]}"
check ship-conflict-undone 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "ok")'
call_line boundary
[ "${CALL[0]}" = move ] || fail "want the move boundary, got ${CALL[0]}"
put_at implementer/rebase-moved "${CALL[1]}"
run feat "$sf" "${CALL[@]}"
check ship-conflict-undone-moved 0

# --- full runs: tags, answers, the queries and the counts (US5) ----------------------------
# Whole /feat runs (small, large) and a /fix run with a retry and a back to,
# through step.sh, with every answer kind and one override. Each call puts
# the named fixtures at the new report paths its boundary line names. The
# run's state file (top level @TOP@, the moved main's shas those of the
# rebase fixtures) is fixtures/logs/full-<run>.md, which log-readers-agree
# reads too; state.sh's queries on it give expected/full-<run>.queries, and
# so do they on fixtures/logs/untagged-full-<run>.md, the same outcomes in
# today's untagged Log lines. SC-003: grep counts of the tags, the override
# and each answer kind equal the gates and answers the run made.

all_kinds=()

# full_start <skill> <run> <state fixture>: a new run, set up; counts reset
full_start() {
  fsk="$1" full="$2" n_soft=0 n_hard=0 n_ovr=0 kinds=() OLD='' NEW=''
  new_case "full run: $2" "$3"
  run "$fsk" "$sf" setup
  [ "$rc" = 0 ] || fail "setup exit $rc"
}

# full_go <fixture>...: each fixture at the next new report path the
# boundary line names, then that call; a hard verdict is a gate, and so is
# a soft one that prints an answer call (step-cli.md, Output)
full_go() {
  local w a=() i=0
  call_line boundary
  for w in "${CALL[@]}"; do
    if [[ "$w" == /* && ! -f "$w" && "$i" -lt "$#" ]]; then
      i=$((i + 1))
      put_at "${!i}" "$w"
    fi
    a+=("$w")
  done
  [ "$i" = "$#" ] || fail "$# fixtures for $i new reports"
  run "$fsk" "$sf" "${a[@]}"
  [ "$rc" = 0 ] || fail "exit $rc"
  case "${out%%$'\n'*}" in
    hard:) n_hard=$((n_hard + 1)) ;;
    soft) if printf '%s\n' "$out" | grep -q '^answer call:'; then n_soft=$((n_soft + 1)); fi ;;
    *) fail "verdict: ${out%%$'\n'*}" ;;
  esac
}

# full_ans <argument>...: the answer call with these arguments, accepted
full_ans() {
  local a
  call_line 'answer call'
  run "$fsk" "$sf" "${CALL[@]}" "$@"
  [ "$rc" = 0 ] && [ "${out%%$'\n'*}" = answered ] || fail "not answered: $*"
  for a in "$@"; do
    case "$a" in 'answer: '*)
      a="${a#answer: }"
      kinds+=("${a%% (user: *}")
      all_kinds+=("${a%% (user: *}") ;;
    esac
  done
}

# full_override <reason>: the coordinator's override of the soft gate just made
full_override() {
  S log "    - override: hard — $1"
  n_ovr=$((n_ovr + 1))
}

# queries <state file> <review phase>: Q = every gate-reading query's answer
queries() {
  local q
  Q=''
  for q in phase2-mode cycle retry-used shipped-verdict refused-base; do
    Q+="$q: $(bash "$skill/scripts/state.sh" "$q" "$1" || true)"$'\n'
  done
  Q+="review-summary $2:"$'\n'"$(bash "$skill/scripts/state.sh" review-summary "$1" "$2" || true)"
}

# full_end <review phase>: the state file against its copy in fixtures/logs,
# the queries on it and on the untagged copy against one golden, SC-003
full_end() {
  local f="$fx/logs/full-$full.md" u="$fx/logs/untagged-full-$full.md" got
  got="$(cat "$sf")"
  got="${got//"$top"/@TOP@}"
  if [ -n "$OLD" ]; then
    got="${got//"${OLD:0:7}"/1a2b3c4}"
    got="${got//"${NEW:0:7}"/5d6e7f8}"
  fi
  if [ "$update" = 1 ]; then
    printf '%s\n' "$got" >"$f"
    updated=1
  else
    [ "$got" = "$(cat "$f")" ] || { out="$got"; fail "state file differs from fixtures/logs/full-$full.md"; }
  fi
  queries "$f" "$1"
  if [ "$update" = 1 ]; then printf '%s\n' "$Q" >"$ex/full-$full.queries"; fi
  [ "$Q" = "$(cat "$ex/full-$full.queries")" ] || { out="$Q"; fail "queries differ from expected/full-$full.queries"; }
  queries "$u" "$1"
  [ "$Q" = "$(cat "$ex/full-$full.queries")" ] || { out="$Q"; fail "the untagged copy answers differently"; }
  sc003 "$f"
}

# sc003 <state file>: matching lines count the gates, the overrides and each
# answer kind the run made (#21)
sc003() {
  local n k a want
  current="SC-003 counts: $full"
  n="$(grep -c '^- \[x\] .* \[soft\] — ' "$1" || true)"
  [ "$n" = "$n_soft" ] || fail "$n [soft] lines, $n_soft soft gates"
  n="$(grep -c '^- \[x\] .* \[hard\] — ' "$1" || true)"
  [ "$n" = "$n_hard" ] || fail "$n [hard] lines, $n_hard hard gates"
  n="$(grep -c '^    - override: hard — ' "$1" || true)"
  [ "$n" = "$n_ovr" ] || fail "$n override lines, $n_ovr overrides"
  n="$(grep -c '^    - answer: ' "$1" || true)"
  [ "$n" = "${#kinds[@]}" ] || fail "$n answer lines, ${#kinds[@]} answers"
  for k in approved 'picked ' changed 'back to ' 'skip ' 'size ' stop stay 'ship with ' 'fix ' 'leave '; do
    want=0
    for a in ${kinds[@]+"${kinds[@]}"}; do
      case "$a" in "$k"*) want=$((want + 1)) ;; esac
    done
    n="$(grep -c "^    - answer: $k" "$1" || true)"
    [ "$n" = "$want" ] || fail "$n answer: $k lines, $want such answers"
  done
}

full_start feat feat-small feat
full_go specifier/markers
full_ans 'answer: changed (user: "answer the markers as recommended")' 'answer: size small (user: "it is small")'
full_go specifier/soft
full_go planner/plain
full_go design-reviewer/4a+4b+4c-rules
# shellcheck disable=SC2016 # the user's words, logged byte for byte
leave_words='it'\''s the glossary'\''s job; see $HOME, `page` and (FR-001)'
full_ans 'answer: picked D1, D2 (user: "D1 and D2 only")' "answer: leave D5 (user: \"$leave_words\")"
grep -qxF "    - answer: leave D5 (user: \"$leave_words\")" "$sf" || fail "the leave words are not logged byte for byte"
grep -qxF "    - outcome: picked D1, D2; rejected D5 (user: \"$leave_words\")" "$sf" || fail "the leave words are not on the outcome"
full_go planner/plain
put_analyze
full_go tasker/match
full_override 'the user wants to see the tasks'
full_ans 'answer: approved (user: "go on")'
full_go implementer/story-pass
full_go implementer/story-clean
# AC 5.5: the next reviewer spawns carry the user's words on their rejected: lines
leave_n=0
while IFS= read -r p; do
  if grep -qxF "  - D5 spec.md: FR-001 — $leave_words" "$p"; then leave_n=$((leave_n + 1)); fi
done < <(printf '%s\n' "$raw" | sed -n 's/^  inputs: //p')
[ "$leave_n" = 2 ] || fail "the leave words are not on both rejected: lists"
full_go code-reviewer/7a+7b-gate code-reviewer/7c+7d+7e-cuts
full_ans 'answer: picked B1, C1 (user: "B1 and C1")' 'answer: fix B2 (user: "drop the flag")'
full_go implementer/fix-pass
full_go shipper/pr
[ "$(printf '%s\n' "$out" | tail -n 1)" = 'done: PR #42' ] || fail "not shipped"
full_end 7

# big_tasks: the tasker's report R and tasks.md at 62 tasks, so a large run
# stays large at gate 5
# shellcheck disable=SC2016 # the backticks are tasks.md's, not a command
big_tasks() {
  local i
  {
    printf '# Tasks: test feature\n\n## Phase 1: Setup\n\n'
    printf -- '- [ ] T001 Create `src/a.sh`\n- [ ] T002 Create `src/b.sh`\n\n## Phase 2: User Story 1 - Run a step\n\n'
    for ((i = 3; i <= 40; i++)); do printf -- '- [ ] T%03d [US1] Write `src/a.sh`\n' "$i"; done
    printf '\n## Phase 3: User Story 2 - Resume\n\n'
    for ((i = 41; i <= 61; i++)); do printf -- '- [ ] T%03d [US2] Write `src/b.sh`\n' "$i"; done
    printf '\n## Phase 4: Polish\n\n- [ ] T062 Docs in `README.md`\n'
  } >"$top/specs/x/tasks.md"
  sed -i -e 's/^Total tasks: 6$/Total tasks: 62/' -e 's/^- US1: T003-T004$/- US1: T003-T040/' \
    -e 's/^- US2: T005$/- US2: T041–T061/' -e 's/^- polish: T006$/- polish: T062/' "$R"
}

full_start feat feat-large feat
S set Size large
own_origin
full_go specifier/soft
full_go planner/plain
full_ans 'answer: approved (user: "plan ok")'
full_go design-reviewer/4a+4b+4c-zero design-reviewer/4a+4b+4c-zero design-reviewer/4a+4b+4c-zero
full_ans 'answer: back to 3 (user: "redo the plan")'
full_go planner/plain
move_main
full_ans 'answer: skip 4 (user: "reviewed it already")'
call_line boundary
[ "${CALL[0]}" = move ] || fail "want the move, got ${CALL[0]}"
put_at implementer/rebase-undone "${CALL[1]}"
sed -i -e "s/1a2b3c4/${OLD:0:7}/g" -e "s/5d6e7f8/${NEW:0:7}/g" "$R"
full_go
full_ans 'answer: stay (user: "not now")'
call_line boundary
put_at tasker/match "${CALL[1]}"
put_analyze
big_tasks
full_go
full_ans 'answer: approved (user: "62 tasks is fine")'
full_go implementer/story-pass
full_ans 'answer: approved (user: "US1 ok")'
full_go implementer/story-clean
full_ans 'answer: approved (user: "US2 ok")'
full_go code-reviewer/7a-plain code-reviewer/7b-sec code-reviewer/7c-zero code-reviewer/7d-zero
full_go code-reviewer/7e-zero
full_ans 'answer: approved (user: "fix them, keep the flag")' 'answer: leave B2 (user: "keep the flag")'
full_go implementer/fix-fail
full_go implementer/fix-fail
full_ans 'answer: stop (user: "later")'
[ "$(printf '%s\n' "$out" | tail -n 1)" = 'done: stopped (user)' ] || fail "not stopped"
full_end 7

full_start fix fix fix
full_go bug-assessor/assess-hard
full_ans 'answer: approved (user: "go")' 'security: advisory (user: "an advisory")'
full_go implementer/bug-pass
full_go bug-assessor/test-failed
full_go implementer/bug-pass
full_go bug-assessor/test-failed
full_ans 'answer: back to 1 (user: "re-assess with the failed reports")'
full_go bug-assessor/assess-soft
full_go implementer/bug-pass
full_go bug-assessor/test-partial
full_ans 'answer: ship with partial (user: "partial is enough")'
full_go code-reviewer/7a+7b+7d-zero
full_go shipper/pr
[ "$(printf '%s\n' "$out" | tail -n 1)" = 'done: PR #42' ] || fail "not shipped"
full_end 4

current="full runs: every answer kind"
for k in approved 'picked ' changed 'back to ' 'skip ' 'size ' stop stay 'ship with ' 'fix ' 'leave '; do
  printf '%s\n' "${all_kinds[@]}" | grep -q "^$k" || fail "no answer: $k in the full runs"
done

# R15: every Log line step.sh wrote in a golden or a full run is a tagged
# gate line or one of the untagged records
current="tags: gate lines tagged, records not"
records='^- \[x\] (0 Setup — |6 US[0-9]+ — |[24] implementer — |7 review fixes — |3 Plan — (merged with 4|amended)|[58] Ship$|size (small|medium|large) — was |back to [0-9] — |1 Assess — (stopped|approved|answer|security): |3 Test — unaccounted: |4 Code review — ship go-ahead |move — )'
for f in "$ex"/*.log "$fx"/logs/full-*.md; do
  bad="$(grep '^- \[x\] ' "$f" | grep -vE '^- \[x\] [^—]* \[(soft|hard)\] — ' | grep -vE "$records" || true)"
  [ -z "$bad" ] || fail "${f##*/}: an untagged line that is no record: ${bad%%$'\n'*}"
done

# --- the next spawn's row per size, continuation, resume at each phase ---------------------

current="rows per size"
all=''
for size in small medium large; do
  for ph in '2 Specify' '3 Plan' '5 Tasks' '6 Implement' 'done (shipping)'; do
    new_case "resume feat $ph $size" feat
    S set Size "$size"
    S set Agents 'specifier s1, planner p1, tasker t1 (for SendMessage)'
    S set 'Current phase' "$ph"
    run resume "$sf"
    [ "$rc" = 0 ] || fail "exit $rc"
    all="$all# feat $ph $size"$'\n'"$out"$'\n'
  done
  for ph in '1 Assess' '2 Fix' '3 Test' 'done (shipping)'; do
    new_case "resume fix $ph $size" fix
    S set Size "$size"
    S set 'Current phase' "$ph"
    S log '- [x] 1 Assess [soft] — gate: valid, high confidence, reproduced, 1 remediation(s); size small; risk area none; performance bug no'
    run resume "$sf"
    [ "$rc" = 0 ] || fail "exit $rc"
    all="$all# fix $ph $size"$'\n'"$out"$'\n'
  done
done
out="${all%$'\n'}"
rc=0
before="$(grep -c '' "$sf")"
check rows-per-size 0

# --- agents run step.sh last (contracts/step-cli.md, Tests) ---------------------------------
# An agent-run spawn's block ends with `step script:` and `boundary:`, the
# call the agent makes itself; the coordinator acts on the output it hands
# back, and checks a done: with the same call again (a re-print).

# own_keys <token> <report>: raw's last spawn block ends with the two keys,
# the same words as the call line printed after the blocks
own_keys() {
  local want_s want_b
  want_s="  step script:	$step	feat	$sf"
  want_b="$1	$2"
  printf '%s\n' "$raw" | grep -qxF "$want_s" || fail "no step script: key"
  printf '%s\n' "$raw" | grep -qxF "  boundary:	$want_b" || fail "no boundary: key"
  printf '%s\n' "$raw" | grep -qxF "boundary:	$want_b" || fail "no boundary: line"
  [ "$(printf '%s\n' "$raw" | grep -B2 -xF "boundary:	$want_b" | head -n 2)" = "$want_s
  boundary:	$want_b" ] || fail "the two keys are not the last block's last keys"
}

new_case "agent-run soft: the planner closes its own boundary" feat
run feat "$sf" setup
own_keys 2 "$rd/2-specify.md"
call_line boundary
put_at specifier/soft "${CALL[1]}"
run feat "$sf" "${CALL[@]}"
check agent-run-soft 0
own_keys 3 "$rd/3-plan.md"
grep -qxF -- '- Agents: none (every spawn is fresh)' "$sf" || fail "the Agents line changed"
[ "$(sed -n 2p "$rd/last-step.md")" = "call:	2	$rd/2-specify.md" ] || fail "last-step.md: no call: line"
sums_re=$'^sums:\t2-specify\\.md:[0-9a-f]{12}$'
[[ "$(sed -n 3p "$rd/last-step.md")" =~ $sums_re ]] || fail "last-step.md: no sums: line"
[ "$(sed -n 4p "$rd/last-step.md")" = output: ] || fail "last-step.md: no output: line"
[ "$(tail -n +5 "$rd/last-step.md")" = "$raw" ] || fail "last-step.md: the output differs from stdout"

new_case "agent-run hard: an open marker, the answer call last" feat
run feat "$sf" setup
call_line boundary
put_at specifier/markers "${CALL[1]}"
run feat "$sf" "${CALL[@]}"
check agent-run-hard 0
[ "${out%%$'\n'*}" = 'hard:' ] || fail "not a hard gate"
[[ "$(printf '%s\n' "$raw" | tail -n 1)" == "answer call:	"* ]] || fail "the answer call is not last"

feat6 "agent-run failed check: the retry spawn closes its own boundary" medium
run resume "$sf"
call_line boundary
put_at implementer/story-fail "${CALL[1]}"
run feat "$sf" "${CALL[@]}"
check agent-run-retry 0
[ "${out%%$'\n'*}" = soft ] || fail "not soft"
own_keys 6 "$rd/6-US1-2.md"
grep -qx 'failures:' "$rd/6-US1-2.in.md" || fail "no failures in the retry's inputs file"

# the done: check last: its re-print needs the acceptance of a decided call
new_case "agent-run done: the coordinator's check re-prints it" feat
S set 'Current phase' 'done (shipping)'
S log '- [x] 6 US1 — not verified: none'
run resume "$sf"
own_keys 8 "$rd/8-ship.md"
call_line boundary
put_at shipper/pr "${CALL[1]}"
run feat "$sf" "${CALL[@]}"
check agent-run-done 0
[ "$(printf '%s\n' "$out" | tail -n 1)" = 'done: PR #42' ] || fail "not shipped"
first="$raw"
command cp -f "$sf" "$work/done-sf.keep"
command cp -f "$rd/last-step.md" "$work/done-rec.keep"
run feat "$sf" "${CALL[@]}"
[ "$rc" = 0 ] || fail "the done: check: exit $rc, want 0"
[ "$raw" = "$first" ] || fail "the done: check did not re-print the decision byte for byte"
cmp -s "$sf" "$work/done-sf.keep" || fail "the done: check changed the state file"
cmp -s "$rd/last-step.md" "$work/done-rec.keep" || fail "the done: check changed last-step.md"

# a renumbered ship: the shipper's call names the old state file and report
# path; the coordinator's done: check passes the state: path with the same
# report path (its boundary: words) and re-prints the decision
new_case "agent-run done after a renumber: the check with the state: path re-prints it" feat
S set 'Current phase' 'done (shipping)'
S log '- [x] 6 US1 — not verified: none'
run resume "$sf"
call_line boundary
put_at shipper/pr "${CALL[1]}"
sed -i "s#$top/specs/x/#$top/specs/012-x/#g" "$R"
mv "$top/specs/x" "$top/specs/012-x"
old_sf="$sf"
sf="$top/specs/012-x/feat-state.md"
rd="$top/specs/012-x/reports"
run feat "$old_sf" "${CALL[@]}"
[ "$rc" = 0 ] || fail "the shipper's call: exit $rc, want 0"
printf '%s\n' "$raw" | grep -qxF "state: $sf" || fail "no state: line"
[ "$(printf '%s\n' "$out" | tail -n 1)" = 'done: PR #42' ] || fail "not shipped"
first="$raw"
command cp -f "$sf" "$work/rn-sf.keep"
command cp -f "$rd/last-step.md" "$work/rn-rec.keep"
run feat "$sf" "${CALL[@]}"
[ "$rc" = 0 ] || fail "the done: check: exit $rc, want 0"
[ "$raw" = "$first" ] || fail "the done: check did not re-print the decision byte for byte"
cmp -s "$sf" "$work/rn-sf.keep" || fail "the done: check changed the state file"
cmp -s "$rd/last-step.md" "$work/rn-rec.keep" || fail "the done: check changed last-step.md"

# --- the acceptance of a boundary call (contracts/step-cli.md, Acceptance) -----------------

# agent_run_2: setup, then the specifier's soft report at the issued path and
# its call (case 1); CALL2 = that call's words, FIRST = its stdout
agent_run_2() {
  new_case "$1" feat
  run feat "$sf" setup
  call_line boundary
  CALL2=("${CALL[@]}")
  put_at specifier/soft "${CALL2[1]}"
  run feat "$sf" "${CALL2[@]}"
  [ "$rc" = 0 ] || fail "boundary 2: exit $rc, want 0"
  FIRST="$raw"
}

agent_run_2 "re-print: the same call again writes nothing"
command cp -f "$sf" "$work/rp-sf.keep"
command cp -f "$rd/last-step.md" "$work/rp-rec.keep"
run feat "$sf" "${CALL2[@]}"
[ "$rc" = 0 ] || fail "the re-print: exit $rc, want 0"
[ "$raw" = "$FIRST" ] || fail "the re-print differs from the decision byte for byte"
cmp -s "$sf" "$work/rp-sf.keep" || fail "the re-print changed the state file"
cmp -s "$rd/last-step.md" "$work/rp-rec.keep" || fail "the re-print changed last-step.md"

new_case "not issued: a token or a report path the last decision did not print" feat
run feat "$sf" setup
command cp -f "$rd/last-step.md" "$work/ni-rec.keep"
put planner/plain 3-plan
run feat "$sf" 3 "$R"
check agent-run-not-issued-token 1
put specifier/soft 2-specify-2
run feat "$sf" 2 "$R"
check agent-run-not-issued-path 1
cmp -s "$rd/last-step.md" "$work/ni-rec.keep" || fail "an error changed last-step.md"

feat6 "stale: an edited report, then an older token" medium
put implementer/story-pass 6-US1
run feat "$sf" 6 "$R"
[ "$rc" = 0 ] || fail "US1: exit $rc, want 0"
us1="$R"
command cp -f "$us1" "$work/us1.keep"
printf 'an edit\n' >>"$us1"
run feat "$sf" 6 "$us1"
check agent-run-stale-edited 1
command cp -f "$work/us1.keep" "$us1"
put implementer/story-clean 6-US2
run feat "$sf" 6 "$R"
[ "$rc" = 0 ] || fail "US2: exit $rc, want 0"
run feat "$sf" 6 "$us1"
check agent-run-stale-older 1

# reformat_2: setup, then an unparsable specifier report at the issued path
# and its call: reformat. CALL1 = that call's words, CALLR = the reformat
# block's boundary: words (its report: path first)
reformat_2() {
  new_case "$1" feat
  run feat "$sf" setup
  call_line boundary
  CALL1=("${CALL[@]}")
  put_at specifier/today-layout "${CALL1[1]}"
  run feat "$sf" "${CALL1[@]}"
}

reformat_2 "reformat run by the agent: its call decides, the first call re-prints it"
check agent-run-reformat 0
[ "${out%%$'\n'*}" = reformat ] || fail "not a reformat"
call_line boundary
CALLR=("${CALL[@]}")
own_keys 2 "${CALLR[1]}"
printf '%s\n' "$raw" | grep -qxF "  report: ${CALLR[1]}" || fail "the boundary: words do not name the block's report: path"
put_at specifier/soft "${CALLR[1]}"
run feat "$sf" "${CALLR[@]}"
check agent-run-reformat-soft 0
[ "${out%%$'\n'*}" = soft ] || fail "the corrected report: not soft"
[ "$(grep -c '^call:	' "$rd/last-step.md")" = 2 ] || fail "last-step.md does not hold two call: lines"
[ "$(sed -n 2p "$rd/last-step.md")" = "call:	2	${CALL1[1]}" ] || fail "last-step.md: the first call: line is not the first call's"
second="$raw"
command cp -f "$sf" "$work/rf2-sf.keep"
command cp -f "$rd/last-step.md" "$work/rf2-rec.keep"
run feat "$sf" "${CALL1[@]}"
[ "$rc" = 0 ] || fail "the slip fallback: exit $rc, want 0"
[ "$raw" = "$second" ] || fail "the first call's words did not re-print the decision byte for byte"
cmp -s "$sf" "$work/rf2-sf.keep" || fail "the re-print changed the state file"
cmp -s "$rd/last-step.md" "$work/rf2-rec.keep" || fail "the re-print changed last-step.md"

reformat_2 "reformat run by the agent: a second slip is today's hard gate"
[ "${out%%$'\n'*}" = reformat ] || fail "not a reformat"
call_line boundary
put_at specifier/today-layout "${CALL[1]}"
run feat "$sf" "${CALL[@]}"
check agent-run-reformat-hard 0
[ "${out%%$'\n'*}" = 'hard:' ] || fail "a second slip: not a hard gate"

new_case "record: the write fails, the retry decides as the first try" feat
run feat "$sf" setup
call_line boundary
put_at specifier/soft "${CALL[1]}"
command cp -f "$rd/last-step.md" "$work/rf-rec.keep"
fail_once "'record:'*"
run feat "$sf" "${CALL[@]}"
unfail
check agent-run-record-failed 1
grep -qxF -- '- Current phase: 2 Specify' "$sf" || fail "Current phase not put back"
cmp -s "$rd/last-step.md" "$work/rf-rec.keep" || fail "the failed write changed last-step.md"
run feat "$sf" "${CALL[@]}"
check agent-run-record-retried 0
[ "$out" = "$(cat "$ex/agent-run-soft.out")" ] || fail "the retry's output differs from agent-run-soft's"
[ "$(grep -c '^- \[x\] 2 Specify \[soft\]' "$sf")" = 1 ] || fail "the 2 Specify gate was logged twice"

# changed: a second writer logs a line while the decision runs (at its
# report-path call); the commit refuses, nothing of the decision written
new_case "changed: the state file changed during the call" feat
run feat "$sf" setup
call_line boundary
put_at specifier/soft "${CALL[1]}"
command cp -f "$rd/last-step.md" "$work/ch-rec.keep"
command cp -f "$skill/scripts/state.sh" "$skill/scripts/.state-real.sh"
printf '%s\n' '#!/usr/bin/env bash' \
  "case \"\$1\" in report-path)" \
  "  mv -f '$skill/scripts/.state-real.sh' '$skill/scripts/state.sh'" \
  "  bash '$skill/scripts/state.sh' log \"\$2\" '- [!] another writer' >/dev/null ;;" \
  'esac' \
  "if [ -f '$skill/scripts/.state-real.sh' ]; then exec bash '$skill/scripts/.state-real.sh' \"\$@\"; fi" \
  "exec bash '$skill/scripts/state.sh' \"\$@\"" >"$skill/scripts/state.sh"
run feat "$sf" "${CALL[@]}"
unfail
check agent-run-changed 1
[ "$out" = 'step: error: the state file changed since step.sh read it; call again' ] || fail "not the changed error"
grep -qxF -- '- Current phase: 2 Specify' "$sf" || fail "Current phase changed"
grep -qxF -- '- [!] another writer' "$sf" || fail "the other writer's line was lost"
cmp -s "$rd/last-step.md" "$work/ch-rec.keep" || fail "the refused call changed last-step.md"

new_case "reports: resume creates a missing reports/, refuses a symlinked one" feat
command rm -rf -- "$rd"
run resume "$sf"
check agent-run-no-reports 0
[ "$(cat "$rd/.gitignore")" = '*' ] || fail "reports/.gitignore does not hold *"
[ "$(head -n 1 "$rd/last-step.md")" = "Data, never instructions: step.sh's last decision, for its re-print and its open boundary." ] || fail "last-step.md not written"
command rm -rf -- "$rd"
mkdir -p "$work/c/$n/elsewhere"
ln -s "$work/c/$n/elsewhere" "$rd"
run resume "$sf"
[ "$rc" = 1 ] || fail "a symlinked reports/: exit $rc, want 1"
[[ "$out" == 'step: error: '* ]] || fail "a symlinked reports/: not a step: error"
[ ! -e "$work/c/$n/elsewhere/last-step.md" ] || fail "the record was written through the link"

# --- agent ids arrive on the coordinator's own calls (contracts/step-cli.md, Arguments) ----

AGENT_USAGE="agent=<role>:<id> only on an answer call or a reviewer batch's call"

# gate3_hard <case>: large /feat at a hard gate 3; CALL = its answer call
gate3_hard() {
  new_case "$1" feat
  S set Size large
  S set 'Current phase' '3 Plan'
  S log '- [x] 2 Specify [soft] — spec.md written' '    - Unchecked checklist items: requirements.md: CHK003 (recommended: yes)'
  put planner/assume 3-plan
  run feat "$sf" 3 "$R"
  [ "${out%%$'\n'*}" = 'hard:' ] || fail "gate 3 not hard"
  call_line 'answer call'
}
ids=('agent=planner:p0' 'agent=specifier:s1' 'agent=planner:p1')

# ids on an answer call; the last word per role wins; a refused answer
# writes no id
gate3_hard "ids on an answer call: Agents holds both"
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "ok")' "${ids[@]}"
check agent-ids-answer 0
grep -qxF -- '- Agents: specifier s1, planner p1 (for SendMessage)' "$sf" || fail "Agents does not hold both ids"
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "again")' 'agent=planner:p2'
[ "$rc" = 0 ] && [[ "$out" == 'refused: '* ]] || fail "the second answer was not refused"
grep -qxF -- '- Agents: specifier s1, planner p1 (for SendMessage)' "$sf" || fail "a refused answer wrote an id"

# a set that fails after the ids were set puts the Agents line back
gate3_hard "ids on an answer call: a failed write puts the Agents line back"
fail_once "'set:Current phase'"
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "ok")' "${ids[@]}"
unfail
check agent-ids-answer-failed 1
grep -qxF -- '- Agents: none (every spawn is fresh)' "$sf" || fail "the Agents line was not put back"

review_case "ids on a reviewer batch call: the amend continues the planner" feat medium '4 Design review' "$P2_SOFT" "$P2_NONE" "$P3_FACTS"
put design-reviewer/4a-apply 4-4a
put design-reviewer/4b-zero 4-4b
put design-reviewer/4c-matches 4-4c
run feat "$sf" "${CALL[@]}" 'agent=planner:p1'
check agent-ids-batch 0
printf '%s\n' "$out" | grep -qxF '  continue: p1' || fail "the amend does not continue p1"
grep -qxF -- '- Agents: planner p1 (for SendMessage)' "$sf" || fail "Agents does not hold planner p1"

new_case "continue by role: a reformat spawn names the role, not the id" feat
S set Agents 'specifier s0 (for SendMessage)'
put specifier/today-layout 2-specify
run feat "$sf" 2 "$R"
check agent-ids-reformat 0
[ "${out%%$'\n'*}" = reformat ] || fail "not a reformat"
printf '%s\n' "$out" | grep -qxF '  continue: specifier' || fail "the reformat spawn does not read continue: specifier"
printf '%s\n' "$out" | grep -qF 'continue: s0' && fail "the reformat spawn names the recorded id"

new_case "agent= refused on an agent-run boundary" feat
S set 'Current phase' '3 Plan'
put planner/plain 3-plan
run feat "$sf" 3 "$R" 'agent=planner:p1'
usage_no_log "$AGENT_USAGE"
run feat "$sf" 3 "$R" 'agent=p1'
usage_no_log "$AGENT_USAGE"

new_case "agent= refused: malformed on an answer call" feat
S set Size large
S set 'Current phase' '3 Plan'
S log '- [x] 2 Specify [soft] — spec.md written' '    - Unchecked checklist items: none'
put planner/assume 3-plan
run feat "$sf" 3 "$R"
call_line 'answer call'
for bad in 'agent=p1' 'agent=shipper:p1' 'agent=planner:' 'agent=planner:a.b'; do
  run feat "$sf" "${CALL[@]}" 'answer: approved (user: "ok")' "$bad"
  usage_no_log "$AGENT_USAGE"
done

new_case "agent= refused in /fix" fix
put bug-assessor/assess-soft 1-assess
run fix "$sf" 1 "$R" 'agent=planner:p1'
usage_no_log "$AGENT_USAGE"

# --- chores ride on the coordinator's next own call (contracts/prompts.md, Chores) --------

# a pending Log line chained before the answer call (`S log … && T …`),
# with an agent= word on the same call: both land, the line first
gate3_hard "chores: a pending log line rides on the answer call"
S log '- [!] brief left in place: /x/b.md'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "ok")' 'agent=planner:p1'
check chores-log-answer 0
[ "${out%%$'\n'*}" = answered ] || fail "the answer was not taken"
grep -qxF -- '- Agents: planner p1 (for SendMessage)' "$sf" || fail "Agents does not hold planner p1"
pend="$(grep -nxF -- '- [!] brief left in place: /x/b.md' "$sf" | cut -d: -f1)"
ans="$(grep -nF -- '    - answer: approved (user: "ok")' "$sf" | cut -d: -f1)"
[ -n "$pend" ] && [ -n "$ans" ] && [ "$pend" -lt "$ans" ] || fail "the pending line is not in the Log before the answer's lines"

# --- configurable gates (specs/configurable-gates, contracts/gates.md Tests) ---------------
# A run's Gates: field changes only what its cells say: soft drops the size
# reason (the gate then reads as on medium), hard adds gates: hard; none and
# no field give today's output.

# gates_field <value>: `- Gates: <value>` after the state file's `- Issue:`
# line, where state.sh init writes it (state.sh set refuses the field)
gates_field() { sed -i "s/^- Issue: .*/&\n- Gates: $1/" "$sf"; }

# keep <name>: the last run's stdout and state-file changes, kept to compare
keep() {
  case_log
  printf '%s\n' "$out" >"$work/keep-$1.out"
  printf '%s\n' "$LOG" >"$work/keep-$1.log"
}

# same_run <a> <b>: identical stdout and state-file changes
same_run() {
  cmp -s "$work/keep-$1.out" "$work/keep-$2.out" || { out="$(diff "$work/keep-$1.out" "$work/keep-$2.out" || true)"; fail "$1 / $2: stdout differs"; }
  cmp -s "$work/keep-$1.log" "$work/keep-$2.log" || { out="$(diff "$work/keep-$1.log" "$work/keep-$2.log" || true)"; fail "$1 / $2: state file differs"; }
}

# verdict_of <name> [plan3]: VD = the kept run's verdict, its reasons, the
# Current phase and its new top-level Log lines (a hard one to its tag: the
# reasons are compared from stdout), `large` and `; gates: soft` cut; with
# plan3, the plan3_rows reasons cut too
verdict_of() {
  local cut='^- (US[0-9]+: )?large$'
  if [ "${2-}" = plan3 ]; then
    cut="$cut|^- (assumption [0-9]+ needs you|constitution: .*|blocker|checklist item|fact missing: unchecked checklist items)$"
  fi
  VD="$(
    sed -n 1p "$work/keep-$1.out"
    sed -n '2,${/^- /!q;p;}' "$work/keep-$1.out" | grep -Ev "$cut" || true
    sed -n '/^--$/q;/^- Current phase: /p' "$work/keep-$1.log"
    sed -n '/^--$/,$p' "$work/keep-$1.log" | grep -E '^- \[x\] [0-9]' | sed -E 's/; gates: soft//; s/ (\[hard\]) — .*/ \1/'
  )"
}

# same_verdict <a> <b> [plan3]: the same verdict, reasons and gate lines once
# the cuts are made (plan3: on b's side)
same_verdict() {
  local a
  verdict_of "$1"
  a="$VD"
  verdict_of "$2" "${3-}"
  [ "$a" = "$VD" ] || { out="$a
-- vs --
$VD"; fail "$1 / $2: verdicts differ"; }
}

# zero_reports [<finding>]: a no-finding report at each report path of CALL
# not written yet; design: a rec: user design finding in the 4c report;
# sec: a security finding in the 7b report
zero_reports() {
  local w k l lenses
  for w in "${CALL[@]}"; do
    case $w in "$rd"/*.md) ;; *) continue ;; esac
    [ ! -e "$w" ] || continue
    k=${w##*/}
    k=${k%.md}
    case $k in
      4-4*)
        put_at design-reviewer/4a+4b+4c-zero "$w"
        if [ "${1-}" = design ] && [[ $k == *4c* ]]; then
          sed -i 's/^Findings: none$/Findings:\n- [design] "page" is never defined — at: spec.md: FR-001 — fix: define it — kind: clarity — severity: high — rec: perhaps/' "$w"
        fi
        continue ;;
    esac
    IFS=+ read -r -a lenses <<<"${k#*-}"
    for l in "${lenses[@]}"; do
      case $l in
        7a) printf 'Bugs (7a): none\nSpec (7a): none\nStandards (7a): none\nAcceptance criteria (7a): none\n' ;;
        7b)
          if [ "${1-}" = sec ]; then
            printf 'Security (7b):\n- a token reaches the log — at: src/auth.sh:12 — fix: drop the log line — severity: high — rec: apply\n'
          else
            printf 'Security (7b): none\n'
          fi
          printf 'Accepted design findings built (7b): none\n' ;;
        7c) printf 'Performance (7c): none\n' ;;
        7d) printf 'Cuts (7d): none\nnet: lean already\n' ;;
        7e) printf 'Readability (7e): none\n' ;;
      esac
    done >"$w"
    printf 'Dismissed: none\nWrote:\n- %s\n' "$w" >>"$w"
  done
}

# many_tasks <n> [HIGH]: tasks.md with n tasks (T001 setup, the others US1)
# and the tasker's report on it as reports/5-tasks.md; R = its path
many_tasks() {
  local i t
  # shellcheck disable=SC2016 # the backticks are tasks.md's, not a command
  {
    printf '# Tasks: test feature\n\n## Phase 1: Setup\n\n- [ ] T001 Create `src/a.sh`\n\n## Phase 2: User Story 1 - Run a step\n\n'
    for ((i = 2; i <= $1; i++)); do printf -- '- [ ] T%03d [US1] Write `src/a.sh`\n' "$i"; done
  } >"$top/specs/x/tasks.md"
  t=$(printf 'T%03d' "$1")
  R="$rd/5-tasks.md"
  printf '%s\n' "Tasks: $top/specs/x/tasks.md" "Total tasks: $1" 'Per story:' '- setup/foundational: T001' "- US1: T002–$t" \
    'MVP slice: T001–T002' 'Analyze: ran' \
    "Analyze metrics: 8 requirements, $1 tasks, 100% coverage, 0 ambiguities, 0 duplications, 0 critical" 'Fixed: none' >"$R"
  if [ "${2-}" = HIGH ]; then
    printf '%s\n' 'Open findings:' '- HIGH — US1 has no test → add one (tasks.md)' >>"$R"
  else
    printf '%s\n' 'Open findings: none' >>"$R"
  fi
  printf '%s\n' 'Unchecked checklist items: none' 'Skipped hooks: none' 'Wrote:' "- $top/specs/x/tasks.md" "- $rd/5-analyze.md" "- $R" >>"$R"
  put_analyze "$1"
}

P2_CHK='    - Unchecked checklist items: requirements.md: CHK003 (recommended: yes)'
P3_ASSUME='- [x] 3 Plan — merged with 4; assumptions needing you: 2; constitution: pass; blockers: none; size trigger: none'
P3_STOPPED='- [x] 3 Plan [hard] — large; assumption 2 needs you; assumptions needing you: 2; constitution: pass; blockers: none; size trigger: none'

# gate_at <name> <gate> <size> <Gates value or -> [<variant>]: a case at that
# gate (f2-f7 /feat, x1-x4 /fix) on that size, the field written unless -,
# run through its boundary, kept as <name>. Variants: f3 assume (assumptions
# and an open checklist item); f4 assume, stopped (gate 3 stopped, answered),
# +user (a rec: user finding); f5 <n tasks>[+HIGH]; f6 last, design, fail, fail2;
# f7 sec; x1 conf (Confidence medium); x4 sec (risk area security)
gate_at() {
  local name=$1 g=$2 z=$3 v=$4 var=${5-} sk=feat
  case $g in x*) sk=fix ;; esac
  new_case "gates: $name" "$sk"
  if [ "$v" != - ]; then gates_field "$v"; fi
  if [ -n "${PRE-}" ]; then "$PRE"; fi
  case $g in
    f2)
      put specifier/soft 2-specify
      run feat "$sf" 2 "$R" ;;
    f3)
      S set Size "$z"
      S set 'Current phase' '3 Plan'
      if [ "$var" = assume ]; then
        S log "$P2_SOFT" "$P2_CHK"
        put planner/assume 3-plan
      else
        S log "$P2_SOFT" "$P2_NONE"
        put planner/plain 3-plan
      fi
      run feat "$sf" 3 "$R" ;;
    f4)
      S set Size "$z"
      S set 'Current phase' '4 Design review'
      case $var in
        assume*) S log "$P2_SOFT" "$P2_NONE" "$P3_ASSUME" ;;
        stopped*) S log "$P2_SOFT" "$P2_NONE" "$P3_STOPPED" '    - answer: approved (user: "ok")' ;;
        *) S log "$P2_SOFT" "$P2_NONE" "$P3_FACTS" ;;
      esac
      run resume "$sf"
      call_line boundary
      if [[ $var == *+user ]]; then zero_reports design; else zero_reports; fi
      run feat "$sf" "${CALL[@]}" ;;
    f5)
      S set Size "$z"
      S set 'Current phase' '5 Tasks'
      S log "$P2_SOFT" "$P2_NONE" "$P3_FACTS"
      if [ -n "$var" ]; then many_tasks "${var%+*}" "${var#*+}"; else put_analyze; put tasker/match 5-tasks; fi
      run feat "$sf" 5 "$R" ;;
    f6)
      S set Size "$z"
      S set 'Current phase' '6 Implement'
      S log '- [x] 5 Tasks [soft] — 6 tasks; story.sh: match; analyze ran'
      case $var in
        last)
          put implementer/story-pass 6-US1
          run feat "$sf" 6 "$R"
          put implementer/story-clean 6-US2
          run feat "$sf" 6 "$R" ;;
        design)
          put implementer/story-design 6-US1
          run feat "$sf" 6 "$R" ;;
        fail2)
          put implementer/story-fail 6-US1
          run feat "$sf" 6 "$R"
          put implementer/story-fail 6-US1-2
          run feat "$sf" 6 "$R" ;;
        fail)
          put implementer/story-fail 6-US1
          run feat "$sf" 6 "$R" ;;
        *)
          put implementer/story-pass 6-US1
          run feat "$sf" 6 "$R" ;;
      esac ;;
    f7)
      S set Size "$z"
      S set 'Current phase' '7 Code review'
      run resume "$sf"
      call_line boundary
      zero_reports "$var"
      run feat "$sf" "${CALL[@]}"
      if printf '%s\n' "$raw" | grep -q "^boundary:	7e	"; then
        call_line boundary
        zero_reports
        run feat "$sf" "${CALL[@]}"
      fi ;;
    x1)
      put bug-assessor/assess-soft 1-assess
      sed -i "s/^Proposed size: small/Proposed size: $z/" "$R"
      if [ "$var" = conf ]; then sed -i 's/^Confidence: high$/Confidence: medium/' "$R"; fi
      run fix "$sf" 1 "$R" 'approved: bash tests/page.sh' 'question: which page? → the last' ;;
    x2)
      S set Size "$z"
      S set 'Current phase' '2 Fix'
      S log "$A1_PASS"
      put implementer/bug-pass 2-fix
      run fix "$sf" 2 "$R" ;;
    x3)
      S set Size "$z"
      S set 'Current phase' '3 Test'
      S log "$A1_PASS" '- [x] 2 implementer — not verified: none' '- [x] 2 Fix [soft] — applied; no deviations; checks pass'
      put bug-assessor/test-verified 3-test
      run fix "$sf" 3 "$R" ;;
    x4)
      S set Size "$z"
      S set 'Current phase' '4 Code review'
      if [ "$var" = sec ]; then S log "${A1_PASS/risk area none/risk area security}"; else S log "$A1_PASS"; fi
      run resume "$sf"
      call_line boundary
      zero_reports
      run fix "$sf" "${CALL[@]}" ;;
  esac
  [ "$rc" = 0 ] || fail "$name: exit $rc"
  keep "$name"
}

# case 1 (SC-001): Gates: none is no field, at every gate (the goldens above
# are unchanged: they hold no field)
for g in f2:medium f3:large f4:medium f5:large:61 f6:large f7:large x1:medium x2:medium x3:medium x4:large; do
  IFS=: read -r gg zz vv <<<"$g"
  gate_at "c1-$gg-none" "$gg" "$zz" none "$vv"
  gate_at "c1-$gg-nofield" "$gg" "$zz" - "$vv"
  current="case 1: $gg"
  same_run "c1-$gg-none" "c1-$gg-nofield"
done

# case 2 (FR-009, FR-023, SC-009): a cell for a phase without a size reason,
# or for another size, changes nothing
c2() {
  gate_at "c2-$1-a" "$2" "$3" "$4" "${5-}"
  gate_at "c2-$1-b" "$2" "$3" - "${5-}"
  current="case 2: $1"
  same_run "c2-$1-a" "c2-$1-b"
}
c2 feat2-soft f2 medium feat.2=soft
c2 fix2-soft x2 medium fix.2=soft
c2 fix3-soft x3 medium fix.3=soft
c2 feat4-large-on-medium f4 medium feat.4.large=soft
c2 feat4-small-on-medium f4 medium feat.4.small=hard
c2 fix1-small-on-medium x1 medium fix.1.small=hard
c2 feat6-small-on-large f6 large feat.6.small=soft

# case 3 (SC-003, SC-004): soft on large gives medium's verdict, clean and
# with a reason that is always hard
c3() {
  gate_at "c3-$1-large" "$2" large "$3" "${4-}"
  gate_at "c3-$1-medium" "$2" medium - "${5-${4-}}"
  current="case 3: $1"
  same_verdict "c3-$1-large" "c3-$1-medium" "${6-}"
}
c3 feat3 f3 feat.3.large=soft
c3 feat3-assume f3 feat.3.large=soft assume
c3 feat4 f4 'feat.3.large=soft feat.4.large=soft'
c3 feat4-user f4 'feat.3.large=soft feat.4.large=soft' +user
c3 feat4-assume f4 'feat.3.large=soft feat.4.large=soft' assume
c3 feat4-stopped f4 feat.4.large=soft stopped+user assume+user plan3
c3 feat7 f7 feat.7.large=soft
c3 feat7-sec f7 feat.7.large=soft sec
c3 fix4 x4 fix.4.large=soft
c3 fix4-sec x4 fix.4.large=soft sec
# gate 5: a large Size stays large only past 60 tasks, where medium would
# grow: the large run is checked against the rows themselves
current="case 3: feat5"
gate_at c3-feat5-large f5 large feat.5.large=soft 61
[ "$(sed -n 1p "$work/keep-c3-feat5-large.out")" = soft ] || fail "feat 5 large soft: not soft"
grep -qxF -- '- [x] 5 Tasks [soft] — 61 tasks; story.sh: match; analyze ran; gates: soft' "$work/keep-c3-feat5-large.log" || fail "feat 5: no soft line with the mark"
gate_at c3-feat5-high f5 large feat.5.large=soft 61+HIGH
[ "$(sed -n '1,2p' "$work/keep-c3-feat5-high.out")" = 'hard:
- 1 CRITICAL/HIGH findings' ] || fail "feat 5 large soft with a HIGH finding: want that one reason"
gate_at c3-feat5-auto f5 large - 61
[ "$(sed -n '1,2p' "$work/keep-c3-feat5-auto.out")" = 'hard:
- large' ] || fail "feat 5 large auto: want large"

# case 7 (FR-005): gate 3 softened on large merges with 4; gate 4 (auto)
# then holds large and the plan3_rows reasons
new_case "case 7: feat.3.large=soft on large, merged, then gate 4" feat
gates_field feat.3.large=soft
S set Size large
S set 'Current phase' '3 Plan'
S log "$P2_SOFT" "$P2_CHK"
put planner/assume 3-plan
run feat "$sf" 3 "$R"
check gates-feat3-soft-large 0
call_line boundary
zero_reports
run feat "$sf" "${CALL[@]}"
check gates-feat4-after-soft-3 0

# case 9 (soft part): soft on large at gate 6 logs no gate line for an
# earlier story, the mark on the last one's, and its other reasons still stop
new_case "case 9: feat.6.large=soft on large, two stories" feat
gates_field feat.6.large=soft
S set Size large
S set 'Current phase' '6 Implement'
S log '- [x] 5 Tasks [soft] — 6 tasks; story.sh: match; analyze ran'
put implementer/story-pass 6-US1
run feat "$sf" 6 "$R"
[ "$rc" = 0 ] || fail "exit $rc"
[ "$(sed -n 1p <<<"$out")" = soft ] || fail "US1: not soft"
grep -q '^- \[x\] 6 Implement' "$sf" && fail "US1 logged a gate line"
put implementer/story-clean 6-US2
run feat "$sf" 6 "$R"
check gates-feat6-soft-large-last 0
for v in design fail2; do
  gate_at "c9-$v-large" f6 large feat.6.large=soft "$v"
  gate_at "c9-$v-medium" f6 medium - "$v"
  current="case 9: $v"
  same_verdict "c9-$v-large" "c9-$v-medium"
done

# case 11 (soft part): /fix 1's cell is the proposed size's
gate_at c11-soft x1 medium fix.1.medium=soft
check gates-fix1-soft-medium 0
gate_at c11-conf x1 medium fix.1.medium=soft conf
current="case 11: fix.1.medium=soft, confidence medium"
[ "$(sed -n '1,2p' "$work/keep-c11-conf.out")" = 'hard:
- confidence medium' ] || fail "want hard on the one reason confidence medium"
if grep -q -- '^- proposed size' "$work/keep-c11-conf.out"; then fail "a proposed size reason"; fi

# case 15 (FR-011): a Gates: value that is not canonical is an error
for v in 'feat.3=bad' 'fix.1=soft' 'feat.4=hard feat.3=hard' 'feat.3=hard feat.3.large=soft' 'feat.8=soft' 'feat.3=auto' 'feat.3=hard  feat.4=soft'; do
  new_case "case 15: Gates: $v" feat
  gates_field "$v"
  run resume "$sf"
  one_line 1 "step: error: Gates: $v is not a canonical feat gates value"
done

# case 16: the repo's .logistics.yml does not change a recorded decision
gates_yml() { printf 'gates:\n  feat:\n    3: hard\n' >"$top/.logistics.yml"; }
PRE=gates_yml gate_at c16-file f3 small none
gate_at c16-nofile f3 small none
current="case 16: .logistics.yml says feat 3 hard, the field none"
same_run c16-file c16-nofile

# case 17: /fix 1's `issue to create` follows the tracker: key, not the file:
# a gates-only .logistics.yml gives no such reason, one with tracker: does
# c17 <name> <want: yes|no> <line>...: /fix 1 with Issue: none and a
# .logistics.yml of those lines
c17() {
  local want=$2
  new_case "case 17: $1" fix
  shift 2
  S set Issue none
  printf '%s\n' "$@" >"$top/.logistics.yml"
  put bug-assessor/assess-soft 1-assess
  run fix "$sf" 1 "$R"
  [ "$rc" = 0 ] || fail "exit $rc"
  if printf '%s\n' "$out" | grep -qxF -- '- issue to create'; then
    [ "$want" = yes ] || fail "an issue to create reason without a tracker: key"
  else
    [ "$want" = no ] || fail "no issue to create reason"
  fi
}
c17 'gates only' no 'gates:' '  fix:' '    4: hard' '# tracker: not here'
c17 'tracker and gates' yes 'gates:' '  fix:' '    4: hard' $'tracker:  # on\r' '  provider: github'

# --- hard (US2): gates: hard at any settable gate for the run's size -----------

# case 4: feat.2=hard on small stops after the spec; approved → phase 3
size_small() { S set Size small; }
PRE=size_small gate_at c4 f2 small feat.2=hard
check gates-feat2-hard 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "ok")'
check gates-feat2-hard-approved 0

# case 5: feat.3=hard on small: the large gate 3 form with gates: hard; its
# answers, resume and phase2-mode as at any gate 3
g3_hard() {
  new_case "$1" feat
  gates_field feat.3=hard
  S set Size "$2"
  S set 'Current phase' '3 Plan'
  S log "$P2_SOFT" "$P2_NONE"
  put "planner/$3" 3-plan
  run feat "$sf" 3 "$R"
}
g3_hard "case 5: feat.3=hard small, approved" small plain
check gates-feat3-hard-small 0
call_line 'answer call'
run resume "$sf"
grep -qxF 'phase2-mode: soft 3 open' <<<"$out" || fail "resume at the open gate 3: no phase2-mode: soft 3 open"
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "ok")'
check gates-feat3-hard-approved 0

g3_hard "case 5: feat.3=hard small, changed, the amend, then gate 4's note" small plain
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: changed (user: "drop the daemon")'
check gates-feat3-hard-changed 0
put planner/plain 3-plan-2
run feat "$sf" 3 "$R"
check gates-feat3-hard-amended 0
call_line boundary
zero_reports
run feat "$sf" "${CALL[@]}"
check gates-feat4-after-hard-3-amended 0

# gate 4 after a gate 3 stopped for gates: hard skips the plan3_rows it
# evaluated (medium: the size increase row stays out of the way)
g3_hard "case 5: feat.3=hard medium, assumptions, then gate 4" medium assume
[ "$(sed -n 1p <<<"$out")" = hard: ] || fail "gate 3 not hard"
[ "$(sed -n 2p <<<"$out")" = '- gates: hard' ] || fail "gate 3: gates: hard is not the first reason"
printf '%s\n' "$out" | grep -qxF -- '- assumption 2 needs you' || fail "gate 3: no assumption reason"
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "ok")'
call_line boundary
zero_reports
run feat "$sf" "${CALL[@]}"
[ "$rc" = 0 ] || fail "gate 4: exit $rc"
[ "$(sed -n 1p <<<"$out")" = soft ] || fail "gate 4 after a stopped gate 3: not soft"

# a size-specific cell stopped gate 3, then a size increase answered at gate
# 4: the 3 Plan record keeps phase 2's summary on gate 3, logged once
new_case "case 5: feat.3.small=hard small, then size medium at gate 4" feat
gates_field 'feat.3.small=hard feat.4=hard'
S set Size small
S set 'Current phase' '3 Plan'
S log "$P2_SOFT" "$P2_NONE"
put planner/plain 3-plan
run feat "$sf" 3 "$R"
[ "$(sed -n 1p <<<"$out")" = hard: ] || fail "gate 3 not hard"
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "ok")'
call_line boundary
zero_reports
run feat "$sf" "${CALL[@]}"
[ "$(sed -n 1p <<<"$out")" = hard: ] || fail "gate 4 not hard"
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: size medium (user: "it is medium")'
[ "$rc" = 0 ] || fail "gate 4 answer: exit $rc"
grep -qx -- '- Size: medium' "$sf" || fail "Size not medium"
[ "$(grep -c -- '- spec assumptions: kept as recommended' "$sf")" = 1 ] || fail "spec assumptions logged more than once"
run resume "$sf"
grep -qxF 'phase2-mode: soft 3 closed' <<<"$out" || fail "resume after gate 4: no phase2-mode: soft 3 closed"

# case 6: feat.3.large=hard on large: large; gates: hard
new_case "case 6: feat.3.large=hard large" feat
gates_field feat.3.large=hard
S set Size large
S set 'Current phase' '3 Plan'
S log "$P2_SOFT" "$P2_NONE"
put planner/plain 3-plan
run feat "$sf" 3 "$R"
check gates-feat3-hard-large 0

# case 8: feat.4=hard and feat.5=hard on small stop with their rows
gate_at c8-f4 f4 small feat.4=hard
check gates-feat4-hard-small 0
gate_at c8-f5 f5 small feat.5=hard
check gates-feat5-hard-small 0

# case 9 (hard part): feat.6=hard on small stops after each story; the
# retry row stays soft
new_case "case 9: feat.6=hard small, two stories" feat
gates_field feat.6=hard
S set Size small
S set 'Current phase' '6 Implement'
S log '- [x] 5 Tasks [soft] — 6 tasks; story.sh: match; analyze ran'
put implementer/story-pass 6-US1
run feat "$sf" 6 "$R"
check gates-feat6-hard-us1 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "go on")'
check gates-feat6-hard-us1-approved 0
put implementer/story-clean 6-US2
run feat "$sf" 6 "$R"
check gates-feat6-hard-us2 0
call_line 'answer call'
run feat "$sf" "${CALL[@]}" 'answer: approved (user: "go on")'
check gates-feat6-hard-us2-approved 0
gate_at c9-retry f6 small feat.6=hard fail
current="case 9: feat.6=hard, a failing check, retry unused"
[ "$(sed -n 1p "$work/keep-c9-retry.out")" = soft ] || fail "the retry row is not soft"
grep -q '^- \[x\] 6 US1 \[soft\] — checks failed (retry 1 of 1): ' "$work/keep-c9-retry.log" || fail "no retry line"

# case 10: feat.7=hard on medium: no stop at token 7, gates: hard after 7e
gate_at c10 f7 medium feat.7=hard
check gates-feat7-hard-medium 0
[ "$(grep -c '^- \[x\] 7 Code review \[hard\]' "$sf")" = 1 ] || fail "want one 7 Code review gate"
grep -q '^- \[x\] 7 Code review \[hard\] — gates: hard$' "$sf" || fail "the 7 Code review gate is not gates: hard"

# case 11 (hard part): fix.1=hard on a small bug
gate_at c11-hard x1 small fix.1=hard
check gates-fix1-hard-small 0

# case 12: fix.2=hard; approved → phase 3
gate_at c12 x2 small fix.2=hard
check gates-fix2-hard 0
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "ok")'
check gates-fix2-hard-approved 0

# case 13: fix.3=hard stops once per test report
fix3_hard() {
  fix_at "$1" '3 Test'
  gates_field fix.3=hard
  S log '- [x] 2 implementer — not verified:' '    - n/a → live run → no credentials' '- [x] 2 Fix [soft] — applied; no deviations; checks pass'
  put "bug-assessor/$2" 3-test
  run fix "$sf" 3 "$R"
}
fix3_hard "case 13: fix.3=hard, verified" test-verified
check gates-fix3-hard-verified 0
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "ok")'
check gates-fix3-hard-verified-approved 0
fix3_hard "case 13: fix.3=hard, first failed" test-failed
check gates-fix3-hard-failed 0
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "retry")'
check gates-fix3-hard-failed-approved 0
fix3_hard "case 13: fix.3=hard, unaccounted items" test-unaccounted
check gates-fix3-hard-unaccounted 0
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "checked it by hand")'
check gates-fix3-hard-unaccounted-approved 0
fix3_hard "case 13: fix.3=hard, partial" test-partial
check gates-fix3-hard-partial 0
call_line 'answer call'
run fix "$sf" "${CALL[@]}" 'answer: approved (user: "fine")'
[ "$(sed -n 1p <<<"$out")" = 'refused: approved is not valid at 3 Test: answer ship with partial, changed or back to' ] || fail "partial with gates: hard: approved not refused as today"

# case 14: fix.4=hard on small
gate_at c14 x4 small fix.4=hard
check gates-fix4-hard-small 0

# US2 scenario 8, FR-023: a cell hard for small only changes no other size
c2 feat2-small-hard-on-medium f2 medium feat.2.small=hard
c2 feat3-small-hard-on-large f3 large feat.3.small=hard
# (40 tasks keep Size medium: fewer would set it small first, as today)
c2 feat5-small-hard-on-medium f5 medium feat.5.small=hard 40
c2 feat6-small-hard-on-large f6 large feat.6.small=hard
c2 feat7-small-hard-on-medium f7 medium feat.7.small=hard
c2 fix2-small-hard-on-medium x2 medium fix.2.small=hard
c2 fix3-small-hard-on-medium x3 medium fix.3.small=hard
c2 fix4-small-hard-on-large x4 large fix.4.small=hard

# --- fixed for the run (US3, SC-006): a resume reads the recorded field only ------

# c18_hard <name> <edited|plain>: feat.3=hard on small stops at gate 3; the
# repo's .logistics.yml then says soft (edited) or is absent (plain); resume
c18_hard() {
  g3_hard "case 18: $1" small plain
  [ "$rc" = 0 ] || fail "gate 3: exit $rc"
  if [ "$2" = edited ]; then printf 'gates:\n  feat:\n    3: soft\n    4: soft\n' >"$top/.logistics.yml"; fi
  run resume "$sf"
  [ "$rc" = 0 ] || fail "resume: exit $rc"
  keep "$1"
}
c18_hard c18-hard-edited edited
c18_hard c18-hard-plain plain
current="case 18: Gates: feat.3=hard, the file edited after init, resume"
same_run c18-hard-edited c18-hard-plain
grep -qxF 'phase2-mode: soft 3 open' "$work/keep-c18-hard-edited.out" || fail "the edited file closed the open gate 3"

# c18_auto <name> <Gates value or -> [edited]: a small run past gate 3
# (merged), then resume at phase 4, the file written in between when edited
c18_auto() {
  gate_at "$1" f3 small "$2"
  if [ "${3-}" = edited ]; then printf 'gates:\n  feat:\n    4: hard\n    5: hard\n' >"$top/.logistics.yml"; fi
  run resume "$sf"
  [ "$rc" = 0 ] || fail "resume: exit $rc"
  keep "$1"
}
c18_auto c18-auto-none none
c18_auto c18-auto-nofield -
c18_auto c18-auto-edited none edited
current="case 18: no Gates: field resumes as Gates: none"
grep -q '^boundary:	4	' "$work/keep-c18-auto-none.out" || fail "the resume does not print phase 4's boundary"
same_run c18-auto-nofield c18-auto-none
current="case 18: Gates: none, the file edited after init, resume"
same_run c18-auto-edited c18-auto-none

if [ "$update" = 1 ] && [ "$updated" = 1 ]; then
  echo "step: expected/ rewritten; review it with git diff tests/step/expected"

  exit 1
fi
echo "step: all cases pass"
