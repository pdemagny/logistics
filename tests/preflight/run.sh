#!/usr/bin/env bash
# Offline tests for .apm/skills/feat/scripts/preflight.sh (mise run
# test:preflight).
#
# One template is built per run: a bare origin whose main holds two commits
# (the base: .specify/ with the bug extension; then a brief,
# specs/briefs/x.md), and a clone of it on the branch EnterWorktree would
# make. Each case copies both (`cp -R`), points the copy's origin at its own
# bare repo and lays out a scratch install around it:
#   <case>/base/.claude/skills/feat/scripts/  a copy of preflight.sh and a
#                                             stub tracker.sh (its `check`
#                                             line and exit come from the
#                                             case's board-line, board-exit)
#   <case>/base/.claude/agents/               every feat-*.md agent
#   <case>/home/                              HOME
# `second_worktree` adds a worktree of the base commit (no brief) for the
# brief search. The stub tests/preflight/bin/gh is first on PATH and answers
# from the case's dir ($PF_CASE), logging its calls to gh-calls.
#
# Each case checks the exit code, that stderr stays empty, and the output:
# against expected/<case>.out where it names one (the case's dir written
# `@C@`, its top level `@TOP@`), else line by line. `UPDATE=1 bash
# tests/preflight/run.sh` writes the actual outputs over expected/ and exits
# non-zero, so it never passes CI; review the change with
# `git diff tests/preflight/expected`.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(cd "$here/../.." && pwd -P)"
src="$root/.apm/skills/feat/scripts"
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
real_git="$(command -v git)"
export PATH="$here/bin:$PATH"
# The spawn note is off unless a case unsets or empties the variable.
export CLAUDE_CODE_FORK_SUBAGENT=0

FEAT_AGENTS="specifier planner design-reviewer tasker implementer code-reviewer shipper bug-assessor"

# brief <file> [<header line>...]: a brief with that header (default: title,
# size, short name x) and two sections of two lines each
brief() {
  local f="$1"
  shift
  if [ "$#" = 0 ]; then set -- '# Brief: Do x' '- Size: medium — ~10 tasks, one script' '- Short name: x'; fi
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$@" '' '## Why' 'Because.' '' '## Behaviour' '- one' '' '- two' '' \
    '## Acceptance' '- a' '- b' >"$f"
}

# --- the template ------------------------------------------------------------------

tmpl="$work/tmpl"
mkdir -p "$tmpl"
git init -q --bare "$tmpl/origin.git"
git -C "$tmpl/origin.git" symbolic-ref HEAD refs/heads/main
git clone -q "$tmpl/origin.git" "$tmpl/repo" 2>/dev/null
(
  cd "$tmpl/repo"
  git symbolic-ref HEAD refs/heads/main
  mkdir -p .specify/extensions/bug
  printf '%s\n' 'schema_version: "1.0"' 'extension:' '  id: bug' '  version: "1.4.2"' \
    'requires:' '  speckit_version: ">=0.9.0"' >.specify/extensions/bug/extension.yml
  printf 'readme\n' >README.md
  git add -A
  git commit -q -m base
  git tag base
  brief specs/briefs/x.md
  git add -A
  git commit -q -m brief
  git push -q origin main 2>/dev/null
  # what a clone of a non-empty origin has (this one was cloned empty)
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git checkout -q -b worktree-x
)

n=0
# new_case <name>: a fresh copy; c (the case dir), top, org, base, pf (the
# script), PF_CASE (the stubs' dir), HOME
new_case() {
  local a
  current="$1"
  unset out
  n=$((n + 1))
  c="$work/c/$n"
  mkdir -p "$c/case" "$c/home" "$c/base/.claude/skills/feat/scripts" "$c/base/.claude/agents"
  cp -R "$tmpl/origin.git" "$c/origin.git"
  cp -R "$tmpl/repo" "$c/repo"
  top="$(cd "$c/repo" && pwd -P)"
  org="$c/origin.git"
  git -C "$top" remote set-url origin "$org"
  pf="$c/base/.claude/skills/feat/scripts/preflight.sh"
  cp "$src/preflight.sh" "$pf"
  # shellcheck disable=SC2016 # the stub's own text, expanded when it runs
  printf '%s\n' '#!/usr/bin/env bash' 'c="${PF_CASE:?}"' \
    'if [ -e "$c/board-line" ]; then cat "$c/board-line"; else echo "tracker: off"; fi' \
    'exit "$(cat "$c/board-exit" 2>/dev/null || echo 0)"' >"$c/base/.claude/skills/feat/scripts/tracker.sh"
  for a in $FEAT_AGENTS; do printf -- '---\nname: feat-%s\n---\n' "$a" >"$c/base/.claude/agents/feat-$a.md"; done
  export PF_CASE="$c/case" HOME="$c/home"
  pf_path="$PATH"
}

# git_wrap: from now on in this case, preflight's git calls go through a
# wrapper that logs them to $PF_CASE/git-calls; with $PF_CASE/fail-ls-remote
# present, `ls-remote --heads` fails as an unreachable remote does
git_wrap() {
  mkdir -p "$c/gitbin"
  # shellcheck disable=SC2016 # the wrapper's own text, expanded when it runs
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >>"${PF_CASE:?}/git-calls"' \
    'case " $* " in *" ls-remote --heads "*)' \
    '  if [ -e "$PF_CASE/fail-ls-remote" ]; then' \
    '    echo "fatal: unable to access origin: Could not resolve host" >&2; exit 128' \
    '  fi ;;' 'esac' \
    "exec '$real_git' \"\$@\"" >"$c/gitbin/git"
  chmod +x "$c/gitbin/git"
  pf_path="$c/gitbin:$PATH"
}

# no_git_network: no logged git call reached the remote
no_git_network() {
  local l
  [ -e "$PF_CASE/git-calls" ] || return 0
  while IFS= read -r l; do
    case " $l " in
      *' fetch '* | *' ls-remote '* | *' pull '* | *' push '* | *' clone '*) fail "git reached the remote: $l" ;;
    esac
  done <"$PF_CASE/git-calls"
}

