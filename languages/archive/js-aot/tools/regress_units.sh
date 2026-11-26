#!/bin/sh
# regress_units.sh [files…] — T4 with units (PLAN.md M5): each test is compiled as a unit
# (tools/jsu.sh) and run by tools/jsrun3 (tier 0 with the unit loaded: compiled functions
# call tier-0 ones and the reverse). Default: tests/regress/*.js and tests/t1/*.js.
# Outputs must equal each file's "// expect:" line.
D="$(cd "$(dirname "$0")/.." && pwd)"
O="${REGRESS_OUT:-$D/build/units}"
R="$D/build/jsrun3"
mkdir -p "$O"
[ -x "$R" ] || "$D/../../bin/tungsten" -o "$R" --release "$D/tools/jsrun3.w" >&2
files="$*"; [ -n "$files" ] || files="$D/tests/regress/*.js $D/tests/t1/*.js"
pass=0; fail=0; nounit=0
for f in $files; do
  b="$O/$(basename "$f" .js)"
  want=$(head -1 "$f" | sed 's|^// expect: ||')
  if ! TUNGSTEN_MEMORY_LIMIT=4.5G timeout 600 "$D/tools/jsu.sh" "$f" "$b" > "$b.build" 2>&1; then
    nounit=$((nounit+1)); echo "NOUNIT $(basename "$f") ($b.build)"; continue
  fi
  got=$(TUNGSTEN_MEMORY_LIMIT=4.5G timeout 60 "$R" "$f" "$b" 2>"$b.err" | tr '\n' '|' | sed 's/|$//')
  if [ "$got" = "$want" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $(basename "$f"): got [$got] want [$want] ($(head -c 200 "$b.err"))"; fi
done
echo "units: $pass passed, $fail failed, $nounit not built"
