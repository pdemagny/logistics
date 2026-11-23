#!/usr/bin/env bash
# Offline tests for .apm/skills/feat/scripts/measure.py (mise run test:measure).
#
# A temp dir ($work) holds config/projects/ (the fixture templates of
# tests/measure/fixtures/projects with @ROOT@ replaced by $work, then made
# read-only) and real git repos the fixtures' cwds point at. Each case runs
# measure.py from a repo with CLAUDE_CONFIG_DIR=$work/config, writes $work as
# @ROOT@ in its stdout, and compares stdout plus a last line `exit <code>`
# with tests/measure/expected/<case>.txt. No output of any case may contain
# the SECRET- sentinel every free-text fixture field holds. The fixtures are
# synthetic: never copy a real transcript into them.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(cd "$here/../.." && pwd -P)"
script="$root/.apm/skills/feat/scripts/measure.py"
expected="$here/expected"

current="setup"
fail() {
  printf 'FAIL %s: %s\n' "$current" "$1"
  if [ -n "${2:-}" ] && [ -s "$2" ]; then sed 's/^/  /' "$2"; fi
  exit 1
}

command -v python3 >/dev/null || fail "python3 not found"
command -v git >/dev/null || fail "git not found"

work="$(mktemp -d)"
work="$(cd "$work" && pwd -P)"
cleanup() {
  chmod -R u+w "$work" 2>/dev/null || true
  command rm -rf -- "$work"
}
trap cleanup EXIT

# Nothing here may depend on the user's git config, time zone or terminal.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export TZ=UTC NO_COLOR=1 PYTHON_COLORS=0
unset FORCE_COLOR
export CLAUDE_CONFIG_DIR="$work/config"

# --- repos the fixtures' cwds point at ----------------------------------------

new_repo() {
  git init -q -b main "$1"
  git -C "$1" commit -q --allow-empty -m init
}

tab_repo="$work/tab"$'\t'"repo"
new_repo "$work/app"
git -C "$work/app" worktree add -q -b wt "$work/app/.claude/worktrees/wt"
# A worktree whose directory is gone: its sessions still belong to app.
git -C "$work/app" worktree add -q -b gone "$work/app/.claude/worktrees/gone"
command rm -rf -- "$work/app/.claude/worktrees/gone"
new_repo "$work/app-old" # starts like app: never counted for it
new_repo "$work/other"
new_repo "$tab_repo"
new_repo "$work/odd" # the left-out fixtures (US6) and one counted /fix run
# lib's .git is a file naming a separate git dir with no commondir.
git init -q -b main --separate-git-dir "$work/lib-git" "$work/lib"

# --- fixtures -----------------------------------------------------------------

root_sed="$(printf '%s' "$work" | sed 's/[&|\\]/\\&/g')"
# install_fixtures <templates> <projects dir>
install_fixtures() {
  local src rel
  while IFS= read -r -d '' src; do
    rel="${src#"$1/"}"
    mkdir -p "$(dirname "$2/$rel")"
    sed "s|@ROOT@|$root_sed|g" "$src" >"$2/$rel"
  done < <(find "$1" -type f -print0)
}
install_fixtures "$here/fixtures/projects" "$work/config/projects"
# fixtures/edge: sessions that must not end the report, under their own
# config dir so no other case selects them (the `edge` case).
install_fixtures "$here/fixtures/edge" "$work/edge/projects"
chmod -R a-w "$work/config" "$work/edge"

# --- cases --------------------------------------------------------------------

# run_case <name> [args...]: runs measure.py from $from (default: app) and
# compares its stdout and exit code with expected/<name>.txt (or
# expected/$expect.txt when set).
run_case() {
  current="$1"
  shift
  local dir="$work/cases/$current" rc=0
  mkdir -p "$dir"
  (cd "${from:-$work/app}" && python3 -I "$script" "$@") >"$dir/stdout" 2>"$dir/stderr" || rc=$?
  if grep -q 'SECRET-' "$dir/stdout" "$dir/stderr"; then
    fail "output holds fixture text (SECRET-)" "$dir/stdout"
  fi
  local out
  out="$(cat "$dir/stdout")"
  printf '%s\nexit %s\n' "${out//"$work"/@ROOT@}" "$rc" >"$dir/actual"
  local want="$expected/${expect:-$current}.txt"
  [ -f "$want" ] || fail "no ${want#"$here/"}" "$dir/actual"
  if ! diff -u "$want" "$dir/actual" >"$dir/diff"; then
    [ ! -s "$dir/stderr" ] || cat "$dir/stderr" >>"$dir/diff"
    fail "output differs from ${want#"$here/"}" "$dir/diff"
  fi
  printf 'ok %s\n' "$current"
}

