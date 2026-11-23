#!/usr/bin/env bash
# Offline tests for .apm/skills/feat/scripts/secret-scan.sh (mise run
# test:secret-scan).
#
# Each case gets a scratch git repo ($repo). Every secret-looking sample is
# built by concatenation at runtime, so this file passes the scan itself.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(cd "$here/../.." && pwd -P)"
script="$root/.apm/skills/feat/scripts/secret-scan.sh"

current="setup"
fail() {
  printf 'FAIL %s: %s\n' "$current" "$1"
  if [ -n "${out+x}" ]; then printf '  output: %s\n' "$out"; fi
  exit 1
}

work="$(mktemp -d)"
trap 'command rm -rf -- "$work"' EXIT

# Commits here must not depend on the user's git config (signing, hooks).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# Sample pieces: keys and vendor prefixes, split so no line here matches.
pw="pass""word" pwd="pass""wd" tok="tok""en" sec="sec""ret" api="api""_key"
gh="gh""p_" pat="github""_pat_" aws="AK""IA" slack="xo""xb-" oai="s""k-"
pem="-----BEG""IN RSA PRIVATE KEY-----"
long="Zq81mXv0Lw3NcR7tYp2Ue5Ha"
# A Bearer word (two cases), JWT parts and a URL prefix with its `//` split off.
bw="Bear""er" bl="bear""er" jh="ey""JhbGciOiJIUzI1NiJ9" jp="ey""JzdWIiOiIxMjM0In0"
u="https:/""/" btok="Ab12Cd34Ef56Gh78Ij90"

# new_case <name>: a fresh repo ($repo) with one commit.
new_case() {
  current="$1"
  repo="$work/$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  printf 'x\n' >"$repo/README"
  git -C "$repo" add README
  git -C "$repo" commit -q -m init
  unset out
}

# put <file> <lines...>: write <file> in $repo.
put() {
  local f="$repo/$1"
  shift
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$@" >"$f"
}

# scan <args>: run the script in $repo; sets $out and $rc.
scan() {
  rc=0
  out="$(cd "$repo" && bash "$script" "$@" 2>"$work/stderr")" || rc=$?
}

expect_rc() { [ "$rc" = "$1" ] || fail "exit $rc, want $1 (stderr: $(head -n 1 "$work/stderr"))"; }
expect_out() { [ "$out" = "$1" ] || fail "want output: $1"; }
# expect_hidden <value>...: no value appears in the output.
expect_hidden() {
  local v
  for v in "$@"; do
    [[ "$out" != *"$v"* ]] || fail "output shows a value: $v"
  done
}

ok() { printf 'ok %s\n' "$current"; }

# --- cases -------------------------------------------------------------------

# 1. False positives: a removed key/literal line, and keys with no literal
# value (a call, an env-var reference, a boolean, a short value) pass.
new_case "false positives"
put deleted.txt "$pw = \"hunter2024x\"" keep
git -C "$repo" add deleted.txt
git -C "$repo" commit -q -m secret
put deleted.txt keep
put code.go 'package main' "func f() { $sec := cfg.GetString(\"$sec\"); _ = $sec }"
put ci.yml 'env:' "  GH_$tok: \${{ secrets.GH_TOKEN }}" "  DB_$pw: \$DB_PASS"
put flags.yml "$sec: true" "\"$tok\": \"abc\"" "$api = os.environ[\"API\"]"
put .env "$pw=short" "$tok=some_identifier_without_digits"
git -C "$repo" add -A
scan staged
expect_rc 0
expect_out ""
ok

# 2. True positives: each vendor prefix and each key with a literal value,
# reported as <file>:<line>: <rule>, never with the value.
new_case "true positives"
put keys.txt "a ${gh}abcdefghijklmnop" "b ${pat}abcdef" "c ${aws}ABCDEFGHIJKLMNOP" \
  "d ${slack}1234-abcd" "e = \"${oai}abc123\"" "$pem" clean
