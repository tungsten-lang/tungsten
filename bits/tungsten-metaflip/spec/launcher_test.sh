#!/bin/sh

set -eu

PACKAGE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
LAUNCHER=$PACKAGE_ROOT/bin/metaflip
FIXTURES=$PACKAGE_ROOT/spec/fixtures/launcher
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/metaflip-launcher-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

export METAFLIP_TUNGSTEN=$FIXTURES/fake-tungsten
export METAFLIP_LAUNCHER_COMPILE_LOG=$TEST_DIR/compile.log
export TUNGSTEN_METAFLIP_CACHE_DIR=$TEST_DIR/cache

directory_status=0
directory_output=$(METAFLIP_TUNGSTEN=$TEST_DIR $LAUNCHER --help 2>&1) || directory_status=$?
[ "$directory_status" -eq 2 ] || {
  printf 'launcher test: compiler directory exited %s, expected 2\n' "$directory_status" >&2
  exit 1
}
case $directory_output in
  *'METAFLIP_TUNGSTEN does not name an executable'*) ;;
  *) printf 'launcher test: invalid compiler diagnostic missing: %s\n' "$directory_output" >&2; exit 1 ;;
esac

self_test_output=$($LAUNCHER --self-test --no-gpu 2>&1)
case $self_test_output in
  *'metaflip native done: fake self-test exact=1'*) ;;
  *) printf 'launcher test: self-test output was not delegated: %s\n' "$self_test_output" >&2; exit 1 ;;
esac

help_output=$($LAUNCHER --help 2>&1)
case $help_output in
  *'Usage: metaflip [OPTIONS]'*) ;;
  *) printf 'launcher test: help output was not delegated: %s\n' "$help_output" >&2; exit 1 ;;
esac

invalid_status=0
invalid_output=$($LAUNCHER --definitely-invalid 2>&1) || invalid_status=$?
[ "$invalid_status" -eq 2 ] || {
  printf 'launcher test: invalid option exited %s, expected 2\n' "$invalid_status" >&2
  exit 1
}
case $invalid_output in
  *'unknown option --definitely-invalid'*) ;;
  *) printf 'launcher test: invalid-option diagnostic missing: %s\n' "$invalid_output" >&2; exit 1 ;;
esac

compile_count=$(wc -l < "$METAFLIP_LAUNCHER_COMPILE_LOG" | tr -d ' ')
[ "$compile_count" -eq 1 ] || {
  printf 'launcher test: cached CLI compiled %s times, expected 1\n' "$compile_count" >&2
  exit 1
}

compiled_source=$(sed -n '1p' "$METAFLIP_LAUNCHER_COMPILE_LOG")
[ "$compiled_source" = "$PACKAGE_ROOT/bin/metaflip.w" ] || {
  printf 'launcher test: compiled wrong entry point: %s\n' "$compiled_source" >&2
  exit 1
}

printf '%s\n' 'metaflip launcher: ok'
