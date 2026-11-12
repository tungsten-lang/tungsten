#!/usr/bin/env bash
# Where the compiler keeps its artifacts, and what their names cover.
#
# Every checkout, worktree and project shares one build store (default
# ~/.tungsten/build; the compiler's own artifacts in its compile/ directory).
# A project no longer owns a build/cache. TUNGSTEN_BUILD_STORE moves the store,
# TUNGSTEN_CACHE_DIR replaces the compile directory outright. Because the
# directory is shared, runtime objects are named by the CONTENT of the runtime
# sources: a second toolchain root with the same runtime reuses them, and one
# whose runtime differs in any file (including an include fragment) does not.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${TUNGSTEN_COMPILER:-$ROOT/bin/tungsten-compiler}"
REAL_CC="${REAL_CC:-$(command -v clang)}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-cache-location.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT INT TERM

PROJECT="$TMP/project"
STORE="$TMP/home/.tungsten/build"
CACHE="$STORE/compile"
mkdir -p "$PROJECT" "$TMP/home"
printf 'name "cache-location"\n' >"$PROJECT/Bitfile"
printf '<< "cache probe"\n' >"$PROJECT/probe.w"

cat >"$TMP/trace-cc" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TRACE_FILE"
exec "$REAL_CC" "$@"
SH
chmod +x "$TMP/trace-cc"

# compile_probe TRACE command...
compile_probe() {
  local trace="$1"
  shift
  : >"$trace"
  (
    cd "$PROJECT"
    env -u TUNGSTEN_CACHE_DIR -u TUNGSTEN_BUILD_STORE -u TUNGSTEN_HOME \
      HOME="$TMP/home" \
      TUNGSTEN_ROOT="$ROOT" \
      TUNGSTEN_CC="$TMP/trace-cc" \
      TUNGSTEN_INCREMENTAL=1 \
      TRACE_FILE="$trace" \
      REAL_CC="$REAL_CC" \
      "$@"
  )
}

compile_probe "$TMP/first.trace" \
  "$COMPILER" compile --dev --no-lto --out "$PROJECT/probe" "$PROJECT/probe.w"
[[ "$("$PROJECT/probe")" == "cache probe" ]]
find "$CACHE" -maxdepth 1 -name 'runtime-native-*.a' -type f | grep -q .
find "$CACHE" -maxdepth 1 -name 'irbin-*.bin' -type f | grep -q .
find "$CACHE" -maxdepth 1 -name 'irbin-*.manifest' -type f | grep -q .
grep -Fq "$CACHE/runtime-native-" "$TMP/first.trace"
grep -F "$ROOT/runtime/runtime.c" "$TMP/first.trace" | grep -q -- '-fno-omit-frame-pointer'
# Runtime objects must not name the checkout that compiled them.
grep -F "$ROOT/runtime/runtime.c" "$TMP/first.trace" | grep -Fq -- "-ffile-prefix-map=$ROOT/runtime=runtime"
# The project owns no cache, and nothing lands in the pre-store locations.
[[ ! -e "$PROJECT/build" ]]
[[ ! -e "$TMP/home/.tungsten/cache" ]]
[[ ! -e "$TMP/home/.tungsten/build/cache" ]]

# Disable the binary cache and compile to a fresh output. The frame-pointer
# runtime archive itself must stay warm: clang links it into the new program
# instead of recompiling runtime.c for every debug spec.
compile_probe "$TMP/archive-warm.trace" env TUNGSTEN_INCREMENTAL=0 \
  "$COMPILER" compile --dev --no-lto --out "$PROJECT/probe-archive-warm" "$PROJECT/probe.w"
[[ "$("$PROJECT/probe-archive-warm")" == "cache probe" ]]
grep -Fq "$CACHE/runtime-native-" "$TMP/archive-warm.trace"
if grep -Fq "$ROOT/runtime/runtime.c" "$TMP/archive-warm.trace"; then
  printf 'warm frame-pointer compile rebuilt runtime.c\n' >&2
  exit 1
fi

# The compiler Loader's Ruby-only serialized AST cache follows the same
# policy. Exercise its selector directly: `tungsten run --ruby probe.w`
# uses the ordinary tree-walker's separate in-memory loader and therefore is
# not a test of compiler/lib/loader.w.
(
  cd "$PROJECT"
  env -u TUNGSTEN_CACHE_DIR -u TUNGSTEN_BUILD_STORE -u TUNGSTEN_HOME HOME="$TMP/home" \
    "$ROOT/bin/tungsten" run --ruby -e \
      "use $ROOT/core/traits/enumerable; use $ROOT/compiler/lib/loader; << Loader.new().cache_dir()" \
    >"$TMP/ruby-loader-cache.out"
)
grep -Fqx "$CACHE" "$TMP/ruby-loader-cache.out"

# A warm compile must restore the incremental binary without invoking clang.
compile_probe "$TMP/warm.trace" \
  "$COMPILER" compile --dev --no-lto --out "$PROJECT/probe" "$PROJECT/probe.w"
[[ ! -s "$TMP/warm.trace" ]]

# A second toolchain root whose runtime sources are byte-identical shares the
# archive: nothing is recompiled, although the root (and so every runtime
# path) differs. Its programs are its own: the incremental binary is not
# shared, only the content-named runtime objects.
ROOT2="$TMP/root2"
mkdir -p "$ROOT2"
cp -R "$ROOT/runtime" "$ROOT2/runtime"
for part in core languages data bits; do
  ln -s "$ROOT/$part" "$ROOT2/$part"
done
compile_probe "$TMP/root2.trace" env TUNGSTEN_ROOT="$ROOT2" \
  "$COMPILER" compile --dev --no-lto --out "$PROJECT/probe-root2" "$PROJECT/probe.w"
