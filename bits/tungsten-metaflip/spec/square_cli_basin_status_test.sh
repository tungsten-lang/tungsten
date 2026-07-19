#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$PACKAGE_ROOT/../.." && pwd)
COMPILER=${TUNGSTEN_COMPILER:-$REPO_ROOT/bin/tungsten-compiler}
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/metaflip-square-basin-status.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM HUP

BINARY="$TMP_ROOT/metaflip"
RUNTIME="$PACKAGE_ROOT/lib/metaflip"
STATUS="$TMP_ROOT/status.txt"
LIVE_STATUS="$TMP_ROOT/status.live.txt"

"$COMPILER" compile "$RUNTIME/fleet.w" --out "$BINARY" --release --native

status_field() {
  local path=$1
  local key=$2
  awk -v key="$key" '
    {
      for (i = 1; i <= NF; i++) {
        split($i, pair, "=")
        if (pair[1] == key) {
          print pair[2]
          exit
        }
      }
    }
  ' "$path"
}

assert_single_island_semantics() {
  local path=$1
  local expected_state=$2
  local islands unique min_pair on_leader mean_distance

  grep -q "producer_state=$expected_state" "$path"
  islands=$(status_field "$path" cpu_islands)
  unique=$(status_field "$path" cpu_unique_term_sets)
  min_pair=$(status_field "$path" cpu_min_pair_distance)
  on_leader=$(status_field "$path" cpu_on_leader)
  mean_distance=$(status_field "$path" cpu_mean_leader_distance)

  test "$islands" -eq 1
  test "$unique" -eq 1
  test "$min_pair" -eq -1
  test "$on_leader" -ge 0
  test "$on_leader" -le 1
  test "$mean_distance" -ge 0

  # With one island, the integer mean is its exact leader distance. Therefore
  # `on_leader` is one exactly when that mean distance is zero.
  if test "$mean_distance" -eq 0; then
    test "$on_leader" -eq 1
  else
    test "$on_leader" -eq 0
  fi
}

"$BINARY" \
  --tensor 2x2 \
  --runtime-root "$RUNTIME" \
  --state-dir "$TMP_ROOT/state" \
  --best "$TMP_ROOT/best.txt" \
  --status "$STATUS" \
  --near-dir "$TMP_ROOT/near" \
  --run-tag basin-status \
  -J 1 \
  --steps 200000 \
  --rounds 2000000000 \
  --secs 2 \
  --no-gpu \
  --no-tui \
  --quiet \
  --naive \
  > "$TMP_ROOT/output.txt" &
fleet_pid=$!

# Preserve a heartbeat before the terminal atomic rewrite proves the same
# fields are observable while a headless cloud campaign is still running.
attempt=0
while test "$attempt" -lt 300; do
  if test -f "$STATUS" && grep -q 'producer_state=LIVE' "$STATUS"; then
    cp "$STATUS" "$LIVE_STATUS"
    break
  fi
  sleep 0.01
  attempt=$((attempt + 1))
done

test -f "$LIVE_STATUS"
assert_single_island_semantics "$LIVE_STATUS" LIVE

wait "$fleet_pid"
assert_single_island_semantics "$STATUS" DONE
grep -q 'metaflip native done: tensor=2x2' "$TMP_ROOT/output.txt"

printf 'PASS square LIVE/final status exposes CPU basin diversity semantics\n'
