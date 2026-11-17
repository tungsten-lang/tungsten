#!/usr/bin/env bash
# The shared build store: where it is, what `--clear-cache` and
# `cleanup --all` remove from it, and the two compiler behaviours that make
# sharing sound (a dependency list for fingerprinting, and builds whose bytes
# do not name the checkout). Hermetic: everything happens under a temp
# directory; the user's store is never read or written.
#
# See also scripts/test-worktree-compiler-hook.sh (a new worktree gets the
# compiler built from exactly its sources), scripts/test-compiler-cache-location.sh
# (runtime objects are shared by content) and scripts/test-cache-gc.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STORE_SH="$ROOT/bin/commands/store.sh"
COMPILER="${TUNGSTEN_COMPILER:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-build-store.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

clean_env() {
  env -u TUNGSTEN_BUILD_STORE -u TUNGSTEN_CACHE_DIR -u TUNGSTEN_HOME -u HOME "$@"
}

# ── 1. Location policy ──────────────────────────────────────────
[ "$(clean_env HOME=/h bash "$STORE_SH" dir /root)" = "/h/.tungsten/build" ] || fail "default store"
[ "$(clean_env HOME=/h TUNGSTEN_HOME=/th bash "$STORE_SH" dir /root)" = "/th/build" ] || fail "TUNGSTEN_HOME store"
[ "$(clean_env HOME=/h TUNGSTEN_HOME=/th TUNGSTEN_BUILD_STORE=/s bash "$STORE_SH" dir /root)" = "/s" ] || fail "TUNGSTEN_BUILD_STORE"
[ "$(clean_env bash "$STORE_SH" dir /root)" = "/root/.tungsten/build" ] || fail "store without a home"
[ "$(clean_env HOME=/h bash "$STORE_SH" cache-dir /root)" = "/h/.tungsten/build/compile" ] || fail "default cache dir"
[ "$(clean_env HOME=/h TUNGSTEN_BUILD_STORE=/s TUNGSTEN_CACHE_DIR=/c bash "$STORE_SH" cache-dir /root)" = "/c" ] || fail "TUNGSTEN_CACHE_DIR"

# ── 1b. The tuning environment that enters every shared key ─────
# Plain: nothing (so plain builds share keys). Locations, GC knobs and the
# values the keys already hash are not switches; anything else is, including
# a name nobody listed.
[ -z "$(clean_env HOME=/h TUNGSTEN_ROOT=/r TUNGSTEN_HOME=/th TUNGSTEN_BUILD_STORE=/s TUNGSTEN_CACHE_DIR=/c \
        TUNGSTEN_VERSION=1 TUNGSTEN_CPU=native TUNGSTEN_CC=clang TUNGSTEN_MARCH_ARGS=-mcpu=native \
        TUNGSTEN_CACHE_MAX_AGE_DAYS=3 TUNGSTEN_INCREMENTAL=0 bash "$STORE_SH" tuning-environment)" ] ||
  fail "a plain environment has a tuning environment"
tuned="$(clean_env HOME=/h TUNGSTEN_ROOT=/r TUNGSTEN_FREE=0 TUNGSTEN_DEFINES='FAST_MATH=true' \
           TUNGSTEN_SOME_FUTURE_SWITCH=1 bash "$STORE_SH" tuning-environment | tr '\n' ' ')"
[ "$tuned" = "TUNGSTEN_DEFINES=FAST_MATH=true TUNGSTEN_FREE=0 TUNGSTEN_SOME_FUTURE_SWITCH=1 " ] ||
  fail "tuning environment: $tuned"

