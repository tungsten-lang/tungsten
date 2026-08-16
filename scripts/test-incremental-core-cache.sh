#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-core-cache-contract.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/src" "$TMP/solo" "$TMP/cache"
export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
cp compiler/test/fixtures/core_abi_stable_a.w "$TMP/src/a.w"
cp compiler/test/fixtures/core_abi_stable_b.w "$TMP/src/b.w"
cp compiler/test/fixtures/closed_world_dispatch.w "$TMP/src/closed.w"
cp compiler/test/fixtures/core_abi_stable_a.w "$TMP/src/a_again.w"

sources=(
  "$TMP/src/a.w"
  "$TMP/src/b.w"
  "$TMP/src/closed.w"
  "$TMP/src/a_again.w"
)
flags=(--emit-ll --ll --release --native --fast --no-debug)

# A and B share one Core closure, closed has another, and a_again must still
# find the first immutable cohort after the intervening miss.
TUNGSTEN_CORE_CACHE_KEY_REPORT="$TMP/key" \
  "$TUNGSTEN" compile-batch "${sources[@]}" "${flags[@]}" -v \
  >"$TMP/batch.log" 2>&1
statuses="$(awk '/core cache:/{print $3}' "$TMP/batch.log" | paste -sd ' ' -)"
if [[ "$statuses" != "miss hit miss hit" ]]; then
  echo "FAIL: expected cache sequence 'miss hit miss hit', got '$statuses'" >&2
  cat "$TMP/batch.log" >&2
  exit 1
fi

key_count="$(find "$TMP" -maxdepth 1 -type f -name 'key.*' | wc -l | tr -d ' ')"
if [[ "$key_count" != "2" ]]; then
  echo "FAIL: expected two exact Core-closure compatibility keys, got $key_count" >&2
  exit 1
fi
if ! grep -l '^lowered-core-v2$' "$TMP"/key.* >/dev/null; then
  echo "FAIL: Core cache key reports are missing their format identity" >&2
  exit 1
fi
if ! grep -l 'core/math.w' "$TMP"/key.* >/dev/null; then
  echo "FAIL: Core cache key report does not contain the loaded Core closure" >&2
  exit 1
fi

# A separate compiler process must reconstruct the frozen Core graph from the
# persistent snapshot and emit the exact same artifact.
TUNGSTEN_LL_PATH="$TMP/solo/disk-hit.ll" \
  "$TUNGSTEN" compile "$TMP/src/a.w" --out "$TMP/solo/disk-hit" \
  "${flags[@]}" -v >"$TMP/solo/disk-hit.log" 2>&1
if ! grep -E 'core cache: hit .+\(.*disk\)' "$TMP/solo/disk-hit.log" >/dev/null; then
  echo "FAIL: fresh compiler process did not report a persistent Core hit" >&2
  cat "$TMP/solo/disk-hit.log" >&2
  exit 1
fi
cmp "$TMP/src/a.ll" "$TMP/solo/disk-hit.ll"
cmp "$TMP/src/a.wc.sidemap" "$TMP/solo/disk-hit.sidemap"

# A truncated snapshot is a miss, never a partially reconstructed graph. The
# cold rebuild atomically replaces it and remains byte-identical.
default_key_report="$(grep -l 'core/math.w' "$TMP"/key.* | head -1)"
default_key="${default_key_report##*.}"
cache_file="$(find "$TUNGSTEN_CACHE_DIR" -maxdepth 1 -type f -name "core-wire-*-$default_key.twc" -print -quit)"
if [[ -z "$cache_file" ]]; then
  echo "FAIL: persistent Core snapshot was not written" >&2
  exit 1
fi
printf 'truncated' >"$cache_file"
TUNGSTEN_LL_PATH="$TMP/solo/corrupt-rebuild.ll" \
  "$TUNGSTEN" compile "$TMP/src/a.w" --out "$TMP/solo/corrupt-rebuild" \
  "${flags[@]}" -v >"$TMP/solo/corrupt-rebuild.log" 2>&1
if ! grep -E 'core cache: miss .+disk stored' "$TMP/solo/corrupt-rebuild.log" >/dev/null; then
  echo "FAIL: corrupt persistent Core snapshot did not fail closed and rebuild" >&2
  cat "$TMP/solo/corrupt-rebuild.log" >&2
  exit 1
fi
cmp "$TMP/src/a.ll" "$TMP/solo/corrupt-rebuild.ll"

# Lowering toggles are part of compatibility, even for an embedder that
# changes its environment between calls in one long-lived process.
TUNGSTEN_BIGINT_CMP0=0 TUNGSTEN_CORE_CACHE_KEY_REPORT="$TMP/tuned-key" \
  TUNGSTEN_LL_PATH="$TMP/solo/tuned.ll" \
  "$TUNGSTEN" compile "$TMP/src/a.w" --out "$TMP/solo/tuned" \
  "${flags[@]}" >"$TMP/tuned.log" 2>&1
tuned_key_report="$(find "$TMP" -maxdepth 1 -type f -name 'tuned-key.*' | head -1)"
if [[ -z "$tuned_key_report" ]] || cmp -s "$default_key_report" "$tuned_key_report"; then
  echo "FAIL: a Core-lowering environment change reused the default key" >&2
  exit 1
fi

# Every warm batch artifact, including the symbol sidecar, must match a fresh
# process that performs the same cold-cache compile.
for src in "${sources[@]}"; do
  name="$(basename "${src%.w}")"
  out="$TMP/solo/$name"
  TUNGSTEN_LL_PATH="$out.ll" \
    "$TUNGSTEN" compile "$src" --out "$out" "${flags[@]}" \
    >"$out.log" 2>&1
  cmp "$TMP/src/$name.ll" "$out.ll"
  cmp "$TMP/src/$name.wc.sidemap" "$out.sidemap"
done

TUNGSTEN_CORE_LOWER_CACHE=0 \
  "$TUNGSTEN" compile-batch "$TMP/src/a.w" "$TMP/src/b.w" \
  "${flags[@]}" -v >"$TMP/disabled.log" 2>&1
disabled="$(awk '/core cache:/{print $3}' "$TMP/disabled.log" | paste -sd ' ' -)"
if [[ "$disabled" != "bypass bypass" ]]; then
  echo "FAIL: disabling the Core cache did not select the ordinary path" >&2
  exit 1
fi

# The product path emits independent binaries, not merely IR. In release/LTO
# mode this also guards the batch-local runtime object bundle (notably the
# mixed LTO/native object case on macOS).
"$TUNGSTEN" compile-batch "$TMP/src/a.w" "$TMP/src/b.w" \
  --release --native --fast --no-debug >"$TMP/link.log" 2>&1
if [[ ! -x "$TMP/src/a.wc" || ! -x "$TMP/src/b.wc" ]]; then
  echo "FAIL: compile-batch did not produce standalone executables" >&2
  exit 1
fi
if [[ "$("$TMP/src/a.wc")" != "9" || "$("$TMP/src/b.wc")" != "8" ]]; then
  echo "FAIL: linked cache miss/hit executables returned unexpected output" >&2
  exit 1
fi

echo "incremental Core cache contract: ok"