# report: the default report from app. expected/report.txt was written from
# this arithmetic, not from the script. Units of a call = (in + 0.1 cr +
# 5 out + 1.25 cw5m + 2 cw1h) x model (opus 5, sonnet 3, haiku 1; a
# cache write with no breakdown is 5m). Context = in + cw + cr. TZ=UTC.
#
# Counted: sess-feat-1 (app), sess-feat-2 (worktree wt, folder app-wt),
# sess-feat-3 (deleted worktree gone, folder app-gone), sess-feat-6 (app, for
# the comparison), sess-fix-1: finished; sess-feat-4 unfinished (no
# shipper); sess-feat-5 resumed (`resume` args, shipper spawned). Not
# counted: sess-old-1 (app-old), sess-brief-1 (/brief), sess-noagent-1 (/feat
# with an Explore agent only). 7 counted, 0 left out.
#
# sess-feat-1, /feat. Coordinator calls (in/cw/cr/out -> ctx, units):
#   spawn 10/5000 1h/0/100 -> 5010, 52550; chore Bash (fails) 10/0/5000/50
#   -> 5010, 3800; text 10/200 5m/5000/40 -> 5210, 4800; spawn 10/0/5200/100
#   -> 5210, 5150; text 10/0/5200/30 -> 5210, 3400. Calls 5 (2/1/2), ctx
#   5010/5210/5210, units 69700. planner (sonnet) 3500x3 + 1310x3 = 14430,
#   2 calls, ctx 3000, model 260 s, tool 10 s; shipper 2500x3 + 460x3 =
#   8880, model 140 s, tool 30 s. Run 93010: shares 74.94/15.51/9.55%.
#   Timeline from 10:00:00: think 30, tools 1, agents 300 (a system record
#   ends no gap), think 30, tools 10, think 30, user 120, think 30, tools 1,
#   agents 180, think 30 = agents 480 + user 120 + think 150 + tools 12 =
#   762 s = last event - invocation. Answers 1. Tokens in 5070, cw 5200,
#   cr 25400, out 770.
# sess-feat-2, /logistics:feat. msg-2-1 is two records (two parallel spawns),
#   output 50 then 120: the last counts; no breakdown, so 4000 is 5m.
#   Calls: spawn 10/4000/0/120 -> 4010, 28050; text 10/0/4000/40 -> 4010,
#   3050 (twice); chore Read 10/0/4000/20 -> 4010, 2550; spawn
#   10/1000 5m/4000/100 -> 5010, 10800; text 10/0/5000/30 -> 5010, 3300.
#   Calls 6 (2/1/3), ctx 4010/4010/5010, units 50800, no failure. planner
#   (meta logistics:feat-planner) 10500+1680+3960 = 16140, 3 calls, model
#   200 s, tool 30 s; design reviewer (no meta, typed by its spawn) model
#   claude-mystery-1 unweighted -> 5: 2000x5 = 10000, model 120 s; shipper
#   8880, model 80 s, tool 30 s. Run 85820: 59.19/18.81/11.65/10.35%.
#   Timeline: think 21, tools 2, agents 240 (parallel, counted once), think
#   20, user 60, think 20, user 30, think 20, tools 5, think 20, tools 1,
#   agents 120, think 23 = 360 + 90 + 124 + 8 = 582 s. Answers 2. Tokens in
#   6090, cw 5000, cr 29100, out 1050.
# sess-feat-3, /feat at 08:10:00 after a /brief, a call without usage, a
#   feat-brief-reviewer agent and a tagged compact summary: none counts.
#   Calls: spawn 10/0/6000/100 -> 6010, 5550; chore Bash (fails) and Edit
#   (fails) 10/0/6000/20 -> 6010, 3550 each; spawn 5550; text 10/0/8000/30
#   -> 8010, 4800. Calls 5 (2/2/1), ctx 6010/6010/8010, units 23000. planner
#   14430, model 220 s, tool 10 s; shipper 8880 (its report is the spawn's
#   own result), model 140 s, tool 30 s. Run 46310: 49.67/31.16/19.17%.
#   Timeline: think 10, tools 1, agents 240, think 10, tools 10, think 10,
#   tools 2, think 10, agents 180, think 15 = 420 + 0 + 55 + 13 = 488 s.
#   Answers 0. Tokens in 5070, cw 0, cr 37000, out 720.
# sess-feat-6, /feat on 2026-03-10. Calls: spawn 10/4000 1h/0/100 -> 4010,
#   42550; text 10/0/6900/40 -> 6910, 4500; spawn 10/0/6900/100 -> 6910,
#   6000; text 10/0/6940/40 -> 6950, 4520. Calls 4 (2/0/2), ctx
#   4010/6910/6950, units 57570, no failure. planner 14430 (as sess-feat-1),
#   2 calls, ctx 3000, model 220 s, tool 10 s; its first request adds a Grep
#   schema of 83 chars (tools 250, total 348); shipper 8880, model 140 s,
#   tool 30 s. Run 80880: 71.18/17.84/10.98%. Timeline: think 20, tools 1,
#   agents 240, think 20, user 20, think 20, tools 1, agents 180, think 20 =
#   420 + 20 + 80 + 2 = 522 s. Answers 1. Tokens in 5060, cw 4000, cr 25740,
#   out 730.
# /feat medians of 4 (mean of the middle two): calls 5 (4,5,5,6), spawn 2,
#   chores 1 (0,1,1,2), text 2 (1,2,2,3), text only after a spawn 1.5 (sess-feat-1
#   1, sess-feat-2 2, sess-feat-3 1, sess-feat-6 2); ctx first 4510 (4010,4010,5010,
#   6010), median 5610 (4010,5210,6010,6910), max 6080 (5010,5210,6950,
#   8010); share (59.19 + 71.18) / 2 = 65%; failed Bash 2, Edit 1 (totals).
#   planner 4 runs: 1 spawn, 2 calls, ctx 3000, (17.84 + 18.81) / 2 = 18%,
#   model 220 s 3.7, tool 10 s 0.2; design reviewer 1 run: 1, 1, 1000, 12%,
#   2.0, 0.0; shipper 4 runs: 1, 2, 2000, (10.35 + 10.98) / 2 = 11%, 2.3,
#   0.5. Wall: agents 420 s 7.0 (62.99 + 80.46 -> 72%), user (20 + 90) / 2 =
#   55 s 0.9 (3.83 + 15.46 -> 10%), thinking (80 + 124) / 2 = 102 s 1.7
#   (15.33 + 19.69 -> 18%), tools 10 s 0.2 (1.37 + 1.57 -> 1%), duration
#   (522 + 582) / 2 = 552 s 9.2, answers 1. Tokens in 5070, cw 4500, cr
#   (25740 + 29100) / 2 = 27.4k, out 750, units (80880 + 85820) / 2 = 83,350.
# First request (chars): planner tools Bash 81 + Read 86 = 167 (compact
#   JSON), skills listing 21, system 20 + 20 = 40, instructions 2 files 15 +
#   22 = 37, total 265 (63/8/15/14%; sess-feat-6's larger tools part leaves
#   each median on the other three runs); schemas Read 86, Grep 83 (only
#   sess-feat-6), Bash 81; design reviewer tools 81, skills 0, system 17, 0
#   files, total 98 (83/0/17/0%); shipper not recorded.
# sess-fix-1, /fix. Calls: spawn, spawn 10/0/1000/40 -> 1010, 1550 each;
#   text 10/0/1000/20 -> 1010, 1050. Calls 3 (2/0/1), units 4150. Haiku:
#   implementer 2000 + 310 = 2310, ctx 1500, model 90 s, tool 6 s; shipper
#   1250 + 160 = 1410, ctx 1000, model 40 s, tool 10 s. Run 7870:
#   52.73/29.35/17.92%. Timeline: think 6, tools 1, agents 120, think 6,
#   tools 1, agents 60, think 6 = 180 + 0 + 18 + 2 = 200 s (90/0/9/1%).
#   Tokens in 2550, cw 0, cr 5500, out 290.
run_case report

