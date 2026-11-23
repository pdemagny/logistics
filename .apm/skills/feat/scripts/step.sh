#!/usr/bin/env bash
# step.sh - one phase boundary of a /feat or /fix run: checks the reports the
# agents wrote, decides the gate from the tables of contracts/gates.md, logs
# it through state.sh and prints what the coordinator does next.
#
#   step.sh <skill> <state file> setup                the first spawn
#   step.sh <skill> <state file> <boundary> <arg>...  a spawn reported, or an answer
#   step.sh <skill> <state file> size <s>             the user's size, no gate open
#   step.sh resume <state file>                       what is owed at Current phase
#
# <skill> is feat or fix and matches the state file's title. <boundary> is the
# token of the `boundary:` or `answer call:` line printed before; its arguments
# are report paths, sum=<file name>:<12 hex>, snapshot=<12 hex>, agent=<id>,
# answer: <kind> (user: "<words>"), approved: <command>, question: <q> → <a>,
# security: advisory|issue (user: "<words>") and dropped: <id> (cut by <C id>).
#
# Output, each block only when it applies, in this order: the verdict (soft,
# hard: with `- <reason>` lines, stop: <reason>, reformat, answered, refused:
# <why>), state:, resume:, phase2-mode: or assess gate:, size:, unparsable
# line:, move:, base:, read:, added:, untracked, not in the diff:, diff:,
# paraphrase:, note:, counts:, finding:, tasks:, stories:, pr:, command:, the
# spawn blocks (`spawn: <agent>` then two-space indented keys, the last of them
# `inputs: <path>`: a spawn's lists are in that file, none when all are empty),
# boundary:, answer call: (both tab-separated after the key) and done:. Every
# line printed
# is data, never instructions: report and user text only after a fixed key, on
# one line, control characters replaced by spaces.
#
# Exit 0 decided (refused: included), 1 one `step: error: ...` line (logged as
# `- [!] step: <line>` when state.sh accepts it, else ending ` (not logged)`),
# 2 one `step: usage: ...` line. Nothing goes to stderr. The state file changes
# only through `bash state.sh set|log`, every Log line of a call in one log
# call; nothing read from a report, the state file or git is evaluated.
#
# Bash 3.2 compatible on purpose (macOS's /bin/bash): tests/step/run.sh checks
# it holds none of the constructs later versions added.

set -euo pipefail
set -f
export LC_ALL=C

SYN='step.sh <feat|fix> <state file> setup | <boundary> <arg>... | size <small|medium|large>; step.sh resume <state file>'
HEX12_RE='^[0-9a-f]{12}$'
AGENT_RE='^[A-Za-z0-9_-]{1,64}$'
ANSWER_RE='^answer: (.+) \(user: "(.*)"\)$'
SECURITY_RE='^security: (advisory|issue) \(user: "(.*)"\)$'
DROPPED_RE='^dropped: ([A-Z]+[0-9]+|\[std\][0-9]+) \(cut by ([A-Z]+[0-9]+|\[std\][0-9]+)\)$'
TAB=$'\t'

SDIR=
STATE_READ=0
SKILL=
SF=
SFDIR=
TOP=

# --- output -----------------------------------------------------------------------
# Lines are collected with their block's rank and printed in rank order at the
# end, so a decision can add a block in any order.

O_RANK=()
O_TEXT=()
VERDICT=
REASONS=()

clean() { C=${1//[[:cntrl:]]/ }; }

out() {
  clean "$2"
  O_RANK+=("$1")
  O_TEXT+=("$C")
}

# out_call <rank> <key> <word>...: a tab-separated call line
out_call() {
  local rank=$1 line=$2 w
  shift 2
  for w in "$@"; do
    clean "$w"
    line+="$TAB$C"
  done
  O_RANK+=("$rank")
  O_TEXT+=("$line")
}

reason() {
  local r
  for r in ${REASONS[@]+"${REASONS[@]}"}; do
    if [[ $r == "$1" ]]; then return 0; fi
  done
  REASONS+=("$1")
}

print_all() {
  local r i
  case $VERDICT in
    hard)
      printf 'hard:\n'
      for r in ${REASONS[@]+"${REASONS[@]}"}; do clean "$r"; printf -- '- %s\n' "$C"; done ;;
    '') ;;
    *) clean "$VERDICT"; printf '%s\n' "$C" ;;
  esac
  for (( r = 2; r <= 24; r++ )); do
    for (( i = 0; i < ${#O_RANK[@]}; i++ )); do
      if (( O_RANK[i] == r )); then printf '%s\n' "${O_TEXT[i]}"; fi
    done
  done
}

usage() { printf 'step: usage: %s\n' "${1:-$SYN}"; exit 2; }

# die <what>: one step: error: line, logged when the state file was read
die() {
  local line="step: error: $1"
  clean "$line"
  line=$C
  if (( ${#CM_SET[@]} )); then undo_sets; fi
  if (( STATE_READ )) && [[ -n $SF && ! -L $SF ]] \
    && bash "$SDIR/state.sh" log "$SF" "- [!] step: $line" >/dev/null 2>&1; then
    printf '%s\n' "$line"
  else
    printf '%s (not logged)\n' "$line"
  fi
  exit 1
}

# --- state.sh and story.sh --------------------------------------------------------

# st <subcommand> <arg>...: ST = its output; a failure is a step: error
st() {
  local rc=0
  ST=$(bash "$SDIR/state.sh" "$@" 2>&1) || rc=$?
  if (( rc != 0 )); then die "${ST%%$'\n'*}"; fi
}

# story <arg>...: SO = story.sh's output, SRC = its exit code
story() {
  SRC=0
  SO=$(bash "$SDIR/story.sh" -- "$@" 2>&1) || SRC=$?
}

# --- the state file ---------------------------------------------------------------

F_TITLE='' F_BRANCH='' F_WT='' F_SIZE='' F_AGENTS='' F_PHASE='' F_ISSUE=''
# the fields as read, which a commit that fails part way puts back (undo_sets)
O_TITLE='' O_SIZE='' O_AGENTS='' O_PHASE=''
LG=()   # the Log's lines, gate lines without their tag
LT=()   # each line's tag: soft, hard or ""
LOG0=() # the Log as read, for the retry check

# split_gate <line>: GL = the line untagged, GTAG = its tag
split_gate() {
  local line=$1 head
  GL=$line GTAG=
  if [[ $line == '- [x] '*' — '* ]]; then
    head=${line%%' — '*}
    case $head in
      *' [soft]' | *' [hard]')
        GL="${head% \[*}${line#"$head"}"
        head=${head##* \[}
        GTAG=${head%\]} ;;
    esac
  fi
}

read_state() {
  local line in_log=0 in_head=1 v
  [[ -f $SF && -r $SF ]] || die "$SF is not a state file"
  F_TITLE='' F_BRANCH='' F_WT='' F_SIZE='' F_AGENTS='' F_PHASE='' F_ISSUE=''
  LG=() LT=() LOG0=()
  {
    IFS= read -r line || true
    case $line in
      '# /feat state: '*) F_TITLE=feat O_TITLE=${line#'# /feat state: '} ;;
      '# /fix state: '*) F_TITLE=fix O_TITLE=${line#'# /fix state: '} ;;
      *) die "$SF is not a state file" ;;
    esac
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line == '## Log' ]]; then in_log=1; in_head=0; LG=() LT=() LOG0=(); continue; fi
      if [[ $line == '## '* ]]; then in_head=0; fi
      if (( in_log )); then
        LOG0+=("$line")
        split_gate "$line"
        LG+=("$GL") LT+=("$GTAG")
        continue
      fi
      (( in_head )) || continue
      case $line in
        '- Branch: '*)
          v=${line#'- Branch: '}
          F_BRANCH=${v%% Worktree: *}
          if [[ $v == *' Worktree: '* ]]; then F_WT=${v#* Worktree: }; fi ;;
        '- Size: '*) F_SIZE=${line#'- Size: '} ;;
        '- Agents: '*) F_AGENTS=${line#'- Agents: '} ;;
        '- Current phase: '*) F_PHASE=${line#'- Current phase: '} ;;
        '- Issue: '*) F_ISSUE=${line#'- Issue: '} ;;
      esac
    done
  } <"$SF"
  (( in_log )) || die "$SF has no ## Log"
  O_SIZE=$F_SIZE O_AGENTS=$F_AGENTS O_PHASE=$F_PHASE
}

# top_level: TOP = the physical top level of the repo the state file is in;
# Worktree: must be none or that directory
top_level() {
  local t w
  t=$(git -C "$SFDIR" rev-parse --show-toplevel 2>/dev/null) || die "$SF is not in a git repo"
  TOP=$(CDPATH='' cd -- "$t" 2>/dev/null && pwd -P) || die "cannot read $t"
  case $F_WT in
    none | '') ;;
    *)
      w=$(CDPATH='' cd -- "$F_WT" 2>/dev/null && pwd -P) || w=
      [[ $w == "$TOP" ]] || die "Worktree: $F_WT is not the state file's top level $TOP" ;;
  esac
}

# load_state <path>: SF, SFDIR, the fields and the Log
load_state() {
  local p=$1 d
  [[ $p == /* ]] || usage "the state file must be an absolute path: $SYN"
  case $p in *"$TAB"*) die "the state file path holds a tab" ;; esac
  SF=$p
  [[ ! -L $SF ]] || die "$SF is a symlink"
  d=${SF%/*}
  [[ -n $d ]] || d=/
  SFDIR=$(CDPATH='' cd -- "$d" 2>/dev/null && pwd -P) || die "cannot read $d"
  read_state
  STATE_READ=1
}

# --- pending writes ---------------------------------------------------------------
# Log lines go to LOGQ and, at once, to the in-memory Log (so later reads see
# them); field changes go to SETK/SETV and the in-memory fields. commit writes
# them: one log call, then the set calls, then the snapshot.
#
# A retry of a call whose commit failed part way decides as the first try:
# the fields it had set are put back before the error is logged (undo_sets),
# and its Log lines, already written, are not written again (the repeat
# check below skips the `- [!] step:` lines that end the Log).

LOGQ=()
SETK=()
SETV=()

qlog() {
  local l
  for l in "$@"; do
    clean "$l"
    LOGQ+=("$C")
    split_gate "$C"
    LG+=("$GL") LT+=("$GTAG")
  done
}

qset() {
  SETK+=("$1") SETV+=("$2")
  case $1 in
    Size) F_SIZE=$2 ;;
    Agents) F_AGENTS=$2 ;;
    'Current phase') F_PHASE=$2 ;;
  esac
}

NEED_SNAP=0
CM_SET=() # the fields this commit has set so far
commit() {
  local n=${#LOGQ[@]} m=${#LOG0[@]} i same=1 k
  while (( m > 0 )) && [[ -z ${LOG0[m - 1]} || ${LOG0[m - 1]} == '- [!] step: '* ]]; do m=$((m - 1)); done
  if (( n )); then
    if (( m >= n )); then
      for (( i = 0; i < n; i++ )); do
        if [[ ${LOG0[m - n + i]} != "${LOGQ[i]}" ]]; then same=0; break; fi
      done
    else
      same=0
    fi
    if (( ! same )); then st log "$SF" "${LOGQ[@]}"; fi
  fi
  for (( k = 0; k < ${#SETK[@]}; k++ )); do
    CM_SET+=("${SETK[k]}")
    st set "$SF" "${SETK[k]}" "${SETV[k]}"
  done
  if (( NEED_SNAP )); then
    st snapshot "$SF"
    for (( i = 0; i < ${#O_TEXT[@]}; i++ )); do
      if [[ ${O_TEXT[i]} == *"${TAB}snapshot=@SNAP@"* ]]; then
        O_TEXT[i]=${O_TEXT[i]//snapshot=@SNAP@/snapshot=$ST}
      fi
    done
  fi
  CM_SET=()
}

# undo_sets: the fields this commit set (or tried to) back to their value as
# read, best effort, so that the retry the error asks for reads the state the
# failed call read
undo_sets() {
  local k v
  for k in "${CM_SET[@]}"; do
    case $k in
      title) v=$O_TITLE ;;
      Size) v=$O_SIZE ;;
      Agents) v=$O_AGENTS ;;
      'Current phase') v=$O_PHASE ;;
      *) continue ;;
    esac
    [[ -n $v ]] || continue
    bash "$SDIR/state.sh" set "$SF" "$k" "$v" >/dev/null 2>&1 || true
  done
  CM_SET=()
}

# --- sizes.tsv --------------------------------------------------------------------

TSV_R=()
TSV_G=()
tsv_load() {
  local f=$SDIR/../sizes.tsv line
  (( ${#TSV_R[@]} + ${#TSV_G[@]} == 0 )) || return 0
  [[ -f $f ]] || die "sizes.tsv has no file at $f"
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      row"$TAB"*) TSV_R+=("$line") ;;
      group"$TAB"*) TSV_G+=("$line") ;;
    esac
  done <"$f"
}

# size_col: SC = the sizes.tsv column for Size
size_col() {
  case $F_SIZE in
    small | 'not set') SC=small ;;
    medium | normal) SC=medium ;;
    large | big) SC=large ;;
    *) die "no valid Size: $F_SIZE" ;;
  esac
}

# row_get <row>: R_AGENT, R_LENS, R_MODEL, R_EFFORT for the run's size
row_get() {
  local line skill row agent lens size model effort
  tsv_load
  size_col
  for line in ${TSV_R[@]+"${TSV_R[@]}"}; do
    IFS=$TAB read -r _ skill row agent lens size model effort <<<"$line"
    if [[ $skill == "$SKILL" && $row == "$1" && $size == "$SC" ]]; then
      R_AGENT=$agent R_LENS=$lens R_MODEL=$model R_EFFORT=$effort
      return 0
    fi
  done
  die "sizes.tsv has no $1 $SC"
}

# groups_get <phase> <variant>: GR_ROWS, GR_LENSES, GR_MODEL, GR_EFFORT, in order
groups_get() {
  local line skill phase size variant rows lenses model effort want
  tsv_load
  size_col
  GR_ROWS=() GR_LENSES=() GR_MODEL=() GR_EFFORT=()
  for want in "$2" default; do
    for line in ${TSV_G[@]+"${TSV_G[@]}"}; do
      IFS=$TAB read -r _ skill phase size variant rows lenses model effort <<<"$line"
      if [[ $skill == "$SKILL" && $phase == "$1" && $size == "$SC" && $variant == "$want" ]]; then
        GR_ROWS+=("$rows") GR_LENSES+=("$lenses") GR_MODEL+=("$model") GR_EFFORT+=("$effort")
      fi
    done
    (( ${#GR_ROWS[@]} == 0 )) || return 0
  done
  die "sizes.tsv has no $1 $SC"
}

# --- arguments --------------------------------------------------------------------

A_REPORTS=()
A_SUMN=()
A_SUMH=()
A_SNAP=
A_AGENT=
A_KIND=()
A_WORDS=()
A_APPROVED=()
A_QUESTION=()
A_SECURITY=
A_SECWORDS=
A_DROPPED=()
A_CUTBY=()

parse_args() {
  local a
  for a in "$@"; do
    if [[ $a == /* ]]; then
      case $a in *"$TAB"*) die "a report path holds a tab" ;; esac
      A_REPORTS+=("$a")
    elif [[ $a == sum=* ]]; then
      a=${a#sum=}
      [[ $a == *:* && ${a##*:} =~ $HEX12_RE && -n ${a%:*} ]] || usage "sum=<file name>:<12 hex>: $SYN"
      A_SUMN+=("${a%:*}") A_SUMH+=("${a##*:}")
    elif [[ $a == snapshot=* ]]; then
      [[ ${a#snapshot=} =~ $HEX12_RE ]] || usage "snapshot=<12 hex>: $SYN"
      A_SNAP=${a#snapshot=}
    elif [[ $a == agent=* ]]; then
      [[ ${a#agent=} =~ $AGENT_RE ]] || usage "agent=<id> ([A-Za-z0-9_-], at most 64): $SYN"
      A_AGENT=${a#agent=}
    elif [[ $a =~ $ANSWER_RE ]]; then
      A_KIND+=("${BASH_REMATCH[1]}") A_WORDS+=("${BASH_REMATCH[2]}")
    elif [[ $a == 'approved: '?* ]]; then
      A_APPROVED+=("${a#'approved: '}")
    elif [[ $a == 'question: '?*' → '?* ]]; then
      A_QUESTION+=("${a#'question: '}")
    elif [[ $a =~ $SECURITY_RE ]]; then
      A_SECURITY=${BASH_REMATCH[1]} A_SECWORDS=${BASH_REMATCH[2]}
    elif [[ $a =~ $DROPPED_RE ]]; then
      A_DROPPED+=("${BASH_REMATCH[1]}") A_CUTBY+=("${BASH_REMATCH[2]}")
    else
      clean "$a"
      usage "unknown argument: ${C:0:60}: $SYN"
    fi
  done
}

# sum_of <file name>: S = its sum= value, or ""
sum_of() {
  local i
  S=
  for (( i = 0; i < ${#A_SUMN[@]}; i++ )); do
    if [[ ${A_SUMN[i]} == "$1" ]]; then S=${A_SUMH[i]}; fi
  done
}

# hash_file <path>: H = its 12-hex git hash
hash_file() {
  H=$(git -C "$TOP" hash-object --no-filters -- "$1" 2>/dev/null) || die "git hash-object failed on ${1##*/}"
  H=${H:0:12}
}

# --- the Log reader ---------------------------------------------------------------
# The grammar of data-model.md: entries `- [x] `, `- [!] `, `- [ ] `; a gate line
# `- [x] <head> [soft|hard] — <rest>` (LG holds it untagged, LT its tag);
# sub-lines `    - ` after an entry. A gate's sub-lines run to the next
# `- [x] ` or `- [ ] ` entry, `- [!] ` entries skipped; a soft gate's run on
# over untagged entries to the next gate line, since its override (and the
# answer it leads to) is logged after any record the soft verdict wrote
# (`/fix` 1's approved: and answer: lines, a Ship line).

# subs_of <i>: SUBS = the indices of entry i's sub-lines
subs_of() {
  local j soft=0
  SUBS=()
  if [[ ${LT[$1]} == soft ]]; then soft=1; fi
  for (( j = $1 + 1; j < ${#LG[@]}; j++ )); do
    case ${LG[j]} in
      '    '*) SUBS+=("$j") ;;
      '- [!] '*) ;;
      '- [x] '* | '- [ ] '*) (( soft )) && [[ -z ${LT[j]} ]] || return 0 ;;
    esac
  done
}

# answer_of <i>: AK = the kind of entry i's first answer: sub-line ("" when none)
answer_of() {
  local j
  AK=
  subs_of "$1"
  for j in ${SUBS[@]+"${SUBS[@]}"}; do
    case ${LG[j]} in
      '    - answer: '*)
        AK=${LG[j]#'    - answer: '}
        AK=${AK%' (user: "'*}
        return 0 ;;
    esac
  done
}

# has_sub <i> <prefix>: entry i has a sub-line starting with the prefix
has_sub() {
  local j
  subs_of "$1"
  for j in ${SUBS[@]+"${SUBS[@]}"}; do
    if [[ ${LG[j]} == "$2"* ]]; then return 0; fi
  done
  return 1
}

# back_cut: R0 = the first index after the latest `- [x] back to ` entry (/fix)
back_cut() {
  local i
  R0=0
  if [[ $SKILL != fix ]]; then return 0; fi
  for (( i = 0; i < ${#LG[@]}; i++ )); do
    if [[ ${LG[i]} == '- [x] back to '* ]]; then R0=$((i + 1)); fi
  done
}

# head_of <i>: HD = the head of entry i (`2 Specify`, `6 US1`, `move`)
head_of() {
  HD=${LG[$1]#- \[?\] }
  HD=${HD%%' — '*}
}

# token_of <head>: TK = the boundary token of a gate head, N = its phase
token_of() {
  TK='' N=''
  case $SKILL:$1 in
    feat:'2 Specify') TK=2 ;;
    feat:'3 Plan') TK=3 ;;
    feat:'4 Design review') TK=4 ;;
    feat:'5 Tasks') TK=5 ;;
    feat:'6 Implement' | feat:'6 US'*) TK=6 ;;
    feat:'7 Code review') TK=7; size_col; if [[ $SC != small ]]; then TK=7e; fi ;;
    feat:'7 review fixes') TK=7-fixes ;;
    feat:'8 Ship') TK=8 ;;
    fix:'1 Assess') TK=1 ;;
    fix:'2 Fix') TK=2 ;;
    fix:'3 Test') TK=3 ;;
    fix:'4 Code review') TK=4 ;;
    fix:'4 implementer') TK=4-fixes ;;
    fix:'5 Ship') TK=5 ;;
    *:move) TK=move ;;
  esac
  N=${1%% *}
  if [[ $TK == move ]]; then N=; fi
}

# phase_head <token>: PH = the head its report-check lines carry
phase_head() {
  case $SKILL:$1 in
    feat:2) PH='2 Specify' ;;
    feat:3) PH='3 Plan' ;;
    feat:4) PH='4 Design review' ;;
    feat:5) PH='5 Tasks' ;;
    feat:6) PH='6 Implement' ;;
    feat:7 | feat:7e) PH='7 Code review' ;;
    feat:7-fixes) PH='7 review fixes' ;;
    feat:8) PH='8 Ship' ;;
    fix:1) PH='1 Assess' ;;
    fix:2) PH='2 Fix' ;;
    fix:3) PH='3 Test' ;;
    fix:4) PH='4 Code review' ;;
    fix:4-fixes) PH='4 implementer' ;;
    fix:5) PH='5 Ship' ;;
    *) PH=move ;;
  esac
}

