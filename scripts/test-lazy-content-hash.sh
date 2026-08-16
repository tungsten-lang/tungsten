#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-lazy-content-hash-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cache"
export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_CORE_REACHABILITY=1
# The mutually recursive function/method SCCs exercise the cycle arm of the
# reduced topological work set as well as the ordinary acyclic path.
program="benchmarks/compiler/return_class_set_scc.w"
flags=(--release --native --fast --no-debug --emit-ll)

# A cold miss must still hash the complete Core closure before publishing it.
TUNGSTEN_LAZY_CONTENT_HASH=1 TUNGSTEN_LL_PATH="$TMP/cold.ll" \
  "$TUNGSTEN" compile "$program" --out "$TMP/cold" "${flags[@]}" -v \
  >"$TMP/cold.log" 2>&1
if grep 'content hash work set:' "$TMP/cold.log" >/dev/null; then
  echo "FAIL: cold Core miss skipped functions needed by the persistent artifact" >&2
  cat "$TMP/cold.log" >&2
  exit 1
fi

TUNGSTEN_LAZY_CONTENT_HASH=0 TUNGSTEN_LL_PATH="$TMP/full.ll" \
  "$TUNGSTEN" compile "$program" --out "$TMP/full" "${flags[@]}" -v \
  >"$TMP/full.log" 2>&1
TUNGSTEN_LAZY_CONTENT_HASH=1 TUNGSTEN_LL_PATH="$TMP/lazy.ll" \
  "$TUNGSTEN" compile "$program" --out "$TMP/lazy" "${flags[@]}" -v \
  >"$TMP/lazy.log" 2>&1

if ! grep -E 'content hash work set: [1-9][0-9]*/[1-9][0-9]* functions \([1-9][0-9]* cached\)' \
    "$TMP/lazy.log" >/dev/null; then
  echo "FAIL: warm Core hit did not exclude cached functions from hash graph work" >&2
  cat "$TMP/lazy.log" >&2
  exit 1
fi
cmp "$TMP/full.ll" "$TMP/lazy.ll"
cmp "$TMP/full.sidemap" "$TMP/lazy.sidemap"

echo "lazy content hash: ok ($(grep -o 'content hash work set: .*' "$TMP/lazy.log"))"
