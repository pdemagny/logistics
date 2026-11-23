#!/usr/bin/env bash
# Offline tests for .apm/skills/feat/scripts/trail.sh (mise run test:trail).
#
# Each case gets a throwaway bug dir ($bd) under a scratch git repo ($repo),
# in which `secret-scan.sh worktree` checks every redacted file (exit 0
# expected). Inputs live in fixtures/, expected outputs in expected/;
# `UPDATE=1 bash tests/trail/run.sh` writes the actual outputs over
# expected/ and exits non-zero, so it never passes CI; review the change with
# `git diff tests/trail/expected`.
#
# Every rule of the scan's SECRET_VENDOR list must have a sample below: the
# run fails on a new rule without one. Secret-looking samples and key values
# are built by concatenation at run time, so this file and the fixtures pass
# the scan themselves (fixtures hold `@NAME@` placeholders, filled in here).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(cd "$here/../.." && pwd -P)"
src="$root/.apm/skills/feat/scripts"
trail_sh="$src/trail.sh"
fx="$here/fixtures"
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

# --- samples -----------------------------------------------------------------------

# Pieces split so no line here matches the secret rules.
pw="pass""word" tok="tok""en" sec="sec""ret" api="api""_key" API="API""_KEY"
long="Zq81mXv0Lw3NcR7tYp2Ue5Ha"

# sample <rule>: S = a line the scan's <rule> matches
sample() {
  case "$1" in
    private-key) S="-----BEG""IN RSA PRIVATE KEY-----" ;;
    github-token) S="gh""p_$long$long" ;;
    aws-key-id) S="AK""IAZQ81MXV0LW3NCR7T" ;;
    slack-token) S="xo""xb-1234-$long" ;;
    openai-key) S="s""k-proj-$long" ;;
    *) return 1 ;;
  esac
}

# fill <name>: fixtures/<name> with its @NAME@ placeholders filled in, on stdout
fill() {
  local line r
  while IFS= read -r line || [ -n "$line" ]; do
    for r in private-key github-token aws-key-id slack-token openai-key; do
      sample "$r"
      line="${line//@$r@/$S}"
    done
    line="${line//@pw@/$pw}" line="${line//@tok@/$tok}"
    line="${line//@sec@/$sec}" line="${line//@api@/$api}" line="${line//@API@/$API}"
    line="${line//@long@/$long}"
    printf '%s\n' "$line"
  done <"$fx/$1"
}

