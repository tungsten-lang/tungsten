#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-library-wire-cache-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cache" "$TMP/local" "$TMP/corrupt-cache"
cp compiler/test/fixtures/library_wire_cache/local_lib.w "$TMP/local/local_lib.w"
cp compiler/test/fixtures/library_wire_cache/local_entry.w "$TMP/local/local_entry.w"

export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_FUNCTION_EMIT_CACHE=0
flags=(--release --native --fast --emit-ll --verbose)

compile_ll() {
  local cache_dir="$1"
  local source="$2"
  local label="$3"
  local mode="${4:-1}"
  TUNGSTEN_CACHE_DIR="$cache_dir" \
    TUNGSTEN_LIBRARY_WIRE_CACHE="$mode" \
    TUNGSTEN_LL_PATH="$TMP/$label.ll" \
    "$TUNGSTEN" compile "$source" --out "$TMP/$label" "${flags[@]}" \
    >"$TMP/$label.log" 2>&1
}

# First publish Core, then the raw library snapshot; the third independent
# compiler process must restore the library cohort. Release mode alone selects
# the non-debug frame policy: this test intentionally does not pass --no-debug.
compile_ll "$TMP/cache" compiler/test/fixtures/library_wire_cache/entry_a.w prime-core
rg -Fq 'library WIRE cache: bypass (waiting for a warm Core artifact)' "$TMP/prime-core.log"
compile_ll "$TMP/cache" compiler/test/fixtures/library_wire_cache/entry_a.w store
rg -q 'library WIRE cache: miss .*disk stored' "$TMP/store.log"
compile_ll "$TMP/cache" compiler/test/fixtures/library_wire_cache/entry_a.w hit
rg -q 'library WIRE cache: hit .+ \([0-9]+ functions, 3 files\)' "$TMP/hit.log"

# Cache-off, cold/store, and warm-hit paths must produce the exact same module
# and symbol sidecar.
compile_ll "$TMP/cache" compiler/test/fixtures/library_wire_cache/entry_a.w disabled 0
cmp "$TMP/store.ll" "$TMP/hit.ll"
cmp "$TMP/disabled.ll" "$TMP/hit.ll"
cmp "$TMP/store.sidemap" "$TMP/hit.sidemap"
cmp "$TMP/disabled.sidemap" "$TMP/hit.sidemap"

# The entry body is intentionally different but has the same callable/type
# surface. Its compiler process should reuse the same library key.
compile_ll "$TMP/cache" compiler/test/fixtures/library_wire_cache/entry_b.w cross-entry
rg -q 'library WIRE cache: hit ' "$TMP/cross-entry.log"
compile_ll "$TMP/cache" compiler/test/fixtures/library_wire_cache/entry_b.w cross-entry-disabled 0
cmp "$TMP/cross-entry.ll" "$TMP/cross-entry-disabled.ll"
cmp "$TMP/cross-entry.sidemap" "$TMP/cross-entry-disabled.sidemap"

# The source key contains the exact stat tuple and content digest. A metadata
# touch therefore misses safely, republishes, then hits on the next process.
compile_ll "$TMP/cache" "$TMP/local/local_entry.w" local-prime
rg -Fq 'library WIRE cache: bypass (waiting for a warm Core artifact)' "$TMP/local-prime.log"
compile_ll "$TMP/cache" "$TMP/local/local_entry.w" local-store
rg -q 'library WIRE cache: miss .*disk stored' "$TMP/local-store.log"
touch "$TMP/local/local_lib.w"
compile_ll "$TMP/cache" "$TMP/local/local_entry.w" touched
rg -q 'library WIRE cache: miss .*disk stored' "$TMP/touched.log"
compile_ll "$TMP/cache" "$TMP/local/local_entry.w" touched-hit
rg -q 'library WIRE cache: hit ' "$TMP/touched-hit.log"
cmp "$TMP/touched.ll" "$TMP/touched-hit.ll"
cmp "$TMP/touched.sidemap" "$TMP/touched-hit.sidemap"

# A content edit with unchanged public signatures must also miss: source WIRE,
# not only ABI context, participates in the key.
ruby -e 'path = ARGV[0]; text = File.read(path); File.write(path, text.sub("x * 2", "x * 3"))' "$TMP/local/local_lib.w"
compile_ll "$TMP/cache" "$TMP/local/local_entry.w" edited
rg -q 'library WIRE cache: miss .*disk stored' "$TMP/edited.log"
compile_ll "$TMP/cache" "$TMP/local/local_entry.w" edited-hit
rg -q 'library WIRE cache: hit ' "$TMP/edited-hit.log"
cmp "$TMP/edited.ll" "$TMP/edited-hit.ll"
cmp "$TMP/edited.sidemap" "$TMP/edited-hit.sidemap"

# Entry bodies are omitted, but their callable/type surface is not. Changing a
# parameter shape selects a new context key even though the library is intact.
ruby -e '
  path = ARGV[0]
  text = File.read(path)
  text = text.sub("library_cache_local_entry(x)", "library_cache_local_entry(x, y)")
  text = text.sub("LibraryCacheBox.new(x).plus(library_cache_double(x))", "LibraryCacheBox.new(x).plus(library_cache_double(x)) + y")
  text = text.sub("library_cache_local_entry(14)", "library_cache_local_entry(14, 0)")
  File.write(path, text)
' "$TMP/local/local_entry.w"
compile_ll "$TMP/cache" "$TMP/local/local_entry.w" abi-change
rg -q 'library WIRE cache: miss .*disk stored' "$TMP/abi-change.log"
compile_ll "$TMP/cache" "$TMP/local/local_entry.w" abi-hit
rg -q 'library WIRE cache: hit ' "$TMP/abi-hit.log"
cmp "$TMP/abi-change.ll" "$TMP/abi-hit.ll"
cmp "$TMP/abi-change.sidemap" "$TMP/abi-hit.sidemap"

# Checksummed corruption is an ordinary miss and atomic repair, never a
# partially restored graph.
compile_ll "$TMP/corrupt-cache" "$TMP/local/local_entry.w" corrupt-prime
compile_ll "$TMP/corrupt-cache" "$TMP/local/local_entry.w" corrupt-store
bucket="$(find "$TMP/corrupt-cache" -maxdepth 1 -name 'library-wire-v1-*.twc' | head -1)"
test -n "$bucket"
printf 'broken' >"$bucket"
compile_ll "$TMP/corrupt-cache" "$TMP/local/local_entry.w" corrupt-repair
rg -q 'library WIRE cache: miss .*disk stored' "$TMP/corrupt-repair.log"
compile_ll "$TMP/corrupt-cache" "$TMP/local/local_entry.w" corrupt-hit
rg -q 'library WIRE cache: hit ' "$TMP/corrupt-hit.log"
cmp "$TMP/corrupt-repair.ll" "$TMP/corrupt-hit.ll"
cmp "$TMP/corrupt-repair.sidemap" "$TMP/corrupt-hit.sidemap"

echo "library WIRE cache: OK"
