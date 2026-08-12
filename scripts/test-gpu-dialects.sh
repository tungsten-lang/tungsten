#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-gpu-dialects.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cp "$ROOT/spec/compiler/gpu_wgsl_emit_spec.w" "$TMP/fixture.w"

compile_with() {
  local label="$1"
  local dialects="$2"
  TUNGSTEN_GPU_DIALECTS="$dialects" TUNGSTEN_LL_PATH="$TMP/$label.ll" \
    "$TUNGSTEN" compile "$TMP/fixture.w" --out "$TMP/$label" \
    >/dev/null
}

compile_default() {
  env -u TUNGSTEN_GPU_DIALECTS TUNGSTEN_LL_PATH="$TMP/default.ll" \
    "$TUNGSTEN" compile "$TMP/fixture.w" --out "$TMP/default" \
    >/dev/null
}

assert_file() {
  [[ -f "$1" ]] || { echo "FAIL missing $1" >&2; exit 1; }
}

assert_absent() {
  [[ ! -e "$1" ]] || { echo "FAIL unexpected $1" >&2; exit 1; }
}

compile_default
assert_file "$TMP/fixture.metal"
assert_file "$TMP/fixture.cu"
assert_absent "$TMP/fixture.wgsl"

rm "$TMP/fixture.cu" "$TMP/fixture.metal"
compile_with all "metal, cuda, wgsl"
assert_file "$TMP/fixture.metal"
assert_file "$TMP/fixture.cu"
assert_file "$TMP/fixture.wgsl"

rm "$TMP/fixture.cu" "$TMP/fixture.metal" "$TMP/fixture.wgsl"
compile_with none none
assert_file "$TMP/fixture.metal"
assert_absent "$TMP/fixture.cu"
assert_absent "$TMP/fixture.wgsl"

for invalid in vulkan none,cuda cuda,cuda 'cuda,'; do
  rm -f "$TMP/fixture.metal" "$TMP/fixture.cu" "$TMP/fixture.wgsl"
  if TUNGSTEN_GPU_DIALECTS="$invalid" TUNGSTEN_LL_PATH="$TMP/invalid.ll" \
      "$TUNGSTEN" compile "$TMP/fixture.w" --out "$TMP/invalid" \
      >"$TMP/invalid.out" 2>&1; then
    echo "FAIL accepted invalid TUNGSTEN_GPU_DIALECTS=$invalid" >&2
    exit 1
  fi
  grep -Fq E_GPU_DIALECTS "$TMP/invalid.out" || {
    echo "FAIL missing E_GPU_DIALECTS for $invalid" >&2
    cat "$TMP/invalid.out" >&2
    exit 1
  }
  assert_absent "$TMP/fixture.metal"
  assert_absent "$TMP/fixture.cu"
  assert_absent "$TMP/fixture.wgsl"
done

echo "PASS GPU dialect selection (default, all, none, invalid combinations)"