current="every SECRET_VENDOR rule has a sample"
(
  # shellcheck source=/dev/null # the scan's rules, linted with the scripts
  . "$src/secret-scan.sh"
  for ((i = 0; i < ${#SECRET_VENDOR[@]}; i += 2)); do
    r="${SECRET_VENDOR[i]}"
    sample "$r" || fail "no sample for the rule $r: add one to sample()"
    secret_line_rule "$S" && [ "$SECRET_RULE" = "$r" ] || fail "the sample for $r does not match it"
  done
)
ok

# --- harness -----------------------------------------------------------------------

repo="$work/repo"
mkdir -p "$repo"
git -C "$repo" init -q
printf 'x\n' >"$repo/README"
git -C "$repo" add README
git -C "$repo" commit -q -m init

n=0
# new_case <name>: a fresh bug dir ($bd) in the scratch repo
new_case() {
  current="$1"
  unset out
  n=$((n + 1))
  bd="$repo/.specify/bugs/case-$n"
  mkdir -p "$bd"
}

# run <args>...: trail.sh with exactly these arguments; rc, out; stderr must
# stay empty
run() {
  rc=0
  out="$(bash "$trail_sh" "$@" 2>"$work/stderr")" || rc=$?
  out="${out//"$bd"/@BD@}"
  [ ! -s "$work/stderr" ] || fail "stderr not empty"
}

expect_exit() { [ "$rc" = "$1" ] || fail "exit $rc, want $1"; }

# expect_usage: exit 2 and one `trail: usage: ` line
expect_usage() {
  expect_exit 2
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] || fail "not one line"
  [[ "$out" == 'trail: usage: '* ]] || fail "not a usage line"
}

# golden <name> [<file>]: out (or the file) against expected/<name>
golden() {
  local got="$out"
  if [ -n "${2:-}" ]; then got="$(cat "$2")"; fi
  if [ "$update" = 1 ]; then
    printf '%s\n' "$got" >"$ex/$1"
    updated=1
    return 0
  fi
  [ -f "$ex/$1" ] || fail "no golden $ex/$1"
  [ "$got" = "$(cat "$ex/$1")" ] || fail "output differs from expected/$1"
}

# scan_clean <file>: secret-scan.sh worktree finds nothing in the file
scan_clean() {
  local r=0
  (cd "$repo" && bash "$src/secret-scan.sh" worktree "${1#"$repo/"}") >"$work/scan" 2>&1 || r=$?
  [ "$r" = 0 ] || fail "secret-scan still matches $1: $(head -n 1 "$work/scan")"
}

# --- bash 3.2 ------------------------------------------------------------------------

current="bash 3.2 constructs only"
if grep -nE -- 'declare -A|mapfile|readarray|,,\}|\^\^\}|declare -n|local -n|\[\[ -v|\[-[0-9]+\]|;;&|\|&' "$trail_sh"; then
  fail "trail.sh uses a construct bash 3.2 lacks"
fi
ok

current="nothing read is evaluated"
if grep -nE -- '(^|[^A-Za-z_])eval([^A-Za-z_]|$)' "$trail_sh"; then
  fail "trail.sh calls eval"
fi
ok

# --- usage ---------------------------------------------------------------------------

new_case "usage: no arguments, an unknown subcommand, a wrong count"
run
expect_usage
run frobnicate
expect_usage
run rotate "$bd"
expect_usage
run rotate "$bd" spec
expect_usage
run sections "$bd/x.md" assessment extra
expect_usage
run redact
expect_usage
ok

new_case "usage: a missing bug dir or file, a symlink"
run rotate "$bd/nope" fix
expect_usage
run redact "$bd/nope.md"
expect_usage
printf 'x\n' >"$bd/real.md"
ln -s real.md "$bd/link.md"
run redact "$bd/link.md"
expect_usage
run sections "$bd/link.md" test
expect_usage
run sections "$bd/real.md" fix
expect_usage
run sections "$bd/nope.md" test
expect_usage
run slug "$bd" a-slug
expect_usage
run slug "$bd" a-slug "$bd/real.md" printed extra
expect_usage
run slug "$bd" "" "$bd/real.md"
expect_usage
run slug "$bd/nope" a-slug "$bd/real.md"
expect_usage
ln -s "$bd" "$work/bdlink"
run slug "$work/bdlink" a-slug "$bd/real.md"
expect_usage
run rotate "$work/bdlink" fix
expect_usage
ok

# --- rotate --------------------------------------------------------------------------

for r in assessment test fix; do
  new_case "rotate $r: none, then -1, then -2"
  run rotate "$bd" "$r"
  expect_exit 0
  [ "$out" = none ] || fail "out $out, want none"
  printf 'first\n' >"$bd/$r.md"
  run rotate "$bd" "$r"
  expect_exit 0
  [ "$out" = "@BD@/$r-1.md" ] || fail "out $out, want @BD@/$r-1.md"
  [ ! -e "$bd/$r.md" ] && [ "$(cat "$bd/$r-1.md")" = first ] || fail "not renamed"
  printf 'second\n' >"$bd/$r.md"
  run rotate "$bd" "$r"
  [ "$out" = "@BD@/$r-2.md" ] || fail "out $out, want @BD@/$r-2.md"
  [ "$(cat "$bd/$r-1.md")" = first ] && [ "$(cat "$bd/$r-2.md")" = second ] || fail "an earlier report changed"
  ok
done

new_case "rotate: -1 and -3 present give -4; other names are ignored"
for f in assessment.md assessment-1.md assessment-3.md assessment-x.md assessment-2b.md test-9.md; do
  printf '%s\n' "$f" >"$bd/$f"
done
run rotate "$bd" assessment
expect_exit 0
[ "$out" = "@BD@/assessment-4.md" ] || fail "out $out, want @BD@/assessment-4.md"
[ "$(cat "$bd/assessment-4.md")" = assessment.md ] || fail "wrong file renamed"
[ ! -e "$bd/assessment-2.md" ] || fail "a gap was filled"
run rotate "$bd" test
[ "$out" = none ] || fail "test: out $out, want none"
ok

new_case "rotate: a symlink at either name is refused"
printf 'x\n' >"$bd/real.md"
ln -s real.md "$bd/fix.md"
run rotate "$bd" fix
expect_usage
[ -L "$bd/fix.md" ] || fail "the symlink moved"
command rm -f -- "$bd/fix.md"
printf 'x\n' >"$bd/fix.md"
ln -s real.md "$bd/fix-1.md"
run rotate "$bd" fix
expect_exit 0
[ "$out" = "@BD@/fix-2.md" ] || fail "out $out, want @BD@/fix-2.md (a dangling or linked -1 counts)"
ok

# --- sections ------------------------------------------------------------------------

# assessment_parts: a complete assessment, one part per line
assessment_parts() {
  printf '%s\n' '# Bug Assessment: the thing breaks' '' '- **Verdict**: valid' '- **Severity**: medium' \
    '## Symptom' '## Reproduction' '## Suspected Code Paths' '## Root Cause Hypothesis' \
    '## Proposed Remediation' '## Open Questions' 'None.'
}

new_case "sections: a complete assessment and a complete test report are ok"
assessment_parts >"$bd/assessment.md"
run sections "$bd/assessment.md" assessment
expect_exit 0
[ "$out" = "Sections: ok" ] || fail "assessment not ok"
printf '# Bug Test\n\n**Result**: pass\n\n## Checks Performed\n' >"$bd/test.md"
run sections "$bd/test.md" test
[ "$out" = "Sections: ok" ] || fail "test not ok"
ok

new_case "sections: each assessment part missing in turn"
i=0
while IFS= read -r part; do
  i=$((i + 1))
  [ -n "$part" ] && [ "$part" != None. ] || continue
  assessment_parts | grep -vxF -- "$part" >"$bd/assessment.md" || true
  run sections "$bd/assessment.md" assessment
  want="${part#- }" want="${want%%: *}"
  case "$want" in '# Bug Assessment'*) want='# Bug Assessment:' ;; esac
  [ "$out" = "Sections: error: assessment.md lacks $want" ] || fail "part $i ($part): $out"
done < <(assessment_parts)
ok

new_case "sections: several parts missing, in the table's order; test parts"
printf '## Symptom\n**Severity**\n' >"$bd/assessment.md"
run sections "$bd/assessment.md" assessment
[ "$out" = "Sections: error: assessment.md lacks # Bug Assessment:, **Verdict**, ## Reproduction, ## Suspected Code Paths, ## Root Cause Hypothesis, ## Proposed Remediation, ## Open Questions" ] || fail "several missing"
printf 'nothing\n' >"$bd/test.md"
run sections "$bd/test.md" test
[ "$out" = "Sections: error: test.md lacks **Result**, ## Checks Performed" ] || fail "test missing"
ok

new_case "sections: trailing spaces and CR on a heading are ignored; a longer heading is not it"
assessment_parts | sed -e 's/^## Symptom$/## Symptom   /' -e $'s/^## Reproduction$/## Reproduction\r/' >"$bd/assessment.md"
run sections "$bd/assessment.md" assessment
[ "$out" = "Sections: ok" ] || fail "trailing spaces not ignored"
assessment_parts | sed -e 's/^## Open Questions$/## Open Questions and more/' -e 's/^## Symptom$/  ## Symptom/' >"$bd/assessment.md"
run sections "$bd/assessment.md" assessment
[ "$out" = "Sections: error: assessment.md lacks ## Symptom, ## Open Questions" ] || fail "partial heading accepted"
ok

# --- slug ----------------------------------------------------------------------------

new_case "slug: ok, with and without the printed slug"
printf '# Bug Fix\n\n- **Slug**: 29-login-fails\n- **Slug**: other\n' >"$bd/fix.md"
run slug "$bd" 29-login-fails "$bd/fix.md" 29-login-fails
expect_exit 0
[ "$out" = ok ] || fail "out $out"
run slug "$bd" 29-login-fails "$bd/fix.md"
[ "$out" = ok ] || fail "without printed: $out"
ok

new_case "slug: backticks and a trailing note are stripped"
printf -- "- **Slug**: \`29-login-fails\` (from the issue)  \n" >"$bd/fix.md"
run slug "$bd" 29-login-fails "$bd/fix.md" "\`29-login-fails\` (reused)"
[ "$out" = ok ] || fail "out $out"
printf -- "- **Slug**:\`29-login-fails\`\r\n" >"$bd/fix.md"
run slug "$bd" 29-login-fails "$bd/fix.md" ' 29-login-fails '
[ "$out" = ok ] || fail "CRLF bullet: $out"
ok

new_case "slug: any disagreement is a mismatch naming the printed slug, else the bullet"
printf -- '- **Slug**: 29-login-fails\n' >"$bd/fix.md"
run slug "$bd" 29-login-fails "$bd/fix.md" 29-login-broken
expect_exit 0
[ "$out" = "mismatch (29-login-broken)" ] || fail "printed differs: $out"
run slug "$bd" 30-other "$bd/fix.md" 30-other
[ "$out" = "mismatch (30-other)" ] || fail "bullet differs: $out"
run slug "$bd" 30-other "$bd/fix.md"
[ "$out" = "mismatch (29-login-fails)" ] || fail "bullet differs, no printed: $out"
ok

new_case "slug: a file outside the bug dir, a missing bullet, a missing file"
mkdir -p "$repo/.specify/bugs/elsewhere"
printf -- '- **Slug**: 29-login-fails\n' >"$repo/.specify/bugs/elsewhere/fix.md"
run slug "$bd" 29-login-fails "$repo/.specify/bugs/elsewhere/fix.md" 29-login-fails
[ "$out" = "mismatch (29-login-fails)" ] || fail "outside: $out"
run slug "$bd" 29-login-fails "$bd/../elsewhere/fix.md" 29-login-fails
[ "$out" = "mismatch (29-login-fails)" ] || fail "outside through ..: $out"
mkdir -p "$bd-x"
printf -- '- **Slug**: 29-login-fails\n' >"$bd-x/fix.md"
run slug "$bd" 29-login-fails "$bd-x/fix.md"
[ "$out" = "mismatch (29-login-fails)" ] || fail "sibling with the dir as prefix: $out"
printf '# Bug Fix\n\n- **Status**: applied\n' >"$bd/fix.md"
run slug "$bd" 29-login-fails "$bd/fix.md" 29-login-fails
[ "$out" = "mismatch (29-login-fails)" ] || fail "no bullet: $out"
run slug "$bd" 29-login-fails "$bd/fix.md"
[ "$out" = "mismatch (none)" ] || fail "no bullet, no printed: $out"
run slug "$bd" 29-login-fails "$bd/gone.md"
expect_exit 0
[ "$out" = "mismatch (none)" ] || fail "missing file: $out"
run slug "$bd" 29-login-fails "$bd/gone.md" 29-login-fails
[ "$out" = "mismatch (29-login-fails)" ] || fail "missing file, printed: $out"
ok

# --- redact --------------------------------------------------------------------------

# redact_case <fixture> <count>: fill the fixture into the bug dir, redact it,
# check the count, the golden expected/redact-<fixture> and the scan; F is
# the file
redact_case() {
  F="$bd/$1"
  fill "$1" >"$F"
  run redact "$F"
  expect_exit 0
  [ "$out" = "$2" ] || fail "count $out, want $2"
  golden "redact-$1" "$F"
  scan_clean "$F"
}

# again: a second run prints 0 and leaves the file as it is
again() {
  command cp -f "$F" "$work/before"
  run redact "$F"
  expect_exit 0
  [ "$out" = 0 ] || fail "second run printed $out, want 0"
  cmp -s "$F" "$work/before" || fail "second run changed the file"
}

new_case "redact: a sample of every scan rule passes the scan after"
(
  # shellcheck source=/dev/null # the scan's rules, linted with the scripts
  . "$src/secret-scan.sh"
  for ((i = 0; i < ${#SECRET_VENDOR[@]}; i += 2)); do
    r="${SECRET_VENDOR[i]}"
    sample "$r"
    if [ "$r" = private-key ]; then
      printf '%s\nMIIEowIBAAKCAQEA0Zq81mXv0Lw3NcR7tYp2Ue5Ha\n-----END RSA PRIVATE KEY-----\n' "$S"
    else
      printf 'seen in the log: %s (rule %s)\n' "$S" "$r"
    fi
  done
  printf '%s = "hunter2024x"\n%s=%s9\n' "$pw" "$api" "$long"
) >"$bd/rules.md"
n_rules="$(grep -c '' "$bd/rules.md")"
[ "$n_rules" -ge 8 ] || fail "rules.md has $n_rules lines"
F="$bd/rules.md"
run redact "$F"
expect_exit 0
[ "$out" -ge 7 ] || fail "count $out, want one per rule"
golden redact-rules.md "$F"
scan_clean "$F"
again
ok

new_case "redact: every scan rule alone, in its own file"
for r in private-key github-token aws-key-id slack-token openai-key; do
  sample "$r"
  printf 'x %s\n' "$S" >"$bd/$r.md"
  run redact "$bd/$r.md"
  expect_exit 0
  [ "$out" = 1 ] || fail "$r: count $out, want 1"
  scan_clean "$bd/$r.md"
done
[ "$(cat "$bd/github-token.md")" = "x <redacted>" ] || fail "a vendor token is not <redacted> alone"
[ "$(cat "$bd/openai-key.md")" = "x <redacted>" ] || fail "the openai rule's lead is not kept"
[ "$(cat "$bd/private-key.md")" = "<redacted>" ] || fail "a private-key line is not one <redacted> line"
ok

new_case "redact: key values, the contract's rule 2 table line by line"
redact_case keys.md 10
for want in \
  "$pw=<redacted>" \
  "$pw: <redacted>" \
  "  - $pw: <redacted>  # rotated" \
  "export $API=<redacted>" \
  "$api: <redacted>" \
  "$tok = <redacted>" \
  "url?$tok=<redacted>&x=1" \
  "\"$sec\": <redacted>, \"$tok\": <redacted>" \
  "GITHUB_$tok: <redacted>" \
  "$tok:" \
  "$tok: str" \
  "$pw: \"\"" \
  "$pw: NULL" \
  "$sec: # set later"; do
  grep -qxF -- "$want" "$F" || fail "no line: $want"
done
again
ok

new_case "redact: private-key blocks, with and without an end line"
redact_case blocks.md 3
grep -q 'MIIE' "$F" && fail "a key body line is left"
grep -q 'END RSA' "$F" && fail "an end line is left"
for want in 'done' 'kept after the blank line' 'kept after the fence' '~~~'; do
  grep -qxF -- "$want" "$F" || fail "no line: $want"
done
again
ok

new_case "redact: a prose mention of the begin marker costs that line only"
redact_case prose.md 1
[ "$(grep -c '' "$F")" = "$(fill prose.md | grep -c '')" ] || fail "line count changed"
for want in '## Root Cause Hypothesis' '## Proposed Remediation' '## Open Questions' 'None.' '- **Verdict**: valid'; do
  grep -qxF -- "$want" "$F" || fail "no line: $want"
done
ok

new_case "redact: a block ends at the first line that is not its body or a header"
redact_case adjacent.md 4
grep -q 'MIIE\|Proc-Type\|DEK-Info' "$F" && fail "a key body or header line is left"
for want in '- **Verdict**: valid' '- **Severity**: low' 'kept: the line after the body' '## Symptom' '## Reproduction'; do
  grep -qxF -- "$want" "$F" || fail "no line: $want"
done
run sections "$F" assessment
[ "$out" = "Sections: ok" ] || fail "sections after redact: $out"
again
ok

new_case "redact: a multi-line value (block scalar, unclosed quote) becomes one line"
redact_case multiline.md 6
grep -q 'hidden\|part\|runs on' "$F" && fail "a line of a multi-line value is left"
for want in "  $pw: |" '    <redacted>' '  next: kept' "$sec: >-  # folded" '  <redacted>' 'kept at column 0' \
  "$API=<redacted>" '<redacted> # tail' "$tok=<redacted>" 'kept after the blank line' 'kept: an empty block scalar'; do
  grep -qxF -- "$want" "$F" || fail "no line: $want"
done
again
ok

new_case "redact: a secret inside a code excerpt"
redact_case code.md 2
grep -qxF -- "client = Client($tok=<redacted>, retries=3)" "$F" || fail "the code key value is left"
grep -qxF -- 'headers = {"Authorization": "Bearer <redacted>"}' "$F" || fail "the code token is left"
ok

new_case "redact: a key named inside a markdown code span keeps its closing backtick"
redact_case span.md 2
grep -qxF -- "Set \`$tok:\` and \`$pw=\` in the config." "$F" || fail "a code span lost its closing backtick"
grep -qxF -- "Use \`$tok: <redacted>\` in the example." "$F" || fail "a value inside a code span is left or its span broken"
grep -qxF -- "$tok: <redacted>" "$F" || fail "a key at the start of a line is not redacted to the end of the line"
again
ok

new_case "redact: a file with nothing secret stays byte-identical"
fill clean.md >"$bd/clean.md"
command cp -f "$bd/clean.md" "$work/clean"
F="$bd/clean.md"
run redact "$F"
expect_exit 0
[ "$out" = 0 ] || fail "count $out, want 0"
cmp -s "$F" "$work/clean" || fail "the clean file changed"
[ -z "$(find "$bd" -name '.trail-*')" ] || fail "a temp file is left"
: >"$bd/empty.md"
run redact "$bd/empty.md"
[ "$out" = 0 ] && [ ! -s "$bd/empty.md" ] || fail "an empty file changed"
ok

new_case "redact: CRLF line ends and a missing final newline are kept"
printf 'a\r\n%s=hunter2\r\nb\r\n' "$pw" >"$bd/crlf.md"
run redact "$bd/crlf.md"
[ "$out" = 1 ] || fail "count $out, want 1"
printf 'a\r\n%s=<redacted>\r\nb\r\n' "$pw" >"$work/want"
cmp -s "$bd/crlf.md" "$work/want" || fail "CRLF not kept"
printf 'a\n%s=hunter2' "$pw" >"$bd/nonl.md"
run redact "$bd/nonl.md"
printf 'a\n%s=<redacted>' "$pw" >"$work/want"
cmp -s "$bd/nonl.md" "$work/want" || fail "no final newline not kept"
sample private-key
printf 'a\n%s\nMIIEowIBAAKCAQEA' "$S" >"$bd/tail.md"
run redact "$bd/tail.md"
printf 'a\n<redacted>' >"$work/want"
cmp -s "$bd/tail.md" "$work/want" || fail "a block to the end of the file not one line"
printf '%s\r\nMIIE\r\n\r\nb\r\n' "$S" >"$bd/crblock.md"
run redact "$bd/crblock.md"
printf '<redacted>\r\n\r\nb\r\n' >"$work/want"
cmp -s "$bd/crblock.md" "$work/want" || fail "a CRLF block not ended by its blank line"
ok

if [ "$update" = 1 ] && [ "$updated" = 1 ]; then
  printf 'expected/ rewritten: review it, then run again without UPDATE\n'
  exit 1
fi
printf 'all trail tests passed\n'
