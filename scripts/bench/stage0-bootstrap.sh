#!/usr/bin/env bash
# Bench stage0 perf: fixtures + bootstrap timing + sample profile + RSS + binary size.
# Appends a results entry to benchmarks/stage0/results.md.
#
# Usage:
#   scripts/bench/stage0-bootstrap.sh [label]
#   SP_GC_DISABLE=1 scripts/bench/stage0-bootstrap.sh "step-A-gc-off"
#   SP_GC_THRESHOLD=4194304 scripts/bench/stage0-bootstrap.sh "step-A-thr-4M"
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

LABEL="${1:-${SP_LABEL:-default}}"
STAGE0="$ROOT/implementations/spinel/build/tungsten-stage0"
RESULTS="$ROOT/benchmarks/stage0/results.md"
BENCH_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
GIT_DIRTY=""
[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] && GIT_DIRTY="-dirty"

if [ ! -x "$STAGE0" ]; then
  echo "stage0 binary missing at $STAGE0" >&2
  echo "build first: bash implementations/spinel/bin/build_stage0 --force" >&2
  exit 1
fi

BIN_SIZE=$(stat -f %z "$STAGE0" 2>/dev/null || stat -c %s "$STAGE0")

# 1) Fixtures (must all pass quickly; flag any that don't)
FIXTURES="arithmetic array hello add while factorial"
FIX_FAILED=""
FIX_TOTAL_MS=0
for f in $FIXTURES; do
  fp="$ROOT/compiler/test/fixtures/$f.w"
  [ -f "$fp" ] || { FIX_FAILED="$FIX_FAILED $f(missing)"; continue; }
  t0=$(date +%s)
  "$STAGE0" "$fp" > /tmp/stage0-fix-out.$$ 2> /tmp/stage0-fix-err.$$
  rc=$?
  t1=$(date +%s)
  ms=$(( (t1 - t0) * 1000 ))
  FIX_TOTAL_MS=$(( FIX_TOTAL_MS + ms ))
  if [ "$rc" -ne 0 ]; then
    FIX_FAILED="$FIX_FAILED $f(rc=$rc)"
  fi
done
[ -n "$FIX_FAILED" ] && FIX_STATUS="FAIL:$FIX_FAILED" || FIX_STATUS="PASS"

# 2) missing_fn.w must print "unknown function: bogus_fn" and exit 1 (regression)
MFN_OUT=$("$STAGE0" "$ROOT/compiler/test/fixtures/missing_fn.w" 2>&1)
MFN_RC=$?
case "$MFN_OUT" in
  *"unknown function: bogus_fn"*) MFN_STATUS="PASS" ;;
  *) MFN_STATUS="FAIL:$MFN_OUT" ;;
esac

# 3) Bootstrap timing — let it run up to 60 min, capture sample at 60s and at 5min.
BOOT_LOG=$(mktemp /tmp/stage0-boot-XXXXXX.log)
SAMPLE_60S=$(mktemp /tmp/stage0-s60-XXXXXX.txt)
SAMPLE_5M=$(mktemp /tmp/stage0-s5m-XXXXXX.txt)
rm -f /tmp/tungsten/hello.ll 2>/dev/null

t0=$(date +%s)
stdbuf -o0 -e0 "$STAGE0" \
  "$ROOT/compiler/tungsten.w" compile "$ROOT/compiler/test/fixtures/hello.w" --verbose \
  > "$BOOT_LOG" 2>&1 &
BOOT_PID=$!

# Wait until process exits OR target seconds elapsed (whichever first)
# Useful so fast runs don't wait artificial sleep windows
wait_until() {
  local target=$1
  local elapsed=0
  while kill -0 "$BOOT_PID" 2>/dev/null && [ "$elapsed" -lt "$target" ]; do
    sleep 1
    elapsed=$(( elapsed + 1 ))
  done
}

# Phase 1: wait up to 60s, sample if still alive
wait_until 60
PEAK_RSS_60S=0
if kill -0 "$BOOT_PID" 2>/dev/null; then
  sample "$BOOT_PID" 2 -mayDie > "$SAMPLE_60S" 2>/dev/null || true
  PEAK_RSS_60S=$(ps -o rss= -p "$BOOT_PID" 2>/dev/null | tr -d ' ' || echo 0)
fi

