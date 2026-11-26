#!/bin/sh
# regress_jsc.sh [files...] — T1 regression tests through tier 1 (jsc): each file is
# compiled and run; the output must match its "// expect:" first line. Files the slice
# cannot compile yet are counted as unsupported, not failed. JSC_SH: another jsc wrapper;
# REGRESS_OUT: another output directory.
D="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${REGRESS_OUT:-$D/build/regress}"; mkdir -p "$OUT"
pass=0; fail=0; unsup=0
files="$@"; [ -z "$files" ] && files="$D/tests/regress/*.js"
for f in $files; do
  b=$(basename "$f" .js)
  want=$(head -1 "$f" | sed 's|^// expect: ||')
  if ! "${JSC_SH:-$D/tools/jsc.sh}" "$f" -o "$OUT/$b" > "$OUT/$b.log" 2>&1; then
    if grep -q "unsupported" "$OUT/$b.log"; then unsup=$((unsup+1)); echo "UNSUP $b: $(grep -o 'unsupported: .*' "$OUT/$b.log" | sort | uniq -c | sort -rn | head -3 | tr '\n' ';')"; continue; fi
    fail=$((fail+1)); echo "FAIL $b: compile: $(grep -v '^$' "$OUT/$b.log" | head -3 | tr '\n' ' ')"; continue
  fi
  got=$(TUNGSTEN_MEMORY_LIMIT=4.5G timeout 60 "$OUT/$b" 2>&1 | tr '\n' '|' | sed 's/|$//')
  if [ "$got" = "$want" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $b: got [$got] want [$want]"; fi
done
echo "regress (tier 1): $pass passed, $fail failed, $unsup unsupported"