# git_called <word>: a logged git call has that subcommand
git_called() {
  [ -e "$PF_CASE/git-calls" ] && grep -q -- " $1 " "$PF_CASE/git-calls"
}

# second_worktree: wt2, a worktree of the base commit (no brief in it)
second_worktree() {
  git -C "$top" worktree add -q --detach "$c/wt2" base 2>/dev/null
  wt2="$(cd "$c/wt2" && pwd -P)"
}

# on_origin <path> <line>...: commit that file with those lines on origin's
# main through a scratch clone, so only preflight's fetch brings it to the
# case's repo
on_origin() {
  local f="$1" d="$c/push"
  shift
  [ -d "$d" ] || git clone -q "$org" "$d" 2>/dev/null
  mkdir -p "$d/$(dirname "$f")"
  printf '%s\n' "$@" >"$d/$f"
  git -C "$d" add -A
  git -C "$d" commit -q -m "$f"
  git -C "$d" push -q origin HEAD:main 2>/dev/null
}

# issue7: the stub gh knows o/r#7
issue7() { printf 'MEMBER\tSave button crashes\n' >"$PF_CASE/issue-o-r-7"; }

# pre <args>...: preflight.sh with exactly these arguments, from the top
# level; rc, raw, out (the case dir written @C@, the top level @TOP@);
# stderr must stay empty
pre() { pre_in "$top" "$@"; }
pre_in() {
  local d="$1"
  shift
  rc=0
  raw="$(cd "$d" && PATH="$pf_path" bash "$pf" "$@" 2>"$work/stderr")" || rc=$?
  out="${raw//"$top"/@TOP@}"
  out="${out//"$c"/@C@}"
  [ ! -s "$work/stderr" ] || fail "stderr not empty"
}

expect_exit() { [ "$rc" = "$1" ] || fail "exit $rc, want $1"; }

# expect_line <line>: the output holds that exact line
expect_line() {
  local l
  while IFS= read -r l; do [ "$l" != "$1" ] || return 0; done <<<"$out"
  fail "no line: $1"
}

# expect_no_key <key>: no line starts `<key>: `
expect_no_key() {
  local l
  while IFS= read -r l; do [[ "$l" != "$1: "* ]] || fail "unexpected line: $l"; done <<<"$out"
}

# expect_last <line>: the last output line
expect_last() {
  local l
  l="$(printf '%s\n' "$out" | tail -n 1)"
  [ "$l" = "$1" ] || fail "last line: $l, want $1"
}

# expect_usage: exit 2, one `preflight: usage: ` line and nothing else
expect_usage() {
  expect_exit 2
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] || fail "not one line"
  [[ "$out" == 'preflight: usage: '* ]] || fail "not a usage line"
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

# case_run <exit> <golden> <args>...: pre, its exit code and its golden
case_run() {
  local want="$1" g="$2"
  shift 2
  pre "$@"
  expect_exit "$want"
  golden "$g"
}

no_gh() { [ ! -s "$PF_CASE/gh-calls" ] || fail "gh was called: $(head -n 1 "$PF_CASE/gh-calls")"; }
gh_calls() { [ -s "$PF_CASE/gh-calls" ] && cat "$PF_CASE/gh-calls"; }

# --- bash 3.2 ------------------------------------------------------------------------

current="bash 3.2 constructs only"
if grep -nE -- 'declare -A|mapfile|readarray|,,\}|\^\^\}|declare -n|local -n|\[\[ -v|\[-[0-9]+\]|;;&|\|&' \
  "$src/preflight.sh"; then
  fail "preflight.sh uses a construct bash 3.2 lacks"
fi
ok

current="nothing read is evaluated: no eval, no source of read text"
if grep -vE '^[[:space:]]*#' "$src/preflight.sh" |
  grep -nE -- '(^[[:space:]]*|[;&|(!{][[:space:]]*|(then|do|else)[[:space:]]+)(eval|source|\.)([[:space:]]|$)'; then
  fail "preflight.sh evaluates or sources text"
fi
ok

# --- usage ---------------------------------------------------------------------------

new_case "usage: no skill, an unknown skill, too many arguments"
pre
expect_usage
pre brief x
expect_usage
pre feat x y z
expect_usage
pre feat x notslug
expect_usage
ok

new_case "usage: slug= is refused by /feat"
pre feat x slug=a-b
expect_usage
pre feat 'button crashes' 'slug=button crashes'
expect_usage
no_gh
ok

new_case "not a git repository (both modes)"
mkdir -p "$c/plain"
pre_in "$c/plain" feat x
expect_exit 2
[ "$out" = 'preflight: error: not a git repository' ] || fail "want the error line"
pre_in "$c/plain" feat worktree x off
expect_exit 2
[ "$out" = 'preflight: error: not a git repository' ] || fail "want the error line"
ok

# --- argument kinds ------------------------------------------------------------------

new_case "empty argument (feat, fix)"
case_run 0 feat-empty feat
pre feat '  '
expect_exit 0
golden feat-empty
case_run 0 fix-empty fix ''
ok

new_case "resume and rebase (feat)"
case_run 0 feat-resume feat resume
case_run 0 feat-rebase feat rebase
case_run 0 feat-rebase-12 feat 'rebase 12'
ok

new_case "resume and rebase (fix)"
case_run 0 fix-resume fix resume
pre fix 'rebase https://github.com/o/r/pull/12'
expect_exit 0
expect_line 'rebase target: https://github.com/o/r/pull/12'
no_gh
ok

new_case "longer arguments starting with resume or rebase: idea (feat)"
pre feat 'resume button crashes'
expect_exit 1
golden feat-idea-resume
pre feat 'rebase breaks on merge commits'
expect_exit 1
expect_line 'kind: idea'
expect_line 'pointer: /brief "rebase breaks on merge commits"'
ok

new_case "longer arguments starting with resume or rebase: symptom (fix)"
case_run 0 fix-symptom-resume fix 'resume button crashes' 'slug=resume button'
pre fix 'rebase breaks on merge commits' 'slug=rebase merge commits'
expect_exit 0
expect_line 'kind: symptom'
expect_line 'author: user'
no_gh
ok

