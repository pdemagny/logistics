#!/usr/bin/env bash
# Offline tests for .apm/skills/feat/scripts/ship.sh (mise run test:ship).
#
# One template is built per run: a bare origin whose main holds the base
# commit, and a clone on branch feat-x with a run's work in its tree (a spec
# dir specs/x/ with its state file and reports/, a changed and a new file).
# Each case copies both (`cp -R`) and points the copy's origin at its own
# bare repo, so no case runs `git init` or `git clone`. The stub
# tests/ship/bin/gh is first on PATH and answers from the case's gh dir
# ($SHIP_CASE); the real spec-number.sh, secret-scan.sh and state.sh run.
#
# Each case checks the exit code, the report or prepare's output against
# expected/<case>.out where it names one (the case's top level written
# `@TOP@`, commit hashes `@H1@`, `@H2@`... in order of appearance), and the
# repo itself: commits and their files, the index, origin's refs, the gh
# calls and the PR body. `UPDATE=1 bash tests/ship/run.sh` writes the actual
# outputs over expected/ and exits non-zero, so it never passes CI; review
# the change with `git diff tests/ship/expected`. Secret-looking samples are
# built by concatenation at run time, so this file passes the scan itself.
set -euo pipefail

started=$SECONDS
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(cd "$here/../.." && pwd -P)"
src="$root/.apm/skills/feat/scripts"
ship_sh="$src/ship.sh"
ex="$here/expected"
update="${UPDATE:-0}"
updated=0

current="setup"
fail() {
  printf 'FAIL %s: %s\n' "$current" "$1"
  if [ -n "${out+x}" ]; then printf '  output:\n%s\n' "$out"; fi
  if [ -s "${work:-/nonexistent}/stderr" ]; then printf '  stderr:\n%s\n' "$(cat "$work/stderr")"; fi
  exit 1
}
ok() { printf 'ok %s\n' "$current"; }

work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'command rm -rf -- "$work"' EXIT

# Commits here must not depend on the user's git config (signing, hooks).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
export PATH="$here/bin:$PATH"

# Sample pieces, split so no line here matches the secret rules.
tok="tok""en" long="Zq81mXv0Lw3NcR7tYp2Ue5Ha" gh_pre="gh""p_"

# --- the template ------------------------------------------------------------------

tmpl="$work/tmpl"
mkdir -p "$tmpl"
git init -q --bare "$tmpl/origin.git"
git -C "$tmpl/origin.git" symbolic-ref HEAD refs/heads/main
git clone -q "$tmpl/origin.git" "$tmpl/repo" 2>/dev/null
(
  cd "$tmpl/repo"
  git symbolic-ref HEAD refs/heads/main
  mkdir -p src docs .specify
  printf 'echo a\n' >src/a.sh
  printf 'readme\n' >README.md
  printf 'See specs/001-x for its history.\n' >docs/notes.md
  printf '{"feature_directory":"specs/x"}\n' >.specify/feature.json
  git add -A
  git commit -q -m init
  git push -q origin main 2>/dev/null
  git checkout -q -b feat-x
  mkdir -p specs/x/reports
  printf '*\n' >specs/x/reports/.gitignore
  printf '%s\n' '# /feat state: Test feature' '' '- Branch: feat-x Worktree: @TOP@' '- Size: medium' \
    '- Agents: none' '- Current phase: done (shipping)' '- Conventions: none' \
    '- Allowed Spec Kit hooks: none' '- Map: none' '- Issue: #57' '' '## Log' '' \
    '- [x] 0 Setup — worktree @TOP@' '- [x] 8 Ship' >specs/x/feat-state.md
  printf '# Spec\n\nThe plan is specs/x/plan.md.\n' >specs/x/spec.md
  printf 'echo b\n' >>src/a.sh
  printf 'echo new\n' >src/new.sh
)

n=0
# new_case <name>: a fresh copy; top, sd (the spec dir), rd (its reports/),
# org (the case's origin), SHIP_CASE (the stub's dir)
new_case() {
  current="$1"
  unset out
  n=$((n + 1))
  c="$work/c/$n"
  mkdir -p "$c/gh"
  cp -R "$tmpl/origin.git" "$c/origin.git"
  cp -R "$tmpl/repo" "$c/repo"
  top="$(cd "$c/repo" && pwd -P)"
  org="$c/origin.git"
  git -C "$top" remote set-url origin "$org"
  sd="$top/specs/x"
  rd="$sd/reports"
  sed "s#@TOP@#$top#g" "$sd/feat-state.md" >"$c/state.tmp"
  command mv -f "$c/state.tmp" "$sd/feat-state.md"
  export SHIP_CASE="$c/gh"
}

# notes <line>...: the notes file
notes() { printf '%s\n' "$@" >"$rd/ship-notes.md"; }

# std_notes [<extra commit lines>...]: two commits, then the extra lines
std_notes() {
  notes 'Commit: docs(specs): specify x' '- specs/x' \
    'Commit: feat(x): add new' '- src/a.sh' '- src/new.sh' 'Body:' 'Adds new.sh.' \
    "$@" \
    'Docs: none' 'Summary:' '### Why' 'Because.' 'Not verified: see below' \
    'Points to look at:' '- the parser' 'Not verified:' '- n/a → live run → no credentials'
}

# flags: the standard flags of a ship-mode call
flags() {
  F=(--worktree "$top" --default main --state "$sd/feat-state.md" --notes "$rd/ship-notes.md"
    --state-script "$src/state.sh" --secret-scan "$src/secret-scan.sh"
    --spec-number "$src/spec-number.sh" --report "$rd/8-ship.md")
}

# ship <prepare|publish> [<extra flag>...]: a ship-mode call with the standard
# flags; rc, raw (stdout), out (normalized); stderr must stay empty
ship() {
  local cmd="$1"
  shift
  flags
  run "$cmd" ship "${F[@]}" "$@"
  [ ! -s "$work/stderr" ] || fail "stderr not empty"
}

# run <args>...: ship.sh with exactly these arguments; rc, raw, out, err
run() {
  rc=0
  raw="$(bash "$ship_sh" "$@" 2>"$work/stderr")" || rc=$?
  err="$(cat "$work/stderr")"
  norm
}

