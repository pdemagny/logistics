#!/usr/bin/env bash
# ship.sh - the shipper's git and gh steps, in two calls over three modes.
#
#   ship.sh prepare <ship|fix|rebase> <flags>
#   ship.sh publish <ship|fix|rebase> <flags>
#
# Flags (both calls take the same set; a flag the mode does not take is a
# usage error): --worktree <dir> --default <branch> --state <file>
# --notes <file> --state-script <path> --secret-scan <path>, then by mode
# --spec-number <path>, --report <path>, --not-verified-file <path>,
# --security-bug yes|no, --branch <name>, --pr <url>, --lease <sha>,
# --check-fix <path> (repeatable) and --pr-note <line>.
#
# prepare checks the notes file, numbers the spec dir (ship mode), commits
# each notes commit by path, scans what it stages, fetches and rebases onto
# origin/<default> and writes the handoff next to the notes. publish folds
# the check fixes made between the calls, checks the spec number again,
# runs the WIP check and the range scan, builds the PR body, pushes and
# opens the PR. Rebase mode: prepare commits the --check-fix paths and the
# Log lines before its rebase and prints `Brought in:`; publish folds
# nothing, checks the --pr URL's head and repo, pushes with the lease
# (reset to it when refused) and edits the PR body under `### Rebases`.
#
# Exit 0 done (prepare prints its own output, publish the report), 1 `PR:
# blocked` or `PR: conflict` (the shipper's report, printed and written to
# --report), 2 usage error (one `ship: usage: ...` line on stderr, nothing
# done). Nothing else goes to stderr: git's and gh's are captured and only
# their first line reaches a `!` line. Nothing read is evaluated: the notes,
# the not-verified file, the state file and git and gh output are data.
#
# Bash 3.2 compatible on purpose (macOS's /bin/bash): tests/ship/run.sh
# greps it for the constructs later versions added.
set -euo pipefail
export LC_ALL=C
# pathspecs are paths, never globs or magic; no editor ever opens
export GIT_LITERAL_PATHSPECS=1 GIT_EDITOR=: GIT_TERMINAL_PROMPT=0

SYN='ship.sh <prepare|publish> <ship|fix|rebase> --worktree <dir> --default <branch> --state <file> --notes <file> --state-script <path> --secret-scan <path> [<flag> <value>]...'
usage() { printf 'ship: usage: %s\n' "$1" >&2; exit 2; }

RE_NUMBERED='^[0-9]{3,4}-'
RE_KEY='^(Commit: .+|Body:|Docs:( none)?|Summary:|Points to look at:( none)?|Not verified:( none)?)$'
RE_REPORT_KEY='^[A-Za-z0-9][A-Za-z0-9+_-]{0,63}$'
RE_HEX40='^[0-9a-f]{40}$'
# a closing keyword followed by an issue or PR reference (matched in any case)
RE_CLOSING='(^|[^A-Za-z0-9_])(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved):?[[:space:]]+(#[0-9]+|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+|https?://[^[:space:]]+/(issues|pull)/[0-9]+)'
HANDOFF=ship-handoff.md

# --- flags ----------------------------------------------------------------------

# name, then ship fix rebase: r required, o optional, x refused, m repeatable
FLAGS=(worktree rrr default rrr state rrr notes rrr state-script rrr
  secret-scan rrr spec-number rxo report ooo not-verified-file oox
  security-bug xrx branch xxr pr xxr lease xxr check-fix xxm pr-note xxr)

V_worktree='' V_default='' V_state='' V_notes='' V_state_script=''
V_secret_scan='' V_spec_number='' V_report='' V_not_verified_file=''
V_security_bug='' V_branch='' V_pr='' V_lease='' V_pr_note=''
CHECK_FIX=()

(($# >= 2)) || usage "$SYN"
CMD=$1 MODE=$2
shift 2
case $CMD in prepare | publish) ;; *) usage "$SYN" ;; esac
case $MODE in ship) MI=0 ;; fix) MI=1 ;; rebase) MI=2 ;; *) usage "$SYN" ;; esac

