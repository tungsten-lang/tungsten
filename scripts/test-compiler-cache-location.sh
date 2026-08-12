#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${TUNGSTEN_COMPILER:-$ROOT/bin/tungsten-compiler}"
REAL_CC="${REAL_CC:-$(command -v clang)}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-cache-location.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT INT TERM

PROJECT="$TMP/project"
CACHE="$PROJECT/build/cache"
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

compile_probe() {
  local trace="$1"
  shift
  : >"$trace"
  (
    cd "$PROJECT"
    env -u TUNGSTEN_CACHE_DIR \
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
[[ ! -e "$TMP/home/.tungsten/cache" ]]

# The compiler Loader's Ruby-only serialized AST cache follows the same
# project root. Exercise its selector directly: `tungsten run --ruby probe.w`
# uses the ordinary tree-walker's separate in-memory loader and therefore is
# not a test of compiler/lib/loader.w.
(
  cd "$PROJECT"
  env -u TUNGSTEN_CACHE_DIR HOME="$TMP/home" \
    "$ROOT/bin/tungsten" run --ruby -e \
      "use $ROOT/core/traits/enumerable; use $ROOT/compiler/lib/loader; << Loader.new().cache_dir()" \
    >"$TMP/ruby-loader-cache.out"
)
grep -qx './build/cache' "$TMP/ruby-loader-cache.out"
[[ ! -e "$TMP/home/.tungsten/cache" ]]

# A warm compile must restore the incremental binary without invoking clang.
compile_probe "$TMP/warm.trace" \
  "$COMPILER" compile --dev --no-lto --out "$PROJECT/probe" "$PROJECT/probe.w"
[[ ! -s "$TMP/warm.trace" ]]

# Wrapper contents participate in both archive and binary identity. Changing a
# same-path tool must create a new archive and force a real link.
printf '\n# changed tool identity\n' >>"$TMP/trace-cc"
compile_probe "$TMP/tool-change.trace" \
  "$COMPILER" compile --dev --no-lto --out "$PROJECT/probe" "$PROJECT/probe.w"
[[ -s "$TMP/tool-change.trace" ]]
archive_count="$(find "$CACHE" -maxdepth 1 -name 'runtime-native-*.a' -type f | wc -l | tr -d ' ')"
[[ "$archive_count" -ge 2 ]]

# An explicit cache root wins over project discovery for every artifact family.
OVERRIDE="$TMP/override-cache"
: >"$TMP/override.trace"
(
  cd "$PROJECT"
  HOME="$TMP/home" \
    TUNGSTEN_ROOT="$ROOT" \
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

printf 'compiler cache location and identity contracts: PASS\n'