new_case "an issue given to /feat: refused (#N, owner/repo#N, URL, another URL)"
case_run 1 feat-issue feat '#7'
pre feat 'o/r#7'
expect_exit 1
expect_line 'kind: issue'
expect_line 'pointer: /brief o/r#7'
pre feat 'https://github.com/o/r/issues/7'
expect_exit 1
expect_line 'pointer: /brief https://github.com/o/r/issues/7'
pre feat 'https://gitlab.com/g/p/-/issues/3'
expect_exit 1
expect_line 'kind: issue'
expect_no_key install
no_gh
ok

new_case "a brief given to /fix: refused (path, file starting # Brief:)"
case_run 1 fix-brief fix specs/briefs/x.md
brief "$top/docs/elsewhere.md"
pre fix docs/elsewhere.md
expect_exit 1
expect_line 'kind: brief'
expect_line 'pointer: /feat docs/elsewhere.md'
expect_no_key install
ok

new_case "a brief path and a short name (feat)"
case_run 0 feat-brief feat specs/briefs/x.md
pre feat x
expect_exit 0
golden feat-brief
pre feat "$top/specs/briefs/x.md"
expect_exit 0
golden feat-brief
ok

new_case "a GitHub issue (fix): #N, owner/repo#N, URL forms"
printf 'MEMBER\tSave button crashes\n' >"$PF_CASE/issue-o-r-7"
case_run 0 fix-issue fix '#7'
[ "$(gh_calls)" = "$(printf '%s\n' 'repo view --json nameWithOwner --jq .nameWithOwner' \
  'api repos/o/r/issues/7 --jq [.author_association, .title] | @tsv')" ] || fail "gh calls: $(gh_calls)"
for arg in 'o/r#7' 'https://github.com/o/r/issues/7' 'https://github.com/o/r/issues/7/' \
  'https://github.com/o/r/issues/7#issuecomment-1' 'https://github.com/o/r/issues/7?x=1'; do
  pre fix "$arg"
  expect_exit 0
  expect_line 'kind: issue'
  expect_line 'github: yes'
  expect_line 'title: Save button crashes'
  expect_line 'author: MEMBER'
  expect_line 'issue: o/r#7'
done
ok

new_case "another URL (fix): github: no, its last path segment"
case_run 0 fix-other-url fix 'https://gitlab.com/g/p/-/issues/3?tab=x#note'
no_gh
pre fix 'https://github.com.evil/o/r/issues/1'
expect_exit 0
expect_line 'github: no'
expect_line 'author: unknown'
pre fix 'https://github.com/o/r/issues/1/comments'
expect_exit 0
expect_line 'github: no'
pre fix 'https://github.com/o/../issues/1'
expect_exit 0
expect_line 'github: no'
no_gh
ok

new_case "parts that fail the checks: not an issue (../x#1, o/..#1)"
pre fix '../x#1' 'slug=x one'
expect_exit 0
expect_line 'kind: symptom'
pre fix 'o/..#1' 'slug=x one'
expect_exit 0
expect_line 'kind: symptom'
pre fix '#0' 'slug=x zero'
expect_exit 0
expect_line 'kind: symptom'
pre feat '../x#1'
expect_exit 1
expect_line 'kind: idea'
no_gh
ok

new_case "an argument holding ' and \$(touch pwned): printed as data"
hostile="it's \$(touch pwned) and \`touch pwned2\`"
case_run 0 fix-hostile fix "$hostile" "slug=it's \$(touch pwned)"
pre feat "$hostile"
expect_exit 1
expect_line "pointer: /brief \"$hostile\""
[ ! -e "$top/pwned" ] && [ ! -e "$top/pwned2" ] && [ ! -e "$c/pwned" ] || fail "a command ran"
no_gh
ok

new_case "a symptom's title: its first ten words, one line"
pre fix "one two three four five six seven eight nine ten eleven"$'\n'"twelve" 'slug=one two'
expect_exit 0
expect_line 'title: one two three four five six seven eight nine ten'
pre fix 'a * glob' 'slug=a glob'
expect_line 'title: a * glob'
ok

# --- brief ---------------------------------------------------------------------------

new_case "brief fields with line counts, map and issue"
brief "$top/specs/briefs/full.md" '# Brief: Full one' '- Size: large — ~30 tasks, two scripts' \
  '- Short name: full' '- Kind: feat' '- Map: specs/maps/m.md#full' '- Issue: #12'
case_run 0 brief-full feat full
ok

new_case "normal reads as medium, big as large"
brief "$top/specs/briefs/n.md" '# Brief: N' '- Size: normal - older brief' '- Short name: n'
pre feat n
expect_exit 0
expect_line 'size: medium'
expect_line 'size note: older brief'
brief "$top/specs/briefs/b.md" '# Brief: B' '- Size: Big' '- Short name: b'
pre feat b
expect_exit 0
expect_line 'size: large'
expect_line 'size note: none'
ok

new_case "tiny and huge stop with their pointers"
brief "$top/specs/briefs/t.md" '# Brief: T' '- Size: tiny — one line' '- Short name: t'
case_run 1 brief-tiny feat t
brief "$top/specs/briefs/h.md" '# Brief: H' '- Size: huge' '- Short name: h'
pre feat h
expect_exit 1
expect_line "pointer: /brief @TOP@/specs/briefs/h.md"
expect_no_key size
expect_no_key install
ok

new_case "missing fields and an empty Behaviour stop"
printf '%s\n' '# Brief: Bare' '- Size: whatever' '' '## Behaviour' '' '## Acceptance' '- a' \
  >"$top/specs/briefs/bare.md"
case_run 1 brief-lacks feat bare
printf '%s\n' '# Brief: No sections' '- Size: small' '- Short name: ns' >"$top/specs/briefs/ns.md"
pre feat ns
expect_exit 1
expect_last 'stop: brief lacks behaviour, acceptance'
ok

new_case "no brief by that name: every path searched"
second_worktree
case_run 1 brief-none feat nope
ok

