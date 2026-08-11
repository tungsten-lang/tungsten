#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-cache-gc-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/nested"
touch "$TMP/fresh.bin" "$TMP/nested/fresh.bin"
touch -t 202001010000 "$TMP/old.bin" "$TMP/nested/old.bin"

TUNGSTEN_CACHE_GC_FORCE=1 TUNGSTEN_CACHE_MAX_AGE_DAYS=7 \
  bash "$ROOT/bin/commands/cache_gc.sh" "$TMP" >/dev/null

test -f "$TMP/fresh.bin"
test -f "$TMP/nested/fresh.bin"
test ! -e "$TMP/old.bin"
test ! -e "$TMP/nested/old.bin"

if TUNGSTEN_CACHE_GC_FORCE=1 TUNGSTEN_CACHE_MAX_AGE_DAYS=bad \
   bash "$ROOT/bin/commands/cache_gc.sh" "$TMP" >/dev/null 2>&1; then
  printf 'cache gc accepted an invalid retention period\n' >&2
  exit 1
fi

printf 'cache gc retention contract: ok\n'
