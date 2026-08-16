#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-parallel-batch-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/src" "$TMP/cache" "$TMP/release-serial" \
  "$TMP/release-parallel" "$TMP/release-save" "$TMP/debug-serial" \
  "$TMP/debug-parallel" "$TMP/debug-save" "$TMP/link-ll"
sources=()
i=0
while [[ $i -lt 8 ]]; do
  path="$TMP/src/$i.w"
  if (( i % 2 == 0 )); then
    cp compiler/test/fixtures/core_abi_stable_a.w "$path"
  else
    cp compiler/test/fixtures/core_abi_stable_b.w "$path"
  fi
  sources+=("$path")
  i=$((i + 1))
done

export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
release_flags=(--release --native --fast --no-debug --emit-ll)

TUNGSTEN_LL_DIR="$TMP/release-serial" \
  "$TUNGSTEN" compile-batch --jobs 1 "${sources[@]}" \
  "${release_flags[@]}" >/dev/null
for i in $(seq 0 7); do
  ll="$(find "$TMP/release-serial" -type f -name "$i.ll" | head -1)"
  test -n "$ll"
  cp "$ll" "$TMP/release-save/$i.ll"
  cp "$TMP/src/$i.wc.sidemap" "$TMP/release-save/$i.sidemap"
done

TUNGSTEN_LL_DIR="$TMP/release-parallel" \
  "$TUNGSTEN" compile-batch --jobs 4 "${sources[@]}" \
  "${release_flags[@]}" -v >"$TMP/release-parallel.log" 2>&1
release_root="$(find "$TMP/release-parallel" -maxdepth 1 -type d -name 'batch-emit.*' | head -1)"
test -n "$release_root"
for i in $(seq 0 7); do
  worker=$((i / 2))
  local_index=$((i % 2))
  cmp "$TMP/release-save/$i.ll" "$release_root/worker-$worker/$local_index.ll"
  cmp "$TMP/release-save/$i.sidemap" "$TMP/src/$i.wc.sidemap"
done
rg -q 'parallel batch: 4 deterministic workers' "$TMP/release-parallel.log"

# Debug output remains exact and keeps the physical frames needed by source
# backtraces; rendered-function reuse itself is release-only.
TUNGSTEN_LL_DIR="$TMP/debug-serial" \
  "$TUNGSTEN" compile-batch --jobs 1 "${sources[@]}" \
  --debug --frame-pointers --emit-ll >/dev/null
for i in $(seq 0 7); do
  ll="$(find "$TMP/debug-serial" -type f -name "$i.ll" | head -1)"
  cp "$ll" "$TMP/debug-save/$i.ll"
done
TUNGSTEN_LL_DIR="$TMP/debug-parallel" \
  "$TUNGSTEN" compile-batch --jobs 4 "${sources[@]}" \
  --debug --frame-pointers --emit-ll >/dev/null
debug_root="$(find "$TMP/debug-parallel" -maxdepth 1 -type d -name 'batch-emit.*' | head -1)"
for i in $(seq 0 7); do
  worker=$((i / 2))
  local_index=$((i % 2))
  cmp "$TMP/debug-save/$i.ll" "$debug_root/worker-$worker/$local_index.ll"
done
rg -q 'noinline "disable-tail-calls"="true"' "$debug_root/worker-0/0.ll"
rg -q 'uwtable "frame-pointer"="all"' "$debug_root/worker-0/0.ll"

# The parent links in source order and owns the runtime phase. Exercise real
# standalone binaries, not only artifact emission.
TUNGSTEN_LL_DIR="$TMP/link-ll" \
  "$TUNGSTEN" compile-batch --jobs 2 "${sources[@]:0:4}" \
  --release --native --fast --no-debug --no-lto >/dev/null
expected=(9 8 9 8)
for i in $(seq 0 3); do
  test -x "$TMP/src/$i.wc"
  actual="$($TMP/src/$i.wc)"
  test "$actual" = "${expected[$i]}"
done

# A worker failure must make the parent fail while retaining diagnostics on
# stderr rather than folding them into normal progress output.
cp spec/cli/camel_case_invalid.w "$TMP/src/invalid.w"
set +e
TUNGSTEN_LL_DIR="$TMP/error-ll" \
  "$TUNGSTEN" compile-batch --jobs 2 "$TMP/src/0.w" "$TMP/src/invalid.w" \
  "${release_flags[@]}" >"$TMP/error.out" 2>"$TMP/error.err"
error_status=$?
set -e
test "$error_status" -ne 0
rg -q 'uppercase ASCII is not valid in identifiers' "$TMP/error.err"

echo "parallel compile-batch: OK"
