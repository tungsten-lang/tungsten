#!/usr/bin/env bash
# Compile and sample the public bigint `/` and `%` dispatch paths. Same-binary
# A/B via TUNGSTEN_BIGINT_SRC_OPS (unset = native Tungsten, 0 = C pinned).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
PAIRS="${PAIRS:-8}"
OUT="${OUT:-/tmp/tungsten-bigint-opdivmod.txt}"
ROWS="${ROWS:-div:one:2000000 div:one-smallrem:2000000 div:one-high:2000000 div:one-lt:2000000 div:one-nega:2000000 div:one-negb:2000000 div:one-negboth:2000000 div:intarg:2000000 div:fourtwo:1000000 div:sixthree:1000000 div:eightfour:500000 div:eq:200000 div:bz:20000 div:neg:1000000 mod:one:2000000 mod:one-smallrem:2000000 mod:one-high:2000000 mod:one-lt:2000000 mod:one-nega:2000000 mod:one-negb:2000000 mod:one-negboth:2000000 mod:intarg:2000000 mod:fourtwo:1000000 mod:sixthree:1000000 mod:eightfour:500000 mod:eq:200000 mod:bz:20000 mod:neg:1000000}"
BIN="${BIN:-}"
if [ -z "$BIN" ]; then
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-opdivmod.XXXXXX")"
  trap 'rm -rf "$TMP"' EXIT
  BIN="$TMP/bigint-opdivmod"
fi
cd "$ROOT"
if [ -z "${SKIP_COMPILE:-}" ]; then
  echo "Compiling with --release --native --fast..."
  TUNGSTEN_CORE_DISK_CACHE=0 TUNGSTEN_CORE_LOWER_CACHE=0 \
    TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_leaf_public_ref.c" \
    "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_opdivmod_public.w" \
    --release --native --fast --out "$BIN" >/dev/null
fi
"$BIN" check
: > "$OUT"
for row in $ROWS; do
  op="${row%%:*}"; rest="${row#*:}"; s="${rest%%:*}"; it="${rest##*:}"
  p=1
  while [ "$p" -le "$PAIRS" ]; do
    if [ $((p % 2)) -eq 1 ]; then
      "$BIN" "$op" "$s" "$it" | sed "s/^/S|/" >> "$OUT"
      TUNGSTEN_BIGINT_SRC_OPS=0 "$BIN" "$op" "$s" "$it" | sed "s/^/C|/" >> "$OUT"
    else
      TUNGSTEN_BIGINT_SRC_OPS=0 "$BIN" "$op" "$s" "$it" | sed "s/^/C|/" >> "$OUT"
      "$BIN" "$op" "$s" "$it" | sed "s/^/S|/" >> "$OUT"
    fi
    p=$((p + 1))
  done
done
python3 - "$OUT" <<'PY'
import sys
rows = {}
for line in open(sys.argv[1]):
    leg, _, name, total, iters, _ = line.strip().split("|")
    ns = float(total) / int(iters)
    rows.setdefault(name, {"S": [], "C": []})[leg].append(ns)
print(f"{'stratum':<16}{'native med':>12}{'c med':>10}{'med-pair-ratio':>16}")
for name, d in rows.items():
    s, c = d["S"], d["C"]
    sm = sorted(s)[len(s)//2]; cm = sorted(c)[len(c)//2]
    pairs = sorted(si/ci for si, ci in zip(s, c))
    print(f"{name:<16}{sm:>12.3f}{cm:>10.3f}{pairs[len(pairs)//2]:>16.3f}")
PY
echo "raw samples: $OUT"