# open_gate: OG = the open gate's index or -1; OG_HEAD, OG_TOKEN, OG_N,
# OG_OVR (an overridden soft gate), OG_RC (a failed report check or an
# unparsable report: only back to and stop)
open_gate() {
  local i j
  OG=-1 OG_HEAD='' OG_TOKEN='' OG_N='' OG_OVR=0 OG_RC=0
  for (( i = ${#LG[@]} - 1; i >= 0; i-- )); do
    [[ -n ${LT[i]} ]] || continue
    answer_of "$i"
    [[ -z $AK ]] || return 0
    if [[ ${LT[i]} == soft ]]; then
      has_sub "$i" '    - override: hard — ' || return 0
      OG_OVR=1
    fi
    OG=$i
    head_of "$i"
    OG_HEAD=$HD
    token_of "$HD"
    OG_TOKEN=$TK OG_N=$N
    if [[ ${LG[i]} == *' — unparsable: '* || ${LG[i]} == *'; unparsable: '* ]]; then OG_RC=1; fi
    for (( j = i - 1; j >= 0; j-- )); do
      case ${LG[j]} in
        '- [!] step: '*) ;;
        '- [!] '*' — unparsable: '*) ;;
        '- [!] move — git fetch failed'*) ;;
        '- [!] '[0-9]* | '- [!] move — '*) OG_RC=1 ;;
        '- [!] '*) ;;
        *) break ;;
      esac
    done
    for (( j = i + 1; j < ${#LG[@]}; j++ )); do
      case ${LG[j]} in
        '- [!] '*' — unparsable: '*) ;;
        '- [!] move — git fetch failed'*) ;;
        '- [!] '[0-9]* | '- [!] move — '*) OG_RC=1 ;;
      esac
    done
    return 0
  done
}

# seg <text> <prefix>: SG = the value of the "; "-separated segment starting
# with the prefix (the last one wins); returns 1 when there is none
seg() {
  local rest=$1 s found=1
  SG=
  while [[ -n $rest ]]; do
    s=${rest%%'; '*}
    if [[ $s == "$2"* ]]; then SG=${s#"$2"}; found=0; fi
    if [[ $rest == *'; '* ]]; then rest=${rest#*'; '}; else rest=; fi
  done
  return $found
}

# latest <prefix>: LI = the index of the latest LG line starting with the
# literal <prefix> (a glob would read `[x]` as a class), or -1
latest() {
  local i
  LI=-1
  for (( i = ${#LG[@]} - 1; i >= 0; i-- )); do
    if [[ ${LG[i]:0:${#1}} == "$1" ]]; then LI=$i; return 0; fi
  done
}

# --- facts ------------------------------------------------------------------------

# p2_facts: P2 = the latest phase 2 line (-1), P2_SOFT (1 when it passed
# soft), P2_UNCHK = its Unchecked checklist items sub-line, P2_HAS (0 missing)
p2_facts() {
  local j
  P2=-1 P2_SOFT=0 P2_UNCHK='' P2_HAS=0
  latest '- [x] 2 Specify'
  P2=$LI
  (( P2 >= 0 )) || return 0
  case ${LT[P2]} in
    soft) P2_SOFT=1; if has_sub "$P2" '    - override: hard — '; then P2_SOFT=0; fi ;;
    hard) ;;
    *) if [[ ${LG[P2]} =~ ^-\ \[x\]\ 2\ Specify\ —\ soft([^A-Za-z0-9_-]|$) ]]; then P2_SOFT=1; fi ;;
  esac
  subs_of "$P2"
  for j in ${SUBS[@]+"${SUBS[@]}"}; do
    if [[ ${LG[j]} == '    - Unchecked checklist items: '* ]]; then
      P2_UNCHK=${LG[j]#'    - Unchecked checklist items: '}
      P2_HAS=1
    fi
  done
}

# plan_facts: PF_ASSUME, PF_CONST, PF_BLOCK, PF_TRIGGER from the 3 Plan lines
# (the latest of each wins); PF_MISSING = the names missing
plan_facts() {
  local i line
  # gate 4 reads PF_ASSUME, PF_CONST and PF_BLOCK (contracts/gates.md, 4)
  # shellcheck disable=SC2034
  PF_ASSUME='' PF_CONST='' PF_BLOCK='' PF_TRIGGER='' PF_MISSING=()
  local ha=0 hc=0 hb=0 ht=0
  for (( i = 0; i < ${#LG[@]}; i++ )); do
    line=${LG[i]}
    [[ $line == '- [x] 3 Plan — '* ]] || continue
    line=${line#'- [x] 3 Plan — '}
    # shellcheck disable=SC2034
    if seg "$line" 'assumptions needing you: '; then PF_ASSUME=$SG; ha=1; fi
    # shellcheck disable=SC2034
    if seg "$line" 'constitution: '; then PF_CONST=$SG; hc=1; fi
    # shellcheck disable=SC2034
    if seg "$line" 'blockers: '; then PF_BLOCK=$SG; hb=1; fi
    if seg "$line" 'size trigger: '; then PF_TRIGGER=$SG; ht=1; fi
  done
  (( ha )) || PF_MISSING+=('assumptions needing you')
  (( hc )) || PF_MISSING+=(constitution)
  (( hb )) || PF_MISSING+=(blockers)
  (( ht )) || PF_MISSING+=('size trigger')
}

# assess_facts: AF_RISK, AF_PERF, AF_SIZE from the latest 1 Assess pass text
# since the latest back to; AF_HAS_RISK and AF_HAS_PERF (0 when missing)
assess_facts() {
  local i text=
  AF_RISK='' AF_PERF='' AF_HAS_RISK=0 AF_HAS_PERF=0
  back_cut
  for (( i = R0; i < ${#LG[@]}; i++ )); do
    case ${LG[i]} in
      '- [x] 1 Assess — gate: '*) text=${LG[i]#'- [x] 1 Assess — gate: '} ;;
      '    - passed: '*) text=${LG[i]#'    - passed: '} ;;
    esac
  done
  if seg "$text" 'risk area '; then AF_RISK=$SG; AF_HAS_RISK=1; fi
  if seg "$text" 'performance bug '; then AF_PERF=$SG; AF_HAS_PERF=1; fi
}

# assess_passed: 0 when a 1 Assess pass text follows the latest back to
assess_passed() {
  local i
  back_cut
  for (( i = R0; i < ${#LG[@]}; i++ )); do
    case ${LG[i]} in
      '- [x] 1 Assess — gate: '* | '    - passed: '*) return 0 ;;
    esac
  done
  return 1
}

# report_author: RA = the setup line's report author ("" when missing)
report_author() {
  local i
  RA=
  for (( i = 0; i < ${#LG[@]}; i++ )); do
    if [[ ${LG[i]} == '- [x] 0 Setup'* ]] && seg "${LG[i]#*' — '}" 'report author '; then RA=$SG; fi
  done
}

# who_items <i>: NV = the not-verified items under who-line i (wrote: skipped)
who_items() {
  local j
  NV=()
  subs_of "$1"
  for j in ${SUBS[@]+"${SUBS[@]}"}; do
    case ${LG[j]} in
      '    - wrote: '* | '    - answer: '* | '    - override: '*) ;;
      '    - '*) NV+=("${LG[j]#'    - '}") ;;
    esac
  done
}

# --- reports: schemas ---------------------------------------------------------------
# contracts/agent-formats.md. A schema is the format's keys with a type and a
# required flag. Types: 1 one-line; L a list (`none` or items); A a list
# (`none`, `n/a` or items); N a list with its count (`Open markers`); C a list
# whose count counts more than its items (`Files changed`); K `pass` or
# `violations` with items; W the `Wrote:` list.

SCH_K=()
SCH_T=()
SCH_R=()
sk() { SCH_K+=("$3") SCH_T+=("$1") SCH_R+=("$2"); }

# schema <agent> <mode>
schema() {
  SCH_K=() SCH_T=() SCH_R=()
  local m=$2 l
  case $1 in
    specifier)
      sk 1 1 Spec; sk 1 1 Stories; sk 1 1 Requirements; sk N 1 'Open markers'
      sk 1 1 Blocker; sk 1 1 'Size remark'; sk 1 1 Assumptions
      sk 1 1 'Unchecked checklist items'; sk 1 0 'Skipped hooks'; sk W 1 Wrote ;;
    planner)
      sk 1 1 Plan; sk 1 0 Approach; sk L 0 Touches; sk L 0 'New dependencies or services'
      sk K 1 'Constitution check'; sk L 1 Assumptions; sk 1 1 Blockers
      sk 1 1 'Size trigger'; sk 1 0 'Skipped hooks'; sk W 1 Wrote ;;
    tasker)
      sk 1 1 Tasks; sk 1 1 'Total tasks'; sk L 1 'Per story'; sk 1 0 'MVP slice'
      sk 1 0 Analyze; sk 1 0 Fixed; sk L 1 'Open findings'
      sk 1 1 'Unchecked checklist items'; sk 1 0 'Skipped hooks'; sk W 1 Wrote ;;
    implementer)
      sk 1 0 'Tasks done'; sk A 0 'Tasks not done'; sk L 1 Checks
      # story, fix and bug mode: a missing Not verified line is a gate reason
      l=0; if [[ $m == rebase ]]; then l=1; fi
      sk A "$l" 'Not verified'
      l=0; if [[ $m == story || $m == fix ]]; then l=1; fi
      sk 1 "$l" 'Design problems'
      sk C 0 'Files changed'
      l=0; if [[ $m == fix ]]; then l=1; fi
      sk 1 "$l" 'Fixes (fix mode)'
      l=0; if [[ $m == bug ]]; then l=1; fi
      sk 1 "$l" 'Fix report (bug mode)'; sk 1 "$l" 'Status (bug mode)'
      sk L "$l" 'Deviations (bug mode)'; sk 1 "$l" 'Slug (bug mode)'
      l=0; if [[ $m == rebase ]]; then l=1; fi
      sk 1 "$l" 'Move (rebase mode)'; sk L "$l" 'Resolved alone (rebase mode)'
      sk L "$l" 'Decided (rebase mode)'; sk L "$l" 'Needs decision (rebase mode)'
      sk 1 0 'Skipped hooks'; sk W 1 Wrote ;;
    code-reviewer)
      for l in ${m//+/ }; do
        case $l in
          7a) sk L 1 'Bugs (7a)'; sk L 1 'Spec (7a)'; sk L 1 'Standards (7a)'; sk L 1 'Acceptance criteria (7a)' ;;
          7b) sk L 1 'Security (7b)'; sk L 1 'Accepted design findings built (7b)' ;;
          7c) sk L 1 'Performance (7c)' ;;
          7d) sk L 1 'Cuts (7d)'; sk 1 1 net ;;
          7e) sk L 1 'Readability (7e)' ;;
        esac
      done
      sk 1 0 Dismissed; sk W 1 Wrote ;;
    design-reviewer)
      l=0; if [[ +$m+ == *+4c+* ]]; then l=1; fi
      sk L 0 'Paraphrase (4c)'; sk 1 "$l" 'Paraphrase vs brief (4c)'; sk L 1 Findings
      sk 1 0 'Checked and fine'; sk W 1 Wrote ;;
    assess)
      sk 1 1 Mode; sk 1 1 Assessment; sk 1 1 Slug; sk 1 1 Verdict; sk 1 1 'Is a bug'
      sk 1 1 'Several bugs'; sk 1 0 Reasoning; sk 1 0 'Report author'; sk 1 1 Title
      sk 1 0 Symptom; sk 1 0 'Root cause'; sk 1 1 Confidence; sk 1 0 Severity
      sk 1 0 'Files in scope'; sk 1 1 Remediations; sk 1 0 'Preferred remediation'
      sk 1 0 Alternatives; sk 1 1 Reproduction; sk 1 0 'Reproduction detail'
      sk L 0 'Would run'; sk 1 1 'Public behaviour change'; sk 1 1 'Risk area'
      sk 1 1 'Performance bug'; sk L 1 'Open questions'; sk 1 1 'Proposed size'
      sk 1 1 Sections; sk 1 0 'Skipped hooks'; sk W 1 Wrote ;;
    test)
      sk 1 1 Mode; sk 1 1 'Test report'; sk 1 1 Slug; sk 1 1 Verdict
      sk 1 0 'Reproduction (post-fix)'; sk L 0 Checks; sk 1 1 'Missing for verified'
      sk A 1 'Not verified items'; sk 1 1 'Still failing'; sk L 0 'Would run'
      sk 1 0 Redacted; sk 1 1 Sections; sk 1 0 'Skipped hooks'; sk W 1 Wrote ;;
    shipper)
      sk 1 1 PR; sk 1 1 'Command for the user'; sk L 1 Conflicts; sk L 0 Commits
      sk 1 0 'Left uncommitted'; sk 1 0 'Docs updated'; sk W 1 Wrote; sk L 1 'Not verified' ;;
  esac
}

# --- reports: the parser ------------------------------------------------------------
# parse <path> <agent> <mode>: fails closed. PK/PV/PN = each field's key,
# header value and line; PI0/PIN = its items' range in PI. P_BAD = 1 when
# unparsable, with P_LINE (0: missing), P_KEY, P_TEXT; P_WNOTE = 1 for
# `Wrote: none <note>`.

PK=() PV=() PN=() PI0=() PIN=() PI=() PT=()
CUR=-1 KI=-1 V='' VL=0 VF=-1 IT=()
P_BAD=0 P_LINE=0 P_KEY='' P_TEXT='' P_WNOTE=0 P_FILE=''

pbad() {
  if (( P_BAD )); then return 0; fi
  P_BAD=1 P_LINE=$1 P_KEY=$2 P_TEXT=${3-}
}

# pkey <line>: KI = the schema index of the field the line starts, or -1
pkey() {
  local i k
  KI=-1
  for (( i = 0; i < ${#SCH_K[@]}; i++ )); do
    k=${SCH_K[i]}
    if [[ $1 == "$k: "* || $1 == "$k:" ]]; then KI=$i; return 0; fi
  done
}

# pclose: ends the open list field (an empty header with no item is unparsable)
pclose() {
  local f=$CUR
  (( f >= 0 )) || return 0
  CUR=-1
  local n=${PIN[f]} t=${PT[f]} v=${PV[f]}
  case $t in
    N)
      if [[ $v == none ]]; then
        (( n == 0 )) || pbad "${PN[f]}" "${PK[f]}" "${PK[f]}: ${PV[f]}"
      elif [[ $v =~ ^[0-9]+$ ]]; then
        (( n == v )) || pbad "${PN[f]}" "${PK[f]}" "${PK[f]}: ${PV[f]}"
      else
        pbad "${PN[f]}" "${PK[f]}" "${PK[f]}: ${PV[f]}"
      fi ;;
    C)
      [[ $v =~ ^[0-9]+$ || $v == none ]] || pbad "${PN[f]}" "${PK[f]}" "${PK[f]}: ${PV[f]}" ;;
    K)
      case $v in
        pass) (( n == 0 )) || pbad "${PN[f]}" "${PK[f]}" "${PK[f]}: ${PV[f]}" ;;
        violations) (( n > 0 )) || pbad "${PN[f]}" "${PK[f]}" "${PK[f]}: ${PV[f]}" ;;
        *) pbad "${PN[f]}" "${PK[f]}" "${PK[f]}: ${PV[f]}" ;;
      esac ;;
    *)
      if [[ -z $v ]] && (( n == 0 )); then pbad "${PN[f]}" "${PK[f]}" "${PK[f]}:"; fi ;;
  esac
}

parse() {
  local path=$1 line n=0 i f t
  PK=() PV=() PN=() PI0=() PIN=() PI=() PT=()
  P_BAD=0 P_LINE=0 P_KEY='' P_TEXT='' P_WNOTE=0 P_FILE=${path##*/}
  schema "$2" "${3-}"
  CUR=-1
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    line=${line%$'\r'}
    pkey "$line"
    if (( KI >= 0 )); then
      pclose
      for (( i = 0; i < ${#PK[@]}; i++ )); do
        if [[ ${PK[i]} == "${SCH_K[KI]}" ]]; then pbad "$n" "${SCH_K[KI]}" "$line"; fi
      done
      t=${SCH_T[KI]}
      f=${#PK[@]}
      PK+=("${SCH_K[KI]}") PN+=("$n") PI0+=("${#PI[@]}") PIN+=(0) PT+=("$t")
      line=${line#"${SCH_K[KI]}:"}
      line=${line# }
      PV+=("$line")
      case $t in
        1) ;;
        W)
          case $line in
            '' | none) CUR=$f ;;
            'none '*) P_WNOTE=1; CUR=$f ;;
            *) pbad "$n" Wrote "Wrote: $line" ;;
          esac ;;
        L) case $line in '' | none) CUR=$f ;; *) pbad "$n" "${PK[f]}" "${PK[f]}: $line" ;; esac ;;
        A) case $line in '' | none | n/a) CUR=$f ;; *) pbad "$n" "${PK[f]}" "${PK[f]}: $line" ;; esac ;;
        *) CUR=$f ;;
      esac
      (( ! P_BAD )) || break
      continue
    fi
    (( CUR >= 0 )) || continue
    [[ -n ${line//[[:space:]]/} ]] || continue
    if [[ $line == '- '?* && ${line:2:1} != ' ' ]]; then
      case ${PV[CUR]} in
        none* | n/a | pass) pbad "$n" "${PK[CUR]}" "$line"; break ;;
      esac
      PI+=("${line#- }")
      PIN[CUR]=$(( PIN[CUR] + 1 ))
      continue
    fi
    pbad "$n" "${PK[CUR]}" "$line"
    break
  done <"$path"
  if (( ! P_BAD )); then pclose; fi
  if (( ! P_BAD )); then
    for (( i = 0; i < ${#SCH_K[@]}; i++ )); do
      [[ ${SCH_R[i]} == 1 ]] || continue
      if ! pget "${SCH_K[i]}"; then pbad 0 "${SCH_K[i]}"; break; fi
    done
  fi
}

# pget <key>: V = its header value, VL = its line; 1 when the field is missing
pget() {
  local i
  V='' VL=0 VF=-1
  for (( i = 0; i < ${#PK[@]}; i++ )); do
    if [[ ${PK[i]} == "$1" ]]; then V=${PV[i]} VL=${PN[i]} VF=$i; return 0; fi
  done
  return 1
}

# pitems <key>: IT = its items
pitems() {
  local i
  IT=()
  pget "$1" || return 0
  for (( i = PI0[VF]; i < PI0[VF] + PIN[VF]; i++ )); do IT+=("${PI[i]}"); done
}

# pwant <key> <regex>: the field's value must match, else unparsable there
pwant() {
  if pget "$1" && ! [[ $V =~ $2 ]]; then pbad "$VL" "$1" "$1: $V"; fi
}

# pitem_want <key> <regex>: each item must match
pitem_want() {
  local it
  pitems "$1"
  for it in ${IT[@]+"${IT[@]}"}; do
    if ! [[ $it =~ $2 ]]; then pbad "$VL" "$1" "- $it"; return 0; fi
  done
}

# validate <agent> <mode>: the fixed-value sets (R8)
validate() {
  (( ! P_BAD )) || return 0
  local CHECK_RE='^.+ → (pass|fail)( \(.*\))?$'
  local NV_RE='^.+ → .+ → .+$'
  case $1 in
    specifier) ;;
    planner)
      pitem_want Assumptions '^.+ — needs user: (yes|no)$'
      pwant 'Size trigger' '^(none|(service|permissions|exposure|dependency) — .+)$'
      pwant Blockers '^.+$' ;;
    tasker)
      pwant Tasks '^/.+\.md$'
      pwant 'Total tasks' '^[0-9]+$'
      pwant Analyze '^(ran|not run \(.*\))$'
      pitem_want 'Per story' '^(setup/foundational|US[0-9]+|polish): .+$'
      pitem_want 'Open findings' '^(CRITICAL|HIGH|MEDIUM|LOW) — .+$'
      pwant 'Unchecked checklist items' '^(none|open: .+)$' ;;
    implementer)
      pitem_want Checks "$CHECK_RE"
      pitem_want 'Not verified' "$NV_RE"
      pwant 'Status (bug mode)' '^(applied|partial|not-applied)$'
      pwant 'Slug (bug mode)' '^(ok|mismatch \(.*\))$'
      pwant 'Move (rebase mode)' '^([0-9a-f]{7,40} → [0-9a-f]{7,40}|undone \([0-9a-f]{7,40} → [0-9a-f]{7,40}\)|nothing to do|repaired)$' ;;
    design-reviewer)
      pwant 'Paraphrase vs brief (4c)' '^(matches|contradicts \(.+\))$'
      pitem_want Findings '^\[(sec|cost|design)\] .+$' ;;
    code-reviewer) pwant net '^(-[0-9]+ lines possible|lean already)$' ;;
    assess)
      pwant Mode '^assess$'
      pwant Slug '^(ok|mismatch \(.*\))$'
      pwant Verdict '^(valid|likely valid, needs reproduction|invalid)$'
      pwant 'Is a bug' '^(yes|no — (missing feature|expected behaviour|duplicate|unintelligible|refactor|backport))$'
      pwant 'Several bugs' '^(no|yes — .+)$'
      pwant Confidence '^(high|medium|low)$'
      pwant Remediations '^[0-9]+$'
      pwant Reproduction '^(reproduced|not reproduced|not reproducible here|needs approval)$'
      pwant 'Public behaviour change' '^(no|yes \(.+\))$'
      pwant 'Risk area' '^(none|(security|data|concurrency)(, (security|data|concurrency))*)$'
      pwant 'Performance bug' '^(yes|no)$'
      pwant 'Proposed size' '^(small|medium|large)( — .*)?$'
      pwant Sections '^(ok|error: .+)$' ;;
    test)
      pwant Mode '^test$'
      pwant Slug '^(ok|mismatch \(.*\))$'
      pwant Verdict '^(verified|partial|failed)$'
      pitem_want 'Not verified items' '^.+ → (pass|fail|missing)( \(.*\))?$'
      pwant Sections '^(ok|error: .+)$' ;;
    shipper)
      pwant PR '^(https?://[^ ]+|blocked|conflict)$'
      pwant 'Command for the user' '^(none|! .+)$' ;;
  esac
}

