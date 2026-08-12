#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
CC="${CC:-clang}"
FIXTURE="$ROOT/spec/compiler/carry_unroll_metadata_fixture.w"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-carry-unroll.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

emit_ir() {
  local label="$1"
  local count="$2"
  local ll="$TMP/$label.ll"

  if [[ "$count" == unset ]]; then
    env -u TUNGSTEN_CARRY_UNROLL TUNGSTEN_LL_PATH="$ll" \
      "$TUNGSTEN" compile "$FIXTURE" --release --emit-ll \
      --out "$TMP/$label" >/dev/null
  else
    TUNGSTEN_CARRY_UNROLL="$count" TUNGSTEN_LL_PATH="$ll" \
      "$TUNGSTEN" compile "$FIXTURE" --release --emit-ll \
      --out "$TMP/$label" >/dev/null
  fi

  if ! "$CC" -x ir -c "$ll" -o "$TMP/$label.o" \
    >"$TMP/$label.clang.out" 2>&1; then
    cat "$TMP/$label.clang.out" >&2
    exit 1
  fi
}

require_count() {
  local label="$1"
  local count="$2"
  if ! grep -Fq "llvm.loop.unroll.count\", i32 $count" "$TMP/$label.ll"; then
    echo "FAIL $label: missing llvm.loop.unroll.count $count" >&2
    exit 1
  fi
}

emit_ir default unset
require_count default 8

emit_ir custom 4
require_count custom 4
if grep -Fq 'llvm.loop.unroll.count\", i32 8' "$TMP/custom.ll"; then
  echo "FAIL custom: retained the hardcoded count 8" >&2
  exit 1
fi

emit_ir disabled 0
if grep -Fq 'llvm.loop.unroll.count' "$TMP/disabled.ll"; then
  echo "FAIL disabled: emitted an unroll hint for count 0" >&2
  exit 1
fi

if TUNGSTEN_CARRY_UNROLL=bogus TUNGSTEN_LL_PATH="$TMP/invalid.ll" \
  "$TUNGSTEN" compile "$FIXTURE" --release --emit-ll \
  --out "$TMP/invalid" >"$TMP/invalid.out" 2>&1; then
  echo "FAIL invalid: malformed count compiled successfully" >&2
  exit 1
fi
if ! grep -Fq 'E_LOWER_CARRY_UNROLL' "$TMP/invalid.out"; then
  echo "FAIL invalid: missing E_LOWER_CARRY_UNROLL diagnostic" >&2
  cat "$TMP/invalid.out" >&2
  exit 1
fi

cache_step() {
  local label="$1"
  local count="$2"
  local expected="$3"
  local output
  local hit=no

  output="$(TUNGSTEN_CACHE_DIR="$TMP/cache" TUNGSTEN_INCREMENTAL=1 \
    TUNGSTEN_CARRY_UNROLL="$count" "$TUNGSTEN" compile "$FIXTURE" \
    --release --out "$TMP/cache-probe" 2>&1)"
  if grep -Fq '(cache)' <<<"$output"; then
    hit=yes
  fi
  if [[ "$hit" != "$expected" ]]; then
    echo "FAIL cache $label: expected cache=$expected, got cache=$hit" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

cache_step cold-custom 4 no
cache_step warm-custom 4 yes
cache_step changed-count 8 no

echo "PASS carry-chain unroll metadata and cache identity (default=8, custom=4, disabled=0)"
