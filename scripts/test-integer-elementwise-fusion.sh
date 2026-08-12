#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
CC="${CC:-clang}"
FIXTURE="$ROOT/benchmarks/fusion/integer_fusion_bench.w"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-integer-fusion.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

TUNGSTEN_LL_PATH="$TMP/integer-fusion.ll" \
  "$TUNGSTEN" compile "$FIXTURE" --release --emit-ll \
  --out "$TMP/integer-fusion" >/dev/null

if ! "$CC" -x ir -c "$TMP/integer-fusion.ll" \
  -o "$TMP/integer-fusion.o" >"$TMP/clang.out" 2>&1; then
  cat "$TMP/clang.out" >&2
  exit 1
fi

if grep -Eq 'call i64 @w_array_(add|sub|mul)_elem\(' \
    "$TMP/integer-fusion.ll"; then
  echo "FAIL: integer chain retained an intermediate runtime kernel call" >&2
  exit 1
fi

if ! grep -Fq 'call i64 @w_array_new_uninit_sized(i64 66' \
    "$TMP/integer-fusion.ll"; then
  echo "FAIL: integer chain did not allocate one typed fused output" >&2
  exit 1
fi

if ! grep -Fq 'fuse.cond' "$TMP/integer-fusion.ll"; then
  echo "FAIL: integer chain did not emit a fused raw loop" >&2
  exit 1
fi

echo "integer elementwise fusion IR: ok"
