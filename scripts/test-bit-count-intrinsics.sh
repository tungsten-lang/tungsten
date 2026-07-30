#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${TUNGSTEN_COMPILER:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bit-count-intrinsics.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

TUNGSTEN_ROOT="$ROOT" TUNGSTEN_LL_PATH="$TMP/bit_ops.ll" \
  "$COMPILER" compile "$ROOT/spec/numeric/bit_ops_spec.w" \
  --release --emit-ll --out "$TMP/bit_ops" >/dev/null

require_ir() {
  if ! grep -Fq "$1" "$TMP/bit_ops.ll"; then
    echo "missing expected LLVM IR: $1" >&2
    exit 1
  fi
}

require_ir "call i32 @llvm.ctpop.i32(i32"
require_ir "call i64 @llvm.ctpop.i64(i64"
require_ir "call i32 @llvm.cttz.i32(i32"
require_ir "call i64 @llvm.cttz.i64(i64"
require_ir "i32 %v32, i1 false"
require_ir "i64 %v, i1 false"

echo "PASS BitOps emits zero-defined ctpop/cttz intrinsics"