# ── 2. --clear-cache ────────────────────────────────────────────
make_cache() {
  local dir="$1"
  mkdir -p "$dir/run"
  # incremental binaries of two toolchain roots
  printf 'irbin-v7|x|/src/a.w|/out/a|/roots/mine/bin/tungsten-compiler|1|...|/roots/mine|...\n1\t/src/a.w\n' >"$dir/irbin-aaaa.manifest"
  : >"$dir/irbin-aaaa.bin"
  : >"$dir/irbin-aaaa.sidemap"
  printf 'irbin-v7|x|/src/a.w|/out/a|/roots/other/bin/tungsten-compiler|1|...|/roots/other|...\n1\t/src/a.w\n' >"$dir/irbin-bbbb.manifest"
  : >"$dir/irbin-bbbb.bin"
  # compiled-run binaries of the two roots
  : >"$dir/run/1111.wc"
  printf 'irbin-v7|x|/src/a.w|/c/run/1111.wc.stage|/roots/mine/bin/tungsten-compiler|1|...|/roots/mine|...' >"$dir/run/1111.wc.id"
  : >"$dir/run/2222.wc"
  printf 'irbin-v7|x|/src/a.w|/c/run/2222.wc.stage|/roots/other/bin/tungsten-compiler|1|...|/roots/other|...' >"$dir/run/2222.wc.id"
  printf '<< 1\n' >"$dir/run/eval-0123.w"
  # snapshots nobody can attribute
  : >"$dir/linkbin-1.bin"
  : >"$dir/irshard-v1-1.o"
  : >"$dir/loader-parse-1.twc"
  : >"$dir/loader-parse-1-manifest.twc"
  : >"$dir/core-wire-1-2.twc"
  : >"$dir/library-wire-v1-1-2.twc"
  : >"$dir/core-render-v1-1-2.twc"
  : >"$dir/target-probe-v1-1.twc"
  : >"$dir/native-arm-cpu-v1-1.twc"
  : >"$dir/loader-ast-1.memo"
  mkdir -p "$dir/thinlto-cache"
  : >"$dir/thinlto-cache/llvmcache-1"
  # content-named runtime objects
  : >"$dir/runtime-native-1.a"
  : >"$dir/companion-metal_m-1.o"
  mkdir -p "$dir/runtime-lto-1"
  : >"$dir/runtime-lto-1/runtime.o"
}

SHARED="$TMP/shared-store"
make_cache "$SHARED/compile"
out="$(clean_env HOME="$TMP/nohome" TUNGSTEN_BUILD_STORE="$SHARED" bash "$STORE_SH" clear-cache /roots/mine)"
case "$out" in
  "Cleared 16 cache files ("*) ;;
  *) fail "shared clear-cache reported: $out" ;;
esac
c="$SHARED/compile"
# this root's incremental and run binaries are gone ...
for gone in irbin-aaaa.manifest irbin-aaaa.bin irbin-aaaa.sidemap run/1111.wc run/1111.wc.id \
            linkbin-1.bin irshard-v1-1.o loader-parse-1.twc loader-parse-1-manifest.twc core-wire-1-2.twc \
            library-wire-v1-1-2.twc core-render-v1-1-2.twc target-probe-v1-1.twc \
            native-arm-cpu-v1-1.twc loader-ast-1.memo thinlto-cache; do
  [ ! -e "$c/$gone" ] || fail "shared clear-cache left $gone"
done
# ... another root's are not, nor is anything named by content.
for kept in irbin-bbbb.manifest irbin-bbbb.bin run/2222.wc run/2222.wc.id run/eval-0123.w \
            runtime-native-1.a companion-metal_m-1.o runtime-lto-1/runtime.o; do
  [ -e "$c/$kept" ] || fail "shared clear-cache removed $kept"
done

# An isolated cache directory is the caller's own: every incremental binary goes.
ISOLATED="$TMP/isolated"
make_cache "$ISOLATED"
clean_env HOME="$TMP/nohome" TUNGSTEN_CACHE_DIR="$ISOLATED" bash "$STORE_SH" clear-cache /roots/mine >/dev/null
for gone in irbin-aaaa.bin irbin-bbbb.bin irbin-bbbb.manifest run/1111.wc run/2222.wc run/2222.wc.id linkbin-1.bin; do
  [ ! -e "$ISOLATED/$gone" ] || fail "isolated clear-cache left $gone"
