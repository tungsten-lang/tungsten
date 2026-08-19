#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-frontend-parse-cache-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/src" "$TMP/cache" "$TMP/off-ll" "$TMP/on-ll"
export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0

files=()
i=0
while [[ $i -lt 3 ]]; do
  path="$TMP/src/program-$i.w"
  cp compiler/test/fixtures/core_abi_stable_b.w "$path"
  files+=("$path")
  i=$((i + 1))
done
flags=(--release --native --fast --no-debug --emit-ll -v)

TUNGSTEN_FRONTEND_PARSE_CACHE=0 TUNGSTEN_LL_DIR="$TMP/off-ll" \
  "$TUNGSTEN" compile-batch --jobs 1 "${files[@]}" "${flags[@]}" \
  >"$TMP/off.log" 2>&1
cp "$TMP/src/program-0.wc.sidemap" "$TMP/off-0.sidemap"
cp "$TMP/src/program-1.wc.sidemap" "$TMP/off-1.sidemap"
cp "$TMP/src/program-2.wc.sidemap" "$TMP/off-2.sidemap"

TUNGSTEN_FRONTEND_PARSE_CACHE=1 TUNGSTEN_LL_DIR="$TMP/on-ll" \
  "$TUNGSTEN" compile-batch --jobs 1 "${files[@]}" "${flags[@]}" \
  >"$TMP/on.log" 2>&1

if ! grep -E 'frontend parse cache: memory [1-9][0-9]* hits, [0-9]+ misses' \
    "$TMP/on.log" >/dev/null; then
  echo "FAIL: compiled batch did not report parsed-file cache hits" >&2
  cat "$TMP/on.log" >&2
  exit 1
fi

i=0
while [[ $i -lt 3 ]]; do
  off_ll="$(find "$TMP/off-ll" -name "program-$i.ll" -print -quit)"
  on_ll="$(find "$TMP/on-ll" -name "program-$i.ll" -print -quit)"
  cmp "$off_ll" "$on_ll"
  cmp "$TMP/off-$i.sidemap" "$TMP/src/program-$i.wc.sidemap"
  i=$((i + 1))
done

printf 'frontend_cache_probe = 1\n' >"$TMP/invalidation.w"
TUNGSTEN_FRONTEND_PARSE_CACHE=0 \
  "$TUNGSTEN" compile compiler/test/fixtures/frontend_parse_cache_invalidation.w \
    --out "$TMP/invalidation-probe" --dev --native --fast --no-debug \
    >/dev/null 2>&1
if [[ "$("$TMP/invalidation-probe" "$TMP/invalidation.w")" != $'true\ntrue\ntrue' ]]; then
  echo "FAIL: frontend parse cache did not fingerprint/reparse correctly" >&2
  exit 1
fi

# compile-batch --jobs 1 enables the in-process parse cache and then
# clones cached packed ASTs into later entries. Files that `use` the
# compiler emitter (or other large Core graphs) used to die in
# ast_deep_clone with w_node_field_load: field is outside the active
# node allocation. Drive that path on the shipped compiler.
TUNGSTEN_FRONTEND_PARSE_CACHE=1 TUNGSTEN_LL_DIR="$TMP/clone-ll" \
  "$TUNGSTEN" compile-batch --jobs 1 --emit-ll \
    --release --native --fast --no-debug \
    compiler/test/fixtures/core_abi_stable_a.w \
    spec/compiler/one_arg_cached_dispatch_emitter_spec.w \
    spec/core/expression_autoload_spec.w \
    >"$TMP/clone.log" 2>"$TMP/clone.err"
if [[ -s "$TMP/clone.err" ]] && grep -q 'w_node_field_load' "$TMP/clone.err"; then
  echo "FAIL: compile-batch parse-cache clone hit w_node_field_load" >&2
  cat "$TMP/clone.err" >&2
  exit 1
fi
if ! grep -Fq -- '--- Compiling spec/compiler/one_arg_cached_dispatch_emitter_spec.w ---' \
    "$TMP/clone.log"; then
  echo "FAIL: compile-batch did not compile the emitter spec" >&2
  cat "$TMP/clone.log" >&2
  cat "$TMP/clone.err" >&2
  exit 1
fi

echo "frontend parse cache: ok"
