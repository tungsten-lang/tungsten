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

if TUNGSTEN_CACHE_GC_FORCE=1 TUNGSTEN_CACHE_MAX_SIZE_MB=lots \
   bash "$ROOT/bin/commands/cache_gc.sh" "$TMP" >/dev/null 2>&1; then
  printf 'cache gc accepted an invalid size limit\n' >&2
  exit 1
fi

# An empty directory that was just created is a builder about to fill it;
# one that has been empty for days is litter.
mkdir -p "$TMP/just-made" "$TMP/long-empty" "$TMP/held.lock"
touch -t 202001010000 "$TMP/long-empty" "$TMP/held.lock"
TUNGSTEN_CACHE_GC_FORCE=1 bash "$ROOT/bin/commands/cache_gc.sh" "$TMP" >/dev/null
test -d "$TMP/just-made"
test ! -e "$TMP/long-empty"
test -d "$TMP/held.lock"

# Size limit: over the limit, the least recently used files go first, and a
# file used within the last day is never taken, whatever the limit.
SIZED="$TMP/sized"
mkdir -p "$SIZED"
dd if=/dev/zero of="$SIZED/oldest.bin" bs=1024 count=2048 2>/dev/null
for name in older newer; do
  dd if=/dev/zero of="$SIZED/$name.bin" bs=1024 count=1024 2>/dev/null
done
dd if=/dev/zero of="$SIZED/in-use.bin" bs=1024 count=1024 2>/dev/null
touch -t "$(date -v-5d +%Y%m%d%H%M 2>/dev/null || date -d '5 days ago' +%Y%m%d%H%M)" "$SIZED/oldest.bin"
touch -t "$(date -v-4d +%Y%m%d%H%M 2>/dev/null || date -d '4 days ago' +%Y%m%d%H%M)" "$SIZED/older.bin"
touch -t "$(date -v-3d +%Y%m%d%H%M 2>/dev/null || date -d '3 days ago' +%Y%m%d%H%M)" "$SIZED/newer.bin"
# 5 MB present, 4 MB allowed: removing the oldest (2 MB) is enough.
TUNGSTEN_CACHE_GC_FORCE=1 TUNGSTEN_CACHE_MAX_AGE_DAYS=7 TUNGSTEN_CACHE_MAX_SIZE_MB=4 \
  bash "$ROOT/bin/commands/cache_gc.sh" "$SIZED" >/dev/null
test ! -e "$SIZED/oldest.bin"
test -f "$SIZED/older.bin"
test -f "$SIZED/newer.bin"
test -f "$SIZED/in-use.bin"
# 1 MB allowed: every idle file goes, the one in use stays.
TUNGSTEN_CACHE_GC_FORCE=1 TUNGSTEN_CACHE_MAX_AGE_DAYS=7 TUNGSTEN_CACHE_MAX_SIZE_MB=1 \
  bash "$ROOT/bin/commands/cache_gc.sh" "$SIZED" >/dev/null
test ! -e "$SIZED/older.bin"
test ! -e "$SIZED/newer.bin"
test -f "$SIZED/in-use.bin"
# No limit: nothing is taken for size.
dd if=/dev/zero of="$SIZED/idle.bin" bs=1024 count=2048 2>/dev/null
touch -t "$(date -v-3d +%Y%m%d%H%M 2>/dev/null || date -d '3 days ago' +%Y%m%d%H%M)" "$SIZED/idle.bin"
TUNGSTEN_CACHE_GC_FORCE=1 TUNGSTEN_CACHE_MAX_AGE_DAYS=7 TUNGSTEN_CACHE_MAX_SIZE_MB=0 \
  bash "$ROOT/bin/commands/cache_gc.sh" "$SIZED" >/dev/null
test -f "$SIZED/idle.bin"

printf 'cache gc retention contract: ok\n'