done
[ -e "$ISOLATED/runtime-native-1.a" ] || fail "isolated clear-cache removed a runtime archive"

# The launcher routes --clear-cache here.
launcher_out="$(clean_env HOME="$TMP/nohome" TUNGSTEN_BUILD_STORE="$TMP/empty" "$ROOT/bin/tungsten" --clear-cache)"
[ "$launcher_out" = "Cleared 0 cache files ($TMP/empty/compile)" ] || fail "launcher --clear-cache: $launcher_out"

# ── 3. cleanup --all ────────────────────────────────────────────
mkdir -p "$SHARED/stages" "$SHARED/compilers" "$SHARED/bits" "$SHARED/unrelated"
: >"$SHARED/stages/x" ; : >"$SHARED/unrelated/keep"
clean_env HOME="$TMP/nohome" TUNGSTEN_BUILD_STORE="$SHARED" "$ROOT/bin/tungsten" cleanup --all >/dev/null
for part in compile stages compilers bits; do
  [ ! -e "$SHARED/$part" ] || fail "cleanup --all left $part"
done
[ -e "$SHARED/unrelated/keep" ] || fail "cleanup --all removed something that is not the store's"

if [ ! -x "$COMPILER" ]; then
  printf 'build store contracts: PASS (no compiler: compiler-side checks skipped)\n'
  exit 0
fi

# ── 4. The compiler reports what it read ────────────────────────
WORK="$TMP/work"
mkdir -p "$WORK/lib"
printf -- '-> twice(x)\n  x * 2\n' >"$WORK/lib/helper.w"
printf 'use lib/helper\n<< twice(21)\n' >"$WORK/main.w"
(
  cd "$WORK"
  clean_env HOME="$TMP/nohome" TUNGSTEN_ROOT="$ROOT" TUNGSTEN_CACHE_DIR="$TMP/cc" \
    TUNGSTEN_DEPFILE="$TMP/main.deps" "$COMPILER" compile "$WORK/main.w" --out "$WORK/main" --no-lto >/dev/null
)
[ "$("$WORK/main")" = "42" ] || fail "probe program"
grep -Fqx "$WORK/main.w" "$TMP/main.deps" || fail "depfile misses the entry"
grep -Fqx "$WORK/lib/helper.w" "$TMP/main.deps" || fail "depfile misses a used file"
grep -Fq "$ROOT/core/" "$TMP/main.deps" || fail "depfile misses the core modules the program loads"
if grep -v '^/' "$TMP/main.deps" | grep -q .; then
  fail "depfile has a relative path"
fi

# ── 5. Built from the root by relative path, a program does not name it ──
# (how stage compilers, compiler images and in-checkout bits are built; the
# store shares them between checkouts because of it)
mkdir -p "$ROOT/build/store-test-$$"
trap 'rm -rf "$TMP" "$ROOT/build/store-test-$$"' EXIT INT TERM
cp "$WORK/main.w" "$ROOT/build/store-test-$$/main.w"
mkdir -p "$ROOT/build/store-test-$$/lib"
cp "$WORK/lib/helper.w" "$ROOT/build/store-test-$$/lib/helper.w"
(
  cd "$ROOT"
  clean_env HOME="$TMP/nohome" TUNGSTEN_CACHE_DIR="$TMP/cc" TUNGSTEN_INCREMENTAL=0 \
    "$COMPILER" compile "build/store-test-$$/main.w" --out "$TMP/relative-main" --no-lto >/dev/null
)
[ "$("$TMP/relative-main")" = "42" ] || fail "relative build"
if LC_ALL=C grep -q -F -e "$ROOT/" "$TMP/relative-main"; then
  fail "a program built by relative path names the checkout ($ROOT)"
fi
# The same program built the ordinary way does name it (which is why its
# incremental binary is keyed by path and never shared).
LC_ALL=C grep -q -F -e "$ROOT/" "$WORK/main" || fail "expected an absolute-path build to embed its source names"

printf 'build store contracts: PASS\n'
