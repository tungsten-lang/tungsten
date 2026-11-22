#!/bin/sh
# Regression tests for the JS engine: each file's first line is "// expect: <output>"
# (lines joined with "|"). Usage: run.sh <runner binary>  (e.g. a build of jsrun.w or bin/blade --js)
R="$1"; shift
pass=0; fail=0
for f in "$(dirname "$0")"/*.js; do
  want=$(head -1 "$f" | sed 's|^// expect: ||')
  got=$($R "$f" 2>&1 | tr '\n' '|' | sed 's/|$//')
  if [ "$got" = "$want" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $(basename "$f"): got [$got] want [$want]"; fi
done
echo "regress: $pass passed, $fail failed"
