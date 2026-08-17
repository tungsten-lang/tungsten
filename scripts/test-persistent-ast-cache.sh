#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-persistent-ast-cache.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

if [[ ! -x "$TUNGSTEN" ]]; then
  echo "missing compiler: $TUNGSTEN" >&2
  exit 1
fi

mkdir -p "$TMP/cache"
cp "$ROOT/compiler/test/fixtures/simple.w" "$TMP/input.w"

run_compile() {
  local label="$1"
  shift
  env \
    TUNGSTEN_ROOT="$ROOT" \
    TUNGSTEN_CACHE_DIR="$TMP/cache" \
    TUNGSTEN_INCREMENTAL=0 \
    TUNGSTEN_FRONTEND_DISK_CACHE_MIN_BYTES=0 \
    TUNGSTEN_LL_PATH="$TMP/$label.ll" \
    "$@" \
    "$TUNGSTEN" compile "$TMP/input.w" --emit-ll \
      --release --native --fast --no-debug --verbose \
      > "$TMP/$label.log" 2>&1
}

run_compile cold
grep -q 'disk 0 hits, 3 misses, 3 stores' "$TMP/cold.log"

# A new process restores each packed AST into its own active arena.
run_compile warm
grep -q 'disk 3 hits, 0 misses, 0 stores' "$TMP/warm.log"

# A metadata-only change reads the source, confirms its fingerprint, updates
# the small manifest, and still reuses the AST payload.
touch "$TMP/input.w"
run_compile touched
grep -q '(0/1 fingerprint)' "$TMP/touched.log"
grep -q 'disk 3 hits, 0 misses, 0 stores' "$TMP/touched.log"

# Explicit disablement retains the ordinary parser path.
run_compile disabled env TUNGSTEN_FRONTEND_DISK_CACHE=0

# Corrupt payloads fail closed and are replaced from source. Target/native CPU
# entries share the extension, so restrict the damage to loader AST payloads.
while IFS= read -r payload; do
  printf 'corrupt\n' > "$payload"
done < <(find "$TMP/cache" -maxdepth 1 -type f \
  -name 'loader-parse-*.twc' ! -name '*-manifest.twc' -print)
run_compile corrupt
grep -q 'disk 0 hits, 3 misses, 3 stores' "$TMP/corrupt.log"

cmp "$TMP/cold.ll" "$TMP/warm.ll"
cmp "$TMP/cold.ll" "$TMP/touched.ll"
cmp "$TMP/cold.ll" "$TMP/disabled.ll"
cmp "$TMP/cold.ll" "$TMP/corrupt.ll"

echo "persistent packed AST cache: PASS"