new_case "a name in two worktrees: several candidates, nothing else checked"
second_worktree
brief "$wt2/specs/briefs/x.md"
case_run 0 brief-several feat x
expect_no_key install
ok

new_case "brief in checkout: no for a brief in another worktree or elsewhere"
second_worktree
brief "$wt2/specs/briefs/y.md" '# Brief: Y' '- Size: small' '- Short name: y'
pre feat y
expect_exit 0
expect_line "brief: @C@/wt2/specs/briefs/y.md"
expect_line 'brief in checkout: no'
brief "$top/docs/x-copy.md"
pre feat docs/x-copy.md
expect_exit 0
expect_line 'brief: @TOP@/docs/x-copy.md'
expect_line 'brief in checkout: no'
ok

new_case "hostile text in a brief: printed as data"
brief "$top/specs/briefs/evil.md" "# Brief: \$(touch pwned) \`id\`"$'\t'"x"$'\r' '- Size: small'$'\r' \
  '- Short name: evil' "- Issue: #1; rm -rf ~"
case_run 0 brief-hostile feat evil
[ ! -e "$top/pwned" ] || fail "a command ran"
ok

# --- install -------------------------------------------------------------------------

new_case "missing .specify/"
command rm -rf -- "$top/.specify"
case_run 1 install-no-specify feat x
pre fix '#7'
expect_exit 1
expect_last 'stop: .specify/ is missing: run specify init --here --integration claude'
no_gh
ok

new_case "missing agents"
command rm -f -- "$c/base/.claude/agents/feat-shipper.md" "$c/base/.claude/agents/feat-tasker.md"
case_run 1 install-no-agent feat x
pre fix resume
expect_exit 1
expect_last 'stop: agents not installed: feat-shipper (install or update logistics)'
ok

new_case "agents found in every layout (.agent.md beside the skill, the project, HOME)"
command rm -rf -- "$c/base/.claude/agents"
mkdir -p "$c/base/.claude/agents" "$top/.claude/agents" "$HOME/.claude/agents"
printf 'x\n' >"$c/base/.claude/agents/feat-specifier.agent.md"
printf 'x\n' >"$c/base/.claude/agents/feat-planner.agent.md"
printf 'x\n' >"$top/.claude/agents/feat-design-reviewer.md"
printf 'x\n' >"$top/.claude/agents/feat-tasker.md"
for a in implementer code-reviewer shipper; do printf 'x\n' >"$HOME/.claude/agents/feat-$a.md"; done
pre feat x
expect_exit 0
expect_line 'install: ok'
ok

new_case "agents through a symlinked skill dir (the logical path)"
mkdir -p "$c/link/.claude/skills" "$c/link/.claude/agents"
ln -s "$c/base/.claude/skills/feat" "$c/link/.claude/skills/feat"
command rm -rf -- "$c/base/.claude/agents"
for a in $FEAT_AGENTS; do printf 'x\n' >"$c/link/.claude/agents/feat-$a.md"; done
pf="$c/link/.claude/skills/feat/scripts/preflight.sh"
pre feat x
expect_exit 0
expect_line 'install: ok'
ok

new_case "missing bug extension (fix); a speckit-bug skill instead; unknown version"
command rm -rf -- "$top/.specify/extensions"
case_run 1 install-no-bug fix '#7'
no_gh
mkdir -p "$HOME/.claude/skills/speckit-bug-assess"
printf 'MEMBER\tT\n' >"$PF_CASE/issue-o-r-7"
pre fix '#7'
expect_exit 0
expect_line 'install: ok'
expect_line 'bug extension: unknown'
ok

new_case "bug extension: version from the extension: mapping, never speckit_version"
yml="$top/.specify/extensions/bug/extension.yml"
printf '%s\n' 'requires:' '  speckit_version: ">=0.9.0"' '  version: "9.9"' 'extension:' '  id: bug' \
  '  # a comment' '    version: nested' "  version: '2.0.1'  # pinned" 'hooks: {}' >"$yml"
pre fix resume
expect_exit 0
expect_line 'bug extension: 2.0.1'
printf '%s\n' 'extension:' '  id: bug' 'requires:' '  speckit_version: ">=0.9.0"' '  version: 3' >"$yml"
pre fix resume
expect_line 'bug extension: unknown'
# shellcheck disable=SC2016 # a hostile value, never expanded
printf '%s\n' 'extension:' '  version: "1.0 $(x)"' >"$yml"
pre fix resume
expect_line 'bug extension: unknown'
command rm -f -- "$yml"
pre fix resume
expect_exit 0
expect_line 'bug extension: unknown'
ok

# --- issue ---------------------------------------------------------------------------

new_case "issue in another repo: author unknown; same repo in another case: counts"
printf 'OWNER\tElsewhere\n' >"$PF_CASE/issue-other-r-3"
printf 'COLLABORATOR\tHere\n' >"$PF_CASE/issue-O-R-4"
pre fix 'other/r#3'
expect_exit 0
expect_line 'title: Elsewhere'
expect_line 'author: unknown'
expect_line 'issue: other/r#3'
pre fix 'O/R#4'
expect_exit 0
expect_line 'author: COLLABORATOR'
ok

new_case "issue: a title with tabs and newlines (escaped by @tsv), an odd association"
printf 'NONE\tA\\tB\\nC\n' >"$PF_CASE/issue-o-r-5"
printf 'weird value\tT\n' >"$PF_CASE/issue-o-r-6"
pre fix '#5'
expect_line 'title: A\tB\nC'
expect_line 'author: NONE'
pre fix '#6'
expect_line 'author: unknown'
ok

new_case "issue: a gh failure stops"
touch "$PF_CASE/fail-api"
case_run 1 issue-gh-fail fix '#7'
command rm -f -- "$PF_CASE/fail-api"
pre fix '#404'
expect_exit 1
expect_last 'stop: gh failed: gh: Not Found (HTTP 404)'
touch "$PF_CASE/fail-repo"
pre fix 'o/r#7'
expect_exit 1
expect_last 'stop: gh failed: HTTP 502: Bad Gateway'
ok