# no_money: without prices in a weights file no money is printed (FR-015).
no_money() {
  if grep -Eq '\$|USD' "$work/cases/$current/stdout"; then
    fail "money printed without prices" "$work/cases/$current/stdout"
  fi
}
no_money

# no_statistics: a comparison makes no statistical claim (FR-010).
no_statistics() {
  if grep -Eqi 'significan|confidence' "$work/cases/$current/stdout"; then
    fail "statistical wording in the comparison" "$work/cases/$current/stdout"
  fi
}

# compare: --compare-since 2026-03-04 (the date itself is "since"). Before:
# sess-feat-1, sess-feat-2; since: sess-feat-3 (08:10 UTC that day),
# sess-feat-6. Medians of 2 are means; diff = since - before, computed on
# the unrounded values; shares' diffs in whole percentage points.
#   Coordinator: calls 5.5 / 4.5 (-1), spawn 2 / 2, chores 1 / 1, text
#   2.5 / 1.5 (-1), ctx first 4510 / 5010 (+500), median 4610 / 6460
#   (+1850), max 5110 / 7480 (+2370), share (74.94 + 59.19) / 2 = 67.07% /
#   (49.67 + 71.18) / 2 = 60.42% (-6.64 -> -7pp). Failed tools, totals over
#   2 and 2 runs, no diff: Bash 1 / 1, Edit - / 1.
#   Agents, sorted by since's share: planner runs 2 / 2, calls 2.5 / 2
#   (-0.5), share 17.16% / 24.50% (+7pp), model 230 s 3.8 / 220 s 3.7 (-10 s
#   -0.2), tool 20 s 0.3 / 10 s 0.2 (-0.2); shipper share 9.95% / 15.08%
#   (+5pp), model 110 s 1.8 / 140 s 2.3 (+0.5), tool 0.5 / 0.5 (0.0);
#   design reviewer on the before side only: 1, 1, 1, 1000, 12%, 2.0, 0.0 /
#   - (no diff).
#   Wall: agents 420 / 420 s (0.0), shares 62.42% / 83.26% (+21pp); user
#   105 s 1.8 (1.75 is exact in binary: half to even) / 10 s 0.2 (-95 s
#   -1.6), 15.61% / 1.92% (-14pp); thinking 137 s 2.3 / 67.5 s 1.1 (-1.2),
#   20.50% / 13.30% (-7pp); tools 10 s 0.2 / 7.5 s 0.1 (-2.5 s shows 0.0,
#   no sign), 1.47% / 1.52% (0pp); duration 672 s 11.2 / 505 s 8.4 (-2.8);
#   answers 1.5 / 0.5 (-1).
#   First request: planner tools 167 / (167 + 250) / 2 = 208.5 (+41.5),
#   total 265 / 306.5 (+41.5), the rest equal; schemas Read 86 / 86, Grep -
#   / 83, Bash 81 / 81; design reviewer before only; shipper not recorded.
#   Tokens: in 5580 / 5065 (-515), cw 5100 / 2000 (-3100), cr 27250 27.2k
#   (exact half, to even) / 31370 31.4k (+4120), out 910 / 725 (-185), units
#   89,415 / 63,595 (-25,820).
# /fix: sess-fix-1 (2026-03-05) is since; before prints `no runs`, no diffs.
run_case compare --compare-since 2026-03-04
no_statistics

# compare-empty: no run before 2026-03-01, so before is `no runs` in both
# blocks and since holds the report's medians. Exit 0.
run_case compare-empty --compare-since 2026-03-01
no_statistics

