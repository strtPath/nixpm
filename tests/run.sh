#!/usr/bin/env bash
# nixpm unit checks against the working-tree bin/nixpm — host-runnable, no
# network, no real nix touched: PATH shims log every nix call, a coreutils
# symlink farm provides a no-nix PATH, fake meminfo/cgroup files drive the
# RAM gate. `bash tests/run.sh` (also run by CI). Exit 0 = all green.
set -u
REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
TALLY="$TMP/tally"; : > "$TALLY"   # file-backed: subshells can't bump parent vars
step(){ echo "===== $1 ====="; }
ck(){ if [[ "$1" == "$2" ]]; then echo "  PASS: $3"; echo p >> "$TALLY"
      else echo "  FAIL: $3 — got [$1] want [$2]"; echo f >> "$TALLY"; fi }

NIXPM="$REPO/bin/nixpm"
H="$TMP/home"; mkdir -p "$H"
# Isolate every XDG dir so host caches/configs can never leak into a test.
export XDG_CONFIG_HOME="$H/.config" XDG_CACHE_HOME="$H/.cache"
export XDG_STATE_HOME="$H/.local/state" XDG_DATA_HOME="$H/.local/share"
export NIXPM_SEARCH_CACHE_DIR="$H/.cache/nixpm"
export NIXPM_MEMINFO_FILE="$TMP/mi" NIXPM_CGROUP_FILE="$TMP/none"
printf 'MemTotal:        8000000 kB\n' > "$TMP/mi"
printf 'MemTotal:        3000000 kB\n' > "$TMP/mi_small"
printf 'MemTotal:        8000000 kB\nMemAvailable:    3000000 kB\n' > "$TMP/mi_avail"

# no-nix PATH: symlink farm of the externals nixpm shells out to, minus nix.
mkdir -p "$TMP/corebin"
for t in cat date stat mktemp awk sed grep sort tr head tail sleep find \
         basename cut wc rm mv mkdir touch ln cp tee; do
  ln -s "$(command -v "$t")" "$TMP/corebin/$t"
done
NONIXPATH="$TMP/corebin"