# --- board and base ------------------------------------------------------------------

new_case "board: off without .logistics.yml, its line when the check passes"
issue7
pre feat x
expect_exit 0
expect_line 'board: off'
printf 'project: x\n' >"$top/.logistics.yml"
printf 'tracker: ok users/u/projects/2 (Todo, In progress, In review)\n' >"$PF_CASE/board-line"
pre fix '#7'
expect_line 'board: tracker: ok users/u/projects/2 (Todo, In progress, In review)'
ok

new_case "board: a failing check stops before the fetch"
printf 'project: x\n' >"$top/.logistics.yml"
printf 'tracker: error: board users/u/projects/9 not found\n' >"$PF_CASE/board-line"
printf '1\n' >"$PF_CASE/board-exit"
git_wrap
case_run 1 board-fail feat x
expect_no_key default
no_git_network
pre fix 'button crashes' 'slug=button crashes'
expect_exit 1
expect_last 'stop: board check failed: tracker: error: board users/u/projects/9 not found'
ok

new_case "base: the fetch brings origin's new commits"
git_wrap
on_origin docs/new.md 'new'
pre feat x
expect_exit 0
expect_line 'default: main'
expect_line 'fetch: ok'
git_called fetch || fail "no fetch"
git -C "$top" cat-file -e refs/remotes/origin/main:docs/new.md 2>/dev/null || fail "origin/main not fetched"
ok

new_case "base: a failing fetch stops (exit 1)"
git -C "$top" remote set-url origin "$c/nonexistent.git"
pre feat x
expect_exit 1
expect_line 'default: main'
expect_no_key fetch
expect_no_key 'hooks allowed'
[[ "$(printf '%s\n' "$out" | tail -n 1)" == 'stop: git fetch origin main failed: '?* ]] || fail "want the fetch stop"
ok

new_case "base: no origin/HEAD, found through ls-remote --symref"
issue7
git -C "$top" symbolic-ref -d refs/remotes/origin/HEAD
git -C "$org" symbolic-ref HEAD refs/heads/trunk
git -C "$org" branch trunk main
pre fix '#7'
expect_exit 0
expect_line 'default: trunk'
expect_line 'fetch: ok'
ok

new_case "base: an unreachable remote and no origin/HEAD (exit 2)"
git -C "$top" symbolic-ref -d refs/remotes/origin/HEAD
git -C "$top" remote set-url origin "$c/nonexistent.git"
pre feat x
expect_exit 2
expect_last 'preflight: error: no default branch found'
pre fix '#7'
expect_exit 2
expect_last 'preflight: error: no default branch found'
ok

new_case "base: a hostile default branch name (exit 2)"
git -C "$top" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/-x
pre feat x
expect_exit 2
expect_last 'preflight: error: no default branch found'
git -C "$top" symbolic-ref -d refs/remotes/origin/HEAD
git -C "$org" symbolic-ref HEAD 'refs/heads/@{-1}' 2>/dev/null ||
  git -C "$org" symbolic-ref HEAD refs/heads/-x
pre feat x
expect_exit 2
expect_last 'preflight: error: no default branch found'
ok

new_case "base: a refused argument, resume and rebase reach no remote"
git_wrap
for arg in '#7' 'an idea' 'https://github.com/o/r/issues/7' resume rebase; do
  pre feat "$arg"
  expect_no_key fetch
done
pre fix specs/briefs/x.md
expect_exit 1
pre fix resume
expect_exit 0
expect_no_key default
no_git_network
pre feat x
git_called fetch || fail "the wrapper logged no fetch"
ok

# --- hooks ---------------------------------------------------------------------------

# Spec Kit's own layout (PyYAML: indentless lists), with a disabled hook and
# keys the reader skips
SPECKIT_HOOKS=(
  'installed:' '- git' '- docs' 'settings:' '  auto_execute_hooks: true' 'hooks:'
  '  before_specify:' '  - extension: git' '    command: speckit.git.feature' '    enabled: true'
  '    optional: false' '    prompt: Execute speckit.git.feature?' '    description: Create a feature branch'
  '    condition: null'
  '  after_implement:' '  - extension: git' '    command: speckit.git.commit' '    enabled: true'
  '  - extension: docs' '    command: speckit.docs.update'
  '  before_implement:' '  - extension: lint' '    command: speckit.lint.run' '    enabled: false'
  '  after_plan: []'
)

new_case "hooks: Spec Kit's file on origin (feat brief: won't run, would commit, allowed)"
on_origin .specify/extensions.yml "${SPECKIT_HOOKS[@]}"
case_run 0 hooks-feat feat x
ok

new_case "hooks: Spec Kit's file on origin (fix issue: only branch-or-commit hooks)"
issue7
on_origin .specify/extensions.yml "${SPECKIT_HOOKS[@]}"
case_run 0 hooks-fix fix '#7'
expect_no_key "hook won't run"
ok

new_case "hooks: indented lists, quotes, comments, a hook under two keys"
on_origin .specify/extensions.yml 'hooks:' '  # the hooks' '  after_implement:' \
  '    - extension: "docs"' "      command: 'speckit.docs.update'   # inline" '      enabled: Yes' \
  '      description: >' '        folded text: with a colon' '        and - more' \
  '    -' '      extension: sync' '      command: push-all' \
  '  before_implement: {}' '  after_tasks: null' '  before_analyze: ~' \
  '  before_tasks:' '    - extension: sync' '      command: push-all' '      enabled: OFF' \
  '  after_specify:' '    - extension: sync' '      command: push-all'
