#!/usr/bin/env bash
# tungsten-pg test suite: compiles and runs every *_test.w in this directory.
# wire_test.w needs a local Postgres with a `chessbot` database (trust auth);
# set PGWIRE_TEST_DB=0 to skip the live tests.
set -uo pipefail
cd "$(dirname "$0")"
TUNGSTEN="${TUNGSTEN:-$HOME/tungsten/bin/tungsten}"
OUT="${TMPDIR:-/tmp}/tungsten-pg-tests"
mkdir -p "$OUT"

fail=0
for t in *_test.w; do
  name="${t%.w}"
  if [ "$name" = "wire_test" ] && [ "${PGWIRE_TEST_DB:-1}" = "0" ]; then
    echo "SKIP $name (PGWIRE_TEST_DB=0)"
    continue
  fi
  if ! "$TUNGSTEN" compile "$t" -o "$OUT/$name" >"$OUT/$name.build.log" 2>&1; then
    echo "FAIL $name (build)"; tail -5 "$OUT/$name.build.log"; fail=1; continue
  fi
  if "$OUT/$name" >"$OUT/$name.run.log" 2>&1; then
    echo "PASS $name"
  else
    echo "FAIL $name"; tail -10 "$OUT/$name.run.log"; fail=1
  fi
done
exit $fail