# Selection fixtures (US3): five /fix runs shaped like sess-fix-1 (same
# calls, agents, timestamps relative to the invocation) whose last
# coordinator call (opus, text only) has k more output tokens: each one adds
# 5 x 5 = 25 units, so coordinator 4150 + 25k, implementer 2310, shipper
# 1410; nothing else changes (wall clock 3.0/0.0/0.3/0.0, 3.3 min, tokens in
# 2550, cw 0, cr 5500, out 290 + k). Coordinator / implementer / shipper
# shares: k=0 7870 units 52.73/29.35/17.92%; k=20 8370 units
# 4650/8370 = 55.56 -> 56%, 27.60 -> 28%, 16.85 -> 17%, out 310; k=40 8870
# units 5150/8870 = 58.06 -> 58%, 26.04 -> 26%, 15.90 -> 16%, out 330; k=60
# 9370 units (in medians only).
#   other: sess-other-1 k=20 on 2026-04-01 at 23:00 UTC, sess-other-2 k=40
#   on 2026-04-10 at 23:00, sess-other-3 k=60 on 2026-04-11 at 00:00.
#   tab<TAB>repo: sess-tab-1 k=0. lib (cwd lib/src, which does not exist;
#   .git a file naming a git dir with no commondir): sess-lib-1 k=20.

# project: --project other on the one day 2026-04-10 (both bounds
# inclusive): sess-other-2 only (the runs the hour before and the hour after
# that day are not counted). One /fix run, k=40.
run_case project --project "$work/other" --since 2026-04-10 --until 2026-04-10

# all: --all, repos sorted by path. app: as report (both blocks). app-old:
# sess-old-1, /feat at 15:00:00: one spawn 10/0/0/10 -> ctx 10, 60 x 5 =
# 300 units; shipper (sonnet) 100/0/0/10 -> ctx 100, 150 x 3 = 450, model
# 30 s 0.5, tool 0; run 750: 40/60%. Timeline: think 5, tools 1 (async
# launch), agents 60 = 66 s 1.1 (90.91/0/7.58/1.52% -> 91/0/8/2%), think 5 s
# 0.1, tools 1 s 0.0. Tokens in 110, cw 0, cr 0, out 20. lib: k=20. other:
# medians of k=20, 40, 60 are k=40's. tab?repo (tab printed as ?): k=0, the
# report's /fix block.
# all repos, /feat over 5 runs (feat-1, feat-2, feat-3, feat-6, old-1), the
# middle value: calls 1,4,5,5,6 -> 5; spawn 1,2,2,2,2 -> 2; chores
# 0,0,1,1,2 -> 1; text 0,1,2,2,3 -> 2; ctx first 10,4010,4010,5010,6010 ->
# 4010; median 10,4010,5210,6010,6910 -> 5210; max 10,5010,5210,6950,8010
# -> 5210; share 40,49.67,59.19,71.18,74.94 -> 59%; failed Bash 2, Edit 1
# over 5 runs. planner and design reviewer as in report (not in old-1);
# shipper 5 runs: calls 1,2,2,2,2 -> 2, ctx first 100,2000 x4 -> 2000,
# share 9.55,10.35,10.98,19.17,60 -> 11%, model 30,80,140,140,140 s -> 2.3,
# tool 0,30,30,30,30 -> 0.5. Wall: agents 60,360,420,420,480 -> 420 s 7.0,
# share 61.86,62.99,80.46,86.07,90.91 -> 80%; user 0,0,20,90,120 -> 20 s
# 0.3, share 0,0,3.83,15.46,15.75 -> 4%; thinking 5,55,80,124,150 -> 80 s
# 1.3, share 7.58,11.27,15.33,19.69,21.31 -> 15%; tools 1,2,8,12,13 -> 8 s
# 0.1, share 0.38,1.37,1.52,1.57,2.66 -> 2%; duration 66,488,522,582,762 ->
# 522 s 8.7; answers 0,0,1,1,2 -> 1. First request as in report (old-1 has
# none). Tokens: in 110,5060,5070,5070,6090 -> 5070; cw 0,0,4000,5000,5200
# -> 4000; cr 0,25400,25740,29100,37000 -> 25.7k; out 20,720,730,770,1050
# -> 730; units 750,46310,80880,85820,93010 -> 80,880.
# odd (between lib and other): sess-odd-ok, a /fix run shaped like
# sess-fix-1 (k=0), the report's /fix block; its six left-out runs (see
# left-out below) are listed once, after the resumed list.
# all repos, /fix over 7 runs: k = 0 (fix-1), 0 (tab), 0 (odd), 20 (lib),
# 20, 40, 60 (other); every figure is monotone in k, so the middle (4th) is
# k=20, as it was over 6.
# Lists once at the end: 14 counted (12 finished, 1 unfinished, 1 resumed),
# 6 left out.
run_case all --all

# no-runs: app has no run in May 2026. Exit 0.
run_case no-runs --since 2026-05-01 --until 2026-05-31

# session: --session sess-feat-1, run from other with --project other to
# show the id is searched in every project folder and the selection is
# ignored. One /feat block with sess-feat-1's own values (its arithmetic is
# under `report` above): calls 5 (2/1/2), ctx 5010 / median of 5010, 5010,
# 5210, 5210, 5210 = 5210 / 5210, share 69700 / 93010 = 74.94 -> 75%,
# failed Bash 1 (no total). planner: 1 spawn, 2 calls, ctx 3000, 15.51 ->
# 16%, model 260 s 4.3, tool 10 s 0.2; shipper: 1, 2, 2000, 9.55 -> 10%,
# 140 s 2.3, 30 s 0.5. Wall: 480 s 8.0 (62.99 -> 63%), 120 s 2.0 (15.75 ->
# 16%), 150 s 2.5 (19.69 -> 20%), 12 s 0.2 (1.57 -> 2%), duration 762 s
# 12.7, answers 1. First request: planner 167/21/40/37 = 265 (63/8/15/14%),
# schemas Read 86, Bash 81; shipper not recorded. Tokens 5070, 5200, 25.4k,
# 770, 93,010.
from="$work/other" run_case session --session sess-feat-1 --project "$work/other"