pre feat x
expect_exit 0
expect_line "hook won't run: after_specify: sync.push-all → run it by hand: /push-all"
expect_line 'hook would branch or commit: after_implement: sync.push-all → run it by hand: /push-all'
expect_line 'hooks allowed: after_implement: docs.speckit.docs.update'
[ "$(printf '%s\n' "$out" | grep -c "^hook won't run:")" = 1 ] || fail "a disabled hook listed"
ok

new_case "hooks: {}, an empty file, no file"
issue7
pre feat x
expect_line 'hooks allowed: none'
on_origin .specify/extensions.yml 'installed: []' 'hooks: {}'
pre feat x
expect_exit 0
expect_line 'hooks allowed: none'
on_origin .specify/extensions.yml ''
pre fix '#7'
expect_exit 0
expect_line 'hooks allowed: none'
ok

new_case "hooks: flagged by name (push, autocommit, open-pr, gitflow, pull requests, amend, squash, cherry-pick), not prompt or stage"
on_origin .specify/extensions.yml 'hooks:' '  after_implement:' \
  '  - extension: shipit' '    command: release.push' \
  '  - extension: ext' '    command: autocommit' \
  '  - extension: ext' '    command: ext.open-pr' \
  '  - extension: ext' '    command: ext.prompt' \
  '  - extension: ext' '    command: stage' \
  '  - extension: ext' '    command: ext.tag_all' \
  '  - extension: worktree-tools' '    command: speckit.wt.add' \
  '  - extension: gitflow' '    command: start' \
  '  - extension: ext' '    command: ext.gitflow' \
  '  - extension: ext' '    command: create-pull-request' \
  '  - extension: ext' '    command: pull_request' \
  '  - extension: ext' '    command: openpullrequest' \
  '  - extension: ext' '    command: amend-last' \
  '  - extension: ext' '    command: squash' \
  '  - extension: ext' '    command: cherry-pick' \
  '  - extension: notes'
pre fix 'button crashes' 'slug=button crashes'
expect_exit 0
expect_line 'hook would branch or commit: after_implement: shipit.release.push → run it by hand: /release-push'
expect_line 'hook would branch or commit: after_implement: ext.autocommit → run it by hand: /autocommit'
expect_line 'hook would branch or commit: after_implement: ext.ext.open-pr → run it by hand: /ext-open-pr'
expect_line 'hook would branch or commit: after_implement: ext.ext.tag_all → run it by hand: /ext-tag_all'
expect_line 'hook would branch or commit: after_implement: worktree-tools.speckit.wt.add → run it by hand: /speckit-wt-add'
expect_line 'hook would branch or commit: after_implement: gitflow.start → run it by hand: /start'
expect_line 'hook would branch or commit: after_implement: ext.ext.gitflow → run it by hand: /ext-gitflow'
expect_line 'hook would branch or commit: after_implement: ext.create-pull-request → run it by hand: /create-pull-request'
expect_line 'hook would branch or commit: after_implement: ext.pull_request → run it by hand: /pull_request'
expect_line 'hook would branch or commit: after_implement: ext.openpullrequest → run it by hand: /openpullrequest'
expect_line 'hook would branch or commit: after_implement: ext.amend-last → run it by hand: /amend-last'
expect_line 'hook would branch or commit: after_implement: ext.squash → run it by hand: /squash'
expect_line 'hook would branch or commit: after_implement: ext.cherry-pick → run it by hand: /cherry-pick'
expect_line 'hooks allowed: after_implement: ext.ext.prompt, after_implement: ext.stage, after_implement: notes'
ok

new_case "hooks: read from the fetched origin, not the checkout (brief, issue, symptom)"
issue7
on_origin .specify/extensions.yml 'hooks:' '  after_implement:' '  - extension: git' '    command: speckit.git.commit'
printf '%s\n' 'hooks:' '  after_implement:' '  - extension: mine' '    command: mine.commit' \
  >"$top/.specify/extensions.yml"
! git -C "$top" cat-file -e refs/remotes/origin/main:.specify/extensions.yml 2>/dev/null ||
  fail "origin/main already has the file"
for args in 'feat x' "fix #7" 'fix button-crashes slug=button'; do
  # shellcheck disable=SC2086 # the words are the arguments
  pre $args
  expect_exit 0
  expect_line 'hook would branch or commit: after_implement: git.speckit.git.commit → run it by hand: /speckit-git-commit'
  if [[ "$out" == *mine* ]]; then fail "a local-only hook listed"; fi
done
ok

new_case "hooks: resume and rebase read the checkout's file (rebase: implement part only)"
on_origin .specify/extensions.yml 'hooks:' '  after_implement:' '  - extension: git' '    command: speckit.git.commit'
printf '%s\n' 'hooks:' '  before_plan:' '  - extension: mine' '    command: mine.plan' \
  '  after_implement:' '  - extension: mine' '    command: mine.commit' '  - extension: mine' '    command: mine.docs' \
  >"$top/.specify/extensions.yml"
case_run 0 hooks-resume feat resume
case_run 0 hooks-rebase feat rebase
pre fix resume
expect_exit 0
expect_line 'hook would branch or commit: after_implement: mine.mine.commit → run it by hand: /mine-commit'
expect_line 'hooks allowed: before_plan: mine.mine.plan, after_implement: mine.mine.docs'
if [[ "$out" == *git.commit* ]]; then fail "origin's hook listed"; fi
ok

# hooks_bad <line> <file line>...: that file in the checkout stops `resume` at
# that line (exit 1)
hooks_bad() {
  local n="$1"
  shift
  printf '%s\n' "$@" >"$top/.specify/extensions.yml"
  pre feat resume
  expect_exit 1
  expect_last "stop: .specify/extensions.yml can't be read as data (line $n); it may hide a hook that commits"
  expect_no_key 'hooks allowed'
}

new_case "hooks: what the reader can't read stops (exit 1)"
hooks_bad 2 'hooks:' $'\tafter_implement: []'
hooks_bad 3 'hooks:' '  after_implement:' $'  -\textension: git'
hooks_bad 3 'hooks:' '  after_implement:' '  - {extension: git, command: x}'
hooks_bad 3 'hooks:' '  after_implement:' '  - extension: &a git'
hooks_bad 3 'hooks:' '  after_implement:' '  - extension: !!str git'
hooks_bad 5 'hooks:' '  after_implement:' '  - extension: x' '    command: a' '      b'
hooks_bad 2 'hooks:' '  Before-Implement: []'
hooks_bad 2 'hooks:' '  "after_implement": []'
hooks_bad 1 'hooks: {after_implement: []}'
hooks_bad 2 'hooks: {}' '  after_implement: []'
hooks_bad 4 'hooks:' '  after_implement:' '  - extension: x' ' stray'
hooks_bad 3 'hooks:' '  after_implement:' '  - command: speckit.x' '    enabled: true'
hooks_bad 4 'hooks:' '  after_implement:' '  - extension: x' '    enabled: maybe'
hooks_bad 4 'hooks:' '  after_implement:' '  - extension: x' '    enabled: "false"'
hooks_bad 3 'hooks:' '  after_implement:' '    extension: x'
hooks_bad 3 'hooks:' '  after_implement: []' '  - extension: x'
hooks_bad 1 'just text'
hooks_bad 2 'hooks:' '- extension: x'
ok

new_case "hooks: hostile values are refused or skipped, never run"
# shellcheck disable=SC2016 # hostile text, never expanded
on_origin .specify/extensions.yml 'hooks:' '  after_implement:' '  - extension: docs' \
  '    command: speckit.docs.update' '    description: $(touch pwned) `touch pwned2`' \
  '    prompt: "; touch pwned3"'
pre feat x
expect_exit 0
expect_line 'hooks allowed: after_implement: docs.speckit.docs.update'
# shellcheck disable=SC2016 # hostile text, never expanded
on_origin .specify/extensions.yml 'hooks:' '  after_implement:' '  - extension: docs' \
  '    command: $(touch pwned)'
case_run 1 hooks-hostile feat x
# shellcheck disable=SC2016 # hostile text, never expanded
on_origin .specify/extensions.yml 'hooks:' '  after_implement:' '  - extension: docs' \
  '    command: "x; touch pwned"'
pre fix '#7'
expect_exit 1
expect_last "stop: origin/main:.specify/extensions.yml can't be read as data (line 4); it may hide a hook that commits"
for p in pwned pwned2 pwned3; do
  [ ! -e "$top/$p" ] && [ ! -e "$c/$p" ] || fail "a command ran"
done
ok

# --- slug ----------------------------------------------------------------------------

# ls_remote_calls: how many `ls-remote --heads` calls the wrapper logged
ls_remote_calls() {
  if [ -e "$PF_CASE/git-calls" ]; then grep -c -- ' ls-remote --heads ' "$PF_CASE/git-calls" || true; else echo 0; fi
}

S7=7-save-button-crashes

new_case "slug: free, one ls-remote"
issue7
git_wrap
pre fix '#7'
expect_exit 0
expect_line "slug: $S7"
[ "$(ls_remote_calls)" = 1 ] || fail "ls-remote calls: $(ls_remote_calls)"
ok

new_case "slug: the bug dir in the fetched origin tree gives -2"
issue7
on_origin ".specify/bugs/$S7/assessment.md" 'x'
pre fix '#7'
expect_exit 0
expect_line "slug: $S7-2"
ok

new_case "slug: the bug dir in HEAD gives -2"
issue7
mkdir -p "$top/.specify/bugs/$S7"
printf 'x\n' >"$top/.specify/bugs/$S7/fix.md"
git -C "$top" add -A
git -C "$top" commit -q -m bug
pre fix '#7'
expect_exit 0
expect_line "slug: $S7-2"
ok

new_case "slug: a local branch gives -2"
issue7
git -C "$top" branch "fix-$S7"
pre fix '#7'
expect_exit 0
expect_line "slug: $S7-2"
ok

new_case "slug: a remote branch gives -2, two clashes -3, one ls-remote"
issue7
git_wrap
git -C "$org" branch "fix-$S7" main
git -C "$org" branch "fix-$S7-20" main
git -C "$org" branch "x/fix-$S7-2" main
pre fix '#7'
expect_exit 0
expect_line "slug: $S7-2"
git -C "$top" branch "fix-$S7-2"
pre fix '#7'
expect_exit 0
expect_line "slug: $S7-3"
on_origin ".specify/bugs/$S7-3/assessment.md" 'x'
git -C "$org" branch "fix-$S7-4" main
pre fix '#7'
expect_exit 0
expect_line "slug: $S7-5"
[ "$(ls_remote_calls)" = 3 ] || fail "ls-remote calls: $(ls_remote_calls) for 3 runs"
ok

new_case "slug: 40-character cap, two title words when three are too long, suffix trims"
printf 'MEMBER\tSupercalifragilistic expialidocious overflow here\n' >"$PF_CASE/issue-o-r-7"
pre fix '#7'
expect_exit 0
expect_line 'slug: 7-supercalifragilistic-expialidocious'
long='aaaaaaaaaa bbbbbbbbbb cccccccccc ddddddd'
pre fix 'long symptom' "slug=$long extra"
expect_exit 0
expect_line 'slug: aaaaaaaaaa-bbbbbbbbbb-cccccccccc-ddddddd'
git -C "$top" branch fix-aaaaaaaaaa-bbbbbbbbbb-cccccccccc-ddddddd
pre fix 'long symptom' "slug=$long"
expect_exit 0
expect_line 'slug: aaaaaaaaaa-bbbbbbbbbb-cccccccccc-ddddd-2'
# the trimmed base ends at a `-`, which is dropped
git -C "$top" branch fix-aaaaaaaaaa-bbbbbbbbbb-ccccccccccccccc-dd
pre fix 'long symptom' 'slug=aaaaaaaaaa bbbbbbbbbb ccccccccccccccc dd'
expect_exit 0
expect_line 'slug: aaaaaaaaaa-bbbbbbbbbb-ccccccccccccccc-2'
pre fix 'long symptom' "slug=$(printf 'a%.0s' {1..45})"
expect_exit 0
expect_line "slug: $(printf 'a%.0s' {1..40})"
ok

new_case "slug: a title with no word gives <N>; symptom words with none give bug"
printf 'MEMBER\t!!! ???\n' >"$PF_CASE/issue-o-r-7"
pre fix '#7'
expect_exit 0
expect_line 'slug: 7'
pre fix 'button crashes' 'slug=!!! ???'
expect_exit 0
expect_line 'slug: bug'
pre fix 'button crashes' "slug=Save it's \$(Broken)"
expect_exit 0
expect_line 'slug: save-it-s-broken'
ok

new_case "slug: a non-GitHub URL's last path segment (bug when it has no word)"
pre fix 'https://gitlab.com/g/p/-/issues/Login_Fails?tab=x#note'
expect_exit 0
expect_line 'slug: login-fails'
pre fix 'https://example.com/_/'
expect_exit 0
expect_line 'slug: bug'
no_gh
ok

new_case "slug: an unreachable remote during the check (exit 2)"
issue7
git_wrap
touch "$PF_CASE/fail-ls-remote"
pre fix '#7'
expect_exit 2
expect_last 'preflight: error: git ls-remote origin failed: fatal: unable to access origin: Could not resolve host'
expect_no_key slug
pre fix 'button crashes' 'slug=button crashes'
expect_exit 2
ok

new_case "slug: /fix ignores slug= for any kind but a symptom"
issue7
for arg in '#7' 'https://gitlab.com/g/p/-/issues/3' resume rebase 'rebase fails' specs/briefs/x.md; do
  pre fix "$arg"
  want_rc="$rc" want="$out"
  pre fix "$arg" slug=a-b
  [ "$rc" = "$want_rc" ] && [ "$out" = "$want" ] || fail "slug= changed the run of $arg (exit $rc, want $want_rc)"
done
pre fix '#7' slug=a-b
expect_exit 0
expect_line 'slug: 7-save-button-crashes'
pre fix 'rebase fails' 'slug=rebase fails'
expect_exit 0
expect_line 'kind: rebase'
expect_line 'rebase target: fails'
pre feat x slug=a-b
expect_usage
ok

new_case "slug: a /fix symptom without slug= takes its first four words"
pre fix 'Save button crashes on click, every time'
expect_exit 0
expect_line 'kind: symptom'
expect_line 'slug: save-button-crashes-on'
pre fix '../x#1'
expect_exit 0
expect_line 'kind: symptom'
expect_line 'slug: x-1'
pre fix '!!! ???'
expect_exit 0
expect_line 'slug: bug'
ok

# --- worktree mode -------------------------------------------------------------------

new_case "worktree: rename, then a rerun on the target branch"
case_run 0 wt-rename feat worktree x off
[ "$(git -C "$top" branch --show-current)" = x ] || fail "branch not renamed"
case_run 0 wt-rename feat worktree x off
pre fix worktree 12-save-crash off
expect_exit 0
expect_line 'branch: fix-12-save-crash'
[ "$(git -C "$top" branch --show-current)" = fix-12-save-crash ] || fail "branch not renamed"
ok

new_case "worktree: bad short name, slug and on|off (exit 2)"
for name in X -x 'a b' '' 'x/y'; do
  pre feat worktree "$name" off
  expect_usage
done
pre fix worktree "$(printf 'a%.0s' {1..41})" off
expect_usage
pre fix worktree Bad off
expect_usage
pre feat worktree x yes
expect_usage
pre feat worktree x
expect_usage
pre fix worktree x on extra
expect_usage
[ "$(git -C "$top" branch --show-current)" = worktree-x ] || fail "branch renamed"
pre fix worktree "$(printf 'a%.0s' {1..40})" off
expect_exit 0
ok

new_case "worktree: a local branch of that name, a bug dir in the worktree (exit 1)"
git -C "$top" branch taken
pre feat worktree taken off
expect_exit 1
expect_line 'worktree: @TOP@'
[[ "$(printf '%s\n' "$out" | tail -n 1)" == "stop: can't rename the branch to taken: "?* ]] || fail "want the rename stop"
mkdir -p "$top/.specify/bugs/12-save"
case_run 1 wt-bug-dir fix worktree 12-save on
[ "$(git -C "$top" branch --show-current)" = worktree-x ] || fail "branch renamed"
ok

new_case "worktree: the flag line when the board is on and .logistics.yml is missing"
case_run 0 wt-flag fix worktree 12-save on
pre feat worktree x off
expect_exit 0
expect_no_key flag
printf 'project: x\n' >"$top/.logistics.yml"
pre feat worktree x on
expect_no_key flag
ok

new_case "worktree: no network call"
git -C "$top" remote set-url origin "$c/nonexistent.git"
touch "$PF_CASE/fail-repo" "$PF_CASE/fail-api"
pre fix worktree 12-save on
expect_exit 0
expect_line 'branch: fix-12-save'
no_gh
ok

# --- spawn note ----------------------------------------------------------------------

new_case "spawn note: unset, feat resume"
unset CLAUDE_CODE_FORK_SUBAGENT
pre feat resume
export CLAUDE_CODE_FORK_SUBAGENT=0
expect_exit 0
golden feat-resume-note
ok

new_case "spawn note: empty"
CLAUDE_CODE_FORK_SUBAGENT='' pre feat resume
expect_exit 0
[[ "$out" == *$'\nspawn note: '* ]] || fail "no spawn note line"
ok

new_case "spawn note: 0, 1 and another value print none"
for v in 0 1 yes; do
  CLAUDE_CODE_FORK_SUBAGENT=$v pre feat resume
  expect_exit 0
  expect_no_key 'spawn note'
done
ok

new_case "spawn note: a refused kind keeps it, stop last"
CLAUDE_CODE_FORK_SUBAGENT='' pre feat 'some idea words'
expect_exit 1
[[ "$out" == *$'\nspawn note: '* ]] || fail "no spawn note line"
[[ "$(printf '%s\n' "$out" | tail -n 1)" == 'stop: '* ]] || fail "last line is not stop:"
ok

new_case "spawn note: worktree mode prints none"
CLAUDE_CODE_FORK_SUBAGENT='' pre fix worktree 12-save on
expect_exit 0
expect_no_key 'spawn note'
ok

if [ "$update" = 1 ] && [ "$updated" = 1 ]; then
  printf 'expected/ rewritten: review it, then run again without UPDATE\n'
  exit 1
fi
printf 'all preflight tests passed\n'