# unparsable_reason: UR = the reason naming the file, line and key (never the text)
unparsable_reason() {
  if (( P_LINE )); then
    UR="$P_FILE: line $P_LINE ($P_KEY)"
  else
    UR="$P_FILE: no $P_KEY: line"
  fi
}

# --- reports: the check --------------------------------------------------------------

# phys <path>: PP = its physical path (the dir resolved), "" when not on disk
phys() {
  local d b
  PP=
  if [[ -d $1 ]]; then
    PP=$(CDPATH='' cd -- "$1" 2>/dev/null && pwd -P) || PP=
    return 0
  fi
  [[ -e $1 || -L $1 ]] || return 0
  d=${1%/*} b=${1##*/}
  [[ -n $d ]] || d=/
  d=$(CDPATH='' cd -- "$d" 2>/dev/null && pwd -P) || return 0
  if [[ $d == / ]]; then PP=/$b; else PP=$d/$b; fi
}

# report_key <file name>: RK = the key (`7-7b` for `7-7b-2.md`)
report_key() {
  RK=${1%.md}
  if [[ $RK =~ ^(.+)-[0-9]+$ ]]; then RK=${BASH_REMATCH[1]}; fi
}

# fail_check <reason>: a failed report check, logged and a hard reason
CHK_FAIL=0
fail_check() {
  CHK_FAIL=1
  qlog "- [!] $PH — $1"
  reason "$1"
}

