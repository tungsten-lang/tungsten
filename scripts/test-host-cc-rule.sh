#!/usr/bin/env bash
# One rule picks the C compiler for everything Tungsten compiles and links:
# the compiler applies it to every program (host_c_compiler in
# compiler/lib/target.w), and bin/commands/toolchain.sh applies it for the
# build of the compiler's own runtime, bootstrap and doctor. This runs both
# against the same fake toolchains and checks they choose the same clang:
#   TUNGSTEN_CC; else the first LLVM clang >= 22 among clang-N on PATH
#   (highest first), Homebrew's llvm, Homebrew's llvm@N (highest first);
#   Apple clang never counts; else plain `clang`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${TUNGSTEN_COMPILER:-$ROOT/bin/tungsten-compiler}"
REAL_CC="$(command -v clang)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-host-cc.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# fake_clang PATH NAME BANNER: a clang that reports BANNER and otherwise logs
# NAME and runs the real clang (the compiler probes its target through it).
fake_clang() {
  mkdir -p "$(dirname "$1")"
  cat >"$1" <<SH
#!/bin/sh
if [ "\$1" = "--version" ]; then printf '%s\n' "$3"; exit 0; fi
printf '%s\n' "$2" >>"\$CC_LOG"
exec "$REAL_CC" "\$@"
SH
  chmod +x "$1"
}

# world DIR: fake bin/ (clang-N, clang, brew) and a fake Homebrew prefix.
world() {
  local dir="$1"
  mkdir -p "$dir/bin" "$dir/brew/opt"
  fake_clang "$dir/bin/clang" "clang" "Apple clang version 21.0.0 (clang-2100.4.1.1)"
  cat >"$dir/bin/brew" <<SH
#!/bin/sh
[ "\$1" = "--prefix" ] || exit 1
case "\${2:-}" in
  "") printf '%s\n' "$dir/brew" ;;
  llvm) [ -d "$dir/brew/opt/llvm" ] && printf '%s\n' "$dir/brew/opt/llvm" || exit 1 ;;
  *) [ -d "$dir/brew/opt/\$2" ] && printf '%s\n' "$dir/brew/opt/\$2" || exit 1 ;;
esac
SH
  chmod +x "$dir/bin/brew"
}

# shell_choice DIR / compiler_choice DIR: the clang each implementation picks
# with only DIR/bin and the system directories on PATH.
shell_choice() {
  env -u TUNGSTEN_CC PATH="$1/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "$ROOT/bin/commands/toolchain.sh" cc
}
compiler_choice() {
  local dir="$1"
  : >"$dir/cc.log"
  printf '<< 1\n' >"$dir/probe.w"
  (cd "$dir" && env -u TUNGSTEN_CC -u TUNGSTEN_MARCH_ARGS -u TUNGSTEN_CPU CC_LOG="$dir/cc.log" \
     PATH="$dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" TUNGSTEN_ROOT="$ROOT" \
     TUNGSTEN_CACHE_DIR="$dir/cache" TUNGSTEN_LL_PATH="$dir/probe.ll" TUNGSTEN_INCREMENTAL=0 \
     "$COMPILER" compile probe.w --emit-ll >"$dir/compile.out" 2>&1) ||
    fail "compile in $dir failed: $(tail -5 "$dir/compile.out")"
  head -n 1 "$dir/cc.log"
}

# case NAME EXPECTED_SHELL_PATH EXPECTED_LOGGED_NAME
check_case() {
  local name="$1" want_path="$2" want_name="$3" dir="$TMP/$1" got
  got="$(shell_choice "$dir")"
  [ "$got" = "$want_path" ] || fail "$name: toolchain.sh picked '$got', expected '$want_path'"
  got="$(compiler_choice "$dir")"
  [ "$got" = "$want_name" ] || fail "$name: the compiler linked with '$got', expected '$want_name' (toolchain.sh: $want_path)"
  printf 'ok   %s: both pick %s\n' "$name" "$want_name"
}

# 1. clang-N on PATH wins, highest N first, over Homebrew.
d="$TMP/path-clang"; world "$d"
fake_clang "$d/bin/clang-24" "clang-24" "clang version 24.0.1"
fake_clang "$d/bin/clang-22" "clang-22" "Ubuntu clang version 22.1.8"
fake_clang "$d/brew/opt/llvm/bin/clang" "brew-llvm" "Homebrew clang version 25.0.0"
check_case path-clang "$d/bin/clang-24" "clang-24"

# 2. A clang-N whose banner is Apple's or too old does not count; Homebrew's
#    llvm is next.
d="$TMP/brew-llvm"; world "$d"
fake_clang "$d/bin/clang-30" "clang-30" "Apple clang version 30.0.0"
fake_clang "$d/bin/clang-23" "clang-23" "clang version 21.1.0"
fake_clang "$d/brew/opt/llvm/bin/clang" "brew-llvm" "Homebrew clang version 25.0.0"
check_case brew-llvm "$d/brew/opt/llvm/bin/clang" "brew-llvm"

# 3. Homebrew's llvm too old: the newest versioned llvm@N that qualifies.
d="$TMP/brew-versioned"; world "$d"
fake_clang "$d/brew/opt/llvm/bin/clang" "brew-llvm" "Homebrew clang version 21.1.0"
fake_clang "$d/brew/opt/llvm@22/bin/clang" "brew-llvm@22" "Homebrew clang version 22.1.8"
fake_clang "$d/brew/opt/llvm@23/bin/clang" "brew-llvm@23" "Homebrew clang version 23.1.5"
check_case brew-versioned "$d/brew/opt/llvm@23/bin/clang" "brew-llvm@23"

# 4. Nothing new enough: plain clang.
d="$TMP/fallback"; world "$d"
fake_clang "$d/bin/clang-21" "clang-21" "clang version 21.1.0"
check_case fallback "clang" "clang"

# 5. TUNGSTEN_CC wins over everything.
d="$TMP/explicit"; world "$d"
fake_clang "$d/bin/clang-24" "clang-24" "clang version 24.0.1"
fake_clang "$d/bin/my-cc" "my-cc" "clang version 22.1.0"
got="$(env TUNGSTEN_CC="$d/bin/my-cc" PATH="$d/bin:/usr/bin:/bin" bash "$ROOT/bin/commands/toolchain.sh" cc)"
[ "$got" = "$d/bin/my-cc" ] || fail "explicit: toolchain.sh picked '$got'"
: >"$d/cc.log"
printf '<< 1\n' >"$d/probe.w"
(cd "$d" && env CC_LOG="$d/cc.log" TUNGSTEN_CC="$d/bin/my-cc" PATH="$d/bin:/usr/bin:/bin" TUNGSTEN_ROOT="$ROOT" \
   TUNGSTEN_CACHE_DIR="$d/cache" TUNGSTEN_LL_PATH="$d/probe.ll" TUNGSTEN_INCREMENTAL=0 \
   "$COMPILER" compile probe.w --emit-ll >"$d/compile.out" 2>&1) || fail "explicit compile failed"
[ "$(head -n 1 "$d/cc.log")" = "my-cc" ] || fail "explicit: the compiler did not use TUNGSTEN_CC"
printf 'ok   explicit: both use TUNGSTEN_CC\n'