# An unknown id, and a session that is not a run (/brief), print the "no
# runs found" line for the session and exit 0.
for id in sess-nope sess-brief-1; do
  current="session-not-found $id"
  out="$(python3 -I "$script" --session "$id")" || fail "exit $?"
  [ "$out" = "no runs found in $work/config/projects for session $id" ] || fail "got: $out"
  printf 'ok %s\n' "$current"
done

# weights: --session sess-feat-2 with fixtures/weights/weights.json (tokens
# output 4, cache write 5m 1; models sonnet 2, opus 4, claude-sonnet-5 6:
# the id beats its part, and 6 is now the highest model weight). Base of a
# call = in + 0.1 cr + 4 out + 1 cw5m (no breakdown is 5m), x the model.
#   Coordinator (claude-opus-5-5, part opus 4): msg-2-1 10 + 4000 + 4 x 120
#   = 4490, msg-2-2 and -3 10 + 400 + 160 = 570, msg-2-4 10 + 400 + 80 =
#   490, msg-2-5 10 + 1000 + 400 + 400 = 1810, msg-2-6 10 + 500 + 120 = 630:
#   sum 8560 x 4 = 34240. planner (claude-sonnet-5, 6): 3000 + 400,
#   10 + 300 + 200, 10 + 310 + 800 = 5030 x 6 = 30180. design reviewer
#   (claude-mystery-1, unweighted: the highest weight in effect, 6): 1000 +
#   800 = 1800 x 6 = 10800. shipper (6): 2000 + 400, 10 + 200 + 200 = 2810 x
#   6 = 16860. Run 92080: 37.19/32.78/18.31/11.73% -> 37/33/18/12%, so the
#   shipper now comes before the design reviewer.
#   The rest is sess-feat-2's own figures (under `report` above): calls 6
#   (2/1/3), ctx 4010 / median of 4010 x4, 5010 x2 = 4010 / 5010; planner 1
#   spawn, 3 calls, ctx 3000, 200 s 3.3, 30 s 0.5; shipper 2 calls, ctx
#   2000, 80 s 1.3, 30 s 0.5; design reviewer 1 call, ctx 1000, 2.0, 0.0.
#   Wall 360/90/124/8 s of 582 s: 6.0 62%, 1.5 15%, 2.1 21%, 0.1 1%, 9.7,
#   answers 2. First request as in report (planner without Grep). Tokens in
#   6090, cw 5000, cr 29.1k, out 1050. No prices: no money.
run_case weights --session sess-feat-2 --weights "$here/fixtures/weights/weights.json"
no_money

# weights-prices: the project case (sess-other-2, k=40) with
# fixtures/weights/prices.json (cache read 0.2, haiku 2; prices opus 400,
# sonnet 300 USD per Mtok). Base: coordinator 10 + 200 + 200 twice, 10 + 200
# + 300 = 1330 x 5 = 6650; implementer (claude-haiku-5, 2) 1500 + 500, 10 +
# 300 + 150 = 2460 x 2 = 4920; shipper 1000 + 250, 10 + 200 + 50 = 1510 x 2
# = 3020. Run 14590: 45.58/33.72/20.70% -> 46/34/21%. USD = base x price,
# no model weight: haiku has no price, so the highest given, 400: (1330 +
# 2460 + 1510) x 400 / 1,000,000 = $2.12. Everything else as `project`.
run_case weights-prices --project "$work/other" --since 2026-04-10 --until 2026-04-10 \
  --weights "$here/fixtures/weights/prices.json"

# A bad weights file: exit 2, a message on stderr naming the section and
# key (never the file's other content: each holds a SECRET- sentinel where
# it can), nothing on stdout. Each line: file, then a part of the message.
while IFS='|' read -r name says; do
  current="weights error $name"
  dir="$work/cases/weights-$name"
  mkdir -p "$dir"
  rc=0
  (cd "$work/app" && python3 -I "$script" --weights "$here/fixtures/weights/$name.json") \
    >"$dir/stdout" 2>"$dir/stderr" || rc=$?
  [ "$rc" -eq 2 ] || fail "exit $rc, not 2" "$dir/stderr"
  [ ! -s "$dir/stdout" ] || fail "stdout not empty" "$dir/stdout"
  grep -qF -- "$says" "$dir/stderr" || fail "stderr does not say: $says" "$dir/stderr"
  if grep -q 'SECRET-' "$dir/stderr"; then fail "stderr holds file content" "$dir/stderr"; fi
  printf 'ok %s\n' "$current"
done <<'EOF'
bad-bool|tokens.input must be a finite number >= 0
bad-nan|NaN is not a number here
bad-infinity|Infinity is not a number here
bad-huge|tokens.output must be a finite number >= 0
bad-negative|models.sonnet must be a finite number >= 0
bad-string|tokens.cache_read must be a finite number >= 0
bad-section|unknown section discounts
bad-token-key|unknown key tokens.cache_write
bad-not-json|not valid JSON
bad-section-type|section models is not an object
bad-root|not a JSON object
missing|cannot be read
EOF

