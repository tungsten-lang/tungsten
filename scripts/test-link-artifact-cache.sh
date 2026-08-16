#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${TUNGSTEN_COMPILER:-$ROOT/bin/tungsten-compiler}"
REAL_CC="${REAL_CC:-$(command -v clang)}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-link-artifact-cache.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/project" "$TMP/cache"
printf 'name "link-artifact-cache"\n' >"$TMP/project/Bitfile"
printf '<< "link artifact cache probe"\n' >"$TMP/project/probe.w"
printf 'int tungsten_link_cache_foreign_probe(void) { return 7; }\n' >"$TMP/project/foreign.c"

cat >"$TMP/trace-cc" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TRACE_FILE"
exec "$REAL_CC" "$@"
SH
chmod +x "$TMP/trace-cc"

compile_probe() {
  local name="$1"
  shift
  : >"$TMP/$name.trace"
  (
    cd "$TMP/project"
    TUNGSTEN_ROOT="$ROOT" \
      TUNGSTEN_CACHE_DIR="$TMP/cache" \
      TUNGSTEN_INCREMENTAL=1 \
      TUNGSTEN_LINK_CACHE=1 \
      TUNGSTEN_CC="$TMP/trace-cc" \
      TUNGSTEN_LL_PATH="$TMP/$name.ll" \
      TRACE_FILE="$TMP/$name.trace" \
      REAL_CC="$REAL_CC" \
      "$@"
  ) >"$TMP/$name.log"
}

profile=(compile --release --native --fast --no-debug --no-lto --verbose)

# Cold link publishes one content-addressed artifact.
compile_probe cold "$COMPILER" "${profile[@]}" --out "$TMP/cold" probe.w
grep -Fq -- "-o $TMP/cold" "$TMP/cold.trace"
[[ "$("$TMP/cold")" == "link artifact cache probe" ]]
[[ "$(find "$TMP/cache" -maxdepth 1 -name 'linkbin-*.bin' -type f | wc -l | tr -d ' ')" == 1 ]]

# A different -o path and explicit LLVM path bypass the early irbin cache, but
# identical LLVM must avoid clang and install the cached executable.
compile_probe warm "$COMPILER" "${profile[@]}" --out "$TMP/warm" probe.w
if grep -Fq -- "-o $TMP/warm" "$TMP/warm.trace"; then
  printf 'warm content-addressed link unexpectedly invoked clang\n' >&2
  exit 1
fi
grep -Fq 'clang (link cache)' "$TMP/warm.log"
cmp "$TMP/cold" "$TMP/warm"

# An mtime-only source change invalidates the early source manifest. The same
# release LLVM still reuses the link artifact.
touch "$TMP/project/probe.w"
compile_probe touched "$COMPILER" "${profile[@]}" --out "$TMP/touched" probe.w
if grep -Fq -- "-o $TMP/touched" "$TMP/touched.trace"; then
  printf 'mtime-only edit unexpectedly relinked identical LLVM\n' >&2
  exit 1
fi
cmp "$TMP/cold" "$TMP/touched"

# Explicit disable is a real linker invocation.
compile_probe disabled env TUNGSTEN_LINK_CACHE=0 \
  "$COMPILER" "${profile[@]}" --out "$TMP/disabled" probe.w
grep -Fq -- "-o $TMP/disabled" "$TMP/disabled.trace"

# Cheap no-LTO links do not pay the content-hash bookkeeping unless explicitly
# opted in. The helper normally forces that opt-in, so unset it in the child.
compile_probe default-nolto-one env -u TUNGSTEN_LINK_CACHE \
  "$COMPILER" "${profile[@]}" --out "$TMP/default-nolto-one" probe.w
compile_probe default-nolto-two env -u TUNGSTEN_LINK_CACHE \
  "$COMPILER" "${profile[@]}" --out "$TMP/default-nolto-two" probe.w
grep -Fq -- "-o $TMP/default-nolto-one" "$TMP/default-nolto-one.trace"
grep -Fq -- "-o $TMP/default-nolto-two" "$TMP/default-nolto-two.trace"

# Dynamic-export mode is a distinct link contract and therefore a distinct
# cache entry; its second output then reuses only that entry.
compile_probe dynamic-cold env TUNGSTEN_DYNAMIC_EXPORTS=1 \
  "$COMPILER" "${profile[@]}" --out "$TMP/dynamic-cold" probe.w
grep -Fq -- "-o $TMP/dynamic-cold" "$TMP/dynamic-cold.trace"
[[ "$(find "$TMP/cache" -maxdepth 1 -name 'linkbin-*.bin' -type f | wc -l | tr -d ' ')" == 2 ]]
compile_probe dynamic-warm env TUNGSTEN_DYNAMIC_EXPORTS=1 \
  "$COMPILER" "${profile[@]}" --out "$TMP/dynamic-warm" probe.w
if grep -Fq -- "-o $TMP/dynamic-warm" "$TMP/dynamic-warm.trace"; then
  printf 'matching dynamic-export link unexpectedly missed cache\n' >&2
  exit 1
fi
cmp "$TMP/dynamic-cold" "$TMP/dynamic-warm"

# Explicit runtime artifacts participate by mtime. Copy the archive generated
# by the cold lane so this test never touches checkout files or timestamps.
runtime_archive="$(find "$TMP/cache" -maxdepth 1 -name 'runtime-native-*.a' -type f | head -n 1)"
[[ -n "$runtime_archive" ]]
cp "$runtime_archive" "$TMP/runtime-copy.a"
compile_probe runtime-cold "$COMPILER" "${profile[@]}" \
  --runtime "$TMP/runtime-copy.a" --out "$TMP/runtime-cold" probe.w
grep -Fq -- "-o $TMP/runtime-cold" "$TMP/runtime-cold.trace"
touch "$TMP/runtime-copy.a"
compile_probe runtime-touched "$COMPILER" "${profile[@]}" \
  --runtime "$TMP/runtime-copy.a" --out "$TMP/runtime-touched" probe.w
grep -Fq -- "-o $TMP/runtime-touched" "$TMP/runtime-touched.trace"
[[ "$(find "$TMP/cache" -maxdepth 1 -name 'linkbin-*.bin' -type f | wc -l | tr -d ' ')" == 4 ]]

# Arbitrary C includes are fail-closed until the driver has a depfile-backed
# transitive header graph. Both invocations must reach clang and publish no
# link artifact.
compile_probe ffi-one env TUNGSTEN_C_INCLUDES="$TMP/project/foreign.c" \
  "$COMPILER" "${profile[@]}" --out "$TMP/ffi-one" probe.w
compile_probe ffi-two env TUNGSTEN_C_INCLUDES="$TMP/project/foreign.c" \
  "$COMPILER" "${profile[@]}" --out "$TMP/ffi-two" probe.w
grep -Fq -- "-o $TMP/ffi-one" "$TMP/ffi-one.trace"
grep -Fq -- "-o $TMP/ffi-two" "$TMP/ffi-two.trace"
[[ "$(find "$TMP/cache" -maxdepth 1 -name 'linkbin-*.bin' -type f | wc -l | tr -d ' ')" == 4 ]]

printf 'content-addressed link artifact cache: PASS\n'
