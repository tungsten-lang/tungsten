#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-incremental-contract.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

common_env=(
  TUNGSTEN_INCREMENTAL=0
)

env "${common_env[@]}" TUNGSTEN_CORE_ABI_REPORT="$TMP/a.abi" \
  "$TUNGSTEN" --emit-wire compiler/test/fixtures/core_abi_stable_a.w \
  >"$TMP/a.wire"
env "${common_env[@]}" TUNGSTEN_CORE_ABI_REPORT="$TMP/b.abi" \
  "$TUNGSTEN" --emit-wire compiler/test/fixtures/core_abi_stable_b.w \
  >"$TMP/b.wire"

grep -q '^core reuse: stable$' "$TMP/a.wire"
grep -q '^core reuse: stable$' "$TMP/b.wire"
abi_a="$(awk '/^core abi:/{print $3}' "$TMP/a.wire")"
abi_b="$(awk '/^core abi:/{print $3}' "$TMP/b.wire")"
if [[ -z "$abi_a" || "$abi_a" != "$abi_b" ]]; then
  echo "FAIL: programs with the same protected Core produced different ABI fingerprints" >&2
  exit 1
fi
cmp "$TMP/a.abi" "$TMP/b.abi"

env "${common_env[@]}" "$TUNGSTEN" --fast --emit-wire \
  compiler/test/fixtures/core_abi_stable_a.w >"$TMP/fast.wire"
abi_fast="$(awk '/^core abi:/{print $3}' "$TMP/fast.wire")"
if [[ -z "$abi_fast" || "$abi_fast" == "$abi_a" ]]; then
  echo "FAIL: fast and precise lowering shared a Core ABI compatibility key" >&2
  exit 1
fi

env "${common_env[@]}" "$TUNGSTEN" --emit-wire \
  compiler/test/fixtures/core_abi_subclass_fallback.w >"$TMP/fallback.wire"
grep -Fq 'core reuse: monolithic fallback (program class CoreAbiArrayChild subclasses Core class Array)' \
  "$TMP/fallback.wire"

echo "incremental lowering ABI contract: ok"