# project-missing: --project on a path that does not exist (app/nope: its
# parent is a repo) is refused like a bad date: exit 2, a message on stderr,
# nothing on stdout. Only a recorded cwd climbs to an existing parent.
current="project-missing"
dir="$work/cases/project-missing"
mkdir -p "$dir"
rc=0
(cd "$work/app" && python3 -I "$script" --project "$work/app/nope") >"$dir/stdout" 2>"$dir/stderr" || rc=$?
[ "$rc" -eq 2 ] || fail "exit $rc, not 2" "$dir/stdout"
[ ! -s "$dir/stdout" ] || fail "stdout not empty" "$dir/stdout"
grep -qxF -- "measure.py: error: --project: no such directory: $work/app/nope" "$dir/stderr" ||
  fail "stderr does not name the path" "$dir/stderr"
printf 'ok %s\n' "$current"

# left-out (US6): --project odd. One counted run, sess-odd-ok (2026-03-17,
# /fix shaped like sess-fix-1: the report's /fix block, figures unchanged),
# and six runs left out whole, each a /feat run with one feat-shipper agent,
# listed by date with the first recorded version (FR-016, FR-017):
#   sess-odd-1 (2.1.310): the agent's only call has no usage (its only feat-*
#     agent: left out, not taken for "not a run");
#   sess-odd-2 (2.1.311): the last coordinator call has no timestamp (a
#     `mode` record without one, unused, changes nothing);
#   sess-odd-3 (2.1.312): a line cut short, not JSON;
#   sess-odd-4 (2.1.313): `usage` is a SECRET- string, not an object:
#     `unexpected record shape`, the value and the error never printed;
#   sess-odd-5 (2.1.314): the spawn's result names agent id `../x`;
#   sess-odd-6 (no version: `unknown`): the invocation has no origin; its
#     date is its first record's.
# Not runs, so neither counted nor listed: sess-odd-7 (invocation without
# origin), sess-odd-8 (a user record whose message is a SECRET- string,
# before the invocation) and sess-odd-9 (invocation without timestamp), each
# with one agent that is not feat-* (Explore from its meta, general-purpose
# from its spawn for sess-odd-8, which has no meta).
# Exit 0 without --strict.
run_case left-out --project "$work/odd"

# left-out --strict: the same stdout, exit 1 (FR-017).
current="left-out --strict"
dir="$work/cases/left-out-strict"
mkdir -p "$dir"
rc=0
(cd "$work/app" && python3 -I "$script" --project "$work/odd" --strict) >"$dir/stdout" 2>"$dir/stderr" || rc=$?
[ "$rc" -eq 1 ] || fail "exit $rc, not 1" "$dir/stderr"
if grep -q 'SECRET-' "$dir/stdout" "$dir/stderr"; then fail "output holds fixture text (SECRET-)"; fi
out="$(cat "$dir/stdout")"
printf '%s\nexit 0\n' "${out//"$work"/@ROOT@}" >"$dir/actual"
diff -u "$expected/left-out.txt" "$dir/actual" >"$dir/diff" || fail "stdout differs from expected/left-out.txt" "$dir/diff"
printf 'ok %s\n' "$current"

# --strict with nothing left out: exit 0 (app has no left-out run).
current="strict-clean"
(cd "$work/app" && python3 -I "$script" --strict >/dev/null) || fail "exit $?"
printf 'ok %s\n' "$current"

# not-a-run: a tagged session with a defect and no feat-* agent is not a run,
# so --strict does not fail on it: "no runs found", exit 0.
for id in sess-odd-7 sess-odd-8 sess-odd-9; do
  current="not-a-run $id"
  out="$(python3 -I "$script" --session "$id" --strict 2>&1)" || fail "exit $?: $out"
  [ "$out" = "no runs found in $work/config/projects for session $id" ] || fail "got: $out"
  printf 'ok %s\n' "$current"
done

# --session on a left-out run (US4, FR-009): its `left out:` row, exit 0,
# then exit 1 with --strict. No golden file.
current="session-left-out"
row="  sess-odd-1  2026-03-11  model call without token usage  (Claude Code 2.1.310)  $work/odd"
for want in 0 1; do
  args=(--session sess-odd-1)
  [ "$want" -eq 0 ] || args+=(--strict)
  rc=0
  out="$(python3 -I "$script" "${args[@]}" 2>&1)" || rc=$?
  [ "$rc" -eq "$want" ] || fail "exit $rc, not $want with ${args[*]}"
  grep -qxF -- "left out:" <<<"$out" || fail "no left out: list: $out"
  grep -qxF -- "$row" <<<"$out" || fail "no row for sess-odd-1: $out"
  grep -qF -- "runs: 0 counted (0 finished, 0 unfinished, 0 resumed), 1 left out" <<<"$out" ||
    fail "header counts: $out"
  if grep -q 'SECRET-' <<<"$out"; then fail "output holds fixture text (SECRET-)"; fi
done
printf 'ok %s\n' "$current"

# unknown-record: sess-feat-1 with a record of an unknown type appended
# (fixtures/unknown-record; its `message` and `usage` are SECRET- strings, a
# shape that would leave the run out if read) gives the report byte for byte.
# The copy replaces app's sess-feat-1 for this case only.
target="$work/config/projects/app/sess-feat-1.jsonl"
chmod u+w "$(dirname "$target")"
command mv -f "$target" "$target.orig"
sed "s|@ROOT@|$root_sed|g" "$here/fixtures/unknown-record/sess-feat-1.jsonl" >"$target"
chmod a-w "$target"
expect=report run_case unknown-record
command rm -f "$target"
command mv -f "$target.orig" "$target"
chmod a-w "$(dirname "$target")"