put conf.py "$pw = \"hunter2024x\"" "$pwd: 'Tr0ub4dor&3'" "DB_${sec^^}=\"q9w8e7r6t5\"" \
  "{\"$tok\": \"abcd1234efgh\"}" "${api^^} := \"k-0123456789\""
put .env "API_KEY=$long" "SAFE=1" "${tok^^}=$long"
git -C "$repo" add -A
scan staged
expect_rc 1
expect_out ".env:1: key-literal
.env:3: key-literal
conf.py:1: key-literal
conf.py:2: key-literal
conf.py:3: key-literal
conf.py:4: key-literal
conf.py:5: key-literal
keys.txt:1: github-token
keys.txt:2: github-token
keys.txt:3: aws-key-id
keys.txt:4: slack-token
keys.txt:5: openai-key
keys.txt:6: private-key"
expect_hidden hunter2024x Tr0ub4dor q9w8e7r6t5 abcd1234efgh 0123456789 "$long" abcdefghijklmnop ABCDEFGHIJKLMNOP
ok

# 3. Line numbers: only the added lines of a modified file count, numbered
# in the new file; an unchanged secret-looking line is not reported.
new_case "line numbers"
put app.cfg one "$pw = \"old-secret-1\"" three four five
git -C "$repo" add app.cfg
git -C "$repo" commit -q -m cfg
put app.cfg one "$pw = \"old-secret-1\"" three "$tok = \"new-secret-2\"" four five "${gh}xyz"
git -C "$repo" add app.cfg
scan staged
expect_rc 1
expect_out "app.cfg:4: key-literal
app.cfg:7: github-token"
ok

# 4. Worktree mode: the lines a tracked file adds over HEAD, and every line
# of an untracked file; paths outside the arguments are not scanned.
new_case "worktree"
put tracked.txt "$pw = \"old-secret-1\"" b
git -C "$repo" add tracked.txt
git -C "$repo" commit -q -m tracked
put tracked.txt "$pw = \"old-secret-1\"" b "${aws}QWERTYUIOPASDFGH"
put new/file.txt a "$sec: \"brand-new-99\""
put other.txt "${gh}notscanned"
scan worktree tracked.txt new
expect_rc 1
expect_out "tracked.txt:3: aws-key-id
new/file.txt:2: key-literal"
scan worktree other.txt
expect_rc 1
expect_out "other.txt:1: github-token"
scan worktree README
expect_rc 0
expect_out ""
ok

# 5. Could not run: a usage error or no git repo exits 2.
new_case "could not run"
scan
expect_rc 2
scan staged extra
expect_rc 2
scan worktree
expect_rc 2
mkdir -p "$work/norepo"
rc=0
out="$(cd "$work/norepo" && GIT_CEILING_DIRECTORIES="$work" bash "$script" staged 2>"$work/stderr")" || rc=$?
expect_rc 2
grep -q '^secret-scan: error: not a git repository$' "$work/stderr" || fail "stderr: $(head -n 1 "$work/stderr")"
ok

# 6. Sourced: secret_rule checks text line by line, as tracker.sh uses it.
current="sourced"
# shellcheck source-path=SCRIPTDIR/../../.apm/skills/feat/scripts source=secret-scan.sh
. "$script"
secret_rule "one"$'\n'"$tok: \"abcd1234efgh\"" || fail "secret_rule missed a quoted literal"
[ "$SECRET_RULE" = key-literal ] || fail "rule: $SECRET_RULE"
! secret_rule "one"$'\n'"$tok: \${{ secrets.X }}" || fail "secret_rule matched an env-var reference"
secret_rule "one"$'\n'"remote: ${u}deploy:s3cretpw@host" || fail "secret_rule missed URL credentials"
[ "$SECRET_RULE" = url-credentials ] || fail "rule: $SECRET_RULE"
ok

