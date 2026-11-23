#!/usr/bin/env bash
# The bug trail's chores for feat-bug-assessor and feat-implementer (bug
# mode), one plain call each (contract: setup-trail-scripts).
#
#   trail.sh rotate <bug dir> <assessment|test|fix>
#   trail.sh sections <file> <assessment|test>
#   trail.sh slug <bug dir> <slug> <file> [<printed slug>]
#   trail.sh redact <file>
#
# rotate renames <report>.md to <report>-<n>.md (n = highest + 1) and prints
# the new path or `none`; sections prints `Sections: ok` or `Sections:
# error: <file> lacks <part>, ...`; slug prints `ok` or `mismatch (<slug>)`;
# redact replaces secret values by `<redacted>` with the secret scan's rules
# (sourced from secret-scan.sh, one list) and prints the count.
#
# Everything on stdout, nothing on stderr. Exit 0 done (a mismatch or a
# section error is output, not an exit code); 2 with one `trail: usage: ...`
# or `trail: error: <why>` line. Nothing read is evaluated or executed.
set -euo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=secret-scan.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/secret-scan.sh" 2>/dev/null ||
  { printf 'trail: error: secret-scan.sh is missing next to trail.sh\n'; exit 2; }

USAGE='trail.sh rotate <bug dir> <assessment|test|fix> | sections <file> <assessment|test> | slug <bug dir> <slug> <file> [<printed slug>] | redact <file>'

usage() { printf 'trail: usage: %s\n' "${1:-$USAGE}"; exit 2; }
die() { printf 'trail: error: %s\n' "$1"; exit 2; }

# need_dir <path>: a directory, not a symlink
need_dir() {
  [ ! -L "$1" ] || usage "$1 is a symlink"
  [ -d "$1" ] || usage "no bug dir $1"
}

# need_file <path>: a regular file, not a symlink
need_file() {
  [ ! -L "$1" ] || usage "$1 is a symlink"
  [ -f "$1" ] || usage "no file $1"
}

# --- rotate (contract: rotate) ------------------------------------------------
# cmd_rotate <bug dir> <report>: <report>.md to <report>-<n>.md, n = 1 + the
# highest existing n; prints the new absolute path, or `none`
cmd_rotate() {
  local dir r="$2" f n top=0 dest
  dir="$(cd -- "$1" && pwd -P)" || die "can't read $1"
  [ ! -L "$dir/$r.md" ] || usage "$dir/$r.md is a symlink"
  if [ ! -e "$dir/$r.md" ]; then
    printf 'none\n'
    return 0
  fi
  [ -f "$dir/$r.md" ] || usage "$dir/$r.md is not a file"
  for f in "$dir/$r"-*.md; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    n="${f#"$dir/$r"-}" n="${n%.md}"
    case "$n" in '' | *[!0-9]*) continue ;; esac
    n=$((10#$n))
    if [ "$n" -gt "$top" ]; then top="$n"; fi
  done
  dest="$dir/$r-$((top + 1)).md"
  if [ -e "$dest" ] || [ -L "$dest" ]; then usage "$dest exists"; fi
  command mv -f -- "$dir/$r.md" "$dest" 2>/dev/null || die "can't rename $dir/$r.md"
  printf '%s\n' "$dest"
}

# --- sections (contract: sections) --------------------------------------------
# cmd_sections <file> <report>: the required parts, in the table's order
cmd_sections() {
  local file="$1" part missing="" re
  local -a parts
  if [ "$2" = assessment ]; then
    parts=('# Bug Assessment:' '**Verdict**' '**Severity**' '## Symptom' '## Reproduction'
      '## Suspected Code Paths' '## Root Cause Hypothesis' '## Proposed Remediation' '## Open Questions')
  else
    parts=('**Result**' '## Checks Performed')
  fi
  for part in "${parts[@]}"; do
    case "$part" in
      '# '*) re="^# Bug Assessment:" ;;
      # a heading is the whole line, trailing spaces (and a \r) ignored
      '## '*) re="^${part}[[:space:]]*\$" ;;
      *) re="" ;;
    esac
    if [ -n "$re" ]; then
      grep -Eq -- "$re" "$file" && continue
    else
      grep -Fq -- "$part" "$file" && continue
    fi
    missing="$missing${missing:+, }$part"
  done
  if [ -z "$missing" ]; then
    printf 'Sections: ok\n'
  else
    printf 'Sections: error: %s lacks %s\n' "${file##*/}" "$missing"
  fi
}

