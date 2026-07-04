#!/bin/sh
# run_mini_interp.sh — compile mini_interp.rb with the current patched
# spinel and time it. One command for the lever-measurement loop:
# land a spinel codegen change, run this, compare the median.
#
# Usage:
#   implementations/spinel/bench/run_mini_interp.sh           # 5 runs, median
#   RUNS=11 implementations/spinel/bench/run_mini_interp.sh   # more samples
#   LABEL=baseline implementations/spinel/bench/run_mini_interp.sh
#
# Compares the spinel-compiled binary against reference Ruby for a
# correctness check (outputs must match) and a speed ratio.
set -eu

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SPINEL="$ROOT/src/patched/spinel"
# Default to the str-hash interp; pass a path as $1 to bench a variant
# (e.g. mini_interp_slots.rb) through the same compile+check+time flow.
SRC="${1:-$ROOT/implementations/spinel/bench/mini_interp.rb}"
CFILE="/tmp/mini_interp.c"
BIN="/tmp/mini_interp_spinel"
RUNS="${RUNS:-5}"
LABEL="${LABEL:-current}"

# The spinel shell script prefers a compiled spinel_codegen binary over
# spinel_codegen.rb. Make sure the binary is current with the .rb so the
# measurement reflects the codegen you just edited.
if [ "$SPINEL/spinel_codegen.rb" -nt "$SPINEL/spinel_codegen" ] 2>/dev/null; then
  echo "NOTE: spinel_codegen.rb is newer than the compiled binary."
  echo "      Rebuild it first:  (cd $SPINEL && rm -f build/stamps/spinel_codegen.rb.stamp && make spinel_codegen)"
  echo "      Otherwise you are measuring the OLD codegen."
fi

echo "=== [$LABEL] compile mini_interp via spinel ==="
t0=$(date +%s.%N 2>/dev/null || date +%s)
"$SPINEL/spinel" "$SRC" -c -o "$CFILE" 2>/tmp/mini_interp.spinel.warn || {
  echo "spinel codegen failed:"; tail -20 /tmp/mini_interp.spinel.warn; exit 1
}
cc -O2 -w -I"$SPINEL/lib" -I"$SPINEL/lib/regexp" "$CFILE" "$SPINEL/lib/libspinel_rt.a" -lm -o "$BIN"
t1=$(date +%s.%N 2>/dev/null || date +%s)
warns=$(grep -c "cannot resolve" /tmp/mini_interp.spinel.warn || true)
echo "build done; spinel 'cannot resolve' warnings: $warns"

echo "=== correctness check (spinel vs ruby) ==="
"$BIN" > /tmp/mini_interp.spinel.out 2>&1
ruby "$SRC" > /tmp/mini_interp.ruby.out 2>&1
if diff -q /tmp/mini_interp.spinel.out /tmp/mini_interp.ruby.out >/dev/null; then
  echo "OK — outputs match:"
  sed 's/^/    /' /tmp/mini_interp.spinel.out
else
  echo "MISMATCH:"
  echo "  spinel:"; sed 's/^/    /' /tmp/mini_interp.spinel.out
  echo "  ruby:";   sed 's/^/    /' /tmp/mini_interp.ruby.out
  exit 1
fi

echo "=== timing: $RUNS runs of spinel binary ==="
i=1
while [ "$i" -le "$RUNS" ]; do
  /usr/bin/time -p "$BIN" >/dev/null 2>/tmp/mini_interp.t
  grep '^real' /tmp/mini_interp.t | awk '{print $2}'
  i=$((i+1))
done | sort -n | awk '
  { a[NR]=$1; sum+=$1 }
  END {
    n=NR; med = (n%2==1) ? a[(n+1)/2] : (a[n/2]+a[n/2+1])/2;
    printf "  min=%.3fs  median=%.3fs  max=%.3fs  (n=%d)\n", a[1], med, a[n], n
  }'