# flag_spec <name>: FS = its ship/fix/rebase letters, 1 when unknown
flag_spec() {
  local i
  for ((i = 0; i < ${#FLAGS[@]}; i += 2)); do
    if [[ ${FLAGS[i]} == "$1" ]]; then FS=${FLAGS[i + 1]}; return 0; fi
  done
  return 1
}

# bad_path <path>: BP = why the path is refused, 1 when it is fine
bad_path() {
  BP=''
  case $1 in
    '') BP='empty path' ;;
    /*) BP='absolute path' ;;
    -*) BP='path starts with -' ;;
    .. | ../* | */.. | */../*) BP='path has a .. component' ;;
  esac
  if [[ -z $BP && $1 == *[[:cntrl:]]* ]]; then BP='path holds a control character'; fi
  [[ -n $BP ]]
}

SEEN=' '
while (($#)); do
  a=$1
  case $a in --?*) ;; *) usage "unknown argument: $a" ;; esac
  name=${a#--}
  flag_spec "$name" || usage "unknown flag: $a"
  (($# >= 2)) || usage "$a needs a value"
  v=$2
  shift 2
  case $v in *$'\n'* | *$'\r'*) usage "$a holds a newline" ;; esac
  [[ -n $v ]] || usage "$a is empty"
  c=${FS:MI:1}
  [[ $c != x ]] || usage "$a is refused in $MODE mode"
  if [[ $c == m ]]; then
    if bad_path "$v"; then usage "$a: $BP"; fi
    CHECK_FIX+=("$v")
    continue
  fi
  [[ $SEEN != *" $name "* ]] || usage "$a given twice"
  SEEN+="$name "
  printf -v "V_${name//-/_}" '%s' "$v"
done
for ((i = 0; i < ${#FLAGS[@]}; i += 2)); do
  c=${FLAGS[i + 1]}
  c=${c:MI:1}
  if [[ $c == r && $SEEN != *" ${FLAGS[i]} "* ]]; then usage "--${FLAGS[i]} is required in $MODE mode"; fi
done

if ! [[ $V_default =~ ^[A-Za-z0-9._/-]+$ ]] || ! git check-ref-format --branch "$V_default" >/dev/null 2>&1; then
  usage "--default: not a branch name: $V_default"
fi
case $MODE:$V_security_bug in fix:yes | fix:no | ship: | rebase:) ;; *) usage '--security-bug: yes or no' ;; esac
if [[ $MODE == rebase ]]; then
  [[ $V_lease =~ ^[0-9a-f]{7,40}$ ]] || usage '--lease: 7 to 40 hex digits'
  [[ $V_pr =~ ^https://[^[:space:]]+/pull/[0-9]+$ ]] || usage '--pr: not a pull request URL'
  if ! [[ $V_branch =~ ^[A-Za-z0-9._/-]+$ ]] || ! git check-ref-format --branch "$V_branch" >/dev/null 2>&1; then
    usage "--branch: not a branch name: $V_branch"
  fi
fi

# --- worktree, branch, paths ------------------------------------------------------

cd -- "$V_worktree" 2>/dev/null || usage "--worktree: cannot enter $V_worktree"
TOP=$(pwd -P)
t=$(git rev-parse --show-toplevel 2>/dev/null) || usage "--worktree: not a git worktree: $V_worktree"
t=$(cd -- "$t" 2>/dev/null && pwd -P) || usage "--worktree: not a git worktree: $V_worktree"
[[ $t == "$TOP" ]] || usage "--worktree: not the top level of its worktree: $V_worktree"
GITDIR=$(git rev-parse --absolute-git-dir 2>/dev/null) || usage "--worktree: no git dir"

if [[ $MODE == rebase ]]; then
  BRANCH=$V_branch
  [[ $BRANCH != "$V_default" ]] || usage "the branch to push is --default ($V_default)"
  cur=$(git symbolic-ref -q --short HEAD 2>/dev/null) || cur=''
  [[ $cur == "$BRANCH" ]] || usage "--branch: $BRANCH is not the current branch"
else
  BRANCH=$(git symbolic-ref -q --short HEAD 2>/dev/null) || usage 'HEAD is detached: no branch to push'
  [[ $BRANCH != "$V_default" ]] || usage "the branch to push is --default ($V_default)"
fi

# resolve_path <path> <file|report>: RP = the path, or the same file under the
# numbered dir when the given one is missing and exactly one `<NNN>-<name>`
# holds it (a report: when the numbered dir exists); a missing numbered dir
# is read by its bare name too, so an earlier number finds the renumbered dir
resolve_path() {
  local p=$1 head rest='' base name parent c found='' count n
  if [[ $p != /* ]]; then p=$TOP/$p; fi
  RP=$p
  if [[ -e $p ]]; then return 0; fi
  head=$p
  for n in 1 2 3; do
    base=${head##*/}
    head=${head%/*}
    rest=$base${rest:+/$rest}
    if [[ -z $head || $head != */* ]]; then return 0; fi
    name=${head##*/}
    parent=${head%/*}
    if [[ -z $name || -e $head ]]; then continue; fi
    if [[ $name =~ $RE_NUMBERED ]]; then name=${name#*-}; fi
    count=0
    for c in "$parent"/[0-9][0-9][0-9]-"$name" "$parent"/[0-9][0-9][0-9][0-9]-"$name"; do
      [[ -d $c ]] || continue
      if [[ $2 == report || -e $c/$rest ]]; then found=$c; count=$((count + 1)); fi
    done
    if ((count == 1)); then RP=$found/$rest; return 0; fi
  done
}

# set_ad <dir>: the artifact dir and the names derived from it
set_ad() {
  AD=$1
  AD_REL=${AD#"$TOP"/}
  AD_NAME=${AD##*/}
  if [[ $AD_REL == */* ]]; then AD_PARENT_REL=${AD_REL%/*}/; else AD_PARENT_REL=''; fi
  AD_BARE=$AD_NAME
  if [[ $AD_NAME =~ $RE_NUMBERED ]]; then AD_BARE=${AD_NAME#*-}; fi
}

resolve_path "$V_state" file
[[ -f $RP ]] || usage "--state: no such file: $V_state"
d=$(cd -P -- "${RP%/*}" 2>/dev/null && pwd -P) || usage "--state: cannot read its dir"
[[ $d == "$TOP"/* ]] || usage "--state is not in the worktree"
set_ad "$d"
STATE_NAME=${RP##*/}

# in_reports <flag> <path> <kind>: NAME = the file's name, directly in the
# artifact dir's reports/ (physically), else a usage error
in_reports() {
  local d
  resolve_path "$2" "$3"
  d=$(cd -P -- "${RP%/*}" 2>/dev/null && pwd -P) || usage "$1 is not in $AD/reports"
  [[ $d == "$AD/reports" ]] || usage "$1 is not in $AD/reports"
  NAME=${RP##*/}
  if [[ $3 != report && ! -f $RP ]]; then usage "$1: no such file: $2"; fi
}
in_reports --notes "$V_notes" file
NOTES_NAME=$NAME
NV_NAME=''
REPORT_NAME=''
if [[ -n $V_not_verified_file ]]; then
  in_reports --not-verified-file "$V_not_verified_file" file
  NV_NAME=$NAME
fi
if [[ -n $V_report ]]; then
  in_reports --report "$V_report" report
  REPORT_NAME=$NAME
  [[ $REPORT_NAME == *.md && ${REPORT_NAME%.md} =~ $RE_REPORT_KEY ]] ||
    usage "--report: not a report name: $REPORT_NAME"
fi

# guard: the state tool's own check of reports/, its .gitignore and the files
# this script writes there; 1 with GE = its error line
guard() {
  local k
  GE=''
  for k in "${HANDOFF%.md}" ${REPORT_NAME:+"${REPORT_NAME%.md}"}; do
    if ! GE=$(bash "$V_state_script" report-path "$AD/$STATE_NAME" "$k" 2>&1); then
      GE=${GE%%$'\n'*}
      return 1
    fi
  done
  GE=''
}
guard || usage "reports: ${GE:-the state tool refused it}"

SCR=$(mktemp -d "$GITDIR/ship.XXXXXX" 2>/dev/null) || usage "cannot write in $GITDIR"
trap 'command rm -rf -- "$SCR"' EXIT

# --- the report -------------------------------------------------------------------

R_CMD=none
CONFLICTS=()
DOCS=()
NV_NOTES=()
LEFT_EXTRA=()
BASE=''
NUMBER=none
NUMBERED=0
BK_SRC=()
REWRITTEN=()
MOVED_FROM=()

first_line() {
  local l=''
  if [[ -s $1 ]]; then IFS= read -r l <"$1" || true; fi
  printf '%s' "${l:-exit $2}"
}

# number_error <rc>: the spec-number script's own `spec-number: ` line in
# $SCR/err (gh's lines may come first), else the first line
number_error() {
  local l
  if [[ -s $SCR/err ]]; then
    while IFS= read -r l; do
      if [[ $l == 'spec-number: '* ]]; then
        printf '%s' "$l"
        return 0
      fi
    done <"$SCR/err"
  fi
  first_line "$SCR/err" "$1"
}

# join <sep> <item>...: J = the items joined, or none
join() {
  local sep=$1 x
  shift
  J=''
  for x in "$@"; do J+=${J:+$sep}$x; done
  J=${J:-none}
}

# report_base: RB = the base the commits are counted from, or empty
report_base() {
  RB=$BASE
  if [[ -z $RB ]]; then RB=$(git merge-base HEAD "refs/remotes/origin/$V_default" 2>/dev/null) || RB=''; fi
}

# commit_lines: CL = `- <hash7> <subject>` lines of <base>..HEAD
commit_lines() {
  local h s
  CL=''
  report_base
  [[ -n $RB ]] || return 0
  while IFS=' ' read -r h s; do
    [[ -n $h ]] || continue
    CL+="- ${h:0:7} $s"$'\n'
  done < <(git log --reverse --format='%H %s' "$RB..HEAD" 2>/dev/null)
}

# left_list: LL = every path git status shows, then the extra ones
left_list() {
  local rec p list=()
  while IFS= read -r -d '' rec; do
    # a rename or copy: its source path follows, skipped
    if [[ ${rec:0:1} == R || ${rec:0:1} == C ]]; then IFS= read -r -d '' _ || true; fi
    list+=("${rec:3}")
  done < <(git status --porcelain -z 2>/dev/null)
  for p in ${LEFT_EXTRA[@]+"${LEFT_EXTRA[@]}"}; do list+=("$p"); done
  join ', ' ${list[@]+"${list[@]}"}
  LL=$J
}

# safe_write <path> <text>: through a temp file in the same dir and mv -f
safe_write() {
  local tmp
  if [[ -L $1 ]]; then return 1; fi
  tmp=$(mktemp "${1%/*}/.ship.XXXXXX" 2>/dev/null) || return 1
  if ! printf '%s' "$2" >"$tmp" 2>/dev/null || ! mv -f -- "$tmp" "$1" 2>/dev/null; then
    command rm -f -- "$tmp"
    return 1
  fi
}

# finish <PR value>: prints the report and writes it to --report
finish() {
  local r p wrote=() rb
  r="PR: $1"$'\n'"Command for the user: $R_CMD"$'\n'
  if ((${#CONFLICTS[@]})); then
    r+='Conflicts:'$'\n'
    for p in "${CONFLICTS[@]}"; do r+="- $p"$'\n'; done
  else
    r+='Conflicts: none'$'\n'
  fi
  commit_lines
  if [[ -n $CL ]]; then r+='Commits:'$'\n'$CL; else r+='Commits: none'$'\n'; fi
  left_list
  r+="Left uncommitted: $LL"$'\n'
  join ', ' ${DOCS[@]+"${DOCS[@]}"}
  r+="Docs updated: $J"$'\n'
  if ((NUMBERED)); then wrote+=("$AD"); fi
  rb=$RB
  for p in ${DOCS[@]+"${DOCS[@]}"}; do
    if [[ -e $TOP/$p ]] && { [[ -z $rb ]] || ! git cat-file -e "$rb:$p" 2>/dev/null; }; then wrote+=("$TOP/$p"); fi
  done
  if [[ -n $REPORT_NAME ]]; then wrote+=("$AD/reports/$REPORT_NAME"); fi
  if ((${#wrote[@]})); then
    r+='Wrote:'$'\n'
    for p in "${wrote[@]}"; do r+="- $p"$'\n'; done
  else
    r+='Wrote: none'$'\n'
  fi
  if ((${#NV_NOTES[@]})); then
    r+='Not verified:'$'\n'
    for p in "${NV_NOTES[@]}"; do r+="- $p"$'\n'; done
  else
    r+='Not verified: none'$'\n'
  fi
  if [[ -n $REPORT_NAME ]] && guard; then safe_write "$AD/reports/$REPORT_NAME" "$r" || true; fi
  printf '%s' "$r"
}

H_START=''
UNDOING=0
# undo: a blocked prepare puts the tree back as it found it (commits undone,
# index unstaged, files kept, the numbering undone from its backups); a
# blocked publish keeps its commits and only unstages
undo() {
  local i
  if [[ $CMD == publish || -z $H_START ]]; then
    git reset -q >/dev/null 2>&1 || true
    return 0
  fi
  git reset -q "$H_START" >/dev/null 2>&1 || true
  for ((i = 0; i < ${#BK_SRC[@]}; i++)); do
    command cp -f -p -- "$SCR/bk.$i" "${BK_SRC[i]}" 2>/dev/null || true
  done
  if ((${#MOVED_FROM[@]})) && [[ ! -e $TOP/${MOVED_FROM[0]} ]] && mv -- "$AD" "$TOP/${MOVED_FROM[0]}" 2>/dev/null; then
    set_ad "$TOP/${MOVED_FROM[0]}"
    NUMBERED=0
    NUMBER=none
  fi
}

# block <the ! line>: PR: blocked
block() {
  R_CMD=$1
  if ((UNDOING == 0)); then
    UNDOING=1
    undo
  fi
  finish blocked
  exit 1
}

# conflict <path>...: PR: conflict
conflict() {
  CONFLICTS=("$@")
  finish conflict
  exit 1
}

# gx <verb> <git arguments>...: git, quiet; a failure blocks on its first line
gx() {
  local verb=$1 rc=0
  shift
  git "$@" >"$SCR/out" 2>"$SCR/err" || rc=$?
  if ((rc)); then block "! git $verb: $(first_line "$SCR/err" "$rc")"; fi
}

# push_error <rc>: the reason of a failed push in $SCR/err (its first
# `error:`, ` ! [` or `remote:` line, not the `To <URL>` line), else the first
push_error() {
  local l
  if [[ -s $SCR/err ]]; then
    while IFS= read -r l; do
      case $l in
        'error:'* | ' ! ['* | 'remote:'*)
          printf '%s' "${l# }"
          return 0
          ;;
      esac
    done <"$SCR/err"
  fi
  first_line "$SCR/err" "$1"
}

# --- the secret rules, a rebase in progress -----------------------------------------

# shellcheck source=/dev/null
if ! source "$V_secret_scan" >/dev/null 2>&1 || ! declare -F secret_rule >/dev/null; then
  block "! secret scan: could not run (cannot source $V_secret_scan)"
fi
shopt -u nocasematch

if [[ -e $GITDIR/rebase-merge || -e $GITDIR/rebase-apply || -e $GITDIR/MERGE_HEAD ]]; then
  block '! ship: a rebase or merge is in progress'
fi

# --- the notes ----------------------------------------------------------------------

has_closing() {
  local r=1
  shopt -s nocasematch
  if [[ $1 =~ $RE_CLOSING ]]; then r=0; fi
  shopt -u nocasematch
  return "$r"
}

notes_err() { block "! ship: notes: $1 (line $2)"; }

# commit_lacks_path: parse_notes' commit k ended with no path (rebase mode's
# paths are --check-fix); reads parse_notes' sec and k
commit_lacks_path() { [[ $sec == paths && -z ${C_PATHS[k]} && $MODE != rebase ]]; }

# parse_notes: C_SUBJ, C_PATHS (newline-joined), C_BODY, DOCS, SUMMARY,
# POINTS, NV_NOTES; any slip blocks before anything is staged
parse_notes() {
  local f=$AD/reports/$NOTES_NAME line n=0 sec=none k=-1 once=' ' key s c_line=0 i
  C_SUBJ=() C_PATHS=() C_BODY=() C_LINE=()
  DOCS=() POINTS=() NV_NOTES=()
  SUMMARY=''
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    if [[ $line =~ $RE_KEY ]]; then
      if commit_lacks_path; then notes_err 'Commit: with no path' "$c_line"; fi
      case $line in
        'Commit: '*)
          s=${line#Commit: }
          [[ -n ${s//[[:space:]]/} ]] || notes_err 'empty subject' "$n"
          ((${#s} <= 200)) || notes_err 'subject over 200 characters' "$n"
          for ((i = 0; i <= k; i++)); do
            if [[ ${C_SUBJ[i]} == "$s" ]]; then notes_err 'duplicate subject' "$n"; fi
          done
          k=$((k + 1))
          if has_closing "$s"; then notes_err "closing keyword in commit $((k + 1))" "$n"; fi
          C_SUBJ+=("$s")
          C_PATHS+=('')
          C_BODY+=('')
          C_LINE+=("$n")
          c_line=$n
          sec=paths
          continue
          ;;
        Body:)
          if [[ $sec != paths ]] || ((k < 0)); then notes_err 'Body: outside a commit' "$n"; fi
          sec=body
          continue
          ;;
      esac
      key=${line%%:*}
      [[ $once != *" $key "* ]] || notes_err "$key: given twice" "$n"
      once+="$key "
      case $line in
        *': none') sec=nonelist ;;
        Docs:) sec=docs ;;
        Summary:) sec=summary ;;
        'Points to look at:') sec=points ;;
        'Not verified:') sec=nv ;;
      esac
      continue
    fi
    case $sec in
      summary) SUMMARY+=$line$'\n' ;;
      body)
        if has_closing "$line"; then notes_err "closing keyword in commit $((k + 1))" "$n"; fi
        C_BODY[k]+=$line$'\n'
        ;;
      *)
        if [[ -z ${line//[[:space:]]/} ]]; then continue; fi
        if [[ $line != '- '?* || $sec == none || $sec == nonelist ]]; then notes_err 'unknown key' "$n"; fi
        s=${line#- }
        case $sec in
          paths)
            if [[ $MODE == rebase ]]; then notes_err 'a commit path in rebase mode (the paths are --check-fix)' "$n"; fi
            if bad_path "$s"; then notes_err "$BP" "$n"; fi
            C_PATHS[k]+=$s$'\n'
            ;;
          docs)
            if bad_path "$s"; then notes_err "$BP" "$n"; fi
            DOCS+=("$s")
            ;;
          points) POINTS+=("$s") ;;
          nv) NV_NOTES+=("$s") ;;
        esac
        ;;
    esac
  done <"$f"
  if commit_lacks_path; then notes_err 'Commit: with no path' "$c_line"; fi
  n=$((n + 1))
  if [[ $MODE == rebase ]]; then
    if ((${#CHECK_FIX[@]})) && ((k < 0)); then notes_err 'no Commit: for the --check-fix paths' "$n"; fi
    if ((${#CHECK_FIX[@]} == 0 && k >= 0)); then notes_err 'a Commit: with no --check-fix' "${C_LINE[0]}"; fi
    if ((k > 0)); then notes_err 'more than one Commit: in rebase mode' "${C_LINE[1]}"; fi
  else
    ((k >= 0)) || notes_err 'no Commit:' "$n"
    for key in Docs Summary 'Points to look at'; do
      [[ $once == *" $key "* ]] || notes_err "no $key:" "$n"
    done
  fi
  [[ $once == *' Not verified '* ]] || notes_err 'no Not verified:' "$n"
  while [[ $SUMMARY == *$'\n'$'\n' ]]; do SUMMARY=${SUMMARY%$'\n'}; done
  for ((i = 0; i <= k; i++)); do
    s=${C_SUBJ[i]}
    if [[ -n ${C_BODY[i]} ]]; then s+=$'\n\n'${C_BODY[i]}; fi
    if secret_rule "$s"; then block "! secret scan: commit $((i + 1)) matches $SECRET_RULE"; fi
  done
  NC=$((k + 1))
}

# parse_nv_file: NV_FILE = the implementers' items
parse_nv_file() {
  local line n=0
  NV_FILE=()
  [[ -n $NV_NAME ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    if [[ -z ${line//[[:space:]]/} ]]; then continue; fi
    if [[ $line != '- '?* ]]; then block "! ship: not verified file: unknown line (line $n)"; fi
    NV_FILE+=("${line#- }")
  done <"$AD/reports/$NV_NAME"
}

# --- paths, staging, commits --------------------------------------------------------

# map_path <path>: MP = the path with the artifact dir's other names (the
# unnumbered one, an earlier number) read as its current one; empty when it
# lies in the artifact dir's reports/
map_path() {
  local p=${1%/} seg rest
  MP=$p
  if [[ $p == "$AD_PARENT_REL"* ]]; then
    rest=${p#"$AD_PARENT_REL"}
    seg=${rest%%/*}
    if [[ $seg == "$AD_BARE" || ($seg =~ $RE_NUMBERED && ${seg#*-} == "$AD_BARE") ]]; then
      MP=$AD_REL${rest#"$seg"}
    fi
  fi
  if [[ $MP == "$AD_REL/reports" || $MP == "$AD_REL/reports/"* ]]; then MP=''; fi
}

# tracked <path>: the index holds a file at or under the path
tracked() { [[ -n $(git ls-files -- "$1" 2>/dev/null) ]]; }

# stage <path>...: stages the paths that exist or are tracked, and for a path
# under the artifact dir its old name when this run moved the dir; never
# reports/. STAGED=1 when the index then differs from HEAD.
stage() {
  local p old list=()
  for p in "$@"; do
    map_path "$p"
    p=$MP
    [[ -n $p ]] || continue
    if [[ -e $p || -L $p ]] || tracked "$p"; then list+=("$p"); fi
    for old in ${MOVED_FROM[@]+"${MOVED_FROM[@]}"}; do
      if [[ $p == "$AD_REL" || $p == "$AD_REL/"* ]]; then
        if tracked "$old${p#"$AD_REL"}"; then list+=("$old${p#"$AD_REL"}"); fi
      fi
    done
  done
  if ((${#list[@]})); then gx add add -- "${list[@]}"; fi
  git reset -q -- "$AD_REL/reports" >/dev/null 2>&1 || true
  STAGED=0
  git diff --cached --quiet 2>/dev/null || STAGED=1
}

# scan <secret-scan arguments>...: the secret scan (`staged`, or `range <base>
# <head>`); a match blocks on its `<file>:<line>: <rule>`, a failure as such
scan() {
  local rc=0 l
  bash "$V_secret_scan" "$@" >"$SCR/scan" 2>"$SCR/err" || rc=$?
  case $rc in
    0) ;;
    1)
      l=$(first_line "$SCR/scan" 1)
      block "! secret scan: ${l%: *} matches ${l##*: }"
      ;;
    *) block "! secret scan: could not run ($(first_line "$SCR/err" "$rc"))" ;;
  esac
}

# subject_commit <subject> <base>: SC = the newest commit of <base>..HEAD
# with that subject, or empty
subject_commit() {
  local h s
  SC=''
  [[ -n $2 ]] || return 0
  while IFS=$'\t' read -r h s; do
    if [[ $s == "$1" ]]; then SC=$h; return 0; fi
  done < <(git log --format='%H%x09%s' "$2..HEAD" 2>/dev/null)
}

# new_commit_k <k>: commits what is staged with notes commit k's message
new_commit_k() {
  local m=$SCR/msg
  printf '%s\n' "${C_SUBJ[$1]}" >"$m"
  if [[ -n ${C_BODY[$1]} ]]; then printf '\n%s' "${C_BODY[$1]}" >>"$m"; fi
  gx commit commit -q --cleanup=whitespace -F "$m"
}

# commit_k <k> <base>: commits what is staged as notes commit k, or as a
# fixup of the commit that already has its subject
commit_k() {
  subject_commit "${C_SUBJ[$1]}" "$2"
  if [[ -n $SC ]]; then
    gx commit commit -q --fixup="$SC"
    FIXUPS=1
    return 0
  fi
  new_commit_k "$1"
}

# split_lines <text>: SL = its non-empty lines
split_lines() {
  local l
  SL=()
  while IFS= read -r l; do
    if [[ -n $l ]]; then SL+=("$l"); fi
  done <<<"$1"
}

# commit_notes <base>: each notes commit's changed paths, staged, scanned and
# committed; MADE = how many commits were made. publish records each new
# HEAD in the handoff, so a retry starts from it.
commit_notes() {
  local k
  MADE=0
  for ((k = 0; k < NC; k++)); do
    split_lines "${C_PATHS[k]}"
    ((${#SL[@]})) || continue
    stage "${SL[@]}"
    ((STAGED)) || continue
    scan staged
    commit_k "$k" "$1"
    MADE=$((MADE + 1))
    if [[ $CMD == publish ]]; then set_head; fi
  done
}

# --- numbering ----------------------------------------------------------------------

# re_quote <text>: RQ = the text as a sed ERE matching it literally
re_quote() {
  local s=$1 c i
  RQ=''
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [A-Za-z0-9/_-]) RQ+=$c ;;
      \\) RQ+=\\\\ ;;
      '^') RQ+='\^' ;;
      *) RQ+="[$c]" ;;
    esac
  done
}

# rewrite_file <file> <old> <new>: the old path, when a non-word character or
# the line's end follows it, written as the new one; a byte-exact copy kept
# first in the scratch dir; REWRITTEN gains the file when it changed
rewrite_file() {
  local f=$1 tmp rep=$3
  [[ -f $f && ! -L $f ]] || return 0
  grep -qF -- "$2" "$f" 2>/dev/null || return 0
  grep -qI '' "$f" 2>/dev/null || return 0
  command cp -p -- "$f" "$SCR/bk.${#BK_SRC[@]}" 2>/dev/null || block "! ship: cannot copy $f"
  BK_SRC+=("$f")
  REWRITTEN+=("${f#"$TOP"/}")
  re_quote "$2"
  rep=${rep//\\/\\\\}
  rep=${rep//&/\\&}
  rep=${rep//#/\\#}
  tmp=$(mktemp "${f%/*}/.ship.XXXXXX" 2>/dev/null) || block "! ship: cannot write in ${f%/*}"
  command cp -p -- "$f" "$tmp" 2>/dev/null || true
  if ! sed -E "s#$RQ([^A-Za-z0-9_.-]|\$)#$rep\\1#g" "$f" >"$tmp" 2>/dev/null || ! mv -f -- "$tmp" "$f"; then
    command rm -f -- "$tmp"
    block "! ship: cannot rewrite $f"
  fi
}

# rewrite_dir <old rel> <new rel>: the old path rewritten in the artifact
# dir's files (not reports/) and in .specify/feature.json
rewrite_dir() {
  local f
  while IFS= read -r -d '' f; do rewrite_file "$f" "$1" "$2"; done < <(find "$AD" -path "$AD/reports" -prune -o -type f -print0)
  rewrite_file "$TOP/.specify/feature.json" "$1" "$2"
}

# move_dir <new dir>: git mv (tracked files) or mv, the index back to HEAD
move_dir() {
  local new_rel=${1#"$TOP"/}
  [[ ! -e $1 ]] || block "! ship: $new_rel already exists"
  if tracked "$AD_REL"; then
    gx mv mv -- "$AD_REL" "$new_rel"
    git reset -q >/dev/null 2>&1 || true
  else
    mv -- "$AD" "$1" 2>"$SCR/err" || block "! ship: cannot move $AD_REL ($(first_line "$SCR/err" 1))"
  fi
  MOVED_FROM+=("$AD_REL")
  set_ad "$1"
}

# number_dir: an unnumbered artifact dir takes the next free number
number_dir() {
  local out rc=0 old
  if [[ $AD_NAME =~ $RE_NUMBERED ]]; then return 0; fi
  out=$(bash "$V_spec_number" next "$V_default" 2>"$SCR/err") || rc=$?
  if ((rc)); then block "! $(number_error "$rc")"; fi
  [[ $out =~ ^[0-9]{3,4}$ ]] || block "! spec-number: error: unexpected output"
  old=$AD_REL
  move_dir "$TOP/$AD_PARENT_REL$out-$AD_NAME"
  NUMBER=$out
  NUMBERED=1
  rewrite_dir "$old" "$AD_REL"
}

# --- fetch, rebase --------------------------------------------------------------

fetch_default() {
  gx fetch fetch -q origin "+refs/heads/$V_default:refs/remotes/origin/$V_default"
}

# rebase_onto <commit>: the autosquash rebase; a conflict is aborted and
# reported, an autostash that did not apply is reported as it is
rebase_onto() {
  local rc=0 u=() p
  GIT_SEQUENCE_EDITOR=: git rebase -q -i --autosquash --autostash "$1" >"$SCR/out" 2>"$SCR/err" || rc=$?
  while IFS= read -r p; do
    if [[ -n $p ]]; then u+=("$p"); fi
  done < <(git diff --name-only --diff-filter=U 2>/dev/null)
  if ((rc)); then
    if [[ -e $GITDIR/rebase-merge || -e $GITDIR/rebase-apply ]]; then
      git rebase --abort >/dev/null 2>&1 || true
      if ((${#u[@]})); then
        # rebase mode: the branch back to the PR's head, the tree kept
        if [[ $MODE == rebase ]]; then git reset -q --keep "$V_lease" >/dev/null 2>&1 || true; fi
        conflict "${u[@]}"
      fi
    fi
    block "! git rebase: $(first_line "$SCR/err" "$rc")"
  fi
  # publish records the new HEAD first, so a retry starts from it
  if [[ $CMD == publish ]]; then set_head; fi
  # the autostash did not apply: the tree holds the conflict, the stash stays
  if ((${#u[@]})); then conflict "${u[@]}"; fi
}

# --- the handoff ------------------------------------------------------------------

H_COMMITS=()
write_handoff() {
  local t s
  t="Mode: $MODE"$'\n'"Base: $BASE"$'\n'"Start: $H_START"$'\n'"Head: $H_HEAD"$'\n'
  t+="Number: $NUMBER"$'\n'"Lease: ${H_LEASE:-none}"$'\n'"Artifact dir: $AD_REL"$'\n'
  if ((${#H_COMMITS[@]})); then
    t+='Commits:'$'\n'
    for s in "${H_COMMITS[@]}"; do t+="- $s"$'\n'; done
  else
    t+='Commits: none'$'\n'
  fi
  guard || block "! ship: reports: ${GE:-the state tool refused it}"
  safe_write "$AD/reports/$HANDOFF" "$t" || block "! ship: cannot write $AD_REL/reports/$HANDOFF"
}

# set_head: the handoff's Head: is HEAD again
set_head() {
  H_HEAD=$(git rev-parse HEAD)
  write_handoff
}

read_handoff() {
  local f=$AD/reports/$HANDOFF l=() line i bad='! ship: handoff unreadable; run prepare again'
  [[ -f $f ]] || block '! ship: no handoff from prepare; nothing pushed'
  while IFS= read -r line || [[ -n $line ]]; do l+=("$line"); done <"$f"
  ((${#l[@]} >= 8)) || block "$bad"
  [[ ${l[0]} == "Mode: $MODE" ]] || block "$bad"
  BASE=${l[1]#Base: } H_START=${l[2]#Start: } H_HEAD=${l[3]#Head: }
  [[ ${l[1]} == 'Base: '* && $BASE =~ $RE_HEX40 && ${l[2]} == 'Start: '* && $H_START =~ $RE_HEX40 &&
    ${l[3]} == 'Head: '* && $H_HEAD =~ $RE_HEX40 ]] || block "$bad"
  [[ ${l[4]} =~ ^Number:\ (none|[0-9]{3,4})$ ]] || block "$bad"
  NUMBER=${l[4]#Number: }
  [[ ${l[5]} =~ ^Lease:\ (none|[0-9a-f]{7,40})$ ]] || block "$bad"
  H_LEASE=${l[5]#Lease: }
  [[ $H_LEASE != none ]] || H_LEASE=''
  [[ ${l[6]} == "Artifact dir: $AD_REL" ]] || block "$bad"
  H_COMMITS=()
  if [[ ${l[7]} == 'Commits:' ]]; then
    ((${#l[@]} > 8)) || block "$bad"
    for ((i = 8; i < ${#l[@]}; i++)); do
      [[ ${l[i]} == '- '?* ]] || block "$bad"
      H_COMMITS+=("${l[i]#- }")
    done
  else
    [[ ${l[7]} == 'Commits: none' && ${#l[@]} == 8 ]] || block "$bad"
  fi
  if [[ $NUMBER != none ]]; then NUMBERED=1; fi
  [[ $(git rev-parse HEAD) == "$H_HEAD" ]] || block '! ship: HEAD moved since prepare; nothing pushed'
}

# handoff_commits: H_COMMITS = the notes subjects with a commit in Base..HEAD,
# in the notes' order
handoff_commits() {
  local subjects k
  H_COMMITS=()
  subjects=$'\n'$(git log --format=%s "$BASE..HEAD" 2>/dev/null)$'\n'
  for ((k = 0; k < NC; k++)); do
    if [[ $subjects == *$'\n'"${C_SUBJ[k]}"$'\n'* ]]; then H_COMMITS+=("${C_SUBJ[k]}"); fi
  done
}

# --- prepare ----------------------------------------------------------------------

# brought_in <main sha>: BI = prepare's `Brought in:` lines: the commits of
# origin/<default> new since the branch's merge base, oldest first, at most 20
brought_in() {
  local old h s i=0
  BI=''
  old=$(git merge-base HEAD "$1" 2>/dev/null) || old=''
  if [[ -n $old ]]; then
    while IFS=' ' read -r h s; do
      [[ -n $h ]] || continue
      i=$((i + 1))
      if ((i <= 20)); then BI+="- ${h:0:7} $s"$'\n'; fi
    done < <(git log --reverse --format='%H %s' "$old..$1" 2>/dev/null)
  fi
  if ((i > 20)); then BI+="- … and $((i - 20)) more"$'\n'; fi
  if [[ -n $BI ]]; then BI='Brought in:'$'\n'$BI; else BI='Brought in: none'$'\n'; fi
}

# rebase_commits: rebase mode's commits before its rebase: the --check-fix
# paths with the notes' subject (never a fixup), then the Log lines
rebase_commits() {
  local out rc=0 main l
  fetch_default
  main=$(git rev-parse "refs/remotes/origin/$V_default")
  brought_in "$main"
  if ((${#CHECK_FIX[@]})); then
    stage "${CHECK_FIX[@]}"
    if ((STAGED)); then
      scan staged
      new_commit_k 0
    fi
  fi
  out=$(bash "$V_state_script" restore-phase "$AD/$STATE_NAME" 2>&1) || rc=$?
  if ((rc)); then
    l=${out%%$'\n'*}
    block "! ${l:-state.sh restore-phase: exit $rc}"
  fi
  stage "$AD_REL/$STATE_NAME"
  ((STAGED)) || return 0
  scan staged
  printf 'docs(specs): log rebase onto %s\n' "${main:0:7}" >"$SCR/msg"
  gx commit commit -q -F "$SCR/msg"
}

prepare() {
  local base n
  parse_notes
  H_START=$(git rev-parse HEAD)
  git reset -q >/dev/null 2>&1 || block '! git reset: cannot unstage'
  if [[ $MODE == rebase ]]; then
    rebase_commits
    H_LEASE=$V_lease
  else
    # fix mode never numbers its bug dir
    if [[ $MODE == ship ]]; then number_dir; fi
    base=$(git merge-base HEAD "refs/remotes/origin/$V_default" 2>/dev/null) || base=''
    commit_notes "$base"
    if ((MADE == 0)); then
      n=0
      if [[ -n $base ]]; then n=$(git rev-list --count "$base..HEAD"); fi
      ((n > 0)) || block '! ship: nothing to commit'
    fi
    fetch_default
  fi
  rebase_onto "refs/remotes/origin/$V_default"
  BASE=$(git rev-parse "refs/remotes/origin/$V_default")
  H_HEAD=$(git rev-parse HEAD)
  handoff_commits
  write_handoff
  commit_lines
  left_list
  printf 'Prepared: %s\nNotes: %s\n' "$MODE" "$AD/reports/$NOTES_NAME"
  if [[ -n $CL ]]; then printf 'Commits:\n%s' "$CL"; else printf 'Commits: none\n'; fi
  if [[ $MODE == rebase ]]; then printf '%s' "$BI"; fi
  printf 'Left uncommitted: %s\n' "$LL"
}

# --- publish ----------------------------------------------------------------------

FIXUPS=0
OUTSIDE=()
OLD_REL=''

# rewritten <path>: this run rewrote the file
rewritten() {
  local r
  for r in ${REWRITTEN[@]+"${REWRITTEN[@]}"}; do
    if [[ $r == "$1" ]]; then return 0; fi
  done
  return 1
}

# number_check: the spec number checked again; a number taken since prepare
# is renumbered in the PR's own files, with fixups
number_check() {
  local out rc=0
  # rebase mode: only with --spec-number (/feat's PRs)
  [[ $MODE == ship || ($MODE == rebase && -n $V_spec_number) ]] || return 0
  out=$(bash "$V_spec_number" check "$V_default" "$AD_NAME" 2>"$SCR/err") || rc=$?
  if ((rc)); then block "! $(number_error "$rc")"; fi
  case $out in
    'keep '*) ;;
    'renumber '*)
      [[ ${out#renumber } =~ ^[0-9]{3,4}$ ]] || block '! spec-number: error: unexpected output'
      renumber "${out#renumber }"
      ;;
    *) block '! spec-number: error: unexpected output' ;;
  esac
}

# renumber <MMM>: the dir moved, the old path rewritten in the dir, in
# .specify/feature.json and in the PR's own files, each fixed up into the
# last commit that touched it; other files naming it are listed
renumber() {
  local old=$AD_REL p diff=()
  while IFS= read -r p; do
    if [[ -n $p ]]; then diff+=("$p"); fi
  done < <(git diff --name-only "$BASE" HEAD 2>/dev/null)
  move_dir "$TOP/$AD_PARENT_REL$1-$AD_BARE"
  NUMBERED=1
  rewrite_dir "$old" "$AD_REL"
  for p in ${diff[@]+"${diff[@]}"}; do
    if [[ $p == "$old/"* || $p == .specify/feature.json ]]; then continue; fi
    rewrite_file "$TOP/$p" "$old" "$AD_REL"
  done
  fixup_renumbered "$old" ${diff[@]+"${diff[@]}"}
  set_head
  list_outside_refs "$old"
  OLD_REL=$old
}

# fixup_renumbered <old rel> <path>...: the paths of Base..HEAD this renumber
# changed (the old dir's files under both names), grouped by the last commit
# that touched them, each group committed as a fixup of that commit
fixup_renumbered() {
  local old=$1 p q t i found tgt=() tgp=() list=()
  shift
  for p in "$@"; do
    t=$(git log -1 --format=%H "$BASE..HEAD" -- "$p" 2>/dev/null) || t=''
    [[ -n $t ]] || continue
    q=$p
    if [[ $p == "$old/"* ]]; then
      if [[ $p == "$old/reports/"* ]]; then continue; fi
      q=$p$'\n'$AD_REL/${p#"$old/"}
    elif ! rewritten "$p"; then
      continue
    fi
    found=-1
    for ((i = 0; i < ${#tgt[@]}; i++)); do
      if [[ ${tgt[i]} == "$t" ]]; then found=$i; fi
    done
    if ((found < 0)); then
      tgt+=("$t")
      tgp+=("$q")
    else
      tgp[found]+=$'\n'$q
    fi
  done
  for ((i = 0; i < ${#tgt[@]}; i++)); do
    split_lines "${tgp[i]}"
    list=()
    for p in ${SL[@]+"${SL[@]}"}; do
      if [[ -e $p ]] || tracked "$p"; then list+=("$p"); fi
    done
    ((${#list[@]})) || continue
    gx add add -- "${list[@]}"
    git reset -q -- "$AD_REL/reports" >/dev/null 2>&1 || true
    if git diff --cached --quiet 2>/dev/null; then continue; fi
    scan staged
    gx commit commit -q --fixup="${tgt[i]}"
    FIXUPS=1
    set_head
  done
}

# list_outside_refs <old rel>: the files outside the artifact dir that still
# name the old path, for the PR's points and Left uncommitted
list_outside_refs() {
  local p
  while IFS= read -r p; do
    if [[ -n $p && $p != "$AD_REL/"* ]]; then
      OUTSIDE+=("$p")
      LEFT_EXTRA+=("$p")
    fi
  done < <(git grep -l -F -e "$1" 2>/dev/null || true)
}

# issue_ref: IR = the state file header's Issue: when it is an issue reference
issue_ref() {
  local line v
  IR=''
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == '## '* ]]; then break; fi
    if [[ $line == '- Issue: '* ]]; then v=${line#- Issue: }; fi
  done <"$AD/$STATE_NAME"
  v=${v:-}
  if [[ $v =~ ^#[0-9]+$ || $v =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$ || $v =~ ^https://[^[:space:]]+/issues/[0-9]+$ ]]; then IR=$v; fi
}

# gh_run <verb> <gh arguments>...: GO = its stdout; a failure blocks
gh_run() {
  local verb=$1 rc=0
  shift
  GO=$(gh "$@" 2>"$SCR/err") || rc=$?
  if ((rc)); then block "! gh $verb: $(first_line "$SCR/err" "$rc")"; fi
}

# build_body: BODY = the PR body (ship and fix mode)
build_body() {
  local b summary_out summary_rc=0 verdict verdict_rc=0 p pts nv phase=7 closing=Closes
  if [[ $MODE == fix ]]; then phase=4 closing=Fixes; fi
  b=$SUMMARY
  if [[ $MODE == fix ]]; then
    verdict=$(bash "$V_state_script" shipped-verdict "$AD/$STATE_NAME" 2>&1) || verdict_rc=$?
    verdict=${verdict%%$'\n'*}
    b+=$'\n'"**Shipped verdict:** $verdict"
    if ((verdict_rc == 0)) && [[ ${verdict%% *} != verified ]]; then b+=", shipped on the user's decision (logged)"; fi
    b+=$'\n'
  fi
  summary_out=$(bash "$V_state_script" review-summary "$AD/$STATE_NAME" "$phase" 2>&1) || summary_rc=$?
  b+=$'\n### Code review\n\n'$summary_out$'\n'
  pts=(${POINTS[@]+"${POINTS[@]}"})
  for p in ${OUTSIDE[@]+"${OUTSIDE[@]}"}; do pts+=("\`$p\` still names \`$OLD_REL\`"); done
  if ((verdict_rc)); then pts+=("$verdict"); fi
  if ((summary_rc)); then pts+=("${summary_out%%$'\n'*}"); fi
  if ((${#pts[@]})); then
    b+=$'\n### Points to look at\n\n'
    for p in "${pts[@]}"; do b+="- $p"$'\n'; done
  fi
  nv=(${NV_FILE[@]+"${NV_FILE[@]}"} ${NV_NOTES[@]+"${NV_NOTES[@]}"})
  b+=$'\n### Not verified\n\n'
  if ((${#nv[@]})); then
    for p in "${nv[@]}"; do b+="- $p"$'\n'; done
  else
    b+='none'$'\n'
  fi
  b+=$'\n'"State file: [$AD_REL/$STATE_NAME]($REPO_URL/blob/$BRANCH/$AD_REL/$STATE_NAME)"$'\n'
  issue_ref
  if [[ -n $IR ]]; then b+=$'\n'"$closing $IR"$'\n'; fi
  BODY=$b
}

# pre_push: the WIP check, then the range scan against the recorded base
pre_push() {
  local s
  while IFS= read -r s; do
    if [[ $s == logistics-wip:* ]]; then block "! WIP commit on $BRANCH; nothing pushed"; fi
  done < <(git log --format=%s "$BASE..HEAD")
  scan range "$BASE" HEAD
}

# add_note <body>: BODY = the body with --pr-note as the last line of its
# `### Rebases` section (up to the next heading of level 1 to 3), the
# heading added at the end when missing
add_note() {
  local l=() line i s=-1 last b=$1
  if [[ -n $b ]]; then
    while IFS= read -r line || [[ -n $line ]]; do l+=("$line"); done <<<"$b"
  fi
  for ((i = 0; i < ${#l[@]}; i++)); do
    if [[ ${l[i]%$'\r'} == '### Rebases' ]]; then s=$i; break; fi
  done
  BODY=''
  if ((s < 0)); then
    while [[ $b == *$'\n' ]]; do b=${b%$'\n'}; done
    if [[ -n $b ]]; then BODY=$b$'\n\n'; fi
    BODY+='### Rebases'$'\n\n'$V_pr_note$'\n'
    return 0
  fi
  last=$s
  for ((i = s + 1; i < ${#l[@]}; i++)); do
    if [[ ${l[i]} =~ ^#{1,3}[[:space:]] ]]; then break; fi
    if [[ -n ${l[i]//[[:space:]]/} ]]; then last=$i; fi
  done
  for ((i = 0; i < ${#l[@]}; i++)); do
    BODY+=${l[i]}$'\n'
    if ((i == last)); then
      if ((last == s)); then BODY+=$'\n'; fi
      BODY+=$V_pr_note$'\n'
    fi
  done
}

# lease_push: the push with the lease; refused, the branch back to the lease.
# A retry after `gh pr edit` failed finds the branch already pushed at HEAD.
lease_push() {
  local pushed head lease_sha rc=0 l
  head=$(git rev-parse HEAD)
  pushed=$(git rev-parse -q --verify "refs/remotes/origin/$BRANCH" 2>/dev/null) || pushed=''
  lease_sha=$(git rev-parse -q --verify "$V_lease^{commit}" 2>/dev/null) || lease_sha=''
  if [[ $pushed == "$head" && $head != "$lease_sha" ]]; then return 0; fi
  # an explicit destination: push.default or remote.origin.push never redirect it
  git push -q --force-with-lease="refs/heads/$BRANCH:$V_lease" origin "refs/heads/$BRANCH:refs/heads/$BRANCH" \
    >"$SCR/out" 2>"$SCR/err" || rc=$?
  ((rc)) || return 0
  if grep -qF -e '[rejected]' -e 'stale info' "$SCR/err" 2>/dev/null; then
    l="! push refused: $BRANCH moved on GitHub since ${V_lease:0:7}; nothing overwritten"
    git reset -q --keep "$V_lease" >/dev/null 2>&1 || l+="; $BRANCH left rebased locally"
    block "$l"
  fi
  block "! git push: $(push_error "$rc")"
}

# push_branch: the branch pushed to its own name on origin, upstream set
push_branch() {
  local rc=0
  # an explicit destination: push.default or remote.origin.push never redirect it
  git push -q -u origin "refs/heads/$BRANCH:refs/heads/$BRANCH" >"$SCR/out" 2>"$SCR/err" || rc=$?
  if ((rc)); then block "! git push: $(push_error "$rc")"; fi
}

# publish_rebase: rebase mode after the checks: the PR's head and repo
# checked, its body edited and scanned, the lease push, `gh pr edit`
publish_rebase() {
  local head rest url n b
  gh_run 'pr view' pr view "$V_pr" --json headRefName,url,body --jq '.headRefName, .url, .body'
  head=${GO%%$'\n'*}
  rest=''
  if [[ $GO == *$'\n'* ]]; then rest=${GO#*$'\n'}; fi
  url=${rest%%$'\n'*}
  b=''
  if [[ $rest == *$'\n'* ]]; then b=${rest#*$'\n'}; fi
  [[ $head == "$BRANCH" ]] || block "! gh pr view: PR head is not $BRANCH"
  n=${url#"$REPO_URL/pull/"}
  [[ -n $REPO_URL && $url == "$REPO_URL/pull/"* && $n =~ ^[0-9]+$ ]] || block "! gh pr view: PR is not in $REPO_URL"
  if [[ -n $OLD_REL ]]; then b=${b//"$OLD_REL"/"$AD_REL"}; fi
  add_note "$b"
  if secret_rule "$BODY"; then block "! secret scan: PR body matches $SECRET_RULE"; fi
  printf '%s' "$BODY" >"$SCR/body"
  lease_push
  gh_run 'pr edit' pr edit "$V_pr" --body-file "$SCR/body"
  finish "$V_pr"
}

# publish_ship: ship and fix mode after the checks: the PR body built and
# scanned, the push, `gh pr create`
publish_ship() {
  local title url pushed p
  title=${H_COMMITS[${#H_COMMITS[@]} - 1]}
  build_body
  if secret_rule "$BODY"; then block "! secret scan: PR body matches $SECRET_RULE"; fi
  printf '%s' "$BODY" >"$SCR/body"
  # a retry after `gh pr create` failed: the branch is already pushed at HEAD
  pushed=$(git rev-parse -q --verify "refs/remotes/origin/$BRANCH" 2>/dev/null) || pushed=''
  if [[ $pushed != "$(git rev-parse HEAD)" ]]; then push_branch; fi
  gh_run 'pr create' pr create --base "$V_default" --head "$BRANCH" --title "$title" --body-file "$SCR/body"
  url=''
  while IFS= read -r p; do
    if [[ -n $p ]]; then url=$p; fi
  done <<<"$GO"
  finish "${url:-unknown}"
}

publish() {
  local s
  read_handoff
  parse_notes
  parse_nv_file
  git reset -q >/dev/null 2>&1 || block '! git reset: cannot unstage'
  if [[ $MODE == rebase ]]; then
    # no fold step: nothing is committed after prepare in rebase mode
    [[ $H_LEASE == "$V_lease" ]] || block '! ship: handoff unreadable; run prepare again'
  else
    # the check fixes made between the calls
    commit_notes "$BASE"
  fi
  number_check
  # a fixup an earlier, blocked publish made before its autosquash
  while IFS= read -r s; do
    if [[ $s == 'fixup! '* ]]; then FIXUPS=1; fi
  done < <(git log --format=%s "$BASE..HEAD" 2>/dev/null)
  if ((FIXUPS)); then rebase_onto "$BASE"; fi
  pre_push
  if [[ $MODE != rebase ]]; then ((${#H_COMMITS[@]})) || block '! ship: nothing to commit'; fi
  gh_run 'repo view' repo view --json url --jq .url
  REPO_URL=${GO%%$'\n'*}
  if [[ $MODE == rebase ]]; then publish_rebase; else publish_ship; fi
}

if [[ $CMD == prepare ]]; then prepare; else publish; fi