[[ "$("$PROJECT/probe-root2")" == "cache probe" ]]
[[ -s "$TMP/root2.trace" ]]
if grep -Fq "runtime/runtime.c" "$TMP/root2.trace"; then
  printf 'an identical runtime in a second root was recompiled instead of shared\n' >&2
  exit 1
fi
archive_count="$(find "$CACHE" -maxdepth 1 -name 'runtime-native-*.a' -type f | wc -l | tr -d ' ')"
[[ "$archive_count" -eq 1 ]]

# Change one include fragment of the second root's runtime (one that
# runtime.c pulls in but no hand-kept list ever named). Its next link must
# compile its own archive, and the first root must keep the old one warm.
printf '\n/* changed in root2 only */\n' >>"$ROOT2/runtime/prime_lut.inc"
compile_probe "$TMP/root2-changed.trace" env TUNGSTEN_ROOT="$ROOT2" \
  "$COMPILER" compile --dev --no-lto --out "$PROJECT/probe-root2" "$PROJECT/probe.w"
grep -Fq "$ROOT2/runtime/runtime.c" "$TMP/root2-changed.trace"
[[ "$("$PROJECT/probe-root2")" == "cache probe" ]]
archive_count="$(find "$CACHE" -maxdepth 1 -name 'runtime-native-*.a' -type f | wc -l | tr -d ' ')"
[[ "$archive_count" -eq 2 ]]
compile_probe "$TMP/root1-still-warm.trace" env TUNGSTEN_INCREMENTAL=0 \
  "$COMPILER" compile --dev --no-lto --out "$PROJECT/probe-archive-warm" "$PROJECT/probe.w"
if grep -Fq "runtime/runtime.c" "$TMP/root1-still-warm.trace"; then
  printf 'a change in another root invalidated the first root runtime archive\n' >&2
  exit 1
fi

# Wrapper contents participate in both archive and binary identity. Changing a
# same-path tool must create a new archive and force a real link.
printf '\n# changed tool identity\n' >>"$TMP/trace-cc"
compile_probe "$TMP/tool-change.trace" \
  "$COMPILER" compile --dev --no-lto --out "$PROJECT/probe" "$PROJECT/probe.w"
[[ -s "$TMP/tool-change.trace" ]]
archive_count="$(find "$CACHE" -maxdepth 1 -name 'runtime-native-*.a' -type f | wc -l | tr -d ' ')"
[[ "$archive_count" -ge 3 ]]

# TUNGSTEN_BUILD_STORE moves the whole store.
MOVED="$TMP/moved-store"
compile_probe "$TMP/moved.trace" env TUNGSTEN_BUILD_STORE="$MOVED" \
  "$COMPILER" compile --dev --no-lto --out "$PROJECT/probe-moved" "$PROJECT/probe.w"
find "$MOVED/compile" -maxdepth 1 -name 'runtime-native-*.a' -type f | grep -q .
find "$MOVED/compile" -maxdepth 1 -name 'irbin-*.bin' -type f | grep -q .
grep -Fq "$MOVED/compile/runtime-native-" "$TMP/moved.trace"

# An explicit cache directory wins over everything, for every artifact family.
OVERRIDE="$TMP/override-cache"
: >"$TMP/override.trace"
(
  cd "$PROJECT"
  HOME="$TMP/home" \
    TUNGSTEN_ROOT="$ROOT" \
    TUNGSTEN_BUILD_STORE="$MOVED" \
    TUNGSTEN_CACHE_DIR="$OVERRIDE" \
    TUNGSTEN_CC="$TMP/trace-cc" \
    TUNGSTEN_INCREMENTAL=1 \
    TRACE_FILE="$TMP/override.trace" \
    REAL_CC="$REAL_CC" \
    "$COMPILER" compile --dev --no-lto \
      --out "$PROJECT/probe-override" "$PROJECT/probe.w"
)
find "$OVERRIDE" -maxdepth 1 -name 'runtime-native-*.a' -type f | grep -q .
find "$OVERRIDE" -maxdepth 1 -name 'irbin-*.bin' -type f | grep -q .
grep -Fq "$OVERRIDE/runtime-native-" "$TMP/override.trace"
(
  cd "$PROJECT"
  HOME="$TMP/home" TUNGSTEN_CACHE_DIR="$OVERRIDE" \
    "$ROOT/bin/tungsten" run --ruby -e \
      "use $ROOT/core/traits/enumerable; use $ROOT/compiler/lib/loader; << Loader.new().cache_dir()" \
    >"$TMP/ruby-loader-override.out"
)
grep -Fqx "$OVERRIDE" "$TMP/ruby-loader-override.out"

# `-e` materialises its program inside the cache directory. A toolchain
# installed in the same home (HOME/.tungsten/core, HOME/.tungsten/Bitfile)
# must not be mistaken for the program's toolchain or project: the program is
# resolved against the toolchain root that runs it.
mkdir -p "$TMP/home/.tungsten/core"
printf 'this is not a core manifest\n' >"$TMP/home/.tungsten/core/tungsten.w"
printf 'name "installed-toolchain"\n' >"$TMP/home/.tungsten/Bitfile"
eval_out="$(cd "$TMP" && env -u TUNGSTEN_CACHE_DIR -u TUNGSTEN_BUILD_STORE -u TUNGSTEN_HOME HOME="$TMP/home" \
  "$ROOT/bin/tungsten" -e '<< [3, 1, 2].sort.map(->(x) x * 2).sum')"
[[ "$eval_out" == "12" ]]
# (the program was compiled from inside the store: its binary is there)
find "$CACHE/run" -maxdepth 1 -name '*.wc' -type f | grep -q .

printf 'compiler cache location and identity contracts: PASS\n'