# Phase 2: wait up to 5min total, sample if still alive
wait_until 300
PEAK_RSS_5M=0
if kill -0 "$BOOT_PID" 2>/dev/null; then
  sample "$BOOT_PID" 2 -mayDie > "$SAMPLE_5M" 2>/dev/null || true
  PEAK_RSS_5M=$(ps -o rss= -p "$BOOT_PID" 2>/dev/null | tr -d ' ' || echo 0)
fi

# Phase 3: wait up to LIMIT seconds (default 60min, override via SP_BENCH_LIMIT)
WAITED=300
LIMIT="${SP_BENCH_LIMIT:-3600}"
while kill -0 "$BOOT_PID" 2>/dev/null; do
  sleep 5
  WAITED=$(( WAITED + 5 ))
  if [ "$WAITED" -ge "$LIMIT" ]; then
    echo "bench: bootstrap exceeded 60min, killing pid $BOOT_PID" >&2
    kill -9 "$BOOT_PID" 2>/dev/null
    break
  fi
done
wait "$BOOT_PID" 2>/dev/null
BOOT_RC=$?
t1=$(date +%s)
BOOT_S=$(( t1 - t0 ))

# 4) Detect outcome
if [ -f /tmp/tungsten/hello.ll ]; then
  BOOT_STATUS="OK"
  HELLO_LL_BYTES=$(stat -f %z /tmp/tungsten/hello.ll 2>/dev/null || stat -c %s /tmp/tungsten/hello.ll || echo 0)
else
  if [ "$BOOT_RC" -eq 0 ]; then
    BOOT_STATUS="EXIT0_NO_LL"
  else
    BOOT_STATUS="FAIL_RC$BOOT_RC"
  fi
  HELLO_LL_BYTES=0
fi

# 5) Top leaves from each sample
SAMPLE_60S_TOP=$(awk '/^Sort by/,/^$/' "$SAMPLE_60S" 2>/dev/null | head -10 | sed 's/  */ /g' | sed 's/^/    /')
SAMPLE_5M_TOP=$(awk '/^Sort by/,/^$/' "$SAMPLE_5M" 2>/dev/null | head -10 | sed 's/  */ /g' | sed 's/^/    /')

# 6) Append to results
mkdir -p "$(dirname "$RESULTS")"
{
  echo ""
  echo "## $LABEL — $BENCH_TS"
  echo ""
  echo "- commit: \`$COMMIT$GIT_DIRTY\`"
  echo "- env: \`SP_GC_DISABLE=${SP_GC_DISABLE:-}\` \`SP_GC_THRESHOLD=${SP_GC_THRESHOLD:-}\` \`SPINEL_EMIT_SYM_SWITCH=${SPINEL_EMIT_SYM_SWITCH:-}\`"
  echo "- stage0 binary: ${BIN_SIZE} bytes"
  echo "- fixtures: $FIX_STATUS (total ${FIX_TOTAL_MS}ms)"
  echo "- missing_fn.w: $MFN_STATUS"
  echo "- bootstrap: $BOOT_STATUS in ${BOOT_S}s, hello.ll=${HELLO_LL_BYTES}B"
  echo "- peak RSS @ 60s: ${PEAK_RSS_60S}KB; @ 5min: ${PEAK_RSS_5M}KB"
  if [ -n "$SAMPLE_60S_TOP" ]; then
    echo ""
    echo "Sample @ 60s top leaves:"
    echo '```'
    echo "$SAMPLE_60S_TOP"
    echo '```'
  fi
  if [ -n "$SAMPLE_5M_TOP" ] && [ "$BOOT_S" -gt 300 ]; then
    echo "Sample @ 5min top leaves:"
    echo '```'
    echo "$SAMPLE_5M_TOP"
    echo '```'
  fi
} >> "$RESULTS"

# 7) Print summary
echo ""
echo "=== bench: $LABEL ($COMMIT$GIT_DIRTY) ==="
echo "fixtures:    $FIX_STATUS (${FIX_TOTAL_MS}ms total)"
echo "missing_fn:  $MFN_STATUS"
echo "bootstrap:   $BOOT_STATUS in ${BOOT_S}s"
echo "hello.ll:    ${HELLO_LL_BYTES} bytes"
echo "RSS @60s:    ${PEAK_RSS_60S} KB"
echo "RSS @5min:   ${PEAK_RSS_5M} KB"
echo "binary:      ${BIN_SIZE} bytes"
echo "results appended to: $RESULTS"

# Cleanup
rm -f "$BOOT_LOG" "$SAMPLE_60S" "$SAMPLE_5M" /tmp/stage0-fix-out.$$ /tmp/stage0-fix-err.$$
