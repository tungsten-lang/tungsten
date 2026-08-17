#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
FAKE_CC="$ROOT/compiler/test/fake_target_clang.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-target-probe-cache.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

if [[ ! -x "$TUNGSTEN" ]]; then
  echo "missing compiler: $TUNGSTEN" >&2
  exit 1
fi

printf '0\n' > "$TMP/count"
mkdir -p "$TMP/cache" "$TMP/batch-cache" "$TMP/ll"

run_compile() {
  local cache="$1"
  local source="$2"
  local output="$3"
  shift 3
  env \
    TUNGSTEN_ROOT="$ROOT" \
    TUNGSTEN_CC="$FAKE_CC" \
    TUNGSTEN_TARGET_FAKE_COUNT="$TMP/count" \
    TUNGSTEN_MARCH_ARGS="${TUNGSTEN_TEST_MARCH:--mcpu=apple-m4}" \
    TUNGSTEN_CACHE_DIR="$cache" \
    TUNGSTEN_INCREMENTAL=0 \
    TUNGSTEN_LL_PATH="$TMP/$output.ll" \
    "$@" \
    "$TUNGSTEN" compile --release --native --fast --emit-ll --verbose "$source" \
    > "$TMP/$output.log" 2>&1
}

run_compile "$TMP/cache" compiler/test/fixtures/simple.w first
[[ "$(< "$TMP/count")" == "3" ]]
grep -q 'target probe cache: miss' "$TMP/first.log"

# A fresh compiler process must use the one-day checksummed disk entry.
run_compile "$TMP/cache" compiler/test/fixtures/simple.w disk
[[ "$(< "$TMP/count")" == "3" ]]
grep -q 'target probe cache: disk' "$TMP/disk.log"
grep -q 'native CPU disk' "$TMP/disk.log"

# A serial batch probes once, then serves later entries from process memory.
env \
  TUNGSTEN_ROOT="$ROOT" \
  TUNGSTEN_CC="$FAKE_CC" \
  TUNGSTEN_TARGET_FAKE_COUNT="$TMP/count" \
  TUNGSTEN_MARCH_ARGS="-mcpu=apple-m4" \
  TUNGSTEN_CACHE_DIR="$TMP/batch-cache" \
  TUNGSTEN_LL_DIR="$TMP/ll" \
  TUNGSTEN_INCREMENTAL=0 \
  "$TUNGSTEN" compile-batch --release --native --fast --emit-ll --jobs 1 --verbose \
  compiler/test/fixtures/simple.w compiler/test/fixtures/fib1.w \
  > "$TMP/batch.log" 2>&1
[[ "$(< "$TMP/count")" == "6" ]]
grep -q 'target probe cache: miss' "$TMP/batch.log"
grep -q 'target probe cache: memory' "$TMP/batch.log"

# The diagnostic switch restores the old two-probe behavior.
run_compile "$TMP/cache" compiler/test/fixtures/simple.w disabled env TUNGSTEN_TARGET_CACHE=0
[[ "$(< "$TMP/count")" == "9" ]]
grep -q 'target probe cache: disabled' "$TMP/disabled.log"

# Target configuration changes must not alias the warmed entry.
run_compile "$TMP/cache" compiler/test/fixtures/simple.w variant env TUNGSTEN_TARGET=arm64-apple-macosx14.0
[[ "$(< "$TMP/count")" == "11" ]]
grep -q 'target probe cache: miss' "$TMP/variant.log"

TUNGSTEN_ROOT="$ROOT" "$TUNGSTEN" run --interpret \
  compiler/test/fixtures/target_probe_cache_validation.w \
  > "$TMP/validation.log" 2>&1
grep -q 'target probe cache validation: PASS' "$TMP/validation.log"

cmp "$TMP/first.ll" "$TMP/disk.ll"
cmp "$TMP/first.ll" "$TMP/disabled.ll"
cmp "$TMP/first.ll" "$TMP/variant.ll"

echo "target probe cache: PASS"