# shims that log their invocations
mkdir -p "$TMP/shim"; : > "$TMP/log"
cat > "$TMP/shim/nix" <<EOF
#!/bin/bash
echo "nix \$*" >> "$TMP/log"
for a in "\$@"; do [[ "\$a" == "search" ]] && { printf '* libc\n  The aXb C library\n'; exit 0; }; done
exit 0
EOF
cat > "$TMP/shim/nix-env" <<EOF
#!/bin/bash
echo "nix-env \$*" >> "$TMP/log"
exit 0
EOF
cat > "$TMP/shim/nix-channel" <<EOF
#!/bin/bash
echo "nix-channel \$*" >> "$TMP/log"
exit 0
EOF
chmod +x "$TMP/shim"/*

# ---------- sourced-helper units ----------
sed '$d' "$NIXPM" > "$TMP/helpers"
(
  source "$TMP/helpers"
  # sourcing bin/nixpm re-applied its `set -euo pipefail`; undo it or the
  # first expected-failure helper call silently ends this subshell.
  set +e +u; set +o pipefail 2>/dev/null
  C_B=; C_RST=

  step "R4 _ere_escape + ENVIRON awk"
  e="$(_ere_escape 'lib(foo')"; ck "$e" 'lib\(foo' "paren escaped"
  e="$(_ere_escape 'a.b')";     ck "$e" 'a\.b'     "dot escaped"
  e="$(_ere_escape $'a\\')";    ck "$e" 'a\\'      "lone trailing backslash doubled"
  ck "$(_ere_escape '')" '' "escaper empty stays empty"

  printf '* libc\n  The aXb C library\n* aXb-utils\n  Literal dots like a.b here\n' > "$TMP/idx"
  out="$(_search_cache_grep 'a.b' "$TMP/idx")"
  [[ "$out" == *"aXb-utils"* ]] && [[ "$out" != *"The aXb"* ]] \
    && ck ok ok "a.b matches literal-dot block only, not aXb" || ck "$out" "literal-only" "a.b fixture"
  out="$(_search_cache_grep 'LIBC' "$TMP/idx")"
  [[ "$out" == *libc* ]] && ck ok ok "uppercase query matches (tolower path)" || ck "$out" libc "case-fold query"
  out="$(_search_cache_grep 'lib' "$TMP/idx")"
  [[ "$out" == *libc* ]] && ck ok ok "plain query matches libc" || ck "$out" libc "plain query"
  out="$(_search_cache_grep 'lib(foo' "$TMP/idx" 2>"$TMP/awkerr")"
  ck "$out" "" "regex-metachar query: empty result, no match"
  [[ -s "$TMP/awkerr" ]] && ck "$(cat "$TMP/awkerr")" "clean" "no awk stderr (R4)" || ck ok ok "no awk stderr (R4)"
  _search_cache_grep '' "$TMP/idx" >/dev/null; rc=$?
  ck "$rc" 1 "empty query refused before awk"

  step "R3 _effective_mem_mb detection"
  m="$(NIXPM_MEMINFO_FILE=$TMP/mi _effective_mem_mb)"
  ck "$m" 7812 "MemTotal kB -> MB (no MemAvailable present)"
  m="$(NIXPM_MEMINFO_FILE=$TMP/mi_avail _effective_mem_mb)"
  ck "$m" 2929 "MemAvailable wins over MemTotal"
  printf '3221225472\n' > "$TMP/cg"
  m="$(NIXPM_CGROUP_FILE=$TMP/cg _effective_mem_mb)"
  ck "$m" 3072 "cgroup cap wins"
  printf 'max\n' > "$TMP/cg"
  m="$(NIXPM_CGROUP_FILE=$TMP/cg _effective_mem_mb)"
  ck "$m" 7812 "cgroup 'max' treated absent"
  printf '9223372036854775807\n' > "$TMP/cg"
  m="$(NIXPM_CGROUP_FILE=$TMP/cg _effective_mem_mb)"
  ck "$m" 7812 "v1 unlimited sentinel treated absent"
  m="$(NIXPM_MEMINFO_FILE=$TMP/missing _effective_mem_mb)"
  ck "$m" '' "unreadable meminfo prints nothing"

  step "R3 _full_eval_gate"
  ( NIXPM_MIN_INDEX_MEM_MB=6144 _full_eval_gate 'x' ) 2>/dev/null; ck "$?" 0 "big-enough passes"
  ( NIXPM_MIN_INDEX_MEM_MB=8192 _full_eval_gate 'x' ) > "$TMP/g.out" 2>&1; ck "$?" 1 "below-threshold refuses"
  grep -q 'NIXPM_MIN_INDEX_MEM_MB=0' "$TMP/g.out" && ck ok ok "refusal names the override" || ck miss ok "override hint"
  grep -q 'install <name>' "$TMP/g.out" && ck ok ok "search hint owned by gate" || ck miss ok "gate hint"
  ( NIXPM_MIN_INDEX_MEM_MB=8192 _full_eval_gate 'x' upgrade ) > "$TMP/g2.out" 2>&1
  grep -q 'upgrade <name>' "$TMP/g2.out" && ck ok ok "upgrade hint for upgrade op" || ck miss ok "upgrade hint"
  ( NIXPM_MEMINFO_FILE=$TMP/missing NIXPM_MIN_INDEX_MEM_MB=999999 _full_eval_gate 'x' ) 2>/dev/null
  ck "$?" 0 "unknown size never refuses"
) 2>/dev/null

# ---------- CLI units ----------
run(){ PATH="$1" HOME="$H" "$BASH" "$NIXPM" "${@:2}" ; }

step "CLI: R1/R2 no-nix preflight"
r="$(run "$NONIXPATH" --version 2>&1)"; rc=$?
ck "$rc|$(printf '%s' "$r" | grep -c 'nixpm 0.3.1')" "0|1" "--version works with no nix (R1)"
r="$(run "$NONIXPATH" help 2>&1)"; rc=$?
ck "$rc" 0 "help works with no nix (R1)"
r="$(run "$NONIXPATH" install x 2>&1)"; rc=$?
printf '%s' "$r" | grep -qF '\n' && haslit=yes || haslit=no
ck "$rc/$haslit" "1/no" "install w/o nix: rc=1, no literal backslash-n (R2)"
printf '%s' "$r" | grep -q 'not installed' && printf '%s' "$r" | grep -q 'nixos.org' && ck ok ok "two-line pointer" || ck "$(printf '%s' "$r")" "pointer-lines" "pointer lines"
r="$(run "$NONIXPATH" frobnicate 2>&1)"; rc=$?
printf '%s' "$r" | grep -q 'Unknown command' && ck "$rc" 1 "unknown command beats nix error" || ck "$r" "unknown-msg" "unknown command msg"

step "CLI: R3 gate + R11 gate (shimmed nix, fake small mem)"
export NIXPM_MEMINFO_FILE="$TMP/mi_small"
r="$(run "$TMP/shim:$NONIXPATH" search hello 2>&1)"; rc=$?
ck "$rc" 3 "cold search on small mem: rc=3 (R3)"
grep -q 'search' "$TMP/log" && ck "$(cat "$TMP/log")" "no-search" "gate ran ZERO nix search (R3)" || ck ok ok "zero nix search calls"
grep -q 'Low-RAM' <<<"$r" && ck ok ok "low-RAM notice shown" || ck "$r" "notice" "notice text"
: > "$TMP/log"
r="$(run "$TMP/shim:$NONIXPATH" upgrade 2>&1)"; rc=$?
ck "$rc" 3 "full upgrade on small mem: rc=3 (R11)"
grep -q 'nix-env' "$TMP/log" && ck "$(cat "$TMP/log")" "no-nix-env" "zero nix-env calls before refusal (R11)" || ck ok ok "zero nix-env -u calls"
: > "$TMP/log"
r="$(run "$TMP/shim:$NONIXPATH" upgrade hello 2>&1)"; rc=$?
ck "$rc" 0 "targeted upgrade stays ungated (R11)"
grep -q 'nix-env -u hello' "$TMP/log" && ck ok ok "targeted upgrade ran nix-env -u hello" || ck "$(cat "$TMP/log")" "nix-env -u hello" "targeted cmd"

step "stale index served on low-RAM box (no rebuild, no eval)"
# Same small-mem box, but an index exists on disk (seeded on a bigger box,
# then crossed the TTL). Refusing entirely would make it unsearchable
# forever; serve it with a warning instead. TTL=0 forces stale.
mkdir -p "$NIXPM_SEARCH_CACHE_DIR"
printf '* libc\n  The aXb C library\n' > "$NIXPM_SEARCH_CACHE_DIR/nixpkgs-search"
: > "$TMP/log"
r="$(NIXPM_SEARCH_TTL=0 run "$TMP/shim:$NONIXPATH" search libc 2>&1)"; rc=$?
ck "$rc" 0 "stale index served: rc=0"
printf '%s' "$r" | grep -q 'libc' && ck ok ok "stale results still printed" || ck "$r" "libc" "stale results"
printf '%s' "$r" | grep -qi 'stale' && ck ok ok "staleness warned" || ck "$r" "stale-warn" "stale warning"
grep -q 'nix' "$TMP/log" && ck "$(cat "$TMP/log")" "silent" "stale path called nix anyway" || ck ok ok "stale path zero nix calls"
rm -f "$NIXPM_SEARCH_CACHE_DIR/nixpkgs-search"

step "CLI: warm index fast path + R4 through CLI"
unset NIXPM_SEARCH_TTL
export NIXPM_MEMINFO_FILE="$TMP/mi"
printf '* libc\n  The aXb C library\n* aXb-utils\n  Literal dots like a.b here\n' > "$NIXPM_SEARCH_CACHE_DIR/nixpkgs-search"
# Suite steps run within one second: whole-second mtimes would make the
# channel marker from the upgrade steps "strictly newer" than the seeded
# index. Backdate the marker so the index is legitimately fresh.
[[ -f "$NIXPM_SEARCH_CACHE_DIR/.last-update" ]] && touch -d '1 hour ago' "$NIXPM_SEARCH_CACHE_DIR/.last-update"
: > "$TMP/log"
r="$(run "$TMP/shim:$NONIXPATH" search 'a.b' 2>&1)"; rc=$?
ck "$rc" 0 "warm search rc=0"
printf '%s' "$r" | grep -q 'aXb-utils' && ! printf '%s' "$r" | grep -q 'The aXb' && ck ok ok "warm grep honors literal dot" || ck "$r" "only-literal-block" "warm fixture"
r="$(run "$TMP/shim:$NONIXPATH" search 'lib(foo' 2>&1)"; rc=$?
ck "$rc" 1 "metachar query on warm index: rc=1"
grep -qi 'awk.*fatal\|invalid regexp' <<<"$r" && ck fatal miss "no awk fatal (R4)" || ck ok ok "no awk fatal"
[ -s "$TMP/log" ] && ck "nix called: $(cat "$TMP/log")" "silent" "warm path never calls nix" || ck ok ok "warm path never calls nix"

step "--rebuild forces a fresh index even when warm"
: > "$TMP/log"
r="$(run "$TMP/shim:$NONIXPATH" search --rebuild libc 2>&1)"; rc=$?
ck "$rc" 0 "--rebuild rc=0"
grep -q 'nix .*search' "$TMP/log" && ck ok ok "--rebuild called nix search" || ck "$(cat "$TMP/log")" "search-call" "--rebuild forces eval"
printf '%s' "$r" | grep -q 'libc' && ck ok ok "--rebuild result served from new index" || ck "$r" "libc" "--rebuild result"

step "R5 apps multi-output (shim)"
mkdir -p "$TMP/fakebin/share/applications"; : > "$TMP/fakebin/share/applications/geany.desktop"
cat > "$TMP/shim/nix-env" <<EOF
#!/bin/bash
if [[ "\${1:-}" == "-q" ]]; then echo "geany-4.4 bin=$TMP/fakebin;man=/nonexistent"; fi
exit 0
EOF
chmod +x "$TMP/shim/nix-env"
r="$(run "$TMP/shim:$NONIXPATH" apps 2>&1)"; rc=$?
printf '%s' "$r" | grep -q 'geany' && ck ok ok "multi-output geany found (R5)" || ck "$r" "geany" "apps output"

step "apps survives >5 desktop files (SIGPIPE guard)"
for i in 1 2 3 4 5 6 7; do : > "$TMP/fakebin/share/applications/app$i.desktop"; done
r="$(run "$TMP/shim:$NONIXPATH" apps 2>&1)"; rc=$?
ck "$rc" 0 "apps rc=0 with 7 desktop files"
n="$(printf '%s\n' "$r" | grep -c '^  .*\.desktop$')"
ck "$n" 5 "apps caps listing at 5 without dying"

step "R6 --no-restart both spellings"
cat > "$TMP/shim/nix-env" <<EOF
#!/bin/bash
echo "nix-env \$*" >> "$TMP/log"
exit 0
EOF
chmod +x "$TMP/shim/nix-env"
: > "$TMP/log"
run "$TMP/shim:$NONIXPATH" install hello --no-restart >"$TMP/i1" 2>&1
grep -q -- '--no-restart' "$TMP/log" && ck "$(cat "$TMP/log")" "stripped" "flag leaked into pkg args" || ck ok ok "install hello --no-restart: flag stripped"
grep -q 'hello' "$TMP/log" && ck ok ok "install ran with hello" || ck "$(cat "$TMP/log")" "install-cmd" "install cmd logged"
: > "$TMP/log"
run "$TMP/shim:$NONIXPATH" install --no-restart hello >"$TMP/i2" 2>&1
grep -q -- '--no-restart' "$TMP/log" && ck "$(cat "$TMP/log")" "stripped" "pre-spelling flag leaked" || ck ok ok "install --no-restart hello: flag stripped"

step "R10 bash guard present"
grep -q 'requires bash >= 4' "$NIXPM" && ck ok ok "startup guard present" || ck miss ok "guard"

pass=$(grep -c '^p$' "$TALLY" || true); fail=$(grep -c '^f$' "$TALLY" || true)
echo; echo "RESULT: $pass pass, $fail fail"
[[ $fail -eq 0 ]]
