#!/bin/sh

set -eu

PACKAGE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
REPO_ROOT=$(CDPATH= cd -- "$PACKAGE_ROOT/../.." && pwd -P)

SOURCE=$PACKAGE_ROOT/bin/metaflip.w
RUNNER=${TUNGSTEN_RUNNER:-$REPO_ROOT/bin/tungsten}

run_metaflip() {
  if [ -n "${METAFLIP_TEST_BINARY:-}" ]; then
    "$METAFLIP_TEST_BINARY" "$@"
  else
    "$RUNNER" "$SOURCE" -- "$@"
  fi
}

expect_exit_2() {
  label=$1
  expected=$2
  shift 2
  status=0
  output=$(run_metaflip "$@" 2>&1) || status=$?
  if [ "$status" -ne 2 ]; then
    printf 'FAIL %s exited %s, expected 2; output: %s\n' "$label" "$status" "$output" >&2
    exit 1
  fi
  case $output in
    *"$expected"*) ;;
    *) printf 'FAIL %s missing diagnostic %s; output: %s\n' "$label" "$expected" "$output" >&2; exit 1 ;;
  esac
}

for option in \
  --rect-epoch-rounds --rect-restart-nonce --rect-door-ticket \
  -J --walkers --steps --rounds --secs -d --density --cycles \
  --seed-nonce --record --gpu-walkers --gpu-steps --gpu-epoch-rounds \
  --gpu-novelty-size --migrate --archive-size --cpu-near-size \
  --cpu-near-signature-quota --cpu-symmetry-seeds
do
  expect_exit_2 "malformed_$option" "invalid integer for $option: garbage" "$option" garbage
done

expect_exit_2 trailing_junk 'invalid integer for -J: 12threads' -J 12threads
expect_exit_2 positive_overflow 'invalid integer for --gpu-walkers: 9223372036854775808' --gpu-walkers 9223372036854775808
expect_exit_2 negative_overflow 'invalid integer for --rounds: -9223372036854775809' --rounds -9223372036854775809
expect_exit_2 missing_value 'missing value for --steps' --steps
expect_exit_2 malformed_tensor '--tensor must be square' --tensor 5junkx5junk
expect_exit_2 malformed_portfolio '--cpu-work-moves requires four positive' --cpu-work-moves 1m,2m,oops,4m

printf '%s\n' 'PASS malformed, overflowing, and missing CLI numeric values exit 2'