# edge: --all over fixtures/edge (CLAUDE_CONFIG_DIR=$work/edge). sess-nul-1,
# a finished /feat run whose recorded cwd holds a NUL and a SECRET- text: its
# repo cannot be resolved, so it is left out as `unexpected record shape`,
# repo `unknown`, the error text never printed. sess-sur-1, a finished /fix
# run in odd whose last coordinator call has the model id claude-opus\ud800-5
# (a lone surrogate): printed with `?` in its place. sess-note-1 (the
# `notification` case below) is the second counted run; sess-async-1 and
# sess-fg-1 (the `after-spawn` case) are the third and fourth. Exit 0, then 1 with
# --strict. No golden file: the lines below, and no traceback.
current="edge"
for want in 0 1; do
  args=(--all)
  [ "$want" -eq 0 ] || args+=(--strict)
  rc=0
  out="$(cd "$work/app" && CLAUDE_CONFIG_DIR="$work/edge" python3 -I "$script" "${args[@]}" 2>&1)" || rc=$?
  [ "$rc" -eq "$want" ] || fail "exit $rc, not $want with ${args[*]}: $out"
  for line in \
    "runs: 4 counted (4 finished, 0 unfinished, 0 resumed), 1 left out" \
    "  sess-nul-1  2026-03-21  unexpected record shape  (Claude Code 2.1.330)  unknown" \
    "unweighted models: claude-opus?-5 (weighted as 5)"; do
    grep -qxF -- "$line" <<<"$out" || fail "no line: $line: $out"
  done
  if grep -q 'SECRET-\|Traceback' <<<"$out"; then fail "output holds fixture or error text: $out"; fi
done
printf 'ok %s\n' "$current"

# notification: --session sess-note-1 (fixtures/edge), a finished /fix run
# where no report record arrives, only `task-notification` records, as when an
# agent's end is all the coordinator sees. A notification whose task id names
# one of the session's agent transcripts ends "agents working"; any other task
# (the coordinator's own background command) ends "coordinator tools".
#   09:00:00 invocation
#   09:00:10 reply, spawns feat-shipper     thinking 10 s
#   09:00:11 spawn result, async_launched   tools     1 s
#   09:02:11 notification, task n11 (agent) agents  120 s
#   09:02:20 reply, background Bash         thinking  9 s
#   09:02:21 its tool result                tools     1 s
#   09:03:21 notification, task bash77      tools    60 s
#   09:03:30 reply, text                    thinking  9 s
# agents 120 s = 2.0 min, 120/210 = 57%; user 0; thinking 28 s = 0.5 min,
# 28/210 = 13%; tools 62 s = 1.0 min, 62/210 = 30%; duration 210 s = 3.5 min.
current="notification"
rc=0
out="$(cd "$work/app" && CLAUDE_CONFIG_DIR="$work/edge" python3 -I "$script" --session sess-note-1 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "exit $rc: $out"
for line in \
  "  agents working                   2.0    57%" \
  "  waiting for the user             0.0     0%" \
  "  coordinator thinking             0.5    13%" \
  "  coordinator tools                1.0    30%" \
  "  run duration                     3.5"; do
  grep -qxF -- "$line" <<<"$out" || fail "no line: $line: $out"
done
if grep -q 'SECRET-\|Traceback' <<<"$out"; then fail "output holds fixture or error text: $out"; fi
printf 'ok %s\n' "$current"

# after-spawn: `text only after a spawn` (FR-010), --session over fixtures/edge.
# sess-async-1: two background spawns, each result `async_launched` and
# followed by a text-only turn (2); then the peer reports and a Bash call,
# which are not counted. sess-fg-1: a two-spawn foreground batch and a
# foreground shipper, each result `completed` and followed by a Bash call or
# the final text after a chore (0).
current="after-spawn"
for want in "sess-async-1|2" "sess-fg-1|0"; do
  rc=0
  out="$(cd "$work/app" && CLAUDE_CONFIG_DIR="$work/edge" python3 -I "$script" --session "${want%|*}" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || fail "exit $rc: $out"
  line="$(grep -F '  text only after a spawn' <<<"$out")" || fail "no text only after a spawn line: $out"
  [ "${line##* }" = "${want#*|}" ] || fail "${want%|*}: $line, not ${want#*|}"
  if grep -q 'SECRET-\|Traceback' <<<"$out"; then fail "output holds fixture or error text: $out"; fi
done
printf 'ok %s\n' "$current"

# window: one date bound only; the missing side prints as `start` or `now`
# (docs/measure.md). No golden file: one fixed line each, exit 0.
current="window"
for args in "--since 2099-01-01|2099-01-01 to now" "--until 2000-01-01|start to 2000-01-01"; do
  read -r opt day <<<"${args%%|*}"
  out="$(cd "$work/app" && python3 -I "$script" "$opt" "$day" 2>&1)" || fail "exit $? with $opt"
  want="no runs found in $work/config/projects for $work/app, ${args#*|}"
  [ "$out" = "$want" ] || fail "with $opt: $out"
done
printf 'ok %s\n' "$current"

# help (FR-002, FR-019): --help lists every option and ends with the default
# weights line. The usage paragraph is left out of the comparison: argparse
# wraps it differently across Python versions (3.12 keeps an option group on
# one line, 3.13 and later may split it); the options below it don't change.
current="help"
dir="$work/cases/help"
mkdir -p "$dir"
rc=0
COLUMNS=80 python3 -I "$script" --help >"$dir/stdout" 2>"$dir/stderr" || rc=$?
[ "$rc" -eq 0 ] || fail "exit $rc" "$dir/stderr"
grep -q '^usage: measure.py ' "$dir/stdout" || fail "no usage line" "$dir/stdout"
{ sed '1,/^$/d' "$dir/stdout"; printf 'exit %s\n' "$rc"; } >"$dir/actual"
diff -u "$expected/help.txt" "$dir/actual" >"$dir/diff" || fail "output differs from expected/help.txt" "$dir/diff"
printf 'ok %s\n' "$current"