# norm: out = raw with the top level written @TOP@ and the hashes of `- <hash7> `
# lines written @H<k>@ in order of first appearance
norm() {
  local line h i k hs=()
  out=""
  while IFS= read -r line; do
    line="${line//"$top"/@TOP@}"
    if [[ "$line" =~ ^-\ ([0-9a-f]{7})\  ]]; then
      h="${BASH_REMATCH[1]}"
      k=""
      for ((i = 0; i < ${#hs[@]}; i++)); do
        if [ "${hs[i]}" = "$h" ]; then k=$((i + 1)); fi
      done
      if [ -z "$k" ]; then
        hs+=("$h")
        k=${#hs[@]}
      fi
      line="- @H$k@ ${line:10}"
    fi
    out+="$line"$'\n'
  done <<<"$raw"
  out="${out%$'\n'}"
}

# golden <name>: out against expected/<name>.out
golden() {
  if [ "$update" = 1 ]; then
    printf '%s\n' "$out" >"$ex/$1.out"
    updated=1
    return 0
  fi
  [ -f "$ex/$1.out" ] || fail "no golden $ex/$1.out"
  [ "$out" = "$(cat "$ex/$1.out")" ] || fail "output differs from expected/$1.out"
}

want_rc() { [ "$rc" = "$1" ] || fail "exit $rc, want $1"; }

# usage_err: exit 2, nothing on stdout, one `ship: usage: ` line on stderr
usage_err() {
  want_rc 2
  [ -z "$raw" ] || fail "stdout not empty on a usage error"
  [ "$(printf '%s\n' "$err" | wc -l)" = 1 ] || fail "not one stderr line"
  [[ "$err" == 'ship: usage: '* ]] || fail "stderr: $err"
  if [ -n "${1:-}" ]; then [[ "$err" == *"$1"* ]] || fail "want a usage line naming: $1 (got: $err)"; fi
}

# blocked <the ! line, or a prefix of it ending in *>: exit 1, PR: blocked, that line
blocked() {
  want_rc 1
  [ "$(printf '%s\n' "$raw" | head -n 1)" = 'PR: blocked' ] || fail "not PR: blocked"
  local l
  l="$(printf '%s\n' "$raw" | sed -n 's/^Command for the user: //p')"
  case "$1" in
    *'*') [[ "$l" == "${1%\*}"* ]] || fail "! line: $l" ;;
    *) [ "$l" = "$1" ] || fail "! line: $l, want $1" ;;
  esac
}

# subjects: S = the subjects of origin/main..HEAD, oldest first, one per line
subjects() { S="$(git -C "$top" log --reverse --format=%s refs/remotes/origin/main..HEAD)"; }
# files_of <rev>: FO = the files the commit changes, one per line
files_of() { FO="$(git -C "$top" show --name-only --format= "$1")"; }
no_commit() { [ "$(git -C "$top" rev-list --count refs/remotes/origin/main..HEAD)" = 0 ] || fail "a commit was made"; }
index_empty() { git -C "$top" diff --cached --quiet || fail "the index is not empty"; }
no_push() { ! git -C "$org" rev-parse -q --verify refs/heads/feat-x >/dev/null || fail "feat-x was pushed"; }

# --- bash 3.2 ------------------------------------------------------------------------

current="bash 3.2 constructs only"
if grep -nE -- 'declare -A|mapfile|readarray|,,\}|\^\^\}|declare -n|local -n|\[\[ -v|\[-[0-9]+\]|;;&|\|&' \
  "$src/ship.sh" "$src/secret-scan.sh"; then
  fail "ship.sh or secret-scan.sh uses a construct bash 3.2 lacks"
fi
ok

# --- usage ---------------------------------------------------------------------------

new_case "usage: no arguments"
run
usage_err
run publish
usage_err
ok

new_case "usage: a missing flag"
std_notes
flags
run prepare ship "${F[@]:2}"
usage_err '--worktree is required'
ok

new_case "usage: a flag refused in the mode"
std_notes
flags
run prepare ship "${F[@]}" --branch feat-x
usage_err '--branch is refused in ship mode'
run prepare fix "${F[@]}" --security-bug no
usage_err '--spec-number is refused in fix mode'
ok

new_case "usage: a flag given twice, a value with a newline"
std_notes
flags
run prepare ship "${F[@]}" --default main
usage_err '--default given twice'
run prepare ship "${F[@]}" --report "$rd/a"$'\n'"b.md"
usage_err '--report holds a newline'
ok

new_case "usage: the branch to push is --default (ship)"
std_notes
git -C "$top" checkout -q main
flags
run prepare ship "${F[@]}"
usage_err 'the branch to push is --default'
ok

new_case "usage: the branch to push is --default (rebase)"
std_notes
git -C "$top" checkout -q main
run prepare rebase --worktree "$top" --default main --state "$sd/feat-state.md" --notes "$rd/ship-notes.md" \
  --state-script "$src/state.sh" --secret-scan "$src/secret-scan.sh" --branch main \
  --pr https://github.com/o/r/pull/42 --lease 0123456 --pr-note 'moved'
usage_err 'the branch to push is --default'
ok

new_case "usage: --notes outside reports/"
std_notes
command mv -f "$rd/ship-notes.md" "$sd/ship-notes.md"
flags
run prepare ship "${F[@]:0:6}" --notes "$sd/ship-notes.md" "${F[@]:8}"
usage_err "--notes is not in $sd/reports"
ok

new_case "usage: --report outside reports/"
std_notes
flags
run prepare ship "${F[@]:0:14}" --report "$sd/8-ship.md"
usage_err "--report is not in $sd/reports"
ok

new_case "usage: a symlinked reports/"
std_notes
command mv -f "$rd" "$c/elsewhere"
ln -s "$c/elsewhere" "$rd"
flags
run prepare ship "${F[@]}"
usage_err 'is not in'
no_commit
ok

new_case "usage: a symlinked report file"
std_notes
printf 'keep\n' >"$c/target"
ln -s "$c/target" "$rd/8-ship.md"
flags
run prepare ship "${F[@]}"
usage_err 'is a symlink'
[ "$(cat "$c/target")" = keep ] || fail "the symlink's target was written"
no_commit
ok

new_case "reports/.gitignore emptied: put back to *"
std_notes
: >"$rd/.gitignore"
ship prepare
want_rc 0
[ "$(cat "$top/specs/001-x/reports/.gitignore")" = '*' ] || fail ".gitignore not put back"
git -C "$top" log --name-only --format= refs/remotes/origin/main..HEAD | grep -q '/reports/' && fail "a reports/ path was committed"
ok

# --- notes ---------------------------------------------------------------------------

# notes_case <name> <want ! line> <notes line>...: prepare blocks before staging
notes_case() {
  new_case "notes: $1"
  local want="$2"
  shift 2
  notes "$@"
  ship prepare
  blocked "$want"
  no_commit
  index_empty
  [ -d "$sd" ] || fail "the spec dir moved"
  [ ! -e "$rd/ship-handoff.md" ] || fail "a handoff was written"
  [ "$(cat "$rd/8-ship.md")" = "$raw" ] || fail "report file differs from stdout"
  ok
}

notes_case "a missing key" '! ship: notes: no Summary: (line 6)' \
  'Commit: feat(x): add new' '- src/a.sh' 'Docs: none' 'Points to look at: none' 'Not verified: none'
notes_case "Commit: with no path" '! ship: notes: Commit: with no path (line 1)' \
  'Commit: feat(x): add new' 'Docs: none' 'Summary:' 'x' 'Points to look at: none' 'Not verified: none'
notes_case "an unknown key" '! ship: notes: unknown key (line 3)' \
  'Commit: feat(x): add new' '- src/a.sh' 'Title: x' 'Docs: none' 'Summary:' 'x' 'Points to look at: none' 'Not verified: none'
notes_case "a key given twice" '! ship: notes: Docs: given twice (line 4)' \
  'Commit: feat(x): add new' '- src/a.sh' 'Docs: none' 'Docs: none' 'Summary:' 'x' 'Points to look at: none' 'Not verified: none'
notes_case "a duplicate subject" '! ship: notes: duplicate subject (line 3)' \
  'Commit: feat(x): add new' '- src/a.sh' 'Commit: feat(x): add new' '- src/new.sh' 'Docs: none' 'Summary:' 'x' \
  'Points to look at: none' 'Not verified: none'
notes_case "a path with a .. component" '! ship: notes: path has a .. component (line 2)' \
  'Commit: feat(x): add new' '- src/../../etc' 'Docs: none' 'Summary:' 'x' 'Points to look at: none' 'Not verified: none'
notes_case "an absolute path" '! ship: notes: absolute path (line 2)' \
  'Commit: feat(x): add new' '- /etc/passwd' 'Docs: none' 'Summary:' 'x' 'Points to look at: none' 'Not verified: none'
notes_case "a closing keyword in a subject" '! ship: notes: closing keyword in commit 2 (line 3)' \
  'Commit: docs(specs): specify x' '- specs/x' 'Commit: feat(x): add new, closes #12' '- src/a.sh' \
  'Docs: none' 'Summary:' 'x' 'Points to look at: none' 'Not verified: none'
notes_case "a closing keyword in a body" '! ship: notes: closing keyword in commit 1 (line 4)' \
  'Commit: feat(x): add new' '- src/a.sh' 'Body:' 'Fixes: owner/repo#3 at last' \
  'Docs: none' 'Summary:' 'x' 'Points to look at: none' 'Not verified: none'
notes_case "a secret in a subject" '! secret scan: commit 2 matches key-literal' \
  'Commit: docs(specs): specify x' '- specs/x' "Commit: feat(x): $tok = $long" '- src/a.sh' \
  'Docs: none' 'Summary:' 'x' 'Points to look at: none' 'Not verified: none'
[[ "$raw" != *"$long"* ]] || fail "the value reached the report"
notes_case "a secret in a Body: line" '! secret scan: commit 1 matches github-token' \
  'Commit: feat(x): add new' '- src/a.sh' 'Body:' "uses ${gh_pre}${long}" \
  'Docs: none' 'Summary:' 'x' 'Points to look at: none' 'Not verified: none'
[[ "$raw" != *"$long"* ]] || fail "the value reached the report"

new_case "notes: Not verified: see below inside Summary: is text"
std_notes
ship prepare
want_rc 0
ok

new_case "notes: a reports/ path is dropped, never staged"
std_notes 'Commit: chore(x): notes' '- specs/x/reports/ship-notes.md' '- specs/x/reports'
ship prepare
want_rc 0
subjects
[ "$S" = $'docs(specs): specify x\nfeat(x): add new' ] || fail "subjects: $S"
git -C "$top" log --name-only --format= refs/remotes/origin/main..HEAD | grep -q 'reports' && fail "a reports/ path was committed"
ok

new_case "publish: no handoff"
std_notes
ship publish
blocked '! ship: no handoff from prepare; nothing pushed'
no_push
[ ! -e "$SHIP_CASE/calls" ] || fail "gh was called"
ok

# --- US1: ship mode ----------------------------------------------------------------------

new_case "ship: prepare then publish"
std_notes
ship prepare
want_rc 0
golden ship-prepare
[[ "$out" != *'Brought in:'* ]] || fail "Brought in: in ship mode"
sd="$top/specs/001-x"
rd="$sd/reports"
[ -d "$sd" ] && [ ! -e "$top/specs/x" ] || fail "the spec dir is not numbered"
[ -f "$rd/ship-handoff.md" ] || fail "no handoff"
grep -q '^Commits:$' "$rd/ship-handoff.md" || fail "handoff has no Commits:"
[ "$(cat "$top/.specify/feature.json")" = '{"feature_directory":"specs/001-x"}' ] || fail "feature.json not rewritten"
grep -q 'specs/001-x/plan.md' "$sd/spec.md" || fail "spec.md not rewritten"
subjects
[ "$S" = $'docs(specs): specify x\nfeat(x): add new' ] || fail "subjects: $S"
files_of HEAD~1
[ "$FO" = $'specs/001-x/feat-state.md\nspecs/001-x/spec.md' ] || fail "commit 1 files: $FO"
files_of HEAD
[ "$FO" = $'src/a.sh\nsrc/new.sh' ] || fail "commit 2 files: $FO"
[ "$(git -C "$top" log -1 --format=%b HEAD)" = 'Adds new.sh.' ] || fail "commit 2 body"
index_empty
no_push
ship publish
want_rc 0
golden ship-pr
[ "$(git -C "$org" rev-parse refs/heads/feat-x)" = "$(git -C "$top" rev-parse HEAD)" ] || fail "feat-x not pushed"
create="$(grep '^pr create ' "$SHIP_CASE/calls")"
[[ "$create" == 'pr create --base main --head feat-x --title feat(x): add new --body-file '* ]] || fail "pr create: $create"
[[ "$create" != *--draft* ]] || fail "a draft"
body="$(cat "$SHIP_CASE/pr-body")"
want_body='### Why
Because.
Not verified: see below

### Code review

Code review was skipped.

### Points to look at

- the parser

### Not verified

- n/a → live run → no credentials

State file: [specs/001-x/feat-state.md](https://github.com/o/r/blob/feat-x/specs/001-x/feat-state.md)

Closes #57'
[ "$body" = "$want_body" ] || { out="$body"; fail "PR body differs"; }
[ "$(cat "$rd/8-ship.md")" = "$raw" ] || fail "report file differs from stdout"
ok

new_case "ship: no Issue: line, no closing line"
grep -v '^- Issue:' "$sd/feat-state.md" >"$c/state.tmp"
command mv -f "$c/state.tmp" "$sd/feat-state.md"
std_notes
ship prepare
want_rc 0
ship publish
want_rc 0
! grep -qi 'closes' "$SHIP_CASE/pr-body" || fail "a closing line"
ok

new_case "ship: prepare twice commits nothing twice"
std_notes
ship prepare
want_rc 0
first="$out"
ship prepare
want_rc 0
[ "$out" = "$first" ] || fail "the second prepare differs"
subjects
[ "$S" = $'docs(specs): specify x\nfeat(x): add new' ] || fail "subjects: $S"
ok

new_case "ship: a check fix between the calls is folded into its commit"
std_notes
ship prepare
want_rc 0
printf 'echo fix\n' >>"$top/src/a.sh"
ship publish
want_rc 0
subjects
[ "$S" = $'docs(specs): specify x\nfeat(x): add new' ] || fail "subjects: $S"
git -C "$top" show HEAD:src/a.sh | grep -q 'echo fix' || fail "the fix is not in its commit"
index_empty
git -C "$top" diff --quiet HEAD -- src/a.sh || fail "src/a.sh left uncommitted"
ok

new_case "ship: a check-fix Commit: added between the calls keeps the title"
std_notes
ship prepare
want_rc 0
printf 'echo fix\n' >"$top/src/fix.sh"
rd="$top/specs/001-x/reports"
std_notes 'Commit: fix(x): check fix' '- src/fix.sh'
ship publish
want_rc 0
subjects
[ "$S" = $'docs(specs): specify x\nfeat(x): add new\nfix(x): check fix' ] || fail "subjects: $S"
grep -q '^pr create --base main --head feat-x --title feat(x): add new --body-file ' "$SHIP_CASE/calls" || fail "the title changed"
ok

new_case "ship: numbering rewrites the PR's own files"
printf 'See specs/x/plan.md and specs/xy.\n' >>"$top/README.md"
printf 'Contract: specs/x/contracts/a.md\n' >"$top/docs/guide.md"
std_notes 'Commit: docs: guide' '- README.md' '- docs/guide.md'
ship prepare
want_rc 0
subjects
[ "$S" = $'docs(specs): specify x\nfeat(x): add new\ndocs: guide' ] || fail "subjects: $S"
git -C "$top" show HEAD:README.md | grep -qx 'See specs/001-x/plan.md and specs/xy.' || fail "README.md not rewritten"
git -C "$top" show HEAD:docs/guide.md | grep -qx 'Contract: specs/001-x/contracts/a.md' || fail "docs/guide.md not rewritten"
grep -qx 'See specs/001-x for its history.' "$top/docs/notes.md" || fail "docs/notes.md was changed"
[ -z "$(git -C "$top" status --porcelain -- README.md docs)" ] || fail "a rewritten file is left uncommitted"
ok

new_case "ship: renumbered at publish"
std_notes
ship prepare
want_rc 0
# an open PR took 001 since prepare (main moving instead is a conflict)
printf '%s\n' '7 false other' >"$SHIP_CASE/prs"
printf '%s\n' 'specs/001-other/spec.md' >"$SHIP_CASE/files-7"
ship publish
want_rc 0
golden ship-renumber
sd="$top/specs/002-x"
[ -d "$sd" ] && [ ! -e "$top/specs/001-x" ] || fail "not renumbered"
[ -f "$sd/reports/8-ship.md" ] || fail "the report is not under the new dir"
for h in $(git -C "$org" rev-list refs/heads/main..refs/heads/feat-x); do
  files_of "$h"
  [[ "$FO" != *specs/001-x* ]] || fail "a pushed commit holds specs/001-x: $FO"
done
git -C "$top" show refs/heads/feat-x:specs/002-x/spec.md | grep -q 'specs/002-x/plan.md' || fail "spec.md not rewritten"
grep -q 'specs/001-x' "$top/docs/notes.md" || fail "docs/notes.md was changed"
[[ "$raw" == *'Left uncommitted: '*docs/notes.md* ]] || fail "docs/notes.md not on Left uncommitted"
# shellcheck disable=SC2016 # backticks of the Markdown line, not a command
grep -qF -- '- `docs/notes.md` still names `specs/001-x`' "$SHIP_CASE/pr-body" || fail "not in the points to look at"
ok

# --- US2: fix mode ----------------------------------------------------------------------

# fix_case <name> <Issue: value> <3 Test verdict line> [<Log line>...]: a case
# with a bug dir .specify/bugs/b (bd, its reports/ brd) holding a /fix state
# file, the assessment and fix.md
fix_case() {
  new_case "$1"
  local issue="$2"
  shift 2
  bd="$top/.specify/bugs/b"
  brd="$bd/reports"
  mkdir -p "$brd"
  printf '*\n' >"$brd/.gitignore"
  printf '%s\n' '# /fix state: Test bug' '' "- Branch: feat-x Worktree: $top" '- Size: small' \
    '- Agents: none' '- Current phase: done (shipping)' '- Conventions: none' \
    '- Allowed Spec Kit hooks: none' '- Map: none' "- Issue: $issue" '' '## Report' '' '#10' '' '## Log' '' \
    '- [x] 0 Setup — slug b' '- [x] 1 Assess — hard gate: valid' '- [x] 2 Fix — applied' \
    "$@" >"$bd/feat-state.md"
  printf '# Assessment\n' >"$bd/assessment.md"
  printf '# Fix\n\n- **Slug**: b\n' >"$bd/fix.md"
}

# fix_notes: one fix commit
fix_notes() {
  printf '%s\n' 'Commit: fix(a): echo b' '- .specify/bugs/b' '- src/a.sh' '- src/new.sh' 'Body:' 'Echoes b.' \
    'Docs: none' 'Summary:' '### Symptom' 'a echoed nothing.' '### Fix' 'Echo b.' \
    'Points to look at: none' 'Not verified: none' >"$brd/ship-notes.md"
}

# fix_flags: F = the standard flags of a fix-mode call, --security-bug left out
fix_flags() {
  F=(--worktree "$top" --default main --state "$bd/feat-state.md" --notes "$brd/ship-notes.md"
    --state-script "$src/state.sh" --secret-scan "$src/secret-scan.sh" --report "$brd/5-ship.md")
}

# fix <prepare|publish> [<extra flag>...]: a fix-mode call; stderr must stay empty
fix() {
  local cmd="$1"
  shift
  fix_flags
  run "$cmd" fix "${F[@]}" "$@"
  [ ! -s "$work/stderr" ] || fail "stderr not empty"
}

fix_case "fix: prepare then publish" '#10' '- [x] 3 Test — verified: all checks pass'
fix_notes
printf '%s\n' '- T001 → live run → no credentials' >"$brd/ship-not-verified.md"
fix prepare --security-bug no
want_rc 0
[ -d "$bd" ] && [ ! -e "$top/.specify/bugs/001-b" ] || fail "the bug dir was numbered"
[ -d "$top/specs/x" ] && [ ! -e "$top/specs/001-x" ] || fail "specs/x was numbered"
[ -f "$brd/ship-handoff.md" ] || fail "no handoff"
grep -qx 'Number: none' "$brd/ship-handoff.md" || fail "the handoff has a number"
subjects
[ "$S" = 'fix(a): echo b' ] || fail "subjects: $S"
files_of HEAD
[ "$FO" = $'.specify/bugs/b/assessment.md\n.specify/bugs/b/feat-state.md\n.specify/bugs/b/fix.md\nsrc/a.sh\nsrc/new.sh' ] ||
  fail "commit files: $FO"
index_empty
no_push
[ ! -e "$SHIP_CASE/calls" ] || fail "gh was called in prepare"
fix publish --security-bug no --not-verified-file "$brd/ship-not-verified.md"
want_rc 0
golden fix-pr
[ "$(git -C "$org" rev-parse refs/heads/feat-x)" = "$(git -C "$top" rev-parse HEAD)" ] || fail "feat-x not pushed"
grep -q '^pr create --base main --head feat-x --title fix(a): echo b --body-file ' "$SHIP_CASE/calls" || fail "pr create"
! grep -q '^pr list' "$SHIP_CASE/calls" || fail "the spec number was checked"
body="$(cat "$SHIP_CASE/pr-body")"
want_body='### Symptom
a echoed nothing.
### Fix
Echo b.

**Shipped verdict:** verified

### Code review

Code review was skipped.

### Not verified

- T001 → live run → no credentials

State file: [.specify/bugs/b/feat-state.md](https://github.com/o/r/blob/feat-x/.specify/bugs/b/feat-state.md)

Fixes #10'
[ "$body" = "$want_body" ] || { out="$body"; fail "PR body differs"; }
! grep -qi 'closes' "$SHIP_CASE/pr-body" || fail "a Closes line"
[ "$(cat "$brd/5-ship.md")" = "$raw" ] || fail "report file differs from stdout"
ok

fix_case "fix: shipped on the user's decision" 'none' '- [x] 3 Test — partial: a live run' \
  '- [x] ship with partial (user: "go on")'
fix_notes
fix prepare --security-bug no
want_rc 0
fix publish --security-bug no
want_rc 0
grep -qxF "**Shipped verdict:** partial — ship with partial (user: \"go on\"), shipped on the user's decision (logged)" \
  "$SHIP_CASE/pr-body" || { out="$(cat "$SHIP_CASE/pr-body")"; fail "no shipped verdict line"; }
! grep -qiE '^(fixes|closes) ' "$SHIP_CASE/pr-body" || fail "a closing line with Issue: none"
grep -qx 'Not verified: none' <<<"$raw" || fail "Not verified: not none"
ok

fix_case "fix: --security-bug yes with a secret staged is blocked before any commit" '#10' \
  '- [x] 3 Test — verified: all checks pass'
fix_notes
printf '%s = %s\n' "$tok" "$long" >>"$top/src/new.sh"
fix prepare --security-bug yes
blocked '! secret scan: src/new.sh:2 matches key-literal'
[[ "$raw" != *"$long"* ]] || fail "the value reached the report"
no_commit
index_empty
no_push
[ ! -e "$brd/ship-handoff.md" ] || fail "a handoff was written"
[ "$(cat "$brd/5-ship.md")" = "$raw" ] || fail "report file differs from stdout"
ok

fix_case "fix: --security-bug is required, yes or no" '#10' '- [x] 3 Test — verified: all checks pass'
fix_notes
fix_flags
run prepare fix "${F[@]}"
usage_err '--security-bug is required in fix mode'
run prepare fix "${F[@]}" --security-bug maybe
usage_err '--security-bug: yes or no'
run publish fix "${F[@]}" --security-bug no --spec-number "$src/spec-number.sh"
usage_err '--spec-number is refused in fix mode'
no_commit
ok

# --- US4: stops ------------------------------------------------------------------------

# on_main <path> <content>: a commit on origin's main, from another clone
on_main() {
  [ -d "$c/other" ] || git clone -q "$org" "$c/other" 2>/dev/null
  mkdir -p "$(dirname "$c/other/$1")"
  printf '%s' "$2" >"$c/other/$1"
  git -C "$c/other" add -A
  git -C "$c/other" commit -q -m "main: $1"
  git -C "$c/other" push -q origin HEAD:main 2>/dev/null
}

# undone: prepare put the tree back: no commit, empty index, the spec dir
# unnumbered with its files byte for byte, no handoff, nothing pushed
undone() {
  no_commit
  index_empty
  no_push
  [ -d "$top/specs/x" ] && [ ! -e "$top/specs/001-x" ] || fail "the spec dir is still numbered"
  cmp -s "$tmpl/repo/specs/x/spec.md" "$top/specs/x/spec.md" || fail "spec.md not put back"
  cmp -s "$tmpl/repo/.specify/feature.json" "$top/.specify/feature.json" || fail "feature.json not put back"
  [ ! -e "$top/specs/x/reports/ship-handoff.md" ] || fail "a handoff was written"
  [ "$(cat "$top/specs/x/reports/8-ship.md")" = "$raw" ] || fail "report file differs from stdout"
}

# head_recorded: the handoff's Head: is HEAD
head_recorded() {
  grep -qx "Head: $(git -C "$top" rev-parse HEAD)" "$top/specs/001-x/reports/ship-handoff.md" ||
    fail "the handoff's Head: is not HEAD"
}

# hook <name> <script line>: a hook in the case's origin
hook() {
  printf '#!/bin/sh\n%s\n' "$2" >"$org/hooks/$1"
  chmod +x "$org/hooks/$1"
}

new_case "stop: spec-number error in prepare"
std_notes
: >"$SHIP_CASE/fail-list"
ship prepare
blocked '! spec-number: error: gh pr list failed'
undone
ok

new_case "stop: secret scan match in prepare, after numbering"
std_notes
printf '%s = %s\n' "$tok" "$long" >>"$top/src/new.sh"
printf 'extra\n' >"$top/docs/extra.md"
ship prepare
blocked '! secret scan: src/new.sh:2 matches key-literal'
golden ship-blocked
undone
[[ "$raw" != *"$long"* ]] || fail "the value reached the report"
[[ "$raw" == *'Left uncommitted: '*docs/extra.md* ]] || fail "the unclaimed file is not on Left uncommitted"
git -C "$top" status --porcelain | grep -q 'reports' && fail "reports/ shows in git status"
ok

new_case "stop: a block after numbering puts the PR's own files back"
printf 'See specs/x/plan.md.\n' >>"$top/README.md"
command cp -f -p "$top/README.md" "$c/readme.bk"
printf 'Contract: specs/x/contracts/a.md\n' >"$top/docs/guide.md"
std_notes 'Commit: docs: guide' '- README.md' '- docs/guide.md'
printf '%s = %s\n' "$tok" "$long" >>"$top/src/new.sh"
ship prepare
blocked '! secret scan: src/new.sh:2 matches key-literal'
undone
cmp -s "$c/readme.bk" "$top/README.md" || fail "README.md not put back"
grep -qx 'Contract: specs/x/contracts/a.md' "$top/docs/guide.md" || fail "docs/guide.md not put back"
ok

new_case "stop: secret scan cannot be sourced"
std_notes
flags
run prepare ship "${F[@]:0:11}" "$c/none.sh" "${F[@]:12}"
blocked "! secret scan: could not run (cannot source $c/none.sh)"
undone
ok

new_case "stop: secret scan cannot run, after numbering"
std_notes
# shellcheck disable=SC2016 # the wrapper's own code, expanded when it runs
printf '%s\n' "source '$src/secret-scan.sh'" \
  'if [ "${BASH_SOURCE[0]}" = "$0" ]; then echo "scan broke" >&2; echo more >&2; exit 3; fi' >"$c/scan.sh"
flags
run prepare ship "${F[@]:0:11}" "$c/scan.sh" "${F[@]:12}"
blocked '! secret scan: could not run (scan broke)'
undone
ok

new_case "stop: a secret in the PR body"
notes 'Commit: docs(specs): specify x' '- specs/x' 'Commit: feat(x): add new' '- src/a.sh' '- src/new.sh' \
  'Docs: none' 'Summary:' "uses ${gh_pre}${long}" 'Points to look at: none' 'Not verified: none'
ship prepare
want_rc 0
ship publish
blocked '! secret scan: PR body matches github-token'
[[ "$raw" != *"$long"* ]] || fail "the value reached the report"
no_push
! grep -q '^pr create' "$SHIP_CASE/calls" || fail "gh pr create was called"
subjects
[ "$S" = $'docs(specs): specify x\nfeat(x): add new' ] || fail "subjects: $S"
head_recorded
ok

new_case "stop: a WIP commit"
printf 'wip\n' >>"$top/README.md"
git -C "$top" commit -q -am 'logistics-wip: feat-x'
std_notes
ship prepare
want_rc 0
ship publish
blocked '! WIP commit on feat-x; nothing pushed'
no_push
ok

new_case "stop: a refused push, then publish again"
std_notes
ship prepare
want_rc 0
hook pre-receive 'exit 1'
ship publish
blocked '! git push: ! [remote rejected] feat-x -> feat-x (pre-receive hook declined)'
no_push
! grep -q '^pr create' "$SHIP_CASE/calls" || fail "gh pr create was called"
head_recorded
command rm -f "$org/hooks/pre-receive"
ship publish
want_rc 0
[ "$(git -C "$org" rev-parse refs/heads/feat-x)" = "$(git -C "$top" rev-parse HEAD)" ] || fail "feat-x not pushed"
ok

new_case "stop: a conflict in ship mode"
std_notes
on_main src/a.sh $'echo a\necho main\n'
ship prepare
want_rc 1
golden ship-conflict
[ "$(printf '%s\n' "$raw" | head -n 1)" = 'PR: conflict' ] || fail "not PR: conflict"
[ ! -e "$top/.git/rebase-merge" ] && [ ! -e "$top/.git/rebase-apply" ] || fail "the rebase was not aborted"
subjects
[ "$S" = $'docs(specs): specify x\nfeat(x): add new' ] || fail "subjects: $S"
! git -C "$top" diff --name-only --diff-filter=U | grep -q . || fail "unmerged files left"
[ ! -e "$top/specs/001-x/reports/ship-handoff.md" ] || fail "a handoff was written"
no_push
ok

new_case "stop: an autostash that does not apply"
std_notes
on_main README.md $'readme\nmain\n'
printf 'local\n' >>"$top/README.md"
ship prepare
want_rc 1
[ "$(printf '%s\n' "$raw" | head -n 1)" = 'PR: conflict' ] || fail "not PR: conflict"
[[ "$raw" == *$'Conflicts:\n- README.md\n'* ]] || fail "README.md not on Conflicts:"
[ -n "$(git -C "$top" stash list)" ] || fail "the stash was dropped"
[ ! -e "$top/specs/001-x/reports/ship-handoff.md" ] || fail "a handoff was written"
no_push
ok

new_case "stop: gh pr create fails after the push, publish again opens the PR"
std_notes
ship prepare
want_rc 0
hook pre-receive "cat >>'$c/pushes'"
: >"$SHIP_CASE/fail-create"
ship publish
blocked '! gh pr create: HTTP 502'
[ "$(git -C "$org" rev-parse refs/heads/feat-x)" = "$(git -C "$top" rev-parse HEAD)" ] || fail "feat-x not pushed"
command rm -f "$SHIP_CASE/fail-create"
ship publish
want_rc 0
[ "$(printf '%s\n' "$raw" | head -n 1)" = 'PR: https://github.com/o/r/pull/42' ] || fail "no PR line"
[ "$(wc -l <"$c/pushes" | tr -d ' ')" = 1 ] || fail "pushed twice"
[ "$(grep -c '^pr create' "$SHIP_CASE/calls")" = 2 ] || fail "gh pr create not called again"
ok

new_case "stop: publish run again after a block starts from the recorded HEAD"
std_notes
ship prepare
want_rc 0
printf 'echo fix\n' >>"$top/src/a.sh"
: >"$SHIP_CASE/fail-repo"
ship publish
blocked '! gh repo view: HTTP 502'
head_recorded
index_empty
no_push
command rm -f "$SHIP_CASE/fail-repo"
ship publish
want_rc 0
git -C "$org" show refs/heads/feat-x:src/a.sh | grep -q 'echo fix' || fail "the fix was not pushed"
subjects
[ "$S" = $'docs(specs): specify x\nfeat(x): add new' ] || fail "subjects: $S"
ok

new_case "stop: a fold fixup, a spec-number error, then publish again squashes it"
std_notes
ship prepare
want_rc 0
printf 'echo fix\n' >>"$top/src/a.sh"
: >"$SHIP_CASE/fail-list"
ship publish
blocked '! spec-number: error: gh pr list failed'
head_recorded
no_push
command rm -f "$SHIP_CASE/fail-list"
ship publish
want_rc 0
subjects
[ "$S" = $'docs(specs): specify x\nfeat(x): add new' ] || fail "subjects: $S"
! git -C "$org" log --format=%s refs/heads/main..refs/heads/feat-x | grep -q '^fixup! ' || fail "a fixup! commit was pushed"
git -C "$org" show refs/heads/feat-x:src/a.sh | grep -q 'echo fix' || fail "the fix was not pushed"
ok

new_case "stop: a gh failure after a renumber, then publish again with the earlier number's paths"
std_notes
ship prepare
want_rc 0
printf '%s\n' '7 false other' >"$SHIP_CASE/prs"
printf '%s\n' 'specs/001-other/spec.md' >"$SHIP_CASE/files-7"
: >"$SHIP_CASE/fail-repo"
sd="$top/specs/001-x"
rd="$sd/reports"
ship publish
blocked '! gh repo view: HTTP 502'
[ -d "$top/specs/002-x" ] && [ ! -e "$sd" ] || fail "not renumbered"
no_push
command rm -f "$SHIP_CASE/fail-repo"
ship publish
want_rc 0
[ "$(git -C "$org" rev-parse refs/heads/feat-x)" = "$(git -C "$top" rev-parse HEAD)" ] || fail "feat-x not pushed"
[ -f "$top/specs/002-x/reports/8-ship.md" ] || fail "the report is not under the new dir"
! git -C "$org" log --format=%s refs/heads/main..refs/heads/feat-x | grep -q '^fixup! ' || fail "a fixup! commit was pushed"
ok

# pushed_to_own_name: origin's main is as before ($main_before), feat-x is HEAD
pushed_to_own_name() {
  [ "$(git -C "$org" rev-parse refs/heads/main)" = "$main_before" ] || fail "origin's main was updated"
  [ "$(git -C "$org" rev-parse refs/heads/feat-x)" = "$(git -C "$top" rev-parse HEAD)" ] || fail "feat-x not pushed"
}

new_case "ship: push.default=upstream, the branch tracking origin/main"
git -C "$top" config push.default upstream
git -C "$top" branch -q --set-upstream-to=origin/main
main_before="$(git -C "$org" rev-parse refs/heads/main)"
std_notes
ship prepare
want_rc 0
ship publish
want_rc 0
pushed_to_own_name
ok

new_case "ship: a remote.origin.push mapping onto main"
git -C "$top" config remote.origin.push refs/heads/feat-x:refs/heads/main
main_before="$(git -C "$org" rev-parse refs/heads/main)"
std_notes
ship prepare
want_rc 0
ship publish
want_rc 0
pushed_to_own_name
ok

new_case "stop: a handoff written for another mode"
std_notes
ship prepare
want_rc 0
sed 's/^Mode: ship$/Mode: fix/' "$top/specs/001-x/reports/ship-handoff.md" >"$c/h.tmp"
command mv -f "$c/h.tmp" "$top/specs/001-x/reports/ship-handoff.md"
ship publish
blocked '! ship: handoff unreadable; run prepare again'
no_push
ok

new_case "stop: HEAD moved since prepare"
std_notes
ship prepare
want_rc 0
printf 'more\n' >>"$top/README.md"
git -C "$top" commit -q -am 'docs: more'
ship publish
blocked '! ship: HEAD moved since prepare; nothing pushed'
no_push
ok

# moved_main: PR: conflict, Conflicts: none, exit 1
moved_main() {
  want_rc 1
  [ "$(printf '%s\n' "$raw" | head -n 1)" = 'PR: conflict' ] || fail "not PR: conflict"
  grep -qx 'Conflicts: none' <<<"$raw" || fail "Conflicts: not none"
}

new_case "stop: main moved since prepare (ship)"
std_notes
ship prepare
want_rc 0
head="$(git -C "$top" rev-parse HEAD)"
on_main docs/other.md $'other\n'
ship publish
moved_main
golden ship-moved
[ "$(git -C "$top" rev-parse HEAD)" = "$head" ] || fail "HEAD changed"
[ "$(git -C "$top" rev-parse refs/remotes/origin/main)" = "$(git -C "$org" rev-parse refs/heads/main)" ] ||
  fail "origin/main not fetched"
no_push
index_empty
! grep -q '^pr create' "$SHIP_CASE/calls" || fail "gh pr create was called"
[ "$(cat "$top/specs/001-x/reports/8-ship.md")" = "$raw" ] || fail "report file differs from stdout"
ok

fix_case "stop: main moved since prepare (fix)" '#10' '- [x] 3 Test — verified: all checks pass'
fix_notes
fix prepare --security-bug no
want_rc 0
head="$(git -C "$top" rev-parse HEAD)"
on_main docs/other.md $'other\n'
fix publish --security-bug no
moved_main
[ "$(git -C "$top" rev-parse HEAD)" = "$head" ] || fail "HEAD changed"
no_push
[ ! -e "$SHIP_CASE/calls" ] || fail "gh was called"
[ "$(cat "$brd/5-ship.md")" = "$raw" ] || fail "report file differs from stdout"
ok

new_case "stop: main moved after the push, publish again still opens the PR"
std_notes
ship prepare
want_rc 0
: >"$SHIP_CASE/fail-create"
ship publish
blocked '! gh pr create: HTTP 502'
command rm -f "$SHIP_CASE/fail-create"
on_main docs/other.md $'other\n'
ship publish
want_rc 0
[ "$(printf '%s\n' "$raw" | head -n 1)" = 'PR: https://github.com/o/r/pull/42' ] || fail "no PR line"
ok

# --- US3: rebase mode --------------------------------------------------------------------

# shipped_case <name>: a case whose feat-x was shipped (both ship-mode calls),
# then left as a move leaves it: Current phase changed and a Log line added,
# uncommitted. lease = the pushed head; the PR's body in the stub's pr-view
# (head, URL, then the body); gh's call log cleared.
shipped_case() {
  new_case "$1"
  std_notes
  ship prepare
  want_rc 0
  ship publish
  want_rc 0
  sd="$top/specs/001-x"
  rd="$sd/reports"
  lease="$(git -C "$top" rev-parse HEAD)"
  command rm -f "$SHIP_CASE/calls" "$SHIP_CASE/pr-body"
  sed 's/^- Current phase: .*/- Current phase: rebase (moving)/' "$sd/feat-state.md" >"$c/state.tmp"
  printf '%s\n' '- [x] rebase — moved onto main' >>"$c/state.tmp"
  command mv -f "$c/state.tmp" "$sd/feat-state.md"
  printf '%s\n' 'feat-x' 'https://github.com/o/r/pull/42' '## Why' 'Because.' '' '### Rebases' '' \
    '- onto aaaaaaa' '' '### Not verified' '' 'none' >"$SHIP_CASE/pr-view"
  note='- moved onto main'
}

# rebase_notes [<line>...]: those lines, then the model's not verified item
rebase_notes() { notes "$@" 'Not verified:' '- n/a → mise run lint → killed after 10 min'; }

# rflags: F = the standard flags of a rebase-mode call (the PR note is $note)
rflags() {
  F=(--worktree "$top" --default main --state "$sd/feat-state.md" --notes "$rd/ship-notes.md"
    --state-script "$src/state.sh" --secret-scan "$src/secret-scan.sh"
    --spec-number "$src/spec-number.sh" --report "$rd/r-ship.md"
    --branch feat-x --pr https://github.com/o/r/pull/42 --lease "$lease" --pr-note "$note")
}

# reb <prepare|publish> [<extra flag>...]: a rebase-mode call; stderr must stay empty
reb() {
  local cmd="$1"
  shift
  rflags
  run "$cmd" rebase "${F[@]}" "$@"
  [ ! -s "$work/stderr" ] || fail "stderr not empty"
}

# at_lease: origin's feat-x is still the lease, and gh edited no PR
at_lease() {
  [ "$(git -C "$org" rev-parse refs/heads/feat-x)" = "$lease" ] || fail "feat-x was pushed"
  ! grep -q '^pr edit' "$SHIP_CASE/calls" 2>/dev/null || fail "gh pr edit was called"
}

# on_main_n <k>: k commits on origin's main, pushed at once
on_main_n() {
  local i
  git clone -q "$org" "$c/other" 2>/dev/null
  for ((i = 1; i <= $1; i++)); do
    printf '%s\n' "$i" >"$c/other/docs/n.md"
    git -C "$c/other" add -A
    git -C "$c/other" commit -q -m "main: n $i"
  done
  git -C "$c/other" push -q origin HEAD:main 2>/dev/null
}

shipped_case "rebase: prepare then publish"
on_main docs/other.md $'other\n'
printf 'echo fix\n' >>"$top/src/new.sh"
rebase_notes 'Commit: fix(x): adapt to main'
reb prepare --check-fix src/new.sh
want_rc 0
main7="$(git -C "$top" rev-parse --short=7 refs/remotes/origin/main)"
subjects
[ "$S" = $'docs(specs): specify x\nfeat(x): add new\nfix(x): adapt to main\ndocs(specs): log rebase onto '"$main7" ] ||
  fail "subjects: $S"
files_of HEAD~1
[ "$FO" = src/new.sh ] || fail "check-fix commit files: $FO"
files_of HEAD
[ "$FO" = specs/001-x/feat-state.md ] || fail "Log commit files: $FO"
git -C "$top" show HEAD:specs/001-x/feat-state.md | grep -qx -- '- Current phase: done (shipping)' ||
  fail "Current phase not restored"
git -C "$top" show HEAD:specs/001-x/feat-state.md | grep -qx -- '- \[x\] rebase — moved onto main' ||
  fail "the Log line is not committed"
[ "$(git -C "$top" merge-base HEAD refs/remotes/origin/main)" = "$(git -C "$top" rev-parse refs/remotes/origin/main)" ] ||
  fail "not rebased onto origin/main"
[[ "$out" == 'Prepared: rebase'* ]] || fail "not Prepared: rebase"
[[ "$out" == *$'\nBrought in:\n- @H'*$'@ main: docs/other.md\nLeft uncommitted: '* ]] || fail "Brought in:"
grep -qx "Lease: $lease" "$rd/ship-handoff.md" || fail "no Lease: in the handoff"
grep -qx 'Mode: rebase' "$rd/ship-handoff.md" || fail "no Mode: rebase in the handoff"
index_empty
at_lease
[ ! -e "$SHIP_CASE/calls" ] || fail "gh was called in prepare"
# a check that fails after prepare: nothing fixed, nothing committed
printf 'local\n' >>"$top/README.md"
head="$(git -C "$top" rev-parse HEAD)"
reb publish --check-fix src/new.sh
want_rc 0
golden rebase-pr
[ "$(git -C "$top" rev-parse HEAD)" = "$head" ] || fail "publish committed"
[ "$(git -C "$org" rev-parse refs/heads/feat-x)" = "$head" ] || fail "feat-x not pushed"
grep -q '^pr view https://github.com/o/r/pull/42 --json headRefName,url,body ' "$SHIP_CASE/calls" || fail "pr view"
grep -q '^pr edit https://github.com/o/r/pull/42 --body-file ' "$SHIP_CASE/calls" || fail "pr edit"
! grep -q '^pr create' "$SHIP_CASE/calls" || fail "gh pr create was called"
want_body='## Why
Because.

### Rebases

- onto aaaaaaa
- moved onto main

### Not verified

none'
[ "$(cat "$SHIP_CASE/pr-edit-body")" = "$want_body" ] || { out="$(cat "$SHIP_CASE/pr-edit-body")"; fail "PR body differs"; }
[[ "$raw" == *'Left uncommitted: '*README.md* ]] || fail "README.md not on Left uncommitted"
[ "$(cat "$rd/r-ship.md")" = "$raw" ] || fail "report file differs from stdout"
ok

shipped_case "rebase: Brought in: at most 20, a body with no ### Rebases"
on_main_n 22
rebase_notes
printf '%s\n' 'feat-x' 'https://github.com/o/r/pull/42' '## Why' 'Because.' >"$SHIP_CASE/pr-view"
reb prepare
want_rc 0
bi="$(printf '%s\n' "$out" | sed -n '/^Brought in:$/,/^Left uncommitted:/p')"
[ "$(printf '%s\n' "$bi" | grep -c '^- @H')" = 20 ] || fail "not 20 Brought in: lines"
printf '%s\n' "$bi" | grep -qx -- '- … and 2 more' || fail "no '… and 2 more' line"
printf '%s\n' "$bi" | grep -q ' main: n 1$' || fail "not oldest first"
subjects
[ "$S" = $'docs(specs): specify x\nfeat(x): add new\ndocs(specs): log rebase onto '"$(git -C "$top" rev-parse --short=7 refs/remotes/origin/main)" ] ||
  fail "subjects: $S"
reb publish
want_rc 0
[ "$(cat "$SHIP_CASE/pr-edit-body")" = $'## Why\nBecause.\n\n### Rebases\n\n- moved onto main' ] ||
  { out="$(cat "$SHIP_CASE/pr-edit-body")"; fail "PR body differs"; }
ok

shipped_case "rebase: a refused push resets to the lease"
on_main docs/other.md $'other\n'
rebase_notes
reb prepare
want_rc 0
git clone -q "$org" "$c/gone" 2>/dev/null
git -C "$c/gone" checkout -q feat-x
printf 'gone\n' >>"$c/gone/README.md"
git -C "$c/gone" commit -q -am 'docs: pushed meanwhile'
git -C "$c/gone" push -q origin feat-x 2>/dev/null
moved="$(git -C "$org" rev-parse refs/heads/feat-x)"
reb publish
blocked "! push refused: feat-x moved on GitHub since ${lease:0:7}; nothing overwritten"
[ "$(git -C "$top" rev-parse HEAD)" = "$lease" ] || fail "not reset to the lease"
[ "$(git -C "$org" rev-parse refs/heads/feat-x)" = "$moved" ] || fail "feat-x was overwritten"
! grep -q '^pr edit' "$SHIP_CASE/calls" || fail "gh pr edit was called"
ok

shipped_case "rebase: a conflict resets to the lease"
on_main src/a.sh $'echo a\necho main\n'
rebase_notes
reb prepare
want_rc 1
golden rebase-conflict
[ "$(printf '%s\n' "$raw" | head -n 1)" = 'PR: conflict' ] || fail "not PR: conflict"
[ ! -e "$top/.git/rebase-merge" ] && [ ! -e "$top/.git/rebase-apply" ] || fail "the rebase was not aborted"
[ "$(git -C "$top" rev-parse HEAD)" = "$lease" ] || fail "not reset to the lease"
! grep -qx 'Mode: rebase' "$rd/ship-handoff.md" || fail "a rebase handoff was written"
at_lease
ok

shipped_case "rebase: main moved since prepare resets to the lease"
on_main docs/other.md $'other\n'
rebase_notes
reb prepare
want_rc 0
on_main docs/more.md $'more\n'
reb publish
moved_main
[ "$(git -C "$top" rev-parse HEAD)" = "$lease" ] || fail "not reset to the lease"
at_lease
! grep -q '^pr view' "$SHIP_CASE/calls" 2>/dev/null || fail "gh pr view was called"
[ "$(cat "$rd/r-ship.md")" = "$raw" ] || fail "report file differs from stdout"
ok

shipped_case "rebase: --pr of another branch, then of another repo"
rebase_notes
reb prepare
want_rc 0
printf '%s\n' 'other' 'https://github.com/o/r/pull/42' 'body' >"$SHIP_CASE/pr-view"
reb publish
blocked '! gh pr view: PR head is not feat-x'
at_lease
printf '%s\n' 'feat-x' 'https://github.com/evil/r/pull/42' 'body' >"$SHIP_CASE/pr-view"
reb publish
blocked '! gh pr view: PR is not in https://github.com/o/r'
at_lease
ok

shipped_case "rebase: a secret in the edited body"
rebase_notes
reb prepare
want_rc 0
note="- moved, ${gh_pre}${long}"
reb publish
blocked '! secret scan: PR body matches github-token'
[[ "$raw" != *"$long"* ]] || fail "the value reached the report"
at_lease
ok

# --- US5: the fallback line ------------------------------------------------------------

# sq <value>: the value in POSIX single quotes, each ' written '\''
sq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

# fallback <mode> <flag> <value>...: L = the agent's fallback line for the ship
# script $fb_sh (research R14): only cd, bash, &&, the subcommands, the mode
# and the flag names bare, every value single-quoted. A value holding a
# newline or CR: exit 1, L empty.
fallback() {
  local mode="$1" a args="" kind
  shift
  L=""
  for a in "$top" "$fb_sh" "$@"; do
    case "$a" in *$'\n'* | *$'\r'*) return 1 ;; esac
  done
  while [ "$#" -gt 0 ]; do
    args+=" $1 $(sq "$2")"
    shift 2
  done
  L="! cd $(sq "$top")"
  for kind in prepare publish; do
    L+=" && bash $(sq "$fb_sh") $kind $mode$args"
  done
}

new_case "fallback-quoting"
# the ship script at a path holding a ' and a space, so the quoting is put to
# work (state.sh refuses a quote in the run's own paths)
fb_sh="$c/it's bin/ship.sh"
mkdir -p "$c/it's bin"
command cp -f "$ship_sh" "$fb_sh"
std_notes
item="- T001 → it's \$(touch '$c/pwned') and \`touch $c/pwned\` → no credentials"
printf '%s\n' "$item" >"$rd/ship-not-verified.md"
flags
fallback ship "${F[@]}" --not-verified-file "$rd/ship-not-verified.md" ||
  fail "no line built"
[[ "$L" == "! cd '$top' && bash '$c/it'\\''s bin/ship.sh' prepare ship --worktree '$top' "* ]] ||
  fail "line: $L"
[[ "$L" != *pwned* && "$L" != *T001* ]] || fail "an item is in the line"
rc=0
raw="$(bash -c "${L#! }" 2>"$work/stderr")" || rc=$?
want_rc 0
[ ! -s "$work/stderr" ] || fail "stderr not empty"
[ ! -e "$c/pwned" ] || fail "an item was evaluated"
grep -qxF -- "$item" "$SHIP_CASE/pr-body" || { out="$(cat "$SHIP_CASE/pr-body")"; fail "the item is not verbatim in the PR body"; }
[[ "$raw" == 'Prepared: ship'*$'\nPR: https://github.com/o/r/pull/42\n'* ]] || fail "not prepare's then publish's output"
[ "$(cat "$top/specs/001-x/reports/8-ship.md")" = "$(printf '%s\n' "$raw" | sed -n '/^PR: /,$p')" ] ||
  fail "report file differs from publish's output"
if fallback ship --worktree "$top" --notes "$rd/a"$'\n'"b.md"; then fail "a line built for a path with a newline"; fi
[ -z "$L" ] || fail "L not empty"
if fallback fix --report "$rd/a"$'\r'"b.md"; then fail "a line built for a path with a CR"; fi
ok

printf 'ship tests: %s cases in %ss\n' "$n" "$((SECONDS - started))"
if [ "$updated" = 1 ]; then
  echo "goldens rewritten: review git diff tests/ship/expected (exit 1 on purpose)"
  exit 1
fi