# --- slug (contract: slug) ----------------------------------------------------
# norm <text>: N = the text without backticks and a trailing ` (<note>)`, then
# surrounding spaces
norm() {
  N="${1//\`/}"
  N="${N%"${N##*[![:space:]]}"}"
  if [[ "$N" =~ [[:space:]]+\([^\(\)]*\)$ ]]; then N="${N%"${BASH_REMATCH[0]}"}"; fi
  N="${N#"${N%%[![:space:]]*}"}"
  N="${N%"${N##*[![:space:]]}"}"
}

# cmd_slug <bug dir> <slug> <file> [<printed slug>]
cmd_slug() {
  local slug="$2" file="$3" printed="" bullet="" found=0 good=1 line bdir fdir
  if [ "$#" -eq 4 ]; then
    norm "$4"
    printed="$N"
    [ "$printed" = "$slug" ] || good=0
  fi
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        '- **Slug**:'*)
          norm "${line#'- **Slug**:'}"
          bullet="$N" found=1
          break
          ;;
      esac
    done <"$file"
    [ "$found" = 1 ] && [ "$bullet" = "$slug" ] || good=0
    bdir="$(cd -- "$1" && pwd -P)" || good=0
    fdir="."
    case "$file" in */*) fdir="${file%/*}" ;; esac
    [ -n "$fdir" ] || fdir=/
    fdir="$(cd -- "$fdir" && pwd -P)" || good=0
    case "$fdir/" in "$bdir"/*) ;; *) good=0 ;; esac
  else
    good=0
  fi
  if [ "$good" = 1 ]; then
    printf 'ok\n'
  else
    printf 'mismatch (%s)\n' "${printed:-${bullet:-none}}"
  fi
}

# --- redact (contract rules 1-4, research R5) ---------------------------------
# The rules come from secret-scan.sh's variables (SECRET_VENDOR, SECRET_KEY,
# secret_line_rule), never copied, so there is one list.

RED='<redacted>'
# a key is the line's first token: only indent, `- `, `export `, an opening
# quote and the key's own word characters before it
RE_FIRST='^[[:space:]]*(- )?(export )?["'\'']?[A-Za-z0-9_.-]*$'
# an unquoted value after a key inside a line stops at whitespace or one of
# , ; & ) } ] " ' < > ` (a key named in a markdown code span keeps its span)
RE_INLINE='^[^][:space:],;&)}"'\''<>`]*'
RE_FENCE='^[[:space:]]*(```|~~~)'
# a private-key block's body or header line (rule 1); any other line ends it
RE_PEM='^[[:space:]]*([A-Za-z0-9+/=]+|Proc-Type:.*|DEK-Info:.*)[[:space:]]*$'
# a YAML block scalar indicator, chomping and indent included (rule 2)
RE_SCALAR='^[|>]([+-][1-9]?|[1-9][+-]?)?$'
# a bare type or null word after `:` is no value (`token: str`)
RE_TYPE='^(str|string|int|integer|bool|boolean|bytes|number|any|object|none|null|nil|undefined|true|false)$'

# nocase <text> <regex>: [[ =~ ]] in any case, nocasematch put back off
nocase() {
  local r=1
  shopt -s nocasematch
  if [[ "$1" =~ $2 ]]; then r=0; fi
  shopt -u nocasematch
  return "$r"
}

# redact_keys: rule 2 on R, leftmost key first, scanning on after each value
redact_keys() {
  local rest="$R" out="" first=1 lead m sep pre after val q inner
  while nocase "$rest" "$SECRET_KEY"; do
    m="${BASH_REMATCH[0]}" sep="${BASH_REMATCH[2]}"
    # the leftmost match is the first literal occurrence of its text
    pre="${rest%%"$m"*}"
    after="${rest:${#pre}+${#m}}"
    out="$out$pre$m" rest="$after" lead=0
    if [ "$first" = 1 ] && [[ "$pre" =~ $RE_FIRST ]]; then lead=1; fi
    first=0
    case "$after" in
      '' | '""'* | "''"*) continue ;; # no value
      '"'* | "'"*)
        # a quoted value goes with its quotes (an unclosed one to the end;
        # after a first-token key, its next lines too)
        q="${after:0:1}" inner="${after:1}"
        if [[ "$inner" == *"$q"* ]]; then
          val="$q${inner%%"$q"*}$q"
        else
          val="$after"
          if [ "$lead" = 1 ]; then ML="$q"; fi
        fi
        ;;
      *)
        if [ "$lead" = 1 ]; then
          # to the end of the line, minus a trailing ` #` comment; a
          # comment alone is no value
          if [[ "$after" == '#'* && "$m" =~ [[:space:]]$ ]]; then continue; fi
          val="$after"
          if [[ "$val" =~ [[:space:]]# ]]; then val="${val%%"${BASH_REMATCH[0]}"*}"; fi
          val="${val%"${val##*[![:space:]]}"}"
          # a block scalar's indicator stays; its lines are the value
          if [[ "$val" =~ $RE_SCALAR ]]; then
            ML=block
            continue
          fi
        else
          val=""
          if [[ "$after" =~ $RE_INLINE ]]; then val="${BASH_REMATCH[0]}"; fi
        fi
        # nothing, an earlier run's value, or a bare type word after `:`
        if [ -z "$val" ] || [[ "$val" == "$RED"* ]]; then continue; fi
        if [ "$sep" = : ] && nocase "$val" "$RE_TYPE"; then continue; fi
        ;;
    esac
    out="$out$RED" rest="${after:${#val}}"
    count=$((count + 1))
  done
  R="$out$rest"
}

# redact_vendors: rule 3 on R, each vendor prefix but private-key and its
# token characters; a leading non-word character of the match is kept
redact_vendors() {
  local i re m lead pre
  for ((i = 0; i < ${#SECRET_VENDOR[@]}; i += 2)); do
    [ "${SECRET_VENDOR[i]}" != private-key ] || continue
    re="(${SECRET_VENDOR[i + 1]})[A-Za-z0-9_/+=.-]*"
    while [[ "$R" =~ $re ]]; do
      m="${BASH_REMATCH[0]}" lead=""
      if [[ "${m:0:1}" =~ [^A-Za-z0-9_] ]]; then lead="${m:0:1}"; fi
      pre="${R%%"$m"*}"
      R="$pre$lead$RED${R:${#pre}+${#m}}"
      count=$((count + 1))
    done
  done
}

# redact_line <line>: rules 2-4, the result in R; ML is `block` when the line
# opens a block scalar (ML_IND its indent), the quote when it opens an
# unclosed quoted value, else empty
redact_line() {
  local ind="${1%%[![:space:]]*}"
  R="$1" ML="" ML_IND="${#ind}"
  redact_keys
  redact_vendors
  if secret_line_rule "$R"; then
    R="$RED"
    count=$((count + 1))
  fi
}

# emit <line>: print it, the newline before it rather than after, so the
# last line keeps the input's final newline or its absence
emit() {
  if [ "$started" = 1 ]; then printf '\n'; fi
  printf '%s' "$1"
  started=1
}

# flush_value: the lines a multi-line value took (rule 2), as one `<redacted>`
# line at the first one's indent (left alone when that is all they were),
# then the blank lines held back after them
flush_value() {
  local l
  if [ "$v_n" = 1 ] && [ "$v_first" = "$v_ind$RED" ]; then
    emit "$v_first$v_cr"
  elif [ "$v_n" -gt 0 ]; then
    emit "$v_ind$RED$v_cr"
    count=$((count + 1))
  fi
  for l in ${v_blank[@]+"${v_blank[@]}"}; do emit "$l"; done
  ML="" v_n=0 v_blank=()
}

# take_value <line> <cr>: one more line of a multi-line value
take_value() {
  if [ "$v_n" = 0 ]; then v_ind="${1%%[![:space:]]*}" v_first="$1" v_cr="$2"; fi
  v_n=$((v_n + 1)) v_blank=()
}

cmd_redact() {
  local file="$1" dir line cr nl=1 in_block=0 pk="" i ind
  count=0 started=0 tmp="" ML="" ML_IND=0 v_n=0 v_first="" v_cr="" v_ind=""
  v_blank=()
  for ((i = 0; i < ${#SECRET_VENDOR[@]}; i += 2)); do
    if [ "${SECRET_VENDOR[i]}" = private-key ]; then pk="${SECRET_VENDOR[i + 1]}"; fi
  done
  dir="."
  case "$file" in */*) dir="${file%/*}" ;; esac
  tmp="$(mktemp "$dir/.trail-redact.XXXXXX" 2>/dev/null)" || die "can't write a temp file in $dir"
  trap 'command rm -f -- "$tmp"' EXIT
  while :; do
    if ! IFS= read -r line; then
      if [ -z "$line" ]; then
        # a multi-line value open at the end of the file ends there
        if [ -n "$ML" ]; then flush_value; fi
        break
      fi
      nl=0
    fi
    cr=""
    if [[ "$line" == *$'\r' ]]; then cr=$'\r' line="${line%$'\r'}"; fi
    if [ "$ML" = block ]; then
      # rule 2: a block scalar's value is its lines indented deeper than its
      # key line; blank lines inside it go with it, those after it are kept
      if [[ "$line" =~ ^[[:space:]]*$ ]]; then
        v_blank+=("$line$cr")
        continue
      fi
      ind="${line%%[![:space:]]*}"
      if [ "${#ind}" -gt "$ML_IND" ]; then
        take_value "$line" "$cr"
        continue
      fi
      flush_value
    elif [ -n "$ML" ]; then
      # rule 2: an unclosed quoted value runs to its closing quote (that
      # line's rest kept), or ends before a blank line or a code fence
      if [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ $RE_FENCE ]]; then
        flush_value
      elif [[ "$line" == *"$ML"* ]]; then
        v_n=0 v_blank=()
        redact_line "${line#*"$ML"}"
        emit "$RED$R$cr"
        count=$((count + 1))
        continue
      else
        take_value "$line" "$cr"
        continue
      fi
    fi
    if [ "$in_block" = 1 ]; then
      # rule 1: the block ends at its end line (part of it), or before the
      # first line that is not its body or a header (a blank line, a code
      # fence, prose: kept)
      if [[ "$line" == *-----END* ]]; then in_block=0; continue; fi
      if [[ "$line" =~ $RE_PEM ]]; then continue; fi
      in_block=0
    fi
    if [ -n "$pk" ] && [[ "$line" =~ $pk ]]; then
      emit "$RED$cr"
      count=$((count + 1))
      if [[ "$line" != *-----END* ]]; then in_block=1; fi
      continue
    fi
    redact_line "$line"
    emit "$R$cr"
  done <"$file" >"$tmp"
  if [ "$started" = 1 ] && [ "$nl" = 1 ]; then printf '\n' >>"$tmp"; fi
  # a file with nothing to redact is left as it was, byte for byte
  if [ "$count" != 0 ]; then
    command mv -f -- "$tmp" "$file" 2>/dev/null || die "can't write $file"
  else
    command rm -f -- "$tmp"
  fi
  printf '%s\n' "$count"
}

sub="${1:-}"
[ "$#" -gt 0 ] && shift
case "$sub" in
  rotate)
    [ "$#" -eq 2 ] || usage
    case "$2" in assessment | test | fix) ;; *) usage ;; esac
    need_dir "$1"
    cmd_rotate "$@"
    ;;
  sections)
    [ "$#" -eq 2 ] || usage
    case "$2" in assessment | test) ;; *) usage ;; esac
    need_file "$1"
    cmd_sections "$@"
    ;;
  slug)
    [ "$#" -eq 3 ] || [ "$#" -eq 4 ] || usage
    [ -n "$2" ] || usage "the slug is empty"
    need_dir "$1"
    cmd_slug "$@"
    ;;
  redact)
    [ "$#" -eq 1 ] || usage
    need_file "$1"
    cmd_redact "$@"
    ;;
  *) usage ;;
esac