# docs: docs/measure.md begins with its title and weight front matter and
# quotes the default weights line exactly as --help prints it (FR-020).
current="docs"
page="$root/docs/measure.md"
[ -f "$page" ] || fail "no docs/measure.md"
[ "$(sed -n 1p "$page")" = "---" ] || fail "docs/measure.md has no front matter"
front="$(sed -n '2,/^---$/p' "$page")"
grep -q '^title: ' <<<"$front" || fail "docs/measure.md front matter has no title"
grep -q '^weight: ' <<<"$front" || fail "docs/measure.md front matter has no weight"
line="$(tail -n 1 "$dir/stdout")"
[[ "$line" == weights:* ]] || fail "--help does not end with the weights line" "$dir/stdout"
grep -qxF -- "$line" "$page" || fail "docs/measure.md does not quote: $line"
printf 'ok %s\n' "$current"

# install-check (FR-021): install.sh check with stubs first on PATH (claude
# and gh, so nothing real or online runs; python3 old or new) and an empty
# HOME. An old Python gives a `note` line naming 3.11 and the same exit code.
current="install-check"
dir="$work/cases/install-check"
mkdir -p "$dir/home"
declare -A check_rc=()
for py in new old; do
  rc=0
  (cd "$dir" && HOME="$dir/home" PATH="$here/bin:$PATH" MEASURE_PYTHON="$py" \
    bash "$root/install.sh" check) >"$dir/$py" 2>&1 || rc=$?
  check_rc[$py]="$rc"
done
grep -qxF "ok       python3 3.11 or later (measure.py)" "$dir/new" ||
  fail "no ok line for python3" "$dir/new"
grep -qxF "note     python3 3.11 or later not found (needed by measure.py only: docs/measure.md)" "$dir/old" ||
  fail "no note line for python3" "$dir/old"
if grep -q 'MISSING.*python' "$dir/old"; then fail "python3 counted as missing" "$dir/old"; fi
[ "${check_rc[old]}" = "${check_rc[new]}" ] ||
  fail "exit ${check_rc[old]} with an old python3, ${check_rc[new]} with a new one" "$dir/old"
printf 'ok %s\n' "$current"

# static (FR-003): measure.py imports only the standard-library allowlist, no
# network or subprocess module, uses only the `os` readers it needs (named
# below; `os` itself only as `os.<name>`), opens files only for reading, and
# calls no exec, eval or __import__. Read with ast, so comments and strings
# don't count.
current="static"
python3 -I - "$script" <<'EOF' || fail "measure.py breaks the read-only, offline rule"
import ast, sys
allowed = {"argparse", "json", "math", "os", "re", "statistics", "datetime",
           "collections", "sys"}
os_names = {"environ", "getcwd", "listdir", "path"}
os_path_names = {"abspath", "dirname", "expanduser", "isdir", "isfile", "join", "realpath"}
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
parent = {child: node for node in ast.walk(tree) for child in ast.iter_child_nodes(node)}


def attr_of(node):
    """The attribute name read on `node` (node.<name>), or None."""
    p = parent.get(node)
    return p.attr if isinstance(p, ast.Attribute) and p.value is node else None


bad = []
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        names = [a.name for a in node.names]
        bad += [f"import {a.name} as {a.asname}" for a in node.names if a.name.split(".")[0] == "os" and a.asname]
    elif isinstance(node, ast.ImportFrom):
        names = [node.module or ""] if node.level == 0 else ["relative import"]
        if names[0].split(".")[0] == "os":
            bad.append(f"from {names[0]} import (line {node.lineno})")
    else:
        names = []
    bad += [f"import {n}" for n in names if n.split(".")[0] not in allowed]
    if isinstance(node, ast.Name) and node.id == "os":
        name = attr_of(node)
        if name == "path":
            sub = attr_of(parent[node])
            if sub not in os_path_names:
                bad.append(f"os.path.{sub} (line {node.lineno})")
        elif name not in os_names:
            bad.append(f"os.{name} (line {node.lineno})" if name else f"bare os (line {node.lineno})")
    if not isinstance(node, ast.Call):
        continue
    f = node.func
    name = f.id if isinstance(f, ast.Name) else f.attr if isinstance(f, ast.Attribute) else ""
    if isinstance(f, ast.Name) and name in ("exec", "eval", "__import__", "compile"):
        bad.append(f"call {name} (line {node.lineno})")
    if name == "open":
        if isinstance(f, ast.Attribute):  # os.open, io.open: flags not checked here
            bad.append(f"call {ast.unparse(f)} (line {node.lineno})")
            continue
        mode = node.args[1] if len(node.args) > 1 else next(
            (k.value for k in node.keywords if k.arg == "mode"), None)
        if mode is None:
            continue  # "r"
        if not isinstance(mode, ast.Constant) or not isinstance(mode.value, str) \
                or set(mode.value) & set("wax+"):
            bad.append(f"open with mode {ast.unparse(mode)} (line {node.lineno})")
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
EOF
printf 'ok %s\n' "$current"

# The fixtures were read from read-only files and directories (chmod a-w at
# setup): every case above ran on them.
current="read-only fixtures"
if [ -n "$(find "$work/config" "$work/edge" -perm /222 -print -quit)" ]; then
  fail "a fixture is writable"
fi
printf 'ok %s\n' "$current"

echo "all measure tests passed"
