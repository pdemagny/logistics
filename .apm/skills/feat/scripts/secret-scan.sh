#!/usr/bin/env bash
# Secret scan for the shipper, and the secret rules tracker.sh shares.
#
#   secret-scan.sh staged             the lines the staged diff adds
#   secret-scan.sh worktree <path>... the lines <path> adds over HEAD (every
#                                     line of an untracked file)
#   secret-scan.sh range <from> <to>  the lines git diff <from> <to> adds
#
# Paths are relative to the repo root; the script works from any directory
# of the repo. Removed lines never count. Prints `<file>:<line>: <rule>` for
# each match, never the value. Exit 0 clean, 1 a match, 2 could not run
# (usage, not a git repo, git failed); errors go to stderr.
#
# Rules: the vendor prefixes (private-key, github-token, aws-key-id,
# slack-token, openai-key), and key-literal: a key named password, passwd,
# token, secret or api key (any case, `api_key`, `api-key` or `apikey`),
# then `:`, `=`, `:=` or `=>`, then a literal value: quoted, 8 or more
# characters with no `$` and no whitespace; or unquoted, 20 or more token
# characters (letters, digits, `_/+=.@-`) holding a digit and running to the
# end of the line. A variable, a call, an env-var reference or a short value
# is not a literal secret.
# Three more rules run after the vendor prefixes, which win where both match.
# bearer-token: the word Bearer or bearer, at the line start or after a
# character that is not a letter, digit, `_` or `-`, whitespace, then 16 or
# more token characters (letters, digits, `._~+/-`). jwt: a part starting eyJ of 10 or
# more base64url characters, a dot, a second part of 10 or more, a dot.
# url-credentials: a scheme and `://`, a user, a colon, a password of 6 or
# more characters not starting with `<`, `$` or `{`, then `@`.
#
# Sourced (tracker.sh does), it only defines functions and the rule
# variables; it runs nothing.

# Each pattern holds one bracketed letter, so its own text does not match
# it and this file passes its own scan.
SECRET_VENDOR=(
  private-key '-----BEGI[N]'
  github-token 'gh[opsur]_|github_pa[t]_'
  aws-key-id 'AKI[A]'
  slack-token 'xox[bp]-'
  openai-key '(^|[^A-Za-z0-9_])s[k]-'
  bearer-token '(^|[^A-Za-z0-9_-])[Bb]earer[[:space:]]+[A-Za-z0-9._~+/-]{16,}'
  jwt 'ey[J][A-Za-z0-9_-]{7,}[.][A-Za-z0-9_-]{10,}[.]'
  url-credentials '[A-Za-z][A-Za-z0-9+.-]{0,31}://[^/:@[:space:]]+:[^/@[:space:]<{$][^/@[:space:]]{5,}@'
)
# Matched case-insensitively (nocasematch: bash 3.2 has no lowercase
# expansion). Groups: 1 key, 2 separator, 3 value.
SECRET_KEY='(password|passwd|token|secret|api[_-]?key)["'\'']?[[:space:]]*(:=|=>|[:=])[[:space:]]*'
SECRET_QUOTED="$SECRET_KEY"'("[^"$[:space:]]{8,}"|'\''[^'\''$[:space:]]{8,}'\'')'
SECRET_BARE="$SECRET_KEY"'([a-z0-9_/+=.@-]{20,})[[:space:]]*$'

