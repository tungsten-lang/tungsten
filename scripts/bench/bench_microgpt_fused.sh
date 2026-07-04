#!/bin/bash
# microGPT fused bench — Metal kernel + threaded Accelerate concurrently.
#
# Spawns the C SME2 bench in the background, runs the Tungsten GPU bench
# in the foreground, and reports both rates.
#
# Pre-requirements:
#   1. The 4 C bench binaries are built in bits/tungsten-llama/lib/microgpt/c/
#   2. The Tungsten sg-streams bench is compiled to /tmp/bench_streams_sg
#      ( bin/tungsten compile -o /tmp/bench_streams_sg \
#          scripts/bench/bench_microgpt_gpu_streams_sg.w )
#
# usage: scripts/bench/bench_microgpt_fused.sh [seconds]

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SECS="${1:-5}"

CPU_BIN="$ROOT/bits/tungsten-llama/lib/microgpt/c/bench_c_sme_mt"
GPU_BIN="${GPU_BIN:-/tmp/bench_streams_sg}"
WEIGHTS="$ROOT/bits/tungsten-llama/lib/models/microgpt/weights_fp32.bin"

if [[ ! -x "$CPU_BIN" ]]; then
  echo "missing $CPU_BIN — run:"
  echo "  cd $ROOT/bits/tungsten-llama/lib/microgpt/c && \\"
  echo "  clang -O3 -march=native -ffast-math bench_c_sme_mt.c -o bench_c_sme_mt -framework Accelerate -lpthread"
  exit 1
fi
if [[ ! -x "$GPU_BIN" ]]; then
  echo "missing $GPU_BIN — run:"
  echo "  bin/tungsten compile -o $GPU_BIN scripts/bench/bench_microgpt_gpu_streams_sg.w"
  exit 1
fi

export MICROGPT_WEIGHTS="$WEIGHTS"

CPU_THREADS=12
CPU_BATCH=3072
# Calibrate N so the CPU run lasts ~SECS seconds.
calibrate_out=$("$CPU_BIN" $CPU_BATCH $CPU_THREADS 200 50)
calibrate_rate=$(echo "$calibrate_out" | awk '{print $(NF-1)}')
N=$(awk -v rate="$calibrate_rate" -v secs="$SECS" -v B="$CPU_BATCH" \
    'BEGIN { n = int(rate * secs / B); if (n < 1000) n = 1000; print n }')

echo "=== microGPT fused: GPU sg-streams + CPU SME2 threaded ==="
echo "  CPU: bench_c_sme_mt  T=$CPU_THREADS  B=$CPU_BATCH  N=$N (~${SECS}s)"
echo "  GPU: bench_streams_sg sweeps S × N_STEPS"
echo

echo "[baseline] CPU alone..."
cpu_alone_out=$("$CPU_BIN" $CPU_BATCH $CPU_THREADS $N 100)
echo "  $cpu_alone_out"
cpu_alone_rate=$(echo "$cpu_alone_out" | awk '{print $(NF-1)}')

echo "[baseline] GPU alone..."
gpu_alone_full=$("$GPU_BIN")
gpu_alone_peak=$(echo "$gpu_alone_full" | awk '/^  S=/ { gsub(/,/, "", $3); if ($3+0 > peak) peak=$3+0 } END { print peak }')
echo "  GPU peak (best S × N_STEPS over sweep): $gpu_alone_peak tok/sec"

echo
echo "[concurrent] GPU + CPU together..."
"$CPU_BIN" $CPU_BATCH $CPU_THREADS $N 100 > /tmp/_fused_cpu.out &
CPU_PID=$!
gpu_concurrent_full=$("$GPU_BIN")
wait $CPU_PID

cpu_concurrent_out=$(cat /tmp/_fused_cpu.out)
cpu_concurrent_rate=$(echo "$cpu_concurrent_out" | awk '{print $(NF-1)}')
gpu_concurrent_peak=$(echo "$gpu_concurrent_full" | awk '/^  S=/ { gsub(/,/, "", $3); if ($3+0 > peak) peak=$3+0 } END { print peak }')

echo "  CPU: $cpu_concurrent_out"
echo "  GPU peak (concurrent): $gpu_concurrent_peak tok/sec"
echo
total=$(awk -v c="$cpu_concurrent_rate" -v g="$gpu_concurrent_peak" 'BEGIN { print c + g }')
sum_alone=$(awk -v c="$cpu_alone_rate" -v g="$gpu_alone_peak" 'BEGIN { print c + g }')
cpu_pct=$(awk -v cc="$cpu_concurrent_rate" -v ca="$cpu_alone_rate" 'BEGIN { print 100 * cc / ca }')
gpu_pct=$(awk -v gc="$gpu_concurrent_peak" -v ga="$gpu_alone_peak" 'BEGIN { print 100 * gc / ga }')
fused_pct=$(awk -v t="$total" -v s="$sum_alone" 'BEGIN { print 100 * t / s }')

echo "=== Summary ==="
printf "  CPU alone:       %14s tok/sec\n" "$cpu_alone_rate"
printf "  GPU alone:       %14s tok/sec\n" "$gpu_alone_peak"
printf "  CPU concurrent:  %14s tok/sec  (%.0f%% of alone)\n" "$cpu_concurrent_rate" "$cpu_pct"
printf "  GPU concurrent:  %14s tok/sec  (%.0f%% of alone)\n" "$gpu_concurrent_peak" "$gpu_pct"
printf "  TOTAL fused:     %14s tok/sec  (%.0f%% of theoretical sum %s)\n" "$total" "$fused_pct" "$sum_alone"