# 7. More literals: a `=>` separator (PHP, Ruby), unquoted values holding
# `.` (a JWT) or `@`, and a path with a space, which git ends with a tab in
# the `+++` header: the reported name has no tab. A key whose value is a JWT
# reports jwt: the vendor rules run before key-literal.
new_case "separators and paths"
jwt="eyJhbGciOiJIUzI1NiJ9"".eyJzdWIiOiIxMjM0In0"".c2lnbmF0dXJlMQ"
put conf.php "\$c = ['$pw' => 'hunter2024x'];" "\$d = ['$tok' => \$x];"
put "my conf.env" "${tok^^}=$jwt" "DB_${pw^^}=adm1n@db-host.example" "${sec^^}=adm1n@x"
git -C "$repo" add -A
scan staged
expect_rc 1
expect_out "conf.php:1: key-literal
my conf.env:1: jwt
my conf.env:2: key-literal"
expect_hidden hunter2024x "$jwt" adm1n
ok

# 8. Range mode: only the lines the branch adds over <from>, numbered in the
# new files, over several commits; main's own line and a removed one are not
# reported. A missing argument or an unknown ref exits 2.
new_case "range"
put main.cfg a "$pw = \"main-secret-1\"" b
put old.cfg "$tok = \"gone-secret-2\"" c
git -C "$repo" add -A
git -C "$repo" commit -q -m main
base="$(git -C "$repo" rev-parse HEAD)"
put main.cfg a "$pw = \"main-secret-1\"" b "$sec: \"branch-sec-3\""
git -C "$repo" add -A
git -C "$repo" commit -q -m one
put new/file.txt x "${gh}branchtokenvalue"
put old.cfg c
git -C "$repo" add -A
git -C "$repo" commit -q -m two
scan range "$base" HEAD
expect_rc 1
expect_out "main.cfg:4: key-literal
new/file.txt:2: github-token"
expect_hidden main-secret-1 gone-secret-2 branch-sec-3 branchtokenvalue
scan range HEAD HEAD
expect_rc 0
expect_out ""
scan range "$base"
expect_rc 2
scan range no-such-ref HEAD
expect_rc 2
ok

# 9. Self: the scanner and this test pass their own scan.
new_case "self"
command cp -f -- "$script" "$repo/secret-scan.sh"
command cp -f -- "$here/run.sh" "$repo/run.sh"
scan worktree secret-scan.sh run.sh
expect_rc 0
expect_out ""
ok

# 10. Bearer headers, JWTs and URL credentials: lines 1-7 are positives, the
# rest near misses (placeholders, short or incomplete shapes, prose, ssh).
new_case "bearer, jwt and URL credentials"
put creds.txt \
  "Authorization: $bw $btok" \
  "authorization: $bl $btok" \
  "see $jh.$jp.c2lnbmF0dXJlMQ ok" \
  "x $jh.$jp." \
  "remote: ${u}deploy:s3cretpw@host/o/r.git" \
  "${u}deploy:abc123@host" \
  "x $bw ${gh}abcdefghijklmnop" \
  "my-pkg-$bl $long$long" \
  "$bw <token>" \
  "$bw <redacted>" \
  "$bw \$TOKEN" \
  "a $bw token" \
  "ey""J.." \
  "ey""Jabc.defghijklmnop." \
  "$jh.short." \
  "${u}user@host" \
  "${u}user:abcde@host" \
  "${u}user:<password>@host" \
  "${u}user:\${PASS}@host" \
  "${u}user:{abcdefg}@host" \
  "git@host:owner/repo"
git -C "$repo" add -A
scan staged
expect_rc 1
expect_out "creds.txt:1: bearer-token
creds.txt:2: bearer-token
creds.txt:3: jwt
creds.txt:4: jwt
creds.txt:5: url-credentials
creds.txt:6: url-credentials
creds.txt:7: github-token"
expect_hidden "$btok" "$jh" "$jp" c2lnbmF0dXJlMQ s3cretpw abc123
ok