# secret_line_rule <line>: 0 and SECRET_RULE set to the rule's name when the
# line matches one, else 1.
secret_line_rule() {
  local i hit=1 nocase=0
  SECRET_RULE=""
  # the vendor prefixes match case-sensitively, the key literal in any case;
  # the caller's nocasematch is put back as it was
  if shopt -q nocasematch; then nocase=1; fi
  shopt -u nocasematch
  for ((i = 0; i < ${#SECRET_VENDOR[@]}; i += 2)); do
    if [[ "$1" =~ ${SECRET_VENDOR[i + 1]} ]]; then
      SECRET_RULE="${SECRET_VENDOR[i]}"
      hit=0
      break
    fi
  done
  if [ "$hit" = 1 ]; then
    shopt -s nocasematch
    if [[ "$1" =~ $SECRET_QUOTED ]] ||
      { [[ "$1" =~ $SECRET_BARE ]] && [[ "${BASH_REMATCH[3]}" =~ [0-9] ]]; }; then
      SECRET_RULE=key-literal
      hit=0
    fi
  fi
  if [ "$nocase" = 1 ]; then shopt -s nocasematch; else shopt -u nocasematch; fi
  return "$hit"
}

# secret_rule <text>: secret_line_rule over each line of <text>.
secret_rule() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    secret_line_rule "$line" && return 0
  done <<<"$1"
  return 1
}

# The scanner itself: runs only when the file is executed, not sourced.

scan_die() { printf 'secret-scan: error: %s\n' "$1" >&2; exit 2; }

# scan_report <file> <line number> <line>: print a match, never the value.
scan_report() {
  if secret_line_rule "$3"; then
    printf '%s:%s: %s\n' "$1" "$2" "$SECRET_RULE"
    scan_found=1
  fi
}

# scan_diff <file>: the added lines of a `git diff -U0` saved in <file>.
scan_diff() {
  local line file="" num=0 in_hunk=0 re_hunk='^@@ -[0-9,]+ \+([0-9]+)(,[0-9]+)? @@'
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      'diff --git '*) file="" in_hunk=0 ;;
      '@@ '*)
        [[ "$line" =~ $re_hunk ]] || scan_die "unreadable hunk header in git diff"
        num="${BASH_REMATCH[1]}" in_hunk=1
        ;;
      *)
        if [ "$in_hunk" = 0 ]; then
          # git ends the header with a tab when the path holds a space.
          if [[ "$line" == '+++ '* ]]; then
            file="${line#+++ }" file="${file#b/}" file="${file%$'\t'}"
          fi
        elif [[ "$line" == +* ]]; then
          scan_report "$file" "$num" "${line:1}"
          num=$((num + 1))
        fi
        ;;
    esac
  done <"$1"
}

# scan_file <file>: every line of an untracked text file.
# shellcheck disable=SC2094 # scan_report only prints the file's name
scan_file() {
  local line num=0
  grep -qI '' -- "$1" 2>/dev/null || return 0 # binary or empty
  while IFS= read -r line || [ -n "$line" ]; do
    num=$((num + 1))
    scan_report "$1" "$num" "$line"
  done <"$1"
}

scan_main() {
  local mode="${1:-}" root f
  case "$mode" in
    staged) [ "$#" -eq 1 ] ;;
    worktree) [ "$#" -ge 2 ] ;;
    range) [ "$#" -eq 3 ] ;;
    *) false ;;
  esac || scan_die "usage: secret-scan.sh staged | worktree <path>... | range <from> <to>"
  shift

  root="$(git rev-parse --show-toplevel 2>/dev/null)" || scan_die "not a git repository"
  cd "$root"
  tmp="$(mktemp -d)" || scan_die "mktemp failed"
  trap 'command rm -rf -- "$tmp"' EXIT

  local diff_opts=(-c core.quotePath=false diff -U0 --no-color --no-ext-diff --no-textconv
    --no-relative --src-prefix=a/ --dst-prefix=b/ --diff-filter=ACMR)
  scan_found=0
  if [ "$mode" = staged ]; then
    git "${diff_opts[@]}" --cached >"$tmp/diff" 2>"$tmp/err" ||
      scan_die "git diff failed: $(head -n 1 "$tmp/err")"
    scan_diff "$tmp/diff"
  elif [ "$mode" = range ]; then
    git "${diff_opts[@]}" --end-of-options "$1" "$2" -- >"$tmp/diff" 2>"$tmp/err" ||
      scan_die "git diff failed: $(head -n 1 "$tmp/err")"
    scan_diff "$tmp/diff"
  else
    git "${diff_opts[@]}" HEAD -- "$@" >"$tmp/diff" 2>"$tmp/err" ||
      scan_die "git diff failed: $(head -n 1 "$tmp/err")"
    scan_diff "$tmp/diff"
    git ls-files -z --others --exclude-standard -- "$@" >"$tmp/new" 2>"$tmp/err" ||
      scan_die "git ls-files failed: $(head -n 1 "$tmp/err")"
    while IFS= read -r -d '' f; do scan_file "$f"; done <"$tmp/new"
  fi
  return "$scan_found"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  export LC_ALL=C
  scan_main "$@"
fi