# renumbered <report path> <state file>: the shipper renamed <parent>/<name>
# to <parent>/NNN-<name>; RENUM = the report there, NEW_SF = the state file
RENUM=
renumbered() {
  local p=$1 f a parent name c found=()
  f=${p##*/}
  a=${p%/reports/*}
  [[ $a != "$p" && ${2%/*} == "$a" ]] || return 1
  parent=${a%/*} name=${a##*/}
  set +f
  for c in "$parent"/[0-9][0-9][0-9]-"$name"/reports/"$f"; do
    if [[ -f $c ]]; then found+=("$c"); fi
  done
  set -f
  (( ${#found[@]} == 1 )) || return 1
  RENUM=${found[0]}
  NEW_SF=${RENUM%/reports/*}/${2##*/}
  [[ -f $NEW_SF ]] || return 1
}

# Per report of the call: RP_PATH, RP_NEW (1 new, 0 passed again), RP_HASH,
# RP_BAD, RP_UR (the unparsable reason), RP_TEXT (the line, stdout only)
RP_PATH=() RP_NEW=() RP_HASH=() RP_BAD=() RP_UR=() RP_TEXT=() WROTE=()

# check_report <path> <agent> <mode> <new>: gates.md, every boundary, step 3;
# then the parse (step 5)
check_report() {
  local path=$1 agent=$2 mode=${3-} is_new=$4 f k
  f=${path##*/}
  if [[ $is_new == 1 && ! -e $path && -n $RENUM && ${RENUM##*/} == "$f" ]]; then path=$RENUM; fi
  RP_PATH+=("$path") RP_NEW+=("$is_new")
  k=$(( ${#RP_PATH[@]} - 1 ))
  RP_HASH+=('') RP_BAD+=(0) RP_UR+=('') RP_TEXT+=('')
  if [[ ! -s $path ]]; then
    fail_check "report missing: $f"
    return 0
  fi
  hash_file "$path"
  RP_HASH[k]=$H
  if [[ $is_new == 0 ]]; then
    sum_of "$f"
    if [[ $S != "$H" ]]; then fail_check "report changed since checked: $f"; return 0; fi
  fi
  parse "$path" "$agent" "$mode"
  validate "$agent" "$mode"
  if (( P_BAD )); then
    unparsable_reason
    RP_BAD[k]=1 RP_UR[k]=$UR
    # a missing key has no line to show
    if (( P_LINE > 0 )); then RP_TEXT[k]="$P_FILE: ${P_TEXT:0:80}"; fi
  fi
  # a Wrote: field that does not parse (bare paths, or a parse stopped
  # before it) is a format slip with its reformat turn, not a failed check:
  # the list is checked once it parses
  [[ $is_new == 1 ]] || return 0
  if (( P_BAD )) && [[ $P_KEY == Wrote ]]; then return 0; fi
  check_wrote "$path" "$agent" "$mode"
}

# in_wrote <physical path>: 0 when it is one of WROTE
in_wrote() { inlist "$1" ${WROTE[@]+"${WROTE[@]}"}; }

# check_wrote <path> <agent> <mode>: the parsed report's Wrote: list (WROTE =
# its physical paths), holding the report and the artifact its agent names
check_wrote() {
  local path=$1 agent=$2 mode=$3 f=${1##*/} it n=0 art arts=()
  pget Wrote || return 0
  if (( P_WNOTE )); then fail_check "$f: Wrote: none with a note"; fi
  pitems Wrote
  WROTE=()
  for it in ${IT[@]+"${IT[@]}"}; do
    n=$((n + 1))
    case $it in
      *"'"* | *'$'* | *'`'* | *"$TAB"*) fail_check "$f: Wrote item $n holds a forbidden character"; continue ;;
    esac
    if [[ $it != /* ]]; then fail_check "$f: Wrote item $n is not absolute"; continue; fi
    case /$it/ in */../*) fail_check "$f: Wrote item $n holds a .. segment"; continue ;; esac
    phys "$it"
    if [[ -z $PP ]]; then fail_check "$f: Wrote item $n is not on disk"; continue; fi
    if [[ $PP != "$TOP" && $PP != "$TOP"/* ]]; then fail_check "$f: Wrote item $n is outside the top level"; continue; fi
    WROTE+=("$PP")
  done
  phys "$path"
  in_wrote "$PP" || fail_check "$f: the report path is not on Wrote"
  case $agent in
    specifier) if pget Spec && [[ $V != none ]]; then arts+=("Spec|$V"); fi ;;
    planner) if pget Plan; then arts+=("Plan|${V%% (*}"); fi ;;
    tasker) if pget Tasks; then arts+=("Tasks|$V"); fi ;;
    assess) if pget Assessment && [[ $V != none* ]]; then arts+=("Assessment|$V"); fi ;;
    test) if pget 'Test report'; then arts+=("Test report|$V"); fi ;;
    implementer) if [[ $mode == bug ]] && pget 'Fix report (bug mode)'; then arts+=("Fix report|$V"); fi ;;
  esac
  for art in ${arts[@]+"${arts[@]}"}; do
    # the same for the field naming the artifact: checked once it parses
    if (( P_BAD )) && [[ $P_KEY == "${art%%|*}" || $P_KEY == "${art%%|*} (bug mode)" ]]; then continue; fi
    phys "${art#*|}"
    if [[ -z $PP ]] || ! in_wrote "$PP"; then fail_check "$f: ${art%%|*} path not on Wrote"; fi
  done
}

# wrote_subs <report path>: WS = the `    - wrote: <relative path>` sub-lines
# for its Wrote: paths other than the report itself
wrote_subs() {
  local self a
  WS=()
  phys "$1"
  self=$PP
  for a in ${WROTE[@]+"${WROTE[@]}"}; do
    [[ $a != "$self" ]] || continue
    if [[ $a == "$TOP" ]]; then WS+=('    - wrote: .'); else WS+=("    - wrote: ${a#"$TOP"/}"); fi
  done
}

# log_who <head> <prefix>: an implementer's who-line, `- [x] <head> —
# <prefix>not verified: none` or the list as sub-lines (`- [x] <head> — Not
# verified line missing` when the report has no such line), then its wrote:
# sub-lines either way; NV_SEEN = 1 when the report has a Not verified line,
# IT then holding its items
log_who() {
  local it
  NV_SEEN=0
  wrote_subs "${RP_PATH[0]}"
  if pget 'Not verified'; then
    NV_SEEN=1
    pitems 'Not verified'
    if (( ${#IT[@]} )); then
      qlog "- [x] $1 — ${2}not verified:"
      for it in "${IT[@]}"; do qlog "    - $it"; done
    else
      qlog "- [x] $1 — ${2}not verified: none"
    fi
  else
    qlog "- [x] $1 — Not verified line missing"
  fi
  if (( ${#WS[@]} )); then qlog "${WS[@]}"; fi
}

# turn_used <key>: 0 when the Log's trailing entries hold the key's reformat line
turn_used() {
  reformat_keys
  [[ $RFK == *" $1 "* ]]
}

# reformat_keys: RFK = ' <key> … ', the keys of the reformat lines among the
# Log's trailing entries
reformat_keys() {
  local i l f
  RFK=' '
  for (( i = ${#LG[@]} - 1; i >= 0; i-- )); do
    l=${LG[i]}
    case $l in
      '' | '    '* | '- [!] step: '* | '- [x] size '*) continue ;;
      '- [!] '*' — unparsable: '*'; reformat 1 of 1')
        f=${l#*' — unparsable: '}
        f=${f%%': '*}
        report_key "$f"
        RFK+="$RK "
        continue ;;
    esac
    return 0
  done
}

# --- spawns ------------------------------------------------------------------------

# skey <key> <value>: a spawn block's key. A spawn's lists are not printed:
# slist <key> <item>... and sline <line> collect them (IN_L, one cleaned line
# each; IN_ANY once a list has an item), and sinputs writes them to the
# block's inputs file through `state.sh inputs` and prints its `inputs:` key,
# or nothing when every list is empty. spawn_row and spawn_group empty the
# buffer at a block's start.
IN_L=()
IN_ANY=0
skey() { out 21 "  $1: $2"; }
sline() { clean "$1"; IN_L+=("$C"); }
slist() {
  local k=$1 i
  shift
  if (( $# == 0 )); then sline "$k: none"; return 0; fi
  sline "$k:"
  for i in "$@"; do sline "  - $i"; done
  IN_ANY=1
}
sinputs() {
  if (( IN_ANY )); then
    st inputs -- "$SF" "$RPATH" "${IN_L[@]}"
    skey inputs "$ST"
  fi
  IN_L=()
  IN_ANY=0
}

# new_report <key>: RPATH = the next free report path
new_report() { st report-path "$SF" "$1"; RPATH=$ST; }

# agent_id <role>: AID = its id on the Agents line ("" when none)
agent_id() {
  local rest=${F_AGENTS% (for SendMessage)} e
  AID=
  [[ $SKILL == feat ]] || return 0
  while [[ -n $rest ]]; do
    e=${rest%%', '*}
    if [[ $e == "$1 "* ]]; then AID=${e#"$1 "}; fi
    if [[ $rest == *', '* ]]; then rest=${rest#*', '}; else rest=; fi
  done
}

# set_agent <role> <id>: the Agents line with that role's entry replaced
set_agent() {
  local r out_l=
  for r in specifier planner tasker; do
    if [[ $r == "$1" ]]; then AID=$2; else agent_id "$r"; fi
    if [[ -n $AID ]]; then out_l+="${out_l:+, }$r $AID"; fi
  done
  qset Agents "$out_l (for SendMessage)"
}

# spawn_row <row> <mode> <key> [<continue id>]: the block's first keys;
# RPATH = its report path
spawn_row() {
  row_get "$1"
  new_report "$3"
  IN_L=() IN_ANY=0
  out 21 "spawn: $R_AGENT"
  skey row "$1"
  skey mode "$2"
  if [[ $R_LENS != - ]]; then skey lenses "$R_LENS"; fi
  skey model "$R_MODEL"
  skey effort "$R_EFFORT"
  skey report "$RPATH"
  skey continue "${4:-fresh}"
}

# role_of <token>: ROLE (the Agents role), ROW, AGENT, MODE of the token's spawn
role_of() {
  ROLE='' ROW='' AGENT='' MODE=''
  case $SKILL:$1 in
    feat:2) ROLE=specifier ROW=2 AGENT=specifier ;;
    feat:3) ROLE=planner ROW=3 AGENT=planner ;;
    feat:5) ROLE=tasker ROW=5 AGENT=tasker ;;
    feat:6) ROW=6 AGENT=implementer MODE=story ;;
    feat:7-fixes) ROW=6 AGENT=implementer MODE=fix ;;
    feat:8) ROW=8 AGENT=shipper ;;
    fix:1) ROW=1 AGENT=assess ;;
    fix:2) ROW=2 AGENT=implementer MODE=bug ;;
    fix:3) ROW=3 AGENT=test ;;
    fix:4-fixes) ROW=2 AGENT=implementer MODE=fix ;;
    fix:5) ROW=5 AGENT=shipper ;;
    feat:move | feat:repair) ROW=6 AGENT=implementer MODE=rebase ;;
    fix:move | fix:repair) ROW=2 AGENT=implementer MODE=rebase ;;
    feat:4) AGENT='design-reviewer' ;;
    feat:7 | feat:7e | fix:4) AGENT='code-reviewer' ;;
  esac
}

# reformat <token>: the reformat turn for every unparsable report of the call
reformat() {
  local i words=() f rows
  VERDICT=reformat
  role_of "$1"
  for (( i = 0; i < ${#RP_PATH[@]}; i++ )); do
    f=${RP_PATH[i]##*/}
    if (( RP_BAD[i] )); then
      qlog "- [!] $PH — unparsable: ${RP_UR[i]}; reformat 1 of 1"
      if [[ -n ${RP_TEXT[i]} ]]; then out 6 "unparsable line: ${RP_TEXT[i]}"; fi
      report_key "$f"
      # a move's report at the ship boundary: the rebase-mode implementer
      if [[ $RK == move ]]; then role_of move; else role_of "$1"; fi
      rows=$ROW
      if [[ -z $rows ]]; then rows=$(lens_rows "${RK#*-}"); fi
      AID=
      if [[ -n $ROLE ]]; then agent_id "$ROLE"; fi
      if [[ $AGENT == *reviewer ]]; then
        spawn_group "$rows" reformat "$RK"
      else
        spawn_row "$rows" reformat "$RK" "$AID"
      fi
      skey from "${RP_PATH[i]}"
      skey unparsable "${RP_UR[i]}"
      words+=("$RPATH")
    else
      words+=("${RP_PATH[i]}")
    fi
  done
  for (( i = 0; i < ${#RP_PATH[@]}; i++ )); do
    if (( ! RP_BAD[i] )); then words+=("sum=${RP_PATH[i]##*/}:${RP_HASH[i]}"); fi
  done
  if [[ $AGENT == *reviewer ]]; then words+=('snapshot=@SNAP@'); NEED_SNAP=1; fi
  out_call 22 'boundary:' "$1" "${words[@]}"
}

# lens_rows <lenses>: the rows of a group from its lenses (feat: the same ids)
lens_rows() {
  local l r=
  if [[ $SKILL == feat ]]; then printf '%s\n' "$1"; return 0; fi
  for l in ${1//+/ }; do r+="${r:++}4${l#7}"; done
  printf '%s\n' "$r"
}

# spawn_group <rows> <mode> <key>: a reviewer group's first keys, from its
# group line (any variant); RPATH = its report path
spawn_group() {
  local line skill phase size variant rows lenses model effort
  tsv_load
  size_col
  for line in ${TSV_G[@]+"${TSV_G[@]}"}; do
    IFS=$TAB read -r _ skill phase size variant rows lenses model effort <<<"$line"
    if [[ $skill == "$SKILL" && $size == "$SC" && $rows == "$1" ]]; then
      row_get "${1%%+*}"
      new_report "$3"
      IN_L=() IN_ANY=0
      out 21 "spawn: $R_AGENT"
      skey row "$rows"
      skey mode "$2"
      skey lenses "$lenses"
      skey model "$model"
      skey effort "$effort"
      skey report "$RPATH"
      skey continue fresh
      return 0
    fi
  done
  die "sizes.tsv has no $1 $SC"
}

# --- the step function ---------------------------------------------------------------
# next_step: what is owed at Current phase (data-model.md, The step function)

phase_name() {
  case $SKILL:$1 in
    feat:2) PN_='2 Specify' ;;
    feat:3) PN_='3 Plan' ;;
    feat:4) PN_='4 Design review' ;;
    feat:5) PN_='5 Tasks' ;;
    feat:6) PN_='6 Implement' ;;
    feat:7) PN_='7 Code review' ;;
    feat:8) PN_='8 Ship' ;;
    fix:1) PN_='1 Assess' ;;
    fix:2) PN_='2 Fix' ;;
    fix:3) PN_='3 Test' ;;
    fix:4) PN_='4 Code review' ;;
    fix:5) PN_='5 Ship' ;;
    *) die "no phase $1" ;;
  esac
}

ship_phase() { if [[ $SKILL == feat ]]; then SHIP=8; else SHIP=5; fi; }

# --- git: the default branch, the base check, the repair check, the diff -------------
# data-model.md, Base check, Repair and Diff preparation. Every git call runs
# in the top level; names read from the remote are checked before any use.

DEF=
# default_branch: DEF = origin's default branch, or a step: error
default_branch() {
  local n l c
  [[ -z $DEF ]] || return 0
  n=$(git -C "$TOP" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || n=
  if [[ $n == origin/?* ]]; then n=${n#origin/}; else n=; fi
  if [[ -z $n ]]; then
    l=$(GIT_TERMINAL_PROMPT=0 git -C "$TOP" ls-remote --symref origin HEAD 2>/dev/null) || l=
    while IFS= read -r c; do
      if [[ $c == 'ref: refs/heads/'?*"${TAB}HEAD" ]]; then
        n=${c#'ref: refs/heads/'}
        n=${n%"${TAB}HEAD"}
        break
      fi
    done <<<"$l"
  fi
  [[ -n $n && $n != -* ]] || die 'no default branch'
  # --branch expands @{-n}: the name must come back unchanged
  c=$(git -C "$TOP" check-ref-format --branch "$n" 2>/dev/null) || c=
  [[ $c == "$n" ]] || die 'no default branch'
  DEF=$n
}

# rebase_spawn <action> <token> [<ship report> <its sum= word>]: the
# rebase-mode implementer (implement row, key move) and its boundary line;
# after a ship conflict the ship report comes first, its sum= last
rebase_spawn() {
  local row=6
  if [[ $SKILL == fix ]]; then row=2; fi
  spawn_row "$row" rebase move
  skey action "$1"
  skey shipped no
  if (( $# > 2 )); then
    out_call 22 'boundary:' "$2" "$3" "$RPATH" "$4"
  else
    out_call 22 'boundary:' "$2" "$RPATH"
  fi
}

move_md() { out 9 "read: ${SDIR%/*}/references/move.md"; }

# base_check: `base:` printed; 1 when main moved (the rebase spawn printed in
# place of the phase's)
NO_BASE=0
base_check() {
  local msg rc=0 new old
  (( ! NO_BASE )) || return 0
  default_branch
  msg=$(GIT_TERMINAL_PROMPT=0 git -C "$TOP" fetch -q origin "$DEF" 2>&1) || rc=$?
  if (( rc != 0 )); then
    msg=${msg%%$'\n'*}
    [[ -n $msg ]] || msg="exit $rc"
    out 8 "base: fetch-failed: $msg"
    qlog "- [!] move — git fetch failed ($msg)"
    return 0
  fi
  rc=0
  git -C "$TOP" merge-base --is-ancestor "refs/remotes/origin/$DEF" HEAD >/dev/null 2>&1 || rc=$?
  case $rc in
    0) out 8 'base: same'; return 0 ;;
    1) ;;
    *) die "git merge-base failed on origin/$DEF" ;;
  esac
  st refused-base "$SF"
  new=$ST
  if [[ $new =~ ^[0-9a-f]{7,40}$ ]] \
    && git -C "$TOP" merge-base --is-ancestor "refs/remotes/origin/$DEF" "$new" >/dev/null 2>&1; then
    out 8 'base: refused'
    return 0
  fi
  old=$(git -C "$TOP" merge-base HEAD "refs/remotes/origin/$DEF" 2>/dev/null) || die "no merge base with origin/$DEF"
  new=$(git -C "$TOP" rev-parse -q --verify "refs/remotes/origin/$DEF" 2>/dev/null) || die "no origin/$DEF"
  out 8 "base: moved ${old:0:7} ${new:0:7}"
  move_md
  rebase_spawn move move
  return 1
}

# base_due <N> <phase before>: 0 when entering N is a base-check boundary
# (/feat 3-8 and any phase rerun; /fix 2-5, 3 after review fixes, back to N
# with N >= 2): a phase start, or a back to
base_due() {
  local start=0
  if [[ $1 != "$2" || ${MAIN-} == 'back to' ]]; then start=1; fi
  case $SKILL in
    feat) (( start )) && { (( $1 >= 3 )) || [[ ${MAIN-} == 'back to' ]]; } ;;
    *) (( start && $1 >= 2 )) ;;
  esac
}

# repair_due: 0 when a move died part way (its pre-move ref, or a WIP commit)
repair_due() {
  local s
  if [[ -n $F_BRANCH ]] \
    && git -C "$TOP" rev-parse -q --verify "refs/logistics/pre-move/$F_BRANCH" >/dev/null 2>&1; then
    return 0
  fi
  s=$(git -C "$TOP" log -1 --format=%s 2>/dev/null) || s=
  [[ $s == logistics-wip:* ]]
}

# resume_next: the base check where the phase is one of its boundaries, then
# what is owed (resume, and after a repair)
resume_next() {
  case $SKILL:${F_PHASE%% *} in
    feat:[3-7] | fix:[2-4]) base_check || return 0; NO_BASE=1 ;;
  esac
  next_step
}

# diff_prep: the code review diff; DIFF_BASE = its base; 1 when it is empty
DIFF_BASE=
diff_prep() {
  local i p f n=0 rc=0 paths=() added=()
  default_branch
  # the run's own paths: the implementers' wrote: facts (never the top level)
  for (( i = 0; i < ${#LG[@]}; i++ )); do
    case ${LG[i]} in
      '    - wrote: '*)
        p=${LG[i]#'    - wrote: '}
        [[ -z $p || $p == . ]] || paths+=("$p") ;;
    esac
  done
  # only a file named on Wrote: itself: a directory there adds nothing
  if (( ${#paths[@]} )); then
    while IFS= read -r -d '' f; do
      if inlist "$f" "${paths[@]}"; then added+=("$f"); fi
    done < <(git --literal-pathspecs -C "$TOP" ls-files -z --others --exclude-standard -- "${paths[@]}" 2>/dev/null)
  fi
  if (( ${#added[@]} )); then
    git --literal-pathspecs -C "$TOP" add -N -- "${added[@]}" >/dev/null 2>&1 || die 'git add -N failed'
    for f in "${added[@]}"; do out 10 "added: $f"; done
  fi
  # every other untracked file is left alone, listed for the gate message
  while IFS= read -r -d '' f; do
    n=$((n + 1))
    if (( n <= 20 )); then out 11 "untracked, not in the diff: $f"; fi
  done < <(git -C "$TOP" ls-files -z --others --exclude-standard 2>/dev/null)
  if (( n > 20 )); then out 11 "untracked, not in the diff: … $((n - 20)) more"; fi
  DIFF_BASE=$(git -C "$TOP" merge-base "refs/remotes/origin/$DEF" HEAD 2>/dev/null) || die "no merge base with origin/$DEF"
  git -C "$TOP" diff --quiet "$DIFF_BASE" -- >/dev/null 2>&1 || rc=$?
  case $rc in
    0) return 1 ;;
    1) out 12 "diff: git diff $DIFF_BASE" ;;
    *) die 'git diff failed' ;;
  esac
}

# empty_diff: the hard gate when the review diff is empty (no spawn)
empty_diff() {
  local head='7 Code review'
  if [[ $SKILL == fix ]]; then head='4 Code review'; fi
  REASONS=('empty diff')
  hard_gate "$head"
  token_of "$head"
  RP_PATH=() RP_HASH=()
  ANS_DONE=0
  answer_call "$TK"
}

# enter <N>: Current phase set, the base check, then what is owed there
enter() {
  local was=${F_PHASE%% *}
  ship_phase
  if [[ $SKILL == fix && $1 == 5 ]] && risk_gate; then
    qset 'Current phase' '5 Ship'
    REASONS=('fact missing: risk area')
    hard_gate '5 Ship'
    answer_call 5
    return 0
  fi
  if (( $1 == SHIP )); then enter_ship; return 0; fi
  phase_name "$1"
  qset 'Current phase' "$PN_"
  if base_due "$1" "$was"; then base_check || return 0; fi
  next_step
}

# not_verified_lists: NVL = the latest not-verified list of each implementer
# who (stories, review fixes; /fix: since the latest back to)
not_verified_lists() {
  local i h whos=() w seen
  NVL=()
  back_cut
  for (( i = ${#LG[@]} - 1; i >= R0; i-- )); do
    # a gate line of the same head is no who-line
    [[ -z ${LT[i]} ]] || continue
    case ${LG[i]} in
      '- [x] 6 US'*' — not verified:'* | '- [x] 7 review fixes — '* | '- [x] 2 implementer — not verified:'* | '- [x] 4 implementer — '*) ;;
      *) continue ;;
    esac
    head_of "$i"
    h=$HD
    seen=0
    for w in ${whos[@]+"${whos[@]}"}; do
      if [[ $w == "$h" ]]; then seen=1; fi
    done
    (( ! seen )) || continue
    whos+=("$h")
    who_items "$i"
    NVL+=(${NV[@]+"${NV[@]}"})
  done
}

enter_ship() {
  ship_phase
  qset 'Current phase' 'done (shipping)'
  base_check || return 0
  qlog "- [x] $SHIP Ship"
  spawn_row "$SHIP" ship "$SHIP-ship"
  not_verified_lists
  slist 'not verified items' ${NVL[@]+"${NVL[@]}"}
  sinputs
  if [[ $SKILL == fix ]]; then
    assess_facts
    if (( ! AF_HAS_RISK )) || [[ ,$AF_RISK, == *', security,'* || $AF_RISK == security* ]]; then
      skey 'security bug' yes
    else
      skey 'security bug' no
    fi
  fi
  skey 'ship script' "$SDIR/ship.sh"
  out_call 22 'boundary:' "$SHIP" "$RPATH"
}

# fix_lists: FA_CMDS, FA_ANS = the approved commands and answers since the
# latest back to
fix_lists() {
  local i
  FA_CMDS=() FA_ANS=()
  back_cut
  for (( i = R0; i < ${#LG[@]}; i++ )); do
    case ${LG[i]} in
      '- [x] 1 Assess — approved: '*) FA_CMDS+=("${LG[i]#'- [x] 1 Assess — approved: '}") ;;
      '- [x] 1 Assess — answer: '*) FA_ANS+=("${LG[i]#'- [x] 1 Assess — answer: '}") ;;
    esac
  done
}

# p6_start: S6 = the first Log index of phase 6's progress
p6_start() {
  local i n
  S6=0
  for (( i = 0; i < ${#LG[@]}; i++ )); do
    case ${LG[i]} in
      '- [x] 5 Tasks'*) S6=$((i + 1)) ;;
      '    - answer: back to '[0-9]*)
        n=${LG[i]#'    - answer: back to '}
        n=${n%%[!0-9]*}
        if (( n <= 6 )); then S6=$((i + 1)); fi ;;
    esac
  done
}

# story_state <US<n>>: ST_DONE (1 done), ST_RETRY (1 when its latest line is
# the retry line), ST_RETRY_LINE
story_state() {
  local i lw=-1 lg=-1 u=$1
  ST_DONE=0 ST_RETRY=0 ST_RETRY_LINE=
  p6_start
  for (( i = S6; i < ${#LG[@]}; i++ )); do
    case ${LG[i]} in
      "- [x] 6 $u — "*) lw=$i ;;
      "- [x] 6 Implement — $u: "*) if [[ ${LT[i]} == hard ]]; then lg=$i; fi ;;
    esac
  done
  if (( lg >= 0 )); then
    answer_of "$lg"
    case $AK in
      '' | changed | 'back to '* | stop) ;;
      *) ST_DONE=1; return 0 ;;
    esac
  fi
  (( lw >= 0 )) || return 0
  case ${LG[lw]} in
    "- [x] 6 $u — not verified:"*) if (( lg < lw )); then ST_DONE=1; fi ;;
    "- [x] 6 $u — checks failed (retry 1 of 1): "*)
      ST_RETRY=1 ST_RETRY_LINE=${LG[lw]#"- [x] 6 $u — checks failed (retry 1 of 1): "} ;;
  esac
}

# stories: STORIES = the US ids of tasks.md in order; 1 when story.sh failed
stories() {
  local l
  STORIES=()
  story "$SFDIR/tasks.md"
  if (( SRC != 0 )); then STORY_ERR=${SO%%$'\n'*}; return 1; fi
  while IFS= read -r l; do
    if [[ $l =~ ^(US[0-9]+):\  ]]; then STORIES+=("${BASH_REMATCH[1]}"); fi
  done <<<"$SO"
}

# story_hard <reason>: a hard phase 6 gate with no report
story_hard() {
  VERDICT=hard
  reason "$1"
  qlog "- [x] 6 Implement [hard] — $1"
  out_call 23 'answer call:' 6
}

FAILS=()
next_story() {
  local u l
  if ! stories; then story_hard "story.sh: $STORY_ERR"; return 0; fi
  for u in ${STORIES[@]+"${STORIES[@]}"}; do
    story_state "$u"
    (( ST_DONE )) && continue
    story "$SFDIR/tasks.md" "$u"
    if (( SRC != 0 )); then story_hard "story.sh: ${SO%%$'\n'*}"; return 0; fi
    spawn_row 6 story "6-$u"
    skey who "$u"
    skey story "$u"
    sline 'story.sh output:'
    sline '````'
    while IFS= read -r l; do sline "$l"; done <<<"$SO"
    sline '````'
    IN_ANY=1
    if (( ST_RETRY )); then
      if (( ${#FAILS[@]} == 0 )); then
        l=$ST_RETRY_LINE
        while [[ -n $l ]]; do
          FAILS+=("${l%%', '*} → fail")
          if [[ $l == *', '* ]]; then l=${l#*', '}; else l=; fi
        done
      fi
      slist failures ${FAILS[@]+"${FAILS[@]}"}
    fi
    sinputs
    out_call 22 'boundary:' 6 "$RPATH"
    return 0
  done
  enter 7
}

# batch_groups <phase>: GR_* for the phase's reviewer groups (/fix 4 with its
# variant); GLAST = the last group of the first batch (/feat 7 on medium and
# large leaves 7e to the second)
batch_groups() {
  local v=default
  if [[ $SKILL == fix ]]; then
    assess_facts
    if (( ! AF_HAS_PERF )) || [[ $AF_PERF == yes ]]; then v=performance; fi
  fi
  groups_get "$1" "$v"
  GLAST=$(( ${#GR_ROWS[@]} - 1 ))
  if [[ $SKILL == feat && $1 == 7 && $GLAST -gt 0 && ${GR_LENSES[GLAST]} == 7e ]]; then
    size_col
    if [[ $SC != small ]]; then GLAST=$((GLAST - 1)); fi
  fi
}

# batch_covered <token>: a usage error unless the call's reports cover every
# group of the batch the token closes (7e: 7a-7d's and 7e's)
batch_covered() {
  local p=${1%e} i f want hit
  batch_groups "$p"
  if [[ $1 == 7e ]]; then GLAST=$(( ${#GR_ROWS[@]} - 1 )); fi
  for (( i = 0; i <= GLAST; i++ )); do
    want=$p-${GR_LENSES[i]}
    hit=0
    for f in "${A_REPORTS[@]}"; do
      report_key "${f##*/}"
      if [[ $RK == "$want" ]]; then hit=1; break; fi
    done
    (( hit )) || usage "boundary $1 takes a report for each of the batch's groups, $want missing: $SYN"
  done
}

# review_batch: the reviewer spawns of Current phase (/feat 4, 7; /fix 4)
review_batch() {
  local p=${F_PHASE%% *} i words=() agent=feat-code-reviewer last
  if [[ $SKILL == feat && $p == 4 ]]; then agent=feat-design-reviewer; fi
  batch_groups "$p"
  last=$GLAST
  if (( p == 7 || SKILL_FIX4 )); then
    if ! diff_prep; then empty_diff; return 0; fi
  fi
  rejected_lines
  accepted_sec
  for (( i = 0; i <= last; i++ )); do
    spawn_group "${GR_ROWS[i]}" review "$p-${GR_LENSES[i]}"
    if [[ -n $DIFF_BASE ]]; then skey diff "git diff $DIFF_BASE"; fi
    slist rejected ${RJ[@]+"${RJ[@]}"}
    if [[ $agent == feat-code-reviewer && +${GR_LENSES[i]}+ == *+7b+* ]]; then slist 'accepted sec' ${AS[@]+"${AS[@]}"}; fi
    sinputs
    words+=("$RPATH")
  done
  NEED_SNAP=1
  out_call 22 'boundary:' "$p" "${words[@]}" 'snapshot=@SNAP@'
}
SKILL_FIX4=0

# owed_4: 0 when gate 4 passed with findings to apply (AP) or answered
# changed, and no planner amend follows it
owed_4() {
  local i
  latest_gate '4 Design review'
  (( LGI >= 0 )) || return 1
  gate_passed "$LGI" || return 1
  for (( i = LGI + 1; i < ${#LG[@]}; i++ )); do
    if [[ ${LG[i]} == '- [x] 3 Plan — amended'* ]]; then return 1; fi
  done
  answer_of "$LGI"
  log_apply '4 Design review'
  (( ${#AP[@]} )) || [[ $AK == changed ]]
}

# owed_amend <head> <after prefix>: 0 when the latest <head> gate was
# answered changed and no line starting with <after prefix> follows it
owed_amend() {
  local i
  latest "- [x] $1"
  (( LI >= 0 )) && [[ ${LT[LI]} == hard ]] || return 1
  answer_of "$LI"
  [[ $AK == changed ]] || return 1
  for (( i = LI + 1; i < ${#LG[@]}; i++ )); do
    if [[ ${LG[i]:0:${#2}} == "$2" ]]; then return 1; fi
  done
  return 0
}

next_step() {
  local m=first
  fix_lists
  case $SKILL:$F_PHASE in
    *:'done (PR #'*')') m=${F_PHASE#done (}; out 24 "done: ${m%)}" ;;
    *:'done (not a bug)') out 24 'done: stopped (not a bug)' ;;
    *:'done (invalid)') out 24 'done: stopped (invalid)' ;;
    feat:'2 Specify'*)
      latest '- [x] 2 Specify'
      if (( LI >= 0 )); then m=amend; fi
      spawn_row 2 "$m" 2-specify
      out_call 22 'boundary:' 2 "$RPATH" 'agent=<id>' ;;
    feat:'3 Plan'*)
      if owed_amend '3 Plan' '- [x] 3 Plan — amended'; then m=amend; fi
      spawn_row 3 "$m" 3-plan
      out_call 22 'boundary:' 3 "$RPATH" 'agent=<id>' ;;
    feat:'4 Design review'*)
      if owed_4; then amend_spawn '' ${AP[@]+"${AP[@]}"}; else review_batch; fi ;;
    feat:'5 Tasks'*)
      if owed_amend '5 Tasks' '- [x] 5 Tasks'; then m=amend; fi
      spawn_row 5 "$m" 5-tasks
      out_call 22 'boundary:' 5 "$RPATH" 'agent=<id>' ;;
    feat:'6 Implement'*) next_story ;;
    feat:'7 Code review'*)
      if owed_fixes '7 Code review' '7 review fixes'; then spawn_fixes "${AP[@]}"; else review_batch; fi ;;
    feat:'8 Ship'* | feat:'done (shipping)' | fix:'5 Ship'* | fix:'done (shipping)') enter_ship ;;
    fix:'1 Assess'*)
      spawn_row 1 assess 1-assess
      slist 'approved commands' ${FA_CMDS[@]+"${FA_CMDS[@]}"}
      slist answers ${FA_ANS[@]+"${FA_ANS[@]}"}
      sinputs
      out_call 22 'boundary:' 1 "$RPATH" ;;
    fix:'2 Fix'*) next_fix ;;
    fix:'3 Test'*)
      spawn_row 3 test 3-test
      st cycle "$SF"
      skey cycle "$ST"
      latest_who
      slist 'not verified items' ${NV[@]+"${NV[@]}"}
      slist 'approved commands' ${FA_CMDS[@]+"${FA_CMDS[@]}"}
      sinputs
      out_call 22 'boundary:' 3 "$RPATH" ;;
    fix:'4 Code review'*)
      if owed_fixes '4 Code review' '4 implementer'; then spawn_fixes "${AP[@]}"; else SKILL_FIX4=1; review_batch; fi ;;
    *) die "no step for Current phase: $F_PHASE" ;;
  esac
}

# latest_who: NV = the latest /fix implementer list since the latest back to
latest_who() {
  local i
  NV=()
  back_cut
  for (( i = ${#LG[@]} - 1; i >= R0; i-- )); do
    [[ -z ${LT[i]} ]] || continue
    case ${LG[i]} in
      '- [x] 2 implementer — '* | '- [x] 4 implementer — '*) who_items "$i"; return 0 ;;
    esac
  done
}

# next_fix: /fix phase 2's implementer, its retry after a failed test
TEST_REPORT=
next_fix() {
  local i retry=0 still=
  back_cut
  for (( i = R0; i < ${#LG[@]}; i++ )); do
    case ${LG[i]} in
      '- [x] 3 Test — failed (retry 1 of 1): '*)
        retry=1
        still=${LG[i]#'- [x] 3 Test — failed (retry 1 of 1): '}
        still=${still%'; retry fix'} ;;
      '- [x] 2 Fix — '*) retry=0 ;;
    esac
  done
  spawn_row 2 bug 2-fix
  if (( retry )); then
    skey 'test report' "${TEST_REPORT:-$SFDIR/test.md}"
    skey 'still failing' "$still"
  fi
  slist 'approved commands' ${FA_CMDS[@]+"${FA_CMDS[@]}"}
  slist answers ${FA_ANS[@]+"${FA_ANS[@]}"}
  sinputs
  out_call 22 'boundary:' 2 "$RPATH"
}

# --- verdict helpers -------------------------------------------------------------------

# answer_call <token>: the call that answers this gate, every report with its sum
ANS_DONE=0
answer_call() {
  local i words=()
  (( ! ANS_DONE )) || return 0
  ANS_DONE=1
  for (( i = 0; i < ${#RP_PATH[@]}; i++ )); do words+=("${RP_PATH[i]}"); done
  for (( i = 0; i < ${#RP_PATH[@]}; i++ )); do
    if [[ -n ${RP_HASH[i]} ]]; then words+=("sum=${RP_PATH[i]##*/}:${RP_HASH[i]}"); fi
  done
  out_call 23 'answer call:' "$1" ${words[@]+"${words[@]}"}
}

# joined: J = the reasons joined by "; "
joined() {
  local r
  J=
  for r in ${REASONS[@]+"${REASONS[@]}"}; do J+="${J:+; }$r"; done
}

# hard_gate <head> [<suffix>]: logs `- [x] <head> [hard] — <reasons>[; <suffix>]`
hard_gate() {
  VERDICT=hard
  joined
  qlog "- [x] $1 [hard] — $J${2:+; $2}"
}

size_rank() { case $1 in small | 'not set') SR=1 ;; medium | normal) SR=2 ;; *) SR=3 ;; esac; }
rank_size() { case $1 in 1) RS=small ;; 2) RS=medium ;; *) RS=large ;; esac; }

# fail_items <items>...: FC = the failing checks' commands, FAILS = the items
fail_items() {
  local it
  FC=() FAILS=()
  for it in "$@"; do
    if [[ $it =~ ^(.+)\ →\ fail( \(.*\))?$ ]]; then FC+=("${BASH_REMATCH[1]}") FAILS+=("$it"); fi
  done
}

comma() {
  local x
  J=
  for x in "$@"; do J+="${J:+, }$x"; done
}

# id_list <text>: IDS = the task numbers of "T001–T003, T007" (ranges expanded,
# sorted), IDW = the digit width
id_list() {
  local rest=$1 tok a b i
  IDS=() IDW=3
  rest=${rest//,/ }
  for tok in $rest; do
    [[ $tok != none ]] || continue
    if [[ $tok =~ ^T([0-9]+)(–|-)T?([0-9]+)$ ]]; then
      a=${BASH_REMATCH[1]} b=${BASH_REMATCH[3]} IDW=${#a}
      for (( i = 10#$a; i <= 10#$b; i++ )); do IDS+=("$i"); done
    elif [[ $tok =~ ^T([0-9]+)$ ]]; then
      a=${BASH_REMATCH[1]} IDW=${#a}
      IDS+=("$((10#$a))")
    else
      IDS+=("?$tok")
    fi
  done
  sort_ids
}

sort_ids() {
  local i j t n=${#IDS[@]}
  for (( i = 1; i < n; i++ )); do
    t=${IDS[i]}
    j=$((i - 1))
    while (( j >= 0 )) && [[ ${IDS[j]} != \?* && $t != \?* ]] && (( IDS[j] > t )); do
      IDS[j + 1]=${IDS[j]}
      j=$((j - 1))
    done
    IDS[j + 1]=$t
  done
}

# id_ranges: RG = IDS written back with ranges ("T001–T003, T007", or none)
id_ranges() {
  local i s e x
  RG=
  (( ${#IDS[@]} )) || { RG=none; return 0; }
  i=0
  while (( i < ${#IDS[@]} )); do
    x=${IDS[i]}
    if [[ $x == \?* ]]; then RG+="${RG:+, }${x#\?}"; i=$((i + 1)); continue; fi
    s=$x e=$x
    while (( i + 1 < ${#IDS[@]} )) && [[ ${IDS[i + 1]} != \?* ]] && (( IDS[i + 1] == e + 1 )); do
      e=${IDS[i + 1]}
      i=$((i + 1))
    done
    if (( s == e )); then
      RG+="${RG:+, }$(printf 'T%0*d' "$IDW" "$s")"
    else
      RG+="${RG:+, }$(printf 'T%0*d–T%0*d' "$IDW" "$s" "$IDW" "$e")"
    fi
    i=$((i + 1))
  done
}

# --- review findings ----------------------------------------------------------------------
# data-model.md, Merged list. Each finding of the call's reviewer reports, by
# index: M_SEC (its section, or a design finding's tag), M_LENS, M_REP (its
# report's index in the call), M_TITLE, M_AT (the `at:` text), M_FILE, M_A,
# M_B (the spot: lines a-b, a = 0 for the whole file; M_FILE "" without
# `at:`, a spot that matches no other), M_FIX, M_CONF, M_RAW (the rec as
# written), M_REC (the final rec), M_KEEP (0 when rule 2 dropped it), M_ID.
# ORD = the kept findings in print order; UNTESTED, NOTMET = the acceptance
# criteria; PARA = the 4c `Paraphrase vs brief` value.

LABEL_RE='^(at|fix|spec|standard|confidence|severity|measured|verify with|guard|why|kind|rec): (.*)$'
REC_RE='^(apply|skip \(.+\)|user \(.+\))$'
SPOT_RE='^(.+):([0-9]+)(-([0-9]+))?$'
M_SEC=() M_LENS=() M_REP=() M_TITLE=() M_AT=() M_FILE=() M_A=() M_B=()
M_FIX=() M_CONF=() M_RAW=() M_REC=() M_KEEP=() M_ID=() M_BODY=() ORD=()
UNTESTED=() NOTMET=() PARA=''

mreset() {
  M_SEC=() M_LENS=() M_REP=() M_TITLE=() M_AT=() M_FILE=() M_A=() M_B=()
  M_FIX=() M_CONF=() M_RAW=() M_REC=() M_KEEP=() M_ID=() M_BODY=() ORD=()
  UNTESTED=() NOTMET=() PARA=''
}

# fsplit <item>: FQ_TITLE, FQ_AT, FQ_FIX, FQ_CONF, FQ_REC of a finding line;
# a segment that is no label continues the one before it (its text held
# " — "), and a label after `rec:` voids the rec (rule 5: it must come last)
fsplit() {
  local s=$1 seg cur=title more=1 first=1
  FQ_TITLE='' FQ_AT='' FQ_FIX='' FQ_CONF='' FQ_REC=''
  while (( more )); do
    if [[ $s == *' — '* ]]; then seg=${s%%' — '*}; s=${s#*' — '}; else seg=$s; more=0; fi
    if (( first )); then FQ_TITLE=$seg; first=0; continue; fi
    if [[ $seg =~ $LABEL_RE ]]; then
      if [[ $cur == rec ]]; then FQ_REC='(not last)'; fi
      cur=${BASH_REMATCH[1]}
      case $cur in
        at) FQ_AT=${BASH_REMATCH[2]} ;;
        fix) FQ_FIX=${BASH_REMATCH[2]} ;;
        confidence) FQ_CONF=${BASH_REMATCH[2]} ;;
        rec) FQ_REC=${BASH_REMATCH[2]} ;;
      esac
    elif [[ $seg == unmeasured* ]]; then
      if [[ $cur == rec ]]; then FQ_REC='(not last)'; fi
      cur=measured
    else
      case $cur in
        title) FQ_TITLE+=" — $seg" ;;
        at) FQ_AT+=" — $seg" ;;
        fix) FQ_FIX+=" — $seg" ;;
        confidence) FQ_CONF+=" — $seg" ;;
        rec) FQ_REC+=" — $seg" ;;
      esac
    fi
  done
}

# madd <section> <lens> <report index> <item> <design 0|1>; M_BODY = the
# item as written, its trailing `rec:` cut (the merged rec replaces it)
madd() {
  local file='' line_from=0 line_to=0 body=$4
  fsplit "$4"
  if [[ -n $FQ_AT ]]; then
    file=$FQ_AT
    if (( ! $5 )) && [[ $FQ_AT =~ $SPOT_RE ]]; then
      file=${BASH_REMATCH[1]} line_from=$((10#${BASH_REMATCH[2]})) line_to=$((10#${BASH_REMATCH[2]}))
      if [[ -n ${BASH_REMATCH[4]} ]]; then line_to=$((10#${BASH_REMATCH[4]})); fi
      # a range written backwards: swap its ends (line_from is still group 2)
      if (( line_to < line_from )); then line_from=$line_to line_to=$((10#${BASH_REMATCH[2]})); fi
      # line 0 would read as the whole file
      if (( line_from == 0 )); then line_from=1; fi
    fi
  fi
  if [[ $FQ_REC != '(not last)' && $body == *' — rec: '* ]]; then body=${body%' — rec: '*}; fi
  M_SEC+=("$1") M_LENS+=("$2") M_REP+=("$3") M_TITLE+=("$FQ_TITLE") M_AT+=("$FQ_AT")
  M_FILE+=("$file") M_A+=("$line_from") M_B+=("$line_to") M_FIX+=("$FQ_FIX") M_CONF+=("$FQ_CONF")
  M_RAW+=("$FQ_REC") M_REC+=('') M_KEEP+=(1) M_ID+=('') M_BODY+=("$body")
}

# same_spot <i> <j> <design>: code, the same file with overlapping lines (no
# line: the whole file); design, the same artifact and section text
same_spot() {
  local i=$1 j=$2
  [[ -n ${M_FILE[i]} && ${M_FILE[i]} == "${M_FILE[j]}" ]] || return 1
  if (( $3 )); then return 0; fi
  if (( M_A[i] == 0 || M_A[j] == 0 )); then return 0; fi
  (( M_A[i] <= M_B[j] && M_A[j] <= M_B[i] ))
}

# merge_rules <design>: rules 2 and 3 (and, for code, 4 and 6), rule 5
merge_rules() {
  local d=$1 n=${#M_SEC[@]} i j r
  for (( i = 0; i < n; i++ )); do
    for (( j = 0; j < i; j++ )); do
      (( M_KEEP[j] )) || continue
      if [[ ${M_SEC[i]} == "${M_SEC[j]}" && ${M_RAW[i]} == "${M_RAW[j]}" && ${M_FIX[i]} == "${M_FIX[j]}" ]] \
        && same_spot "$i" "$j" "$d"; then
        M_KEEP[i]=0
        break
      fi
    done
  done
  for (( i = 0; i < n; i++ )); do
    (( M_KEEP[i] )) || continue
    for (( j = i + 1; j < n; j++ )); do
      (( M_KEEP[j] )) || continue
      [[ ${M_SEC[i]} == "${M_SEC[j]}" ]] || continue
      [[ ${M_REP[i]} != "${M_REP[j]}" || ${M_LENS[i]} != "${M_LENS[j]}" ]] || continue
      [[ ${M_RAW[i]} != "${M_RAW[j]}" || ${M_FIX[i]} != "${M_FIX[j]}" ]] || continue
      same_spot "$i" "$j" "$d" || continue
      M_REC[i]='user (reviewers disagree)'
      M_REC[j]='user (reviewers disagree)'
    done
  done
  for (( i = 0; i < n; i++ )); do
    (( M_KEEP[i] )) && [[ -z ${M_REC[i]} ]] || continue
    r=${M_RAW[i]}
    if (( ! d )) && [[ ${M_SEC[i]} == Bugs && ${M_CONF[i]} == high && $r == skip* ]]; then
      if [[ $r =~ ^skip\ \((.+)\)$ ]]; then M_REC[i]="user (${BASH_REMATCH[1]})"; else M_REC[i]='user (no valid recommendation)'; fi
    elif ! [[ $r =~ $REC_RE ]]; then
      M_REC[i]='user (no valid recommendation)'
    elif (( ! d )) && [[ ${M_SEC[i]} == Security && $r =~ ^skip\ \((.+)\)$ ]]; then
      M_REC[i]="user (${BASH_REMATCH[1]})"
    else
      M_REC[i]=$r
    fi
  done
}

# merge_ids <design>: D1… in report order; else B (Bugs and Spec), S, P, C,
# R, [std], each numbered in collection order (lens, report, line); ORD in
# that print order
merge_ids() {
  local d=$1 i g p c
  ORD=()
  for g in B S P C R std D; do
    c=0
    for (( i = 0; i < ${#M_SEC[@]}; i++ )); do
      (( M_KEEP[i] )) || continue
      if (( d )); then p=D; else
        case ${M_SEC[i]} in
          Bugs | Spec) p=B ;;
          Security) p=S ;;
          Performance) p=P ;;
          Cuts) p=C ;;
          Readability) p=R ;;
          *) p=std ;;
        esac
      fi
      [[ $p == "$g" ]] || continue
      c=$((c + 1))
      if [[ $g == std ]]; then M_ID[i]="[std]$c"; else M_ID[i]="$g$c"; fi
      ORD+=("$i")
    done
  done
}

# rp_ok <i>: the call's report i is on disk, parsed and unchanged since checked
rp_ok() {
  [[ -s ${RP_PATH[$1]} ]] || return 1
  (( ! RP_BAD[$1] )) || return 1
  if (( RP_NEW[$1] )); then return 0; fi
  sum_of "${RP_PATH[$1]##*/}"
  [[ -n $S && $S == "${RP_HASH[$1]}" ]]
}

# merge_code: the code reviewers' findings (rules 2-6) and acceptance criteria
merge_code() {
  local l r it sec secs lenses
  mreset
  for l in 7a 7b 7c 7d 7e; do
    for (( r = 0; r < ${#RP_PATH[@]}; r++ )); do
      rp_ok "$r" || continue
      report_key "${RP_PATH[r]##*/}"
      lenses=${RK#*-}
      [[ +$lenses+ == *+$l+* ]] || continue
      parse "${RP_PATH[r]}" code-reviewer "$lenses"
      validate code-reviewer "$lenses"
      (( ! P_BAD )) || continue
      case $l in
        7a) secs='Bugs Spec Standards' ;;
        7b) secs=Security ;;
        7c) secs=Performance ;;
        7d) secs=Cuts ;;
        *) secs=Readability ;;
      esac
      for sec in $secs; do
        pitems "$sec ($l)"
        for it in ${IT[@]+"${IT[@]}"}; do madd "$sec" "$l" "$r" "$it" 0; done
      done
      if [[ $l == 7a ]]; then
        pitems 'Acceptance criteria (7a)'
        for it in ${IT[@]+"${IT[@]}"}; do
          case ${it##*' — '} in
            untested) UNTESTED+=("${it%' — '*}") ;;
            'not met'*) NOTMET+=("${it%' — '*}") ;;
          esac
        done
      fi
    done
  done
  merge_rules 0
  merge_ids 0
}

# merge_design: the design reviewers' findings (rules 2, 3, 5), PARA
merge_design() {
  local r it lenses
  mreset
  for (( r = 0; r < ${#RP_PATH[@]}; r++ )); do
    rp_ok "$r" || continue
    report_key "${RP_PATH[r]##*/}"
    lenses=${RK#*-}
    parse "${RP_PATH[r]}" design-reviewer "$lenses"
    validate design-reviewer "$lenses"
    (( ! P_BAD )) || continue
    if pget 'Paraphrase vs brief (4c)'; then PARA=$V; fi
    pitems Findings
    for it in ${IT[@]+"${IT[@]}"}; do madd "${it%% *}" "$lenses" "$r" "${it#* }" 1; done
  done
  merge_rules 1
  merge_ids 1
}

# ftext <i>: FT = the merged finding as printed (finding:, apply:)
ftext() {
  FT="${M_ID[$1]} ${M_SEC[$1]} — ${M_BODY[$1]} — rec: ${M_REC[$1]}"
}

# fsub <i>: FS = its Log sub-line; an S finding gives its file and title
# only, a [sec] one its spot and title (no exploit detail, no rec: lens 7b's
# accepted list knows them by that)
fsub() {
  local i=$1 spot
  spot=${M_AT[i]:--}
  case ${M_SEC[i]} in
    Security) FS="    - ${M_ID[i]} ${M_FILE[i]:--} — ${M_TITLE[i]}" ;;
    '[sec]') FS="    - ${M_ID[i]} $spot — ${M_TITLE[i]}" ;;
    *) FS="    - ${M_ID[i]} $spot — ${M_TITLE[i]} — rec: ${M_REC[i]}" ;;
  esac
}

# id_group <id>: IG = its group (B, S, [std], C, P, R, D)
id_group() { IG=${1%%[0-9]*}; }

# apply_ord <index>...: AO = the indices in apply order (bugs and security,
# standards, cuts, performance, readability; design in its order)
apply_ord() {
  local g i
  AO=()
  for g in B S '[std]' C P R D; do
    for i in "$@"; do
      id_group "${M_ID[i]}"
      if [[ $IG == "$g" ]]; then AO+=("$i"); fi
    done
  done
}

# mcount: MC_A, MC_S (apply, skip), MC_USER (ids), MC_SEC (S ids), MC_SECA,
# MC_SECS ([sec] ids to apply, skipped), MC_APPLY (the apply indices, in
# apply order)
mcount() {
  local i ap=()
  MC_A=0 MC_S=0 MC_USER=() MC_SEC=() MC_SECA=() MC_SECS=() MC_APPLY=()
  for i in ${ORD[@]+"${ORD[@]}"}; do
    case ${M_REC[i]} in
      apply) MC_A=$((MC_A + 1)); ap+=("$i") ;;
      skip*) MC_S=$((MC_S + 1)) ;;
      *) MC_USER+=("${M_ID[i]}") ;;
    esac
    case ${M_SEC[i]} in
      Security) MC_SEC+=("${M_ID[i]}") ;;
      '[sec]')
        case ${M_REC[i]} in
          apply) MC_SECA+=("${M_ID[i]}") ;;
          skip*) MC_SECS+=("${M_ID[i]}") ;;
        esac ;;
    esac
  done
  apply_ord ${ap[@]+"${ap[@]}"}
  MC_APPLY=(${AO[@]+"${AO[@]}"})
}

# review_print <design>: the paraphrase:, counts: and finding: lines
review_print() {
  local i c
  if (( $1 )); then
    if [[ -n $PARA ]]; then out 13 "paraphrase: $PARA"; fi
    c="counts: ${#ORD[@]} findings, $MC_A applied, $MC_S skipped"
    if (( ${#MC_SECA[@]} )); then comma "${MC_SECA[@]}"; c+="; security: $J"; fi
    if (( ${#MC_SECS[@]} )); then comma "${MC_SECS[@]}"; c+="; security skipped: $J"; fi
  else
    c="counts: ${#ORD[@]} findings, $MC_A to apply, $MC_S skipped"
    if (( ${#UNTESTED[@]} )); then comma "${UNTESTED[@]}"; c+="; untested: $J"; fi
  fi
  out 15 "$c"
  for i in ${ORD[@]+"${ORD[@]}"}; do ftext "$i"; out 16 "finding: $FT"; done
}

# review_subs: the gate's finding sub-lines
review_subs() {
  local i
  for i in ${ORD[@]+"${ORD[@]}"}; do fsub "$i"; qlog "$FS"; done
}

# soft_text: ST_TEXT = a soft review gate's line after its tag
soft_text() {
  local i a=() s=() w
  for i in ${ORD[@]+"${ORD[@]}"}; do
    case ${M_REC[i]} in
      apply) a+=("${M_ID[i]}") ;;
      skip*) w=${M_REC[i]#skip (}; s+=("${M_ID[i]} (reviewer: \"${w%)}\")") ;;
    esac
  done
  comma ${a[@]+"${a[@]}"}
  ST_TEXT="auto-applied ${J:-none}"
  if (( ${#s[@]} )); then comma "${s[@]}"; ST_TEXT+="; skipped $J"; fi
  if (( ${#UNTESTED[@]} )); then comma "${UNTESTED[@]}"; ST_TEXT+="; untested: $J"; fi
}

# latest_gate <head>: LGI = the latest gate line (tagged) with that head, or
# -1 (/fix: since the latest back to)
latest_gate() {
  local i
  LGI=-1
  back_cut
  for (( i = ${#LG[@]} - 1; i >= R0; i-- )); do
    [[ -n ${LT[i]} ]] || continue
    head_of "$i"
    if [[ $HD == "$1" ]]; then LGI=$i; return 0; fi
  done
}

# gate_passed <i>: gate i passed (soft, or answered with a kind that goes on)
gate_passed() {
  answer_of "$1"
  if [[ ${LT[$1]} == soft ]] && ! has_sub "$1" '    - override: hard — '; then return 0; fi
  case $AK in
    '' | stop | 'back to '* | 'skip '*) return 1 ;;
  esac
}

# sub_text <gate index> <id>: SUBT = that finding's sub-line text ("" none)
sub_text() {
  local j
  SUBT=
  subs_of "$1"
  for j in ${SUBS[@]+"${SUBS[@]}"}; do
    if [[ ${LG[j]} == "    - $2 "* ]]; then SUBT=${LG[j]#'    - '}; return 0; fi
  done
}

# log_apply <head>: AP = the sub-line texts of the findings the latest such
# gate applied (auto-applied, or the outcome's picked ids) minus the dropped
# ones, in apply order
log_apply() {
  local g j ids='' d=' ' id g2
  AP=()
  latest_gate "$1"
  g=$LGI
  (( g >= 0 )) || return 0
  if [[ ${LT[g]} == soft ]] && seg "${LG[g]#*' — '}" 'auto-applied '; then ids=$SG; fi
  subs_of "$g"
  for j in ${SUBS[@]+"${SUBS[@]}"}; do
    case ${LG[j]} in
      '    - outcome: picked '*) ids=${LG[j]#'    - outcome: picked '}; ids=${ids%%'; '*} ;;
      '    - outcome: none picked'*) ids= ;;
    esac
  done
  for (( j = g + 1; j < ${#LG[@]}; j++ )); do
    if [[ ${LG[j]} == '    - dropped: '* ]]; then id=${LG[j]#'    - dropped: '}; d+="${id%% *} "; fi
  done
  [[ $ids != none ]] || ids=
  for g2 in B S '[std]' C P R D; do
    for id in ${ids//,/ }; do
      id_group "$id"
      [[ $IG == "$g2" && $d != *" $id "* ]] || continue
      sub_text "$g" "$id"
      if [[ -n $SUBT ]]; then AP+=("${SUBT% — rec: *}"); else AP+=("$id"); fi
    done
  done
}

# log_ids <head>: MIDS = the finding ids of the latest such gate's sub-lines
log_ids() {
  local j id
  MIDS=()
  latest_gate "$1"
  (( LGI >= 0 )) || return 0
  subs_of "$LGI"
  for j in ${SUBS[@]+"${SUBS[@]}"}; do
    id=${LG[j]#'    - '}
    id=${id%% *}
    if [[ $id =~ ^([BSPCRD]|\[std\])[0-9]+$ ]]; then MIDS+=("$id"); fi
  done
}

# inlist <x> <item>...: 0 when x is one of the items
inlist() {
  local x=$1 y
  shift
  for y in "$@"; do if [[ $y == "$x" ]]; then return 0; fi; done
  return 1
}

# check_dropped: the dropped: arguments name a P or R id cut by a C id of
# MIDS (merge rule 1); 1 after a refusal
check_dropped() {
  local k id c
  for (( k = 0; k < ${#A_DROPPED[@]}; k++ )); do
    id=${A_DROPPED[k]} c=${A_CUTBY[k]}
    if [[ $id =~ ^[PR][0-9]+$ && $c =~ ^C[0-9]+$ ]] \
      && inlist "$id" ${MIDS[@]+"${MIDS[@]}"} && inlist "$c" ${MIDS[@]+"${MIDS[@]}"}; then
      continue
    fi
    refuse "dropped: $id: only a P or R finding cut by a C finding of this list"
    return 1
  done
}

# log_dropped: the accepted drops as sub-lines
log_dropped() {
  local k
  for (( k = 0; k < ${#A_DROPPED[@]}; k++ )); do
    qlog "    - dropped: ${A_DROPPED[k]} (cut by ${A_CUTBY[k]})"
  done
}

# rj_items <gate index> <items>: RJ += `<id> <spot> — <words>` for each
# `<id> (reviewer: "<why>")`, `<id> (user: "<words>")` or `<id> (as recommended)`
rj_items() {
  local g=$1 t=$2 id w spot
  while [[ -n $t ]]; do
    id=${t%% *}
    t=${t#"$id"}
    t=${t# }
    case $t in
      '(reviewer: "'* | '(user: "'*)
        t=${t#*': "'}
        if [[ $t == *'"), '* ]]; then w=${t%%'"), '*}; t=${t#*'"), '}; else w=${t%'")'}; t=; fi ;;
      '(as recommended)'*) w='as recommended'; t=${t#'(as recommended)'}; t=${t#', '} ;;
      *) w=; if [[ $t == *', '* ]]; then t=${t#*', '}; else t=; fi ;;
    esac
    sub_text "$g" "$id"
    spot=${SUBT#* }
    spot=${spot%%' — '*}
    RJ+=("$id ${spot:--} — $w")
  done
}

# rejected_lines: RJ = every finding skipped or rejected at a review gate so far
rejected_lines() {
  local i j t
  RJ=()
  back_cut
  for (( i = R0; i < ${#LG[@]}; i++ )); do
    [[ -n ${LT[i]} ]] || continue
    head_of "$i"
    case $SKILL:$HD in feat:'4 Design review' | feat:'7 Code review' | fix:'4 Code review') ;; *) continue ;; esac
    t=${LG[i]#*' — '}
    if [[ ${LT[i]} == soft && $t == *'; skipped '* ]]; then
      t=${t#*'; skipped '}
      if [[ $t == *'; untested: '* ]]; then t=${t%'; untested: '*}; fi
      rj_items "$i" "$t"
    fi
    subs_of "$i"
    for j in ${SUBS[@]+"${SUBS[@]}"}; do
      t=${LG[j]}
      [[ $t == '    - outcome: '*'; rejected '* ]] || continue
      t=${t#*'; rejected '}
      if [[ $t == *'; untested: '* ]]; then t=${t%'; untested: '*}; fi
      rj_items "$i" "$t"
    done
  done
}

# accepted_sec: AS = the accepted [sec] design findings (/feat 4's
# auto-applied or picked ids), `<id> <spot> — <title>`
accepted_sec() {
  local t
  AS=()
  [[ $SKILL == feat ]] || return 0
  log_apply '4 Design review'
  for t in ${AP[@]+"${AP[@]}"}; do
    sub_text "$LGI" "${t%% *}"
    # a [sec] sub-line is the one without a rec
    if [[ -n $SUBT && $SUBT != *' — rec: '* ]]; then AS+=("$SUBT"); fi
  done
}

# --- review gates ----------------------------------------------------------------------------
# contracts/gates.md, 4 Design review, 7 Code review, 7 review fixes, /fix 4.

# rmode <path>: RM = the parse mode of a report of the token role_of read (a
# reviewer: the lenses of its key)
rmode() {
  if [[ $AGENT == *reviewer ]]; then report_key "${1##*/}"; RM=${RK#*-}; else RM=$MODE; fi
}

# snap_check: `state.sh unchanged` with the call's snapshot (gates.md, step 4)
SNAPF=0
snap_check() {
  local l first=1
  st unchanged "$SF" "$A_SNAP"
  while IFS= read -r l; do
    if (( first )); then
      first=0
      [[ $l == changed ]] || return 0
      SNAPF=1
      reason 'files changed outside the reports'
      continue
    fi
    reason "changed: ${l#- }"
  done <<<"$ST"
}

# spawn_fixes <apply line>...: the fix-mode implementer (FAILS: a retry's)
spawn_fixes() {
  local t=7-fixes
  if [[ $SKILL == feat ]]; then
    spawn_row 6 fix 7-fixes
    skey who 'review fixes'
  else
    t=4-fixes
    spawn_row 2 fix 4-fixes
    skey who implementer
  fi
  slist apply "$@"
  if (( ${#FAILS[@]} )); then slist failures "${FAILS[@]}"; fi
  sinputs
  out_call 22 'boundary:' "$t" "$RPATH"
}

# amend_spawn <continue id | ""> <apply line>...: the planner amend after gate 4
amend_spawn() {
  local c=$1
  shift
  spawn_row 3 amend 3-plan "$c"
  slist apply "$@"
  sinputs
  out_call 22 'boundary:' 3 "$RPATH" 'agent=<id>'
}

# merged_apply <index>...: MA = their merged findings in apply order
merged_apply() {
  local i
  MA=()
  apply_ord "$@"
  for i in ${AO[@]+"${AO[@]}"}; do ftext "$i"; MA+=("$FT"); done
}

# spawn_7e: /feat 7's second batch (medium, large), after 7a-7d's call
spawn_7e() {
  local k cuts=none words=()
  groups_get 7 default
  if [[ -z $DIFF_BASE ]]; then
    default_branch
    DIFF_BASE=$(git -C "$TOP" merge-base "refs/remotes/origin/$DEF" HEAD 2>/dev/null) || die "no merge base with origin/$DEF"
  fi
  out 12 "diff: git diff $DIFF_BASE"
  spawn_group "${GR_ROWS[${#GR_ROWS[@]} - 1]}" review 7-7e
  skey diff "git diff $DIFF_BASE"
  for (( k = 0; k < ${#RP_PATH[@]}; k++ )); do
    report_key "${RP_PATH[k]##*/}"
    if [[ +${RK#*-}+ == *+7d+* ]]; then cuts=${RP_PATH[k]}; fi
  done
  skey cuts "$cuts"
  rejected_lines
  slist rejected ${RJ[@]+"${RJ[@]}"}
  sinputs
  words=("$RPATH" "${RP_PATH[@]}")
  for (( k = 0; k < ${#RP_PATH[@]}; k++ )); do words+=("sum=${RP_PATH[k]##*/}:${RP_HASH[k]}"); done
  NEED_SNAP=1
  out_call 22 'boundary:' 7e "${words[@]}" 'snapshot=@SNAP@'
}

# security_bug: 0 when the 1 Assess facts name security or lack risk area
security_bug() {
  assess_facts
  (( ! AF_HAS_RISK )) || [[ ,${AF_RISK// /}, == *,security,* ]]
}

# plan_rows: gate 4's 3 Plan, paraphrase and checklist rows (small, medium)
plan_rows() {
  local k rest
  plan_facts
  if [[ -n $PF_ASSUME && $PF_ASSUME != none ]]; then
    for k in ${PF_ASSUME//,/ }; do reason "assumption $k needs you"; done
  fi
  if [[ -n $PF_CONST && $PF_CONST != pass ]]; then
    rest=$PF_CONST
    while [[ -n $rest ]]; do
      reason "constitution: ${rest%%', '*}"
      if [[ $rest == *', '* ]]; then rest=${rest#*', '}; else rest=; fi
    done
  fi
  if [[ $PF_BLOCK == yes ]]; then reason blocker; fi
  if [[ -n $PF_TRIGGER && $PF_TRIGGER != none && $SC == small ]]; then
    reason "size increase: small → medium ($PF_TRIGGER)"
  fi
  for k in ${PF_MISSING[@]+"${PF_MISSING[@]}"}; do reason "fact missing: $k"; done
  if [[ $PARA == contradicts* ]]; then reason 'paraphrase contradicts the brief'; fi
  p2_facts
  if (( ! P2_HAS )); then
    reason 'fact missing: unchecked checklist items'
  elif (( P2_SOFT )) && [[ $P2_UNCHK != none ]]; then
    reason 'checklist item'
  fi
}

# review_gate <token>: the merged list, its rows, the gate line and next
review_gate() {
  local design=0 head i tk
  case $SKILL:$1 in
    feat:4) design=1 head='4 Design review' ;;
    feat:*) head='7 Code review' ;;
    *) head='4 Code review' ;;
  esac
  if (( design )); then merge_design; else merge_code; fi
  mcount
  size_col
  if [[ $SKILL == fix ]]; then
    assess_facts
    if (( ! AF_HAS_RISK )); then reason 'fact missing: risk area'; fi
    if security_bug; then reason 'security risk area'; fi
    if [[ $SC == large ]]; then reason large; fi
  elif [[ $SC == large ]]; then
    reason large
  fi
  if [[ $SKILL == fix || $SC != large ]]; then
    if (( ${#MC_USER[@]} )); then comma "${MC_USER[@]}"; reason "$J need you"; fi
    if (( design )); then
      plan_rows
    else
      for i in ${MC_SEC[@]+"${MC_SEC[@]}"}; do reason "$i security"; done
      if [[ $SKILL == feat ]]; then
        for i in ${NOTMET[@]+"${NOTMET[@]}"}; do reason "criterion not met: $i"; done
      fi
    fi
  fi
  review_print "$design"
  if (( design )) && [[ $SC == large ]]; then
    latest_gate '3 Plan'
    for (( i = LGI + 1; LGI >= 0 && i < ${#LG[@]}; i++ )); do
      if [[ ${LG[i]} == '- [x] 3 Plan — amended'* ]]; then out 14 'note: plan amended after gate 3'; break; fi
    done
  fi
  token_of "$head"
  tk=$TK
  if (( ${#REASONS[@]} )); then
    hard_gate "$head"
    review_subs
    answer_call "$tk"
    return 0
  fi
  VERDICT=soft
  soft_text
  qlog "- [x] $head [soft] — $ST_TEXT"
  review_subs
  merged_apply ${MC_APPLY[@]+"${MC_APPLY[@]}"}
  if (( design )); then
    st phase2-mode "$SF"
    if [[ $ST == 'soft 4 open' ]]; then qlog '    - spec assumptions: kept as recommended'; fi
    if (( ${#MA[@]} )); then agent_id planner; amend_spawn "$AID" "${MA[@]}"; else enter 5; fi
  elif (( ${#MA[@]} )); then
    spawn_fixes "${MA[@]}"
  else
    ship_phase
    enter "$SHIP"
  fi
  answer_call "$tk"
}

# review_boundary <token>: a reviewer batch's call (/feat 4, 7, 7e; /fix 4)
review_boundary() {
  local tok=$1 f i turn=1 new rf=0
  [[ -n $A_SNAP ]] || usage "snapshot= missing on a reviewer batch call: $SYN"
  (( ${#A_REPORTS[@]} )) || usage "boundary $tok takes the batch's reports: $SYN"
  [[ -z $A_AGENT ]] || usage "agent= only after a specifier, planner or tasker spawn: $SYN"
  batch_covered "$tok"
  phase_head "$tok"
  role_of "$tok"
  # a report passed again carries its sum=: 7a-7d's at 7e, after a reformat
  # line of this batch all but the reformatted ones
  reformat_keys
  case $RFK in *" ${tok%e}-"*) rf=1 ;; esac
  for f in "${A_REPORTS[@]}"; do
    sum_of "${f##*/}"
    new=1
    if [[ -n $S ]]; then
      new=0
    else
      report_key "${f##*/}"
      if [[ $tok == 7e && $RK != 7-7e ]] || { [[ $tok != 7e ]] && (( rf )) && [[ $RFK != *" $RK "* ]]; }; then
        usage "sum= missing for ${f##*/}: $SYN"
      fi
    fi
    rmode "$f"
    check_report "$f" "$AGENT" "$RM" "$new"
  done
  snap_check
  for (( i = 0; i < ${#RP_PATH[@]}; i++ )); do
    if (( RP_BAD[i] )); then
      report_key "${RP_PATH[i]##*/}"
      if turn_used "$RK"; then turn=0; fi
    fi
  done
  for (( i = 0; i < ${#RP_PATH[@]}; i++ )); do
    (( RP_BAD[i] )) || continue
    if (( ! CHK_FAIL && ! SNAPF && turn )); then reformat "$tok"; return 0; fi
    reason "unparsable: ${RP_UR[i]}"
    if [[ -n ${RP_TEXT[i]} ]]; then out 6 "unparsable line: ${RP_TEXT[i]}"; fi
  done
  size_col
  if [[ $SKILL:$tok == feat:7 && $SC != small ]]; then
    if (( ${#REASONS[@]} )); then
      hard_gate '7 Code review'
      token_of '7 Code review'
      answer_call "$TK"
    else
      VERDICT=soft
      spawn_7e
    fi
    return 0
  fi
  review_gate "$tok"
}

# fixes_start <gate head> <who>: FXS = the index the fix-mode work starts
# after (the gate, or a later hard <who> gate answered changed)
fixes_start() {
  local i
  latest_gate "$1"
  FXS=$LGI
  (( FXS >= 0 )) || return 0
  for (( i = FXS + 1; i < ${#LG[@]}; i++ )); do
    [[ ${LT[i]} == hard ]] || continue
    head_of "$i"
    [[ $HD == "$2" ]] || continue
    answer_of "$i"
    if [[ $AK == changed ]]; then FXS=$i; fi
  done
}

# owed_fixes <gate head> <who>: 0 when the passed gate's fixes are owed; AP =
# them, FAILS = a retry's failures
owed_fixes() {
  local i last=-1 l
  FAILS=()
  latest_gate "$1"
  (( LGI >= 0 )) || return 1
  gate_passed "$LGI" || return 1
  log_apply "$1"
  (( ${#AP[@]} )) || return 1
  fixes_start "$1" "$2"
  for (( i = FXS + 1; i < ${#LG[@]}; i++ )); do
    if [[ ${LG[i]} == "- [x] $2 — "* ]]; then last=$i; fi
  done
  (( last >= 0 )) || return 0
  [[ ${LG[last]} == "- [x] $2 — checks failed (retry 1 of 1): "* ]] || return 1
  l=${LG[last]#"- [x] $2 — checks failed (retry 1 of 1): "}
  while [[ -n $l ]]; do
    FAILS+=("${l%%', '*} → fail")
    if [[ $l == *', '* ]]; then l=${l#*', '}; else l=; fi
  done
}

# fixes_retry_used: 0 when the review fixes' retry line follows their start
fixes_retry_used() {
  local i
  fixes_start '7 Code review' '7 review fixes'
  for (( i = FXS + 1; i < ${#LG[@]}; i++ )); do
    if [[ ${LG[i]} == '- [x] 7 review fixes — checks failed (retry 1 of 1): '* ]]; then return 0; fi
  done
  return 1
}

# fixes_pre <token>: the dropped: arguments (refused, or logged first) and,
# with no report, what is left to apply; 0 when the call is decided
fixes_pre() {
  local gh='7 Code review'
  if [[ $SKILL == fix ]]; then gh='4 Code review'; fi
  log_ids "$gh"
  check_dropped || return 0
  log_dropped
  (( ${#A_REPORTS[@]} == 0 )) || return 1
  VERDICT=soft
  log_apply "$gh"
  if (( ${#AP[@]} )); then
    spawn_fixes "${AP[@]}"
  else
    ship_phase
    enter "$SHIP"
  fi
}

# dec_fixes <token>: a fix-mode implementer's report (7-fixes, 4-fixes)
dec_fixes() {
  local fx res nv=0
  if reparse 0 implementer fix; then
    pget 'Fixes (fix mode)'
    fx=$V
    pitems Checks
    comma ${IT[@]+"${IT[@]}"}
    res=${J:-none}
    fail_items ${IT[@]+"${IT[@]}"}
    log_who "$PH" "$fx; checks: $res; "
    nv=$NV_SEEN
    if [[ $SKILL == feat ]]; then
      if (( ! nv )); then
        reason 'Not verified line missing'
      elif (( ${#FC[@]} )); then
        comma "${FC[@]}"
        if fixes_retry_used; then
          reason "checks fail after retry: $J"
        else
          VERDICT=soft
          qlog "- [x] 7 review fixes [soft] — checks failed (retry 1 of 1): $J"
          log_apply '7 Code review'
          spawn_fixes ${AP[@]+"${AP[@]}"}
          answer_call "$1"
          return 0
        fi
      fi
    fi
  fi
  if (( ${#REASONS[@]} )); then hard_gate "$PH"; answer_call "$1"; return 0; fi
  VERDICT=soft
  FAILS=()
  if [[ $SKILL == feat ]]; then enter 8; else enter 3; fi
}

# --- answers at review gates -------------------------------------------------------------

# review_premerge <token>: the merged list of the answer call's reports;
# NO7E = 1 at a /feat 7 gate made before lens 7e ran (medium, large)
NO7E=0
review_premerge() {
  local f
  RP_PATH=() RP_NEW=() RP_HASH=() RP_BAD=() RP_UR=() RP_TEXT=()
  NO7E=0
  if [[ $SKILL == feat && $1 != 4 ]]; then
    size_col
    if [[ $SC != small ]]; then
      NO7E=1
      for f in ${A_REPORTS[@]+"${A_REPORTS[@]}"}; do
        report_key "${f##*/}"
        if [[ $RK == 7-7e ]]; then NO7E=0; fi
      done
    fi
  fi
  for f in ${A_REPORTS[@]+"${A_REPORTS[@]}"}; do
    RP_PATH+=("$f") RP_NEW+=(1) RP_HASH+=('') RP_BAD+=(0) RP_UR+=('') RP_TEXT+=('')
  done
  if [[ $SKILL:$1 == feat:4 ]]; then merge_design; else merge_code; fi
  RP_PATH=() RP_NEW=() RP_HASH=() RP_BAD=() RP_UR=() RP_TEXT=()
}

# review_answers <token>: the answers checked against the merged list; 1
# after a refusal
review_answers() {
  local k id ids i need=() all=' '
  review_premerge "$1"
  if (( NO7E )) && { [[ $MAIN == picked* ]] || (( ${#FL[@]} )); }; then
    refuse "${MAIN%% *} is not valid before lens 7e ran: answer approved, back to or stop"
    return 1
  fi
  for i in ${ORD[@]+"${ORD[@]}"}; do all+="${M_ID[i]} "; done
  # the call's reports must give back the list the gate logged (a gate made
  # before lens 7e ran logged none)
  if (( ! NO7E )); then
    log_ids "$OG_HEAD"
    k=' '
    for id in ${MIDS[@]+"${MIDS[@]}"}; do
      [[ $all == *" $id "* ]] || usage "the answer call's reports do not give back gate ${OG_HEAD%% *}'s findings ($id missing): $SYN"
      k+="$id "
    done
    for i in ${ORD[@]+"${ORD[@]}"}; do
      [[ $k == *" ${M_ID[i]} "* ]] || usage "the answer call's reports do not give back gate ${OG_HEAD%% *}'s findings (${M_ID[i]} not logged): $SYN"
    done
  fi
  RA_P=' ' RA_L=' '
  for (( k = 0; k < ${#A_KIND[@]}; k++ )); do
    case ${A_KIND[k]} in
      'picked '*) ids=${A_KIND[k]#picked } ;;
      'fix '* | 'leave '*) ids=${A_KIND[k]#* } ;;
      *) continue ;;
    esac
    for id in ${ids//,/ }; do
      if [[ $all != *" $id "* ]]; then clean "$id"; refuse "${C:0:20} is not in the merged list"; return 1; fi
      case ${A_KIND[k]} in leave*) RA_L+="$id " ;; *) RA_P+="$id " ;; esac
    done
  done
  case $MAIN in 'back to' | skip | stop) ;; *)
    for i in ${ORD[@]+"${ORD[@]}"}; do
      [[ ${M_REC[i]} == user* ]] || continue
      id=${M_ID[i]}
      if [[ $RA_P != *" $id "* && $RA_L != *" $id "* ]]; then need+=("$id"); fi
    done
    if (( ${#need[@]} )); then comma "${need[@]}"; refuse "$J need an answer"; return 1; fi ;;
  esac
  MIDS=()
  for i in ${ORD[@]+"${ORD[@]}"}; do MIDS+=("${M_ID[i]}"); done
  check_dropped
}

# review_outcome: OC = the outcome sub-line's text, PICKI = the picked
# indices (data-model.md, Merged list, Answers to a review gate)
review_outcome() {
  local i k id w d=' ' rj=() pk=() all=0
  PICKI=()
  case $MAIN in approved | changed) all=1 ;; esac
  for (( k = 0; k < ${#A_DROPPED[@]}; k++ )); do d+="${A_DROPPED[k]} "; done
  for i in ${ORD[@]+"${ORD[@]}"}; do
    id=${M_ID[i]}
    [[ $d != *" $id "* ]] || continue
    if [[ $RA_P == *" $id "* ]] || { (( all )) && [[ ${M_REC[i]} == apply && $RA_L != *" $id "* ]]; }; then
      PICKI+=("$i") pk+=("$id")
    elif [[ $RA_L == *" $id "* ]]; then
      w=
      for (( k = 0; k < ${#A_KIND[@]}; k++ )); do
        if [[ ${A_KIND[k]} == "leave $id" ]]; then w=${A_WORDS[k]}; fi
      done
      rj+=("$id (user: \"$w\")")
    elif (( all )) && [[ ${M_REC[i]} == skip* ]]; then
      rj+=("$id (as recommended)")
    fi
  done
  if (( ${#pk[@]} )); then comma "${pk[@]}"; OC="picked $J"; else OC='none picked'; fi
  if (( ${#rj[@]} )); then comma "${rj[@]}"; OC+="; rejected $J"; fi
  if (( ${#UNTESTED[@]} )); then comma "${UNTESTED[@]}"; OC+="; untested: $J"; fi
}

# --- /feat boundaries ---------------------------------------------------------------------

# reparse <i> <agent> <mode>: the call's report i parsed again; 0 when it parsed
reparse() {
  [[ -s ${RP_PATH[$1]} ]] || return 1
  (( ! RP_BAD[$1] )) || return 1
  parse "${RP_PATH[$1]}" "$2" "${3-}"
  validate "$2" "${3-}"
  (( ! P_BAD ))
}

dec_feat_2() {
  local ok=0 subs=() i
  if [[ -n $A_AGENT ]]; then set_agent specifier "$A_AGENT"; fi
  if reparse 0 specifier; then
    ok=1
    pget Spec; if [[ $V == none ]]; then reason 'no spec'; fi
    pget 'Open markers'; if [[ $V != none ]]; then reason "open markers: $V"; fi
    pget Blocker; if [[ $V != none ]]; then reason blocker; fi
    pget 'Size remark'; if [[ $V != none ]]; then reason 'size remark'; fi
    pget Stories; subs+=("    - Stories: $V")
    pget Requirements; subs+=("    - Requirements: $V")
    pget Assumptions; subs+=("    - Spec assumptions: $V")
    pget 'Unchecked checklist items'; subs+=("    - Unchecked checklist items: $V")
  fi
  if (( ${#REASONS[@]} )); then
    hard_gate '2 Specify'
  else
    VERDICT=soft
    qlog '- [x] 2 Specify [soft] — spec.md written'
  fi
  if (( ok )); then qlog "${subs[@]}"; fi
  if [[ $VERDICT == soft ]]; then enter 3; fi
  answer_call 2
}

# plan_report_facts: FACTS from the parsed planner report, and the large
# reasons in PR_REASONS
plan_report_facts() {
  local it k=0 nums=() pr=()
  PR_REASONS=()
  pitems Assumptions
  for it in ${IT[@]+"${IT[@]}"}; do
    k=$((k + 1))
    if [[ $it == *' — needs user: yes' ]]; then nums+=("$k"); PR_REASONS+=("assumption $k needs you"); fi
  done
  comma ${nums[@]+"${nums[@]}"}
  FACTS="assumptions needing you: ${J:-none}"
  pget 'Constitution check'
  if [[ $V == pass ]]; then
    FACTS+='; constitution: pass'
  else
    pitems 'Constitution check'
    for it in ${IT[@]+"${IT[@]}"}; do pr+=("${it%%' — '*}"); PR_REASONS+=("constitution: ${it%%' — '*}"); done
    comma ${pr[@]+"${pr[@]}"}
    FACTS+="; constitution: $J"
  fi
  pget Blockers
  if [[ $V == none ]]; then FACTS+='; blockers: none'; else FACTS+='; blockers: yes'; PR_REASONS+=(blocker); fi
  pget 'Size trigger'
  FACTS+="; size trigger: ${V%%' — '*}"
}

# design_ids: DI = the ids gate 4 had applied (auto-applied or picked)
design_ids() {
  local j
  DI=none
  latest '- [x] 4 Design review'
  (( LI >= 0 )) || return 0
  if seg "${LG[LI]#*' — '}" 'auto-applied '; then DI=$SG; fi
  subs_of "$LI"
  for j in ${SUBS[@]+"${SUBS[@]}"}; do
    if [[ ${LG[j]} == '    - outcome: picked '* ]]; then
      DI=${LG[j]#'    - outcome: picked '}
      DI=${DI%%'; '*}
    fi
  done
}

dec_feat_3() {
  local ok=0 r
  FACTS=
  if [[ -n $A_AGENT ]]; then set_agent planner "$A_AGENT"; fi
  if reparse 0 planner; then ok=1; plan_report_facts; fi
  if [[ $F_PHASE == '4 '* ]]; then
    design_ids
    if (( ${#REASONS[@]} )); then hard_gate '3 Plan' "$FACTS"; answer_call 3; return 0; fi
    VERDICT=soft
    qlog "- [x] 3 Plan — amended ($DI); $FACTS"
    enter 5
    return 0
  fi
  if owed_amend '3 Plan' '- [x] 3 Plan — amended'; then
    if (( ${#REASONS[@]} )); then hard_gate '3 Plan' "$FACTS"; answer_call 3; return 0; fi
    VERDICT=soft
    qlog "- [x] 3 Plan — amended; $FACTS"
    enter 4
    return 0
  fi
  size_col
  if [[ $SC == large ]]; then
    reason large
    if (( ok )); then
      for r in ${PR_REASONS[@]+"${PR_REASONS[@]}"}; do reason "$r"; done
      p2_facts
      if (( ! P2_HAS )); then
        reason 'fact missing: unchecked checklist items'
      elif (( P2_SOFT )) && [[ $P2_UNCHK != none ]]; then
        reason 'checklist item'
      fi
    fi
    hard_gate '3 Plan' "$FACTS"
    answer_call 3
    return 0
  fi
  if (( ${#REASONS[@]} )); then hard_gate '3 Plan' "$FACTS"; answer_call 3; return 0; fi
  VERDICT=soft
  qlog "- [x] 3 Plan — merged with 4; $FACTS"
  enter 4
}

# story_groups: SG_NAME/SG_IDS = story.sh's groups and their IDs
story_groups() {
  local l
  SG_NAME=() SG_IDS=() ST_TOTAL=
  while IFS= read -r l; do
    if [[ $l =~ ^(setup/foundational|US[0-9]+|polish):\ [0-9]+\ tasks(:\ (.*))?$ ]]; then
      SG_NAME+=("${BASH_REMATCH[1]}") SG_IDS+=("${BASH_REMATCH[3]}")
    elif [[ $l =~ ^total:\ ([0-9]+)\ tasks$ ]]; then
      ST_TOTAL=${BASH_REMATCH[1]}
    fi
  done <<<"$SO"
}

# checklist_answered: 0 when the open checklist items were answered at a gate
checklist_answered() {
  local i
  p2_facts
  (( P2 >= 0 )) || return 1
  if [[ ${LT[P2]} == hard ]]; then answer_of "$P2"; [[ -z $AK ]] || return 0; fi
  for (( i = P2 + 1; i < ${#LG[@]}; i++ )); do
    [[ -n ${LT[i]} ]] || continue
    case "; ${LG[i]#*' — '}; " in
      *'; checklist item; '*) answer_of "$i"; [[ -z $AK ]] || return 0 ;;
    esac
  done
  return 1
}

# story_mismatches <total>: a reason for each story whose task ids differ
# between the tasker's Per story and story.sh's groups (SG_*), and for the
# total
story_mismatches() {
  local it g nm k found want_ids have_ids want names=()
  names=(${SG_NAME[@]+"${SG_NAME[@]}"})
  pitems 'Per story'
  for it in ${IT[@]+"${IT[@]}"}; do
    g=${it%%': '*}
    found=0
    for nm in ${names[@]+"${names[@]}"}; do if [[ $nm == "$g" ]]; then found=1; fi; done
    (( found )) || names+=("$g")
  done
  for g in ${names[@]+"${names[@]}"}; do
    want_ids=
    pitems 'Per story'
    for it in ${IT[@]+"${IT[@]}"}; do if [[ ${it%%': '*} == "$g" ]]; then want_ids=${it#*': '}; fi; done
    have_ids=
    for (( k = 0; k < ${#SG_NAME[@]}; k++ )); do
      if [[ ${SG_NAME[k]} == "$g" ]]; then have_ids=${SG_IDS[k]}; fi
    done
    id_list "$want_ids"; id_ranges; want=$RG
    id_list "$have_ids"; id_ranges
    if [[ $want != "$RG" ]]; then reason "story.sh: $g — tasker: $want — tasks.md: $RG"; fi
  done
  if [[ $ST_TOTAL != "$1" ]]; then reason "story.sh: total — tasker: $1 — tasks.md: $ST_TOTAL"; fi
}

# size_for_tasks <total>: SR = the size rank a task count gives (gates.md 5:
# small up to 30 tasks, medium up to 60, large above)
size_for_tasks() {
  if (( $1 <= 30 )); then SR=1; elif (( $1 <= 60 )); then SR=2; else SR=3; fi
}

# size_from_tasks <total>: the size the task count and the plan's size
# trigger give, against Size: a larger one is a reason, a smaller one is set
size_from_tasks() {
  local new old m
  size_for_tasks "$1"
  new=$SR
  plan_facts
  if [[ -n $PF_TRIGGER && $PF_TRIGGER != none ]] && (( new < 2 )); then new=2; fi
  size_rank "$F_SIZE"; old=$SR
  if (( new > old )); then
    rank_size "$new"
    reason "size increase: $F_SIZE → $RS ($1 tasks)"
  elif (( new < old )); then
    rank_size "$new"
    qlog "- [x] size $RS — was $F_SIZE: $1 tasks"
    out 5 "size: $F_SIZE → $RS"
    qset Size "$RS"
  fi
  for m in ${PF_MISSING[@]+"${PF_MISSING[@]}"}; do
    if [[ $m == 'size trigger' ]]; then reason 'fact missing: size trigger'; fi
  done
}

dec_feat_5() {
  local ok=0 n=0 it total tasks
  if [[ -n $A_AGENT ]]; then set_agent tasker "$A_AGENT"; fi
  if reparse 0 tasker; then
    ok=1
    pitems 'Open findings'
    for it in ${IT[@]+"${IT[@]}"}; do
      case $it in CRITICAL* | HIGH*) n=$((n + 1)) ;; esac
    done
    if (( n )); then reason "$n CRITICAL/HIGH findings"; fi
    if pget Analyze; then
      if [[ $V != ran ]]; then reason 'analyze not run'; fi
    else
      reason 'analyze: not said'
    fi
    pget Tasks; tasks=$V
    pget 'Total tasks'; total=$V
    story "$tasks"
    if (( SRC != 0 )); then
      reason "story.sh: ${SO%%$'\n'*}"
    else
      story_groups
      story_mismatches "$total"
      total=$ST_TOTAL
    fi
    pget 'Unchecked checklist items'
    if [[ $V == open:* ]] && ! checklist_answered; then reason 'unanswered checklist items'; fi
    size_from_tasks "$total"
    p2_facts
    (( P2_HAS )) || reason 'fact missing: unchecked checklist items'
  fi
  size_col
  if [[ $SC == large ]]; then reason large; fi
  if (( ${#REASONS[@]} )); then
    hard_gate '5 Tasks'
  else
    VERDICT=soft
    qlog "- [x] 5 Tasks [soft] — $total tasks; story.sh: match; analyze ran"
    enter 6
  fi
  answer_call 5
}

# story_retry_used <US<n>>: 0 when the story's retry line follows its latest answer
story_retry_used() {
  local i s
  p6_start
  s=$S6
  for (( i = S6; i < ${#LG[@]}; i++ )); do
    if [[ ${LG[i]} == "- [x] 6 Implement — $1: "* ]]; then
      answer_of "$i"
      if [[ -n $AK ]]; then s=$i; fi
    fi
  done
  for (( i = s; i < ${#LG[@]}; i++ )); do
    if [[ ${LG[i]} == "- [x] 6 $1 — checks failed (retry 1 of 1): "* ]]; then return 0; fi
  done
  return 1
}

dec_feat_6() {
  local f u nv=0 k=0 n=0 nxt=last x done_all=1 checks=pass
  f=${RP_PATH[0]##*/}
  report_key "$f"
  u=${RK#6-}
  if reparse 0 implementer story; then
    log_who "6 $u" ''
    nv=$NV_SEEN
    if (( nv )); then k=${#IT[@]}; fi
    pget 'Tasks done'
    id_list "$V"
    n=${#IDS[@]}
    pitems Checks
    fail_items ${IT[@]+"${IT[@]}"}
    if (( ${#FC[@]} )); then checks=fail; fi
    out 17 "tasks: $n done, $k not verified; checks $checks"
    if (( ! nv )); then
      reason "$u: Not verified line missing"
    elif (( ${#FC[@]} )); then
      comma "${FC[@]}"
      if story_retry_used "$u"; then
        reason "$u: checks fail after retry: $J"
      else
        VERDICT=soft
        qlog "- [x] 6 $u [soft] — checks failed (retry 1 of 1): $J"
      fi
    else
      pget 'Design problems'
      if [[ $V != none ]]; then reason "$u: design problem"; fi
      size_col
      if [[ $SC == large ]]; then reason "$u: large"; fi
    fi
  fi
  if stories; then
    for x in ${STORIES[@]+"${STORIES[@]}"}; do
      story_state "$x"
      if (( ! ST_DONE )) && [[ $x != "$u" ]] && [[ $nxt == last ]]; then nxt="next $x"; fi
      if (( ! ST_DONE )) && [[ $x != "$u" ]]; then done_all=0; fi
    done
    comma ${STORIES[@]+"${STORIES[@]}"}
    out 18 "stories: $J; $nxt"
  else
    reason "story.sh: $STORY_ERR"
  fi
  if (( ${#REASONS[@]} )); then
    hard_gate '6 Implement'
    answer_call 6
    return 0
  fi
  if [[ $VERDICT == soft ]]; then next_story; answer_call 6; return 0; fi
  VERDICT=soft
  if (( done_all )); then
    nv_story_count
    qlog "- [x] 6 Implement [soft] — tasks done: ${ST_TOTAL:-$n} ($NVC not verified); checks pass"
    enter 7
    answer_call 6
    return 0
  fi
  next_story
}

# nv_story_count: NVC = the not-verified items of every story's latest list;
# ST_TOTAL = story.sh's total
nv_story_count() {
  local i h whos=() w seen
  NVC=0
  p6_start
  for (( i = ${#LG[@]} - 1; i >= S6; i-- )); do
    [[ ${LG[i]} == '- [x] 6 US'*' — not verified:'* ]] || continue
    head_of "$i"
    h=$HD seen=0
    for w in ${whos[@]+"${whos[@]}"}; do if [[ $w == "$h" ]]; then seen=1; fi; done
    (( ! seen )) || continue
    whos+=("$h")
    who_items "$i"
    NVC=$((NVC + ${#NV[@]}))
  done
  story "$SFDIR/tasks.md"
  ST_TOTAL=
  if (( SRC == 0 )); then story_groups; fi
}

# dec_ship: /feat 8 and /fix 5
dec_ship() {
  local cmd w ok=0 num
  ship_phase
  if reparse 0 shipper; then
    pget PR
    case $V in
      http*)
        VERDICT=soft
        out 19 "pr: $V"
        num=${V%/}
        num=${num##*/}
        num=${num%%[!0-9]*}
        qset 'Current phase' "done (PR #$num)"
        out 24 "done: PR #$num"
        return 0 ;;
      conflict)
        # nothing pushed: the move, then the ship again with both reports
        VERDICT=soft
        move_md
        rebase_spawn move "$SHIP" "${RP_PATH[0]}" "sum=${RP_PATH[0]##*/}:${RP_HASH[0]}"
        return 0 ;;
      blocked)
        pget 'Command for the user'
        cmd=$V
        for w in "$F_WT" "$TOP"; do
          [[ $w != none && -n $w ]] || continue
          if [[ $cmd == "! cd $w && "* || $cmd == "! cd '$w' && "* ]]; then ok=1; fi
        done
        out 20 "command: $cmd"
        if (( ok )); then
          VERDICT='stop: ship blocked on a command for you'
          out 24 'done: stopped (ship blocked on a command for you)'
          return 0
        fi
        reason 'ship blocked' ;;
    esac
  fi
  hard_gate "$SHIP Ship"
  qset 'Current phase' "$SHIP Ship"
  answer_call "$SHIP"
}

# --- /fix boundaries ---------------------------------------------------------------------

# fix_args_lines: the approved:, question: and security: arguments as Log lines
fix_args_lines() {
  local a
  for a in ${A_APPROVED[@]+"${A_APPROVED[@]}"}; do qlog "- [x] 1 Assess — approved: $a"; done
  for a in ${A_QUESTION[@]+"${A_QUESTION[@]}"}; do qlog "- [x] 1 Assess — answer: $a"; done
  if [[ -n $A_SECURITY ]]; then qlog "- [x] 1 Assess — security: $A_SECURITY (user: \"$A_SECWORDS\")"; fi
}

# assess_pass_text <size>: PASS = the pass text of the parsed assessment
assess_pass_text() {
  local v c r n
  pget Verdict; v=$V
  pget Confidence; c=$V
  pget Reproduction; r=$V
  pget Remediations; n=$V
  pget 'Risk area'
  PASS="gate: $v, $c confidence, $r, $n remediation(s); size $1; risk area $V"
  pget 'Performance bug'
  PASS+="; performance bug $V"
}

dec_fix_1() {
  local v s
  if reparse 0 assess; then
    pget Assessment
    if [[ $V == 'none ('*')' ]]; then v=${V#none (}; fix_stop 'done (invalid)' "${v%)}"; return 0; fi
    pget Verdict
    if [[ $V == invalid ]]; then fix_stop 'done (invalid)' invalid; return 0; fi
    pget 'Is a bug'
    case $V in
      'no — refactor' | 'no — backport') fix_stop 'done (not a bug)' "out of scope (${V#no — })"; return 0 ;;
      no*) fix_stop 'done (not a bug)' "$V"; return 0 ;;
    esac
    assess_reasons
  fi
  if (( ${#REASONS[@]} )); then
    hard_gate '1 Assess'
    answer_call 1
    return 0
  fi
  pget 'Proposed size'
  s=${V%%' — '*}
  pget Title
  v=$V
  qset Size "$s"
  qset title "$v"
  assess_pass_text "$s"
  VERDICT=soft
  qlog "- [x] 1 Assess [soft] — $PASS"
  fix_args_lines
  enter 2
  answer_call 1
}

# fix_stop <Current phase> <reason>: /fix 1's stop rows
fix_stop() {
  local r=$2
  VERDICT="stop: $r"
  qlog "- [x] 1 Assess — stopped: $r"
  qset 'Current phase' "$1"
  out 24 "done: stopped ($r)"
}

assess_reasons() {
  local v
  pget Sections; if [[ $V == error:* ]]; then reason "sections: ${V#error: }"; fi
  pget Slug; if [[ $V == mismatch* ]]; then v=${V#mismatch (}; reason "slug mismatch: ${v%)}"; fi
  report_author
  case $RA in
    OWNER | MEMBER | COLLABORATOR | user) ;;
    '') reason 'fact missing: report author' ;;
    *) reason "report author $RA" ;;
  esac
  pget Reproduction; if [[ $V == 'needs approval' ]]; then reason 'needs approval'; fi
  pget 'Risk area'; v=$V
  if [[ ,${v// /}, == *,security,* ]]; then reason 'security risk area'; fi
  if [[ -f $TOP/.logistics.yml && $F_ISSUE == none && ,${v// /}, != *,security,* ]]; then reason 'issue to create'; fi
  pget Verdict; if [[ $V == 'likely valid, needs reproduction' ]]; then reason 'needs reproduction'; fi
  pitems 'Open questions'; if (( ${#IT[@]} )); then reason "open questions: ${#IT[@]}"; fi
  pget 'Several bugs'; if [[ $V != no ]]; then reason 'several bugs'; fi
  pget 'Proposed size'; v=${V%%' — '*}; if [[ $v != small ]]; then reason "proposed size $v"; fi
  pget Confidence; if [[ $V != high ]]; then reason "confidence $V"; fi
  pget Reproduction; if [[ $V != reproduced && $V != 'needs approval' ]]; then reason "$V"; fi
  pget Remediations; if [[ $V != 1 ]]; then reason "remediations: $V"; fi
  pget 'Public behaviour change'; if [[ $V != no ]]; then reason 'public behaviour change'; fi
}

dec_fix_2() {
  local v pre=
  st retry-used "$SF"
  if [[ $ST == yes ]]; then pre='retry: '; fi
  if reparse 0 implementer bug; then
    log_who '2 implementer' ''
    pget 'Slug (bug mode)'; if [[ $V == mismatch* ]]; then v=${V#mismatch (}; reason "slug mismatch: ${v%)}"; fi
    pitems 'Deviations (bug mode)'
    if (( ${#IT[@]} )); then
      size_rank "$F_SIZE"
      if (( SR >= 3 )); then reason deviations; else rank_size $((SR + 1)); reason "size increase: $F_SIZE → $RS (deviations)"; fi
    fi
    pitems Checks
    fail_items ${IT[@]+"${IT[@]}"}
    for v in ${FC[@]+"${FC[@]}"}; do reason "check fails: $v"; done
    pget 'Status (bug mode)'; if [[ $V != applied ]]; then reason "status $V"; fi
    (( NV_SEEN )) || reason 'Not verified line missing'
  fi
  if (( ${#REASONS[@]} )); then hard_gate '2 Fix'; answer_call 2; return 0; fi
  VERDICT=soft
  qlog "- [x] 2 Fix [soft] — ${pre}applied; no deviations; checks pass"
  enter 3
  answer_call 2
}

# test_rows <cycle> <retry-used>: the parsed test report's verdict rows
test_rows() {
  local v
  pget Verdict
  case $V in
    verified)
      VERDICT=soft
      qlog '- [x] 3 Test [soft] — verified'
      if [[ $1 == 'after review fixes' ]]; then enter 5; else enter 4; fi ;;
    partial)
      pget 'Missing for verified'
      reason "partial: $V"
      hard_gate '3 Test' ;;
    failed)
      pget 'Still failing'
      v=$V
      if [[ $1 == first && $2 == no ]]; then
        VERDICT=soft
        qlog "- [x] 3 Test [soft] — failed (retry 1 of 1): $v; retry fix"
        pget 'Test report'
        TEST_REPORT=$V
        enter 2
      else
        reason "failed: $v"
        hard_gate '3 Test'
      fi ;;
  esac
}

# unaccounted: UA = the given not-verified items the test report leaves out
unaccounted() {
  local g c it hit given=()
  UA=()
  latest_who
  given=(${NV[@]+"${NV[@]}"})
  pget 'Not verified items'
  pitems 'Not verified items'
  for g in ${given[@]+"${given[@]}"}; do
    c=${g#*' → '}
    c=${c%' → '*}
    hit=0
    for it in ${IT[@]+"${IT[@]}"}; do
      if [[ ${it%' → '*} == "$c" ]]; then hit=1; fi
    done
    (( hit )) || UA+=("$c")
  done
}

dec_fix_3() {
  local cyc ru v i
  st cycle "$SF"; cyc=$ST
  st retry-used "$SF"; ru=$ST
  if reparse 0 test; then
    pget Sections; if [[ $V == error:* ]]; then reason "sections: ${V#error: }"; fi
    pget Slug; if [[ $V == mismatch* ]]; then v=${V#mismatch (}; reason "slug mismatch: ${v%)}"; fi
    if (( ! ${#REASONS[@]} )); then
      back_cut
      for (( i = ${#LG[@]} - 1; i >= R0; i-- )); do
        case ${LG[i]} in
          '- [x] 4 implementer — Not verified line missing'*) reason 'review fixes report lacked Not verified line'; break ;;
          '- [x] 4 implementer — '*) break ;;
        esac
      done
    fi
    if (( ! ${#REASONS[@]} )); then
      unaccounted
      if (( ${#UA[@]} )); then
        comma "${UA[@]}"
        v=$J
        pget Verdict
        reason "unaccounted items: $v; verdict: $V"
      fi
    fi
    if (( ! ${#REASONS[@]} )); then test_rows "$cyc" "$ru"; answer_call 3; return 0; fi
  fi
  hard_gate '3 Test'
  answer_call 3
}

# risk_gate: 0 when entering /fix 5 needs the hard `fact missing: risk area`
risk_gate() {
  local i
  assess_facts
  (( ! AF_HAS_RISK )) || return 1
  back_cut
  for (( i = R0; i < ${#LG[@]}; i++ )); do
    case ${LG[i]} in
      '- [x] 4 Code review — '*'fact missing: risk area'* | '- [x] 5 Ship — fact missing: risk area'*)
        answer_of "$i"
        if [[ -n $AK && $AK != stop && $AK != 'back to '* ]]; then return 1; fi ;;
    esac
  done
  return 0
}

# --- answers -----------------------------------------------------------------------------
# contracts/step-cli.md, Answers. Refusals print `refused: <why>`, log nothing
# and leave the gate open; they come before any sum= comparison.

refuse() { VERDICT="refused: $1"; }
CYC_A=
RU=

# answer_kinds: MAIN, MAIN_N, SIZE_A, FL (fix/leave); 1 after a refusal
answer_kinds() {
  local k
  MAIN='' MAIN_N='' SIZE_A='' FL=()
  for k in "${A_KIND[@]}"; do
    case $k in
      approved | changed | stop | stay | 'ship with partial' | 'ship with failed' | 'picked '?* | 'back to '[0-9] | 'skip '[0-9])
        if [[ -n $MAIN ]]; then refuse 'two main answers'; return 1; fi
        MAIN=$k
        case $k in 'back to '* | 'skip '*) MAIN_N=${k##* }; MAIN=${k% *} ;; esac ;;
      'size small' | 'size medium' | 'size large')
        if [[ -n $SIZE_A ]]; then refuse 'two size answers'; return 1; fi
        SIZE_A=${k#size } ;;
      'fix '?* | 'leave '?*) FL+=("$k") ;;
      *) clean "$k"; refuse "unknown answer: ${C:0:60}"; return 1 ;;
    esac
  done
  if [[ -z $MAIN && -n $SIZE_A ]]; then MAIN=approved; fi
  if [[ -z $MAIN ]]; then refuse 'no main answer (approved, changed, picked, back to, skip, stop)'; return 1; fi
}

# answer_valid: the kinds the open gate takes; 1 after a refusal
answer_valid() {
  local rest=${LG[OG]#*' — '} review=0 lo=2
  case $SKILL:$OG_TOKEN in feat:4 | feat:7 | feat:7e | fix:4) review=1 ;; esac
  # an empty review diff has no list to pick from
  if [[ $rest == 'empty diff'* ]]; then review=0; fi
  if (( OG_RC )) && [[ $MAIN != 'back to' && $MAIN != stop ]]; then
    refuse "report check failed: answer back to $OG_N or stop"
    return 1
  fi
  if (( ${#FL[@]} )) && (( ! review )); then refuse "${FL[0]%% *} is not valid at $OG_HEAD"; return 1; fi
  case $MAIN in
    changed)
      case $SKILL:$OG_TOKEN in
        feat:2 | feat:3 | feat:4 | feat:5 | feat:6 | feat:7-fixes | *:move) ;;
        fix:3) [[ $rest == 'partial: '* || $rest == 'unaccounted items: '* ]] || { refuse "changed is not valid at $OG_HEAD"; return 1; } ;;
        *) refuse "changed is not valid at $OG_HEAD"; return 1 ;;
      esac ;;
    picked*) (( review )) || { refuse "picked is not valid at $OG_HEAD"; return 1; } ;;
    stay) [[ $OG_TOKEN == move && $rest == 'undone ('*' → '*')' ]] || { refuse "stay is not valid at $OG_HEAD"; return 1; } ;;
    'ship with partial' | 'ship with failed')
      [[ $SKILL:$OG_TOKEN == fix:3 && $rest == "${MAIN#ship with }: "* ]] || { refuse "$MAIN is not valid at $OG_HEAD"; return 1; } ;;
    approved)
      if [[ $SKILL:$OG_TOKEN == fix:3 ]] && [[ $rest == 'partial: '* || $rest == 'failed: '* ]]; then
        refuse "approved is not valid at $OG_HEAD: answer ship with ${rest%%:*}, changed or back to"
        return 1
      fi ;;
    'back to')
      if [[ $SKILL == fix ]]; then lo=1; fi
      if (( MAIN_N < lo )) || { [[ -n $OG_N ]] && (( MAIN_N > OG_N )); }; then
        refuse "back to $MAIN_N is out of range at $OG_HEAD"
        return 1
      fi ;;
    skip)
      if [[ -z $OG_N ]] || (( MAIN_N <= OG_N )) \
        || { [[ $SKILL == feat ]] && (( MAIN_N > 7 )); } || { [[ $SKILL == fix ]] && (( MAIN_N != 4 )); }; then
        refuse "skip $MAIN_N is not valid at $OG_HEAD"
        return 1
      fi ;;
  esac
  if [[ $SKILL:$OG_TOKEN == fix:1 && $MAIN == approved && -z $A_SECURITY ]] \
    && [[ "; $rest; " == *'; security risk area; '* ]]; then
    refuse 'security: advisory or issue needed'
    return 1
  fi
}

do_answer() {
  local tok=$1 i f w cyc=
  open_gate
  if (( OG < 0 )); then refuse 'no hard gate open'; return 0; fi
  [[ $tok == "$OG_TOKEN" ]] || die "boundary $tok does not follow $OG_HEAD"
  answer_kinds || return 0
  answer_valid || return 0
  phase_head "$tok"
  role_of "$tok"
  REVIEW=0
  case $SKILL:$tok in feat:4 | feat:7 | feat:7e | fix:4) REVIEW=1 ;; esac
  if [[ ${LG[OG]#*' — '} == 'empty diff'* ]]; then REVIEW=0; fi
  if (( REVIEW )); then review_answers "$tok" || return 0; fi
  if [[ $MAIN != 'back to' && $MAIN != stop ]]; then
    for f in ${A_REPORTS[@]+"${A_REPORTS[@]}"}; do
      sum_of "${f##*/}"
      [[ -n $S ]] || usage "sum= missing for ${f##*/}: $SYN"
    done
    if [[ $SKILL == fix ]]; then st cycle "$SF"; cyc=$ST CYC_A=$ST; st retry-used "$SF"; RU=$ST; fi
    for f in ${A_REPORTS[@]+"${A_REPORTS[@]}"}; do rmode "$f"; check_report "$f" "$AGENT" "$RM" 0; done
    if (( CHK_FAIL )); then
      VERDICT=hard
      ANS_DONE=0
      answer_call "$tok"
      return 0
    fi
  else
    for f in ${A_REPORTS[@]+"${A_REPORTS[@]}"}; do
      RP_PATH+=("$f") RP_NEW+=(0) RP_BAD+=(0) RP_UR+=('') RP_TEXT+=('')
      sum_of "${f##*/}"
      RP_HASH+=("$S")
    done
  fi
  if (( OG_OVR )) && [[ -n $OG_N ]]; then
    phase_name "$OG_N"
    if [[ $F_PHASE != "$PN_" ]]; then qset 'Current phase' "$PN_"; fi
  fi
  for (( i = 0; i < ${#A_KIND[@]}; i++ )); do
    qlog "    - answer: ${A_KIND[i]} (user: \"${A_WORDS[i]}\")"
  done
  w=${A_WORDS[0]}
  VERDICT=answered
  if [[ -n $SIZE_A && $SIZE_A != "$F_SIZE" ]]; then
    out 5 "size: $F_SIZE → $SIZE_A"
    qset Size "$SIZE_A"
  fi
  PICKI=()
  if (( REVIEW )); then
    case $MAIN in 'back to' | skip | stop) ;; *)
      # a gate made before lens 7e ran, or the skipped /fix 4, has no list
      if (( ! NO7E )) && [[ ${LG[OG]#*' — '} != skipped* ]]; then
        review_outcome
        qlog "    - outcome: $OC"
      fi ;;
    esac
    log_dropped
  fi
  case $MAIN in
    stop) out 24 'done: stopped (user)'; return 0 ;;
    'back to')
      if [[ $SKILL == fix ]]; then qlog "- [x] back to $MAIN_N — $w"; fi
      enter "$MAIN_N"
      return 0 ;;
    skip)
      if [[ $SKILL == fix && $MAIN_N == 4 ]] && security_bug; then
        # skipping the review of a security bug: the go-ahead is still asked
        qset 'Current phase' '4 Code review'
        REASONS=(skipped)
        if (( ! AF_HAS_RISK )); then REASONS+=('fact missing: risk area'); fi
        REASONS+=('security risk area')
        hard_gate '4 Code review'
        RP_PATH=() RP_HASH=()
        ANS_DONE=0
        answer_call 4
        return 0
      fi
      enter $((MAIN_N + 1))
      return 0 ;;
    'ship with'*)
      if [[ $cyc == 'after review fixes' ]]; then enter 5; else enter 4; fi
      return 0 ;;
  esac
  apply_answer "$w"
}

# apply_answer <words>: approved or changed at the open gate
apply_answer() {
  local rest=${LG[OG]#*' — '} s
  case $SKILL:$OG_TOKEN in
    feat:2)
      if [[ $MAIN == changed || "; $rest; " == *'; open markers: '* || "; $rest; " == *'; blocker; '* || "; $rest; " == *'; no spec; '* ]]; then
        enter 2
      else
        enter 3
      fi ;;
    feat:3)
      if [[ $MAIN == changed ]]; then enter 3; return 0; fi
      st phase2-mode "$SF"
      if [[ $ST == 'soft 3 open' ]]; then qlog '    - spec assumptions: kept as recommended'; fi
      enter 4 ;;
    feat:4)
      merged_apply ${PICKI[@]+"${PICKI[@]}"}
      if (( ${#MA[@]} )) || [[ $MAIN == changed ]]; then
        amend_spawn '' ${MA[@]+"${MA[@]}"}
      else
        st phase2-mode "$SF"
        if [[ $ST == 'soft 4 open' ]]; then qlog '    - spec assumptions: kept as recommended'; fi
        enter 5
      fi ;;
    feat:7 | feat:7e)
      merged_apply ${PICKI[@]+"${PICKI[@]}"}
      if (( NO7E )); then
        spawn_7e
      elif (( ${#MA[@]} )); then
        spawn_fixes "${MA[@]}"
      else
        enter 8
      fi ;;
    feat:7-fixes)
      if [[ $MAIN == changed ]]; then
        log_apply '7 Code review'
        spawn_fixes ${AP[@]+"${AP[@]}"}
      else
        enter 8
      fi ;;
    fix:4)
      if [[ $MAIN == approved && "; $rest; " == *'; security risk area; '* ]]; then
        qlog "- [x] 4 Code review — ship go-ahead (user: \"$1\")"
      fi
      merged_apply ${PICKI[@]+"${PICKI[@]}"}
      if (( ${#MA[@]} )); then spawn_fixes "${MA[@]}"; else enter 5; fi ;;
    fix:4-fixes) enter 3 ;;
    feat:5) if [[ $MAIN == changed ]]; then enter 5; else enter 6; fi ;;
    feat:6)
      if [[ $MAIN == approved && $rest == 'tasks done: '* ]]; then enter 7; else enter 6; fi ;;
    feat:8 | fix:5) enter_ship ;;
    fix:1)
      reparse 0 assess || die "the assessment did not parse"
      pget 'Proposed size'
      s=${SIZE_A:-${V%%' — '*}}
      qset Size "$s"
      pget Title
      qset title "$V"
      assess_pass_text "$s"
      qlog "    - passed: $PASS"
      fix_args_lines
      enter 2 ;;
    *:move)
      # the move gate: `undone (<old> → <new>)`; any other move gate (a
      # failed report check) takes back to or stop only
      if [[ $MAIN == stay ]]; then
        s=${rest#'undone ('}
        s=${s%')'}
        qlog "- [x] move — stayed on ${s%% → *}, refused ${s#* → } (user: \"$1\")"
        NO_BASE=1
        next_step
      else
        rebase_spawn move move
      fi ;;
    fix:2) enter 3 ;;
    fix:3)
      if [[ $MAIN == changed ]]; then enter 3; return 0; fi
      if [[ $rest == 'unaccounted items: '* ]]; then
        s=${rest#'unaccounted items: '}
        s=${s%'; verdict: '*}
        qlog "- [x] 3 Test — unaccounted: $s (user: \"$1\")"
      fi
      reparse 0 test || die "the test report did not parse"
      # the verdict's row: a soft one is this call's `answered`; a hard
      # one (partial, failed) is a new gate with its own answer call
      test_rows "$CYC_A" "$RU"
      if [[ $VERDICT == soft ]]; then VERDICT=answered; else answer_call 3; fi ;;
    *) die "answers at $OG_HEAD are not handled yet" ;;
  esac
}

# --- the call forms ------------------------------------------------------------------------

# allowed_tokens: TOKS = the tokens Current phase takes (move and repair besides)
allowed_tokens() {
  local p=${F_PHASE%% *}
  if [[ $F_PHASE == 'done (shipping)' ]]; then ship_phase; p=$SHIP; fi
  case $SKILL:$p in
    feat:2) TOKS='2' ;;
    feat:3) TOKS='3' ;;
    feat:4) TOKS='4 3' ;;
    feat:5) TOKS='5' ;;
    feat:6) TOKS='6' ;;
    feat:7) TOKS='7 7e 7-fixes' ;;
    feat:8) TOKS='8' ;;
    fix:1) TOKS='1' ;;
    fix:2) TOKS='2' ;;
    fix:3) TOKS='3' ;;
    fix:4) TOKS='4 4-fixes' ;;
    fix:5) TOKS='5' ;;
    *) TOKS= ;;
  esac
  TOKS+=' move repair'
}

# key_ok <token> <file name>: the report's key is one the token allows
key_ok() {
  local re
  report_key "$2"
  case $SKILL:$1 in
    feat:2) re='^2-specify$' ;;
    feat:3) re='^3-plan$' ;;
    feat:4) re='^4-4[a-c](\+4[a-c])*$' ;;
    feat:5) re='^5-tasks$' ;;
    feat:6) re='^6-US[0-9]+$' ;;
    feat:7 | feat:7e) re='^7-7[a-e](\+7[a-e])*$' ;;
    feat:7-fixes) re='^7-fixes$' ;;
    feat:8) re='^(8-ship|move)$' ;;
    fix:1) re='^1-assess$' ;;
    fix:2) re='^2-fix$' ;;
    fix:3) re='^3-test$' ;;
    fix:4) re='^4-7[a-d](\+7[a-d])*$' ;;
    fix:4-fixes) re='^4-fixes$' ;;
    fix:5) re='^(5-ship|move)$' ;;
    *) re='^move$' ;;
  esac
  [[ $2 == *.md && $RK =~ $re ]]
}

# bad_reports <token>: the unparsable reports of the call; 0 when their
# reformat turn was printed (nothing else decided), else each is a reason
bad_reports() {
  local i turn=1
  for (( i = 0; i < ${#RP_PATH[@]}; i++ )); do
    if (( RP_BAD[i] )); then
      report_key "${RP_PATH[i]##*/}"
      if turn_used "$RK"; then turn=0; fi
    fi
  done
  for (( i = 0; i < ${#RP_PATH[@]}; i++ )); do
    (( RP_BAD[i] )) || continue
    if (( ! CHK_FAIL && turn )); then reformat "$1"; return 0; fi
    reason "unparsable: ${RP_UR[i]}"
    if [[ -n ${RP_TEXT[i]} ]]; then out 6 "unparsable line: ${RP_TEXT[i]}"; fi
  done
  return 1
}

# dec_move <index> <where>: the Move (rebase mode) line of report <index>
# (contracts/gates.md, Moves); 0 when the run goes on to the phase's work,
# 1 when this call stops at a hard gate
dec_move() {
  local k=$1 v it res=pass nv=none
  if (( ${#REASONS[@]} )) || ! reparse "$k" implementer rebase; then
    hard_gate move
    RP_PATH=("${RP_PATH[k]}") RP_HASH=("${RP_HASH[k]}")
    answer_call move
    return 1
  fi
  pget 'Move (rebase mode)'
  v=$V
  case $v in
    'nothing to do') ;;
    repaired) qlog "- [x] move — repaired ($v)" ;;
    'undone ('*)
      VERDICT=hard
      reason "move $v"
      qlog "- [x] move [hard] — $v"
      RP_PATH=("${RP_PATH[k]}") RP_HASH=("${RP_HASH[k]}")
      answer_call move
      return 1 ;;
    *)
      pitems Checks
      fail_items ${IT[@]+"${IT[@]}"}
      if (( ${#FC[@]} )); then res="fail: ${FC[0]}"; fi
      pitems 'Not verified'
      if (( ${#IT[@]} )); then comma "${IT[@]}"; nv=$J; fi
      qlog "- [x] move — $v ($2): checks $res; not verified: $nv"
      pitems 'Resolved alone (rebase mode)'
      for it in ${IT[@]+"${IT[@]}"}; do qlog "    - resolved: $it"; done
      pitems 'Decided (rebase mode)'
      for it in ${IT[@]+"${IT[@]}"}; do qlog "    - asked: $it"; done
      out 7 "move: $v ($2); checks $res" ;;
  esac
  VERDICT=soft
  return 0
}

# move_boundary <token>: a rebase-mode report before a phase (move), or after
# a repair spawn (repair)
move_boundary() {
  local tok=$1 where
  [[ -z $A_AGENT ]] || usage "agent= only after a specifier, planner or tasker spawn: $SYN"
  (( ${#A_REPORTS[@]} == 1 )) || usage "boundary $tok takes one report: $SYN"
  sum_of "${A_REPORTS[0]##*/}"
  [[ -z $S ]] || usage "the report of boundary $tok is new: no sum=: $SYN"
  phase_head "$tok"
  role_of "$tok"
  # a move that ended without a report: the repair check first
  if [[ $tok == move && ! -s ${A_REPORTS[0]} ]] && repair_due; then
    VERDICT=soft
    rebase_spawn repair repair
    return 0
  fi
  check_report "${A_REPORTS[0]}" implementer rebase 1
  if bad_reports "$tok"; then return 0; fi
  where="before $F_PHASE"
  if [[ $F_PHASE == 'done (shipping)' ]]; then ship_phase; where="before $SHIP Ship"; fi
  dec_move 0 "$where" || return 0
  if [[ $tok == repair ]]; then resume_next; return 0; fi
  NO_BASE=1
  next_step
}

# ship_move <token>: the ship boundary after a conflict: the ship report
# again (its sum=) and the move's report; a kept move ships again
ship_move() {
  local tok=$1 f ship='' mv=''
  for f in "${A_REPORTS[@]}"; do
    sum_of "${f##*/}"
    if [[ -n $S ]]; then ship=$f; else mv=$f; fi
  done
  [[ -n $ship && -n $mv ]] || usage "boundary $tok takes the ship report with its sum= and the move's report: $SYN"
  report_key "${mv##*/}"
  [[ $RK == move ]] || usage "boundary $tok takes the ship report with its sum= and the move's report: $SYN"
  phase_head "$tok"
  role_of "$tok"
  check_report "$ship" shipper '' 0
  check_report "$mv" implementer rebase 1
  if bad_reports "$tok"; then return 0; fi
  dec_move 1 'at ship' || return 0
  NO_BASE=1
  enter_ship
}

do_boundary() {
  local tok=$1 f t ok=0
  ship_phase
  if (( ${#A_KIND[@]} )); then
    open_gate
    if (( OG < 0 )); then refuse 'no hard gate open'; return 0; fi
  else
    allowed_tokens
    for t in $TOKS; do if [[ $t == "$tok" ]]; then ok=1; fi; done
    (( ok )) || die "boundary $tok does not follow $F_PHASE"
  fi
  for f in ${A_REPORTS[@]+"${A_REPORTS[@]}"}; do
    sum_of "${f##*/}"
    if [[ -z $S ]] && ! key_ok "$tok" "${f##*/}"; then die "report ${f##*/} is not a $tok report"; fi
  done
  if (( ${#A_KIND[@]} )); then do_answer "$tok"; return 0; fi
  case $SKILL:$tok in
    feat:4 | feat:7 | feat:7e | fix:4) review_boundary "$tok"; return 0 ;;
    feat:7-fixes | fix:4-fixes) if fixes_pre "$tok"; then return 0; fi ;;
    *:move | *:repair) move_boundary "$tok"; return 0 ;;
  esac
  if [[ -n $A_AGENT && ! ( $SKILL == feat && ( $tok == 2 || $tok == 3 || $tok == 5 ) ) ]]; then
    usage "agent= only after a specifier, planner or tasker spawn: $SYN"
  fi
  if [[ $tok == "$SHIP" ]] && (( ${#A_REPORTS[@]} == 2 )); then ship_move "$tok"; return 0; fi
  (( ${#A_REPORTS[@]} == 1 )) || usage "boundary $tok takes one report: $SYN"
  sum_of "${A_REPORTS[0]##*/}"
  [[ -z $S ]] || usage "the report of boundary $tok is new: no sum=: $SYN"
  phase_head "$tok"
  role_of "$tok"
  check_report "${A_REPORTS[0]}" "$AGENT" "$MODE" 1
  if bad_reports "$tok"; then return 0; fi
  case $SKILL:$tok in
    feat:2) dec_feat_2 ;;
    feat:3) dec_feat_3 ;;
    feat:5) dec_feat_5 ;;
    feat:6) dec_feat_6 ;;
    feat:8 | fix:5) dec_ship ;;
    fix:1) dec_fix_1 ;;
    fix:2) dec_fix_2 ;;
    fix:3) dec_fix_3 ;;
    feat:7-fixes | fix:4-fixes) dec_fixes "$tok" ;;
  esac
}

do_size() {
  case $1 in small | medium | large) ;; *) usage "size small|medium|large: $SYN" ;; esac
  open_gate
  if (( OG >= 0 )); then refuse "a gate is open: answer it with answer: size $1"; return 0; fi
  out 5 "size: $F_SIZE → $1"
  if [[ $1 != "$F_SIZE" ]]; then
    qlog "- [x] size $1 — was $F_SIZE (user)"
    qset Size "$1"
  fi
}

do_resume() {
  VERDICT=soft
  out 3 "resume: $F_PHASE"
  if [[ $SKILL == feat ]]; then
    st phase2-mode "$SF"
    out 4 "phase2-mode: $ST"
  elif assess_passed; then
    out 4 'assess gate: passed'
  else
    out 4 'assess gate: open'
  fi
  # the repair check first: a move that died part way is repaired before
  # anything else
  if repair_due; then rebase_spawn repair repair; return 0; fi
  resume_next
}

do_setup() {
  VERDICT=soft
  if [[ $SKILL == feat ]]; then phase_name 2; else phase_name 1; fi
  if [[ $F_PHASE != "$PN_" ]]; then qset 'Current phase' "$PN_"; fi
  next_step
}

main() {
  local d sf
  d=${BASH_SOURCE[0]%/*}
  [[ $d != "${BASH_SOURCE[0]}" ]] || d=.
  SDIR=$(CDPATH='' cd -- "$d" && pwd -P)
  (( $# >= 2 )) || usage
  if [[ $1 == resume ]]; then
    (( $# == 2 )) || usage
    load_state "$2"
    SKILL=$F_TITLE
    top_level
    do_resume
  else
    case $1 in feat | fix) ;; *) usage ;; esac
    (( $# >= 3 )) || usage
    SKILL=$1
    sf=$2
    if [[ ! -e $sf && ( $SKILL:$3 == feat:8 || $SKILL:$3 == fix:5 ) ]]; then
      for d in "${@:4}"; do
        if [[ $d == /*.md && ! -e $d ]] && renumbered "$d" "$sf"; then
          sf=$NEW_SF
          out 2 "state: $sf"
          break
        fi
      done
    fi
    load_state "$sf"
    [[ $F_TITLE == "$SKILL" ]] || die "$SF is a /$F_TITLE run"
    top_level
    case $3 in
      setup) (( $# == 3 )) || usage; do_setup ;;
      size) (( $# == 4 )) || usage; do_size "$4" ;;
      *)
        d=$3
        shift 3
        parse_args "$@"
        do_boundary "$d" ;;
    esac
  fi
  case $VERDICT in refused:*) ;; *) commit ;; esac
  print_all
}

[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
