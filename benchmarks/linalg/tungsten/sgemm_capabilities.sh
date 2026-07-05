#!/usr/bin/env bash
# Tungsten sgemm capabilities benchmark + autotune policy generator.
#
# Runs every available f32 sgemm backend across a size sweep and writes
# ~/.tungsten/sgemm-policy.json containing:
#   - raw measurements per (backend, N)
#   - a recommended dispatcher policy: which backend wins at which N
#
# Usage:
#   benchmarks/linalg/tungsten/sgemm_capabilities.sh         # run all backends
#   benchmarks/linalg/tungsten/sgemm_capabilities.sh --rebuild  # rebuild binaries first
#
# Assumes each backend's binary has already been built. With --rebuild,
# rebuilds them via their respective build scripts / direct compile.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$REPO"

BENCH_DIR="$REPO/benchmarks/linalg/tungsten"
OUT_DIR="$HOME/.tungsten"
OUT_FILE="$OUT_DIR/sgemm-policy.json"
mkdir -p "$OUT_DIR"

# Sizes to sweep. K is iters-per-size; small N gets more iters to amortize
# clock noise, large N gets few so the sweep finishes in <60 s total.
SIZES=(128 256 512 1024 2048 4096 8192)
ITERS=(500 200 100 50  10   3    2)

# Backends to measure. Each entry: <impl_id>:<binary_path>:<requires_mlx_link>
BACKENDS=(
  "accelerate:$BENCH_DIR/matmul_accelerate:0"
  "mlx:$BENCH_DIR/matmul_mlx:1"
  "mlx-batch:$BENCH_DIR/matmul_mlx_batch:1"
  "mps:$BENCH_DIR/matmul_mps:0"
  "mpsg:$BENCH_DIR/matmul_mpsg:0"
  # Use REUSABLE wrappers (what sgemm_auto can actually dispatch to)
  "metal-tiled:$BENCH_DIR/matmul_metal_sgemm:0"
  "metal-bf16:$BENCH_DIR/matmul_metal_sgemm_bf16:0"
)

if [[ "${1:-}" == "--rebuild" ]]; then
  echo "==== Rebuilding binaries ===="
  ./bin/tungsten -o "$BENCH_DIR/matmul_accelerate" "$BENCH_DIR/matmul_accelerate.w" >/dev/null
  BUILD_ONLY=1 "$BENCH_DIR/build_mlx_bench.sh" >/dev/null
  MLXC_PREFIX="$(brew --prefix mlx-c)"
  MLX_PREFIX="$(brew --prefix mlx)"
  export TUNGSTEN_C_INCLUDES="$REPO/runtime/mlx_bridge.c:-I$MLXC_PREFIX/include:-I$MLX_PREFIX/include:-L$MLXC_PREFIX/lib:-lmlxc:-Wl,-rpath,$MLXC_PREFIX/lib:-Wl,-rpath,$MLX_PREFIX/lib"
  ./bin/tungsten -o "$BENCH_DIR/matmul_mlx_batch" "$BENCH_DIR/matmul_mlx_batch.w" >/dev/null
  unset TUNGSTEN_C_INCLUDES
  export TUNGSTEN_C_INCLUDES="$REPO/runtime/mps_bridge.m:-framework MetalPerformanceShaders:-framework MetalPerformanceShadersGraph"
  ./bin/tungsten -o "$BENCH_DIR/matmul_mps" "$BENCH_DIR/matmul_mps.w" >/dev/null
  ./bin/tungsten -o "$BENCH_DIR/matmul_mpsg" "$BENCH_DIR/matmul_mpsg.w" >/dev/null
  unset TUNGSTEN_C_INCLUDES
  ./bin/tungsten -o "$BENCH_DIR/matmul_metal_tiled" "$BENCH_DIR/matmul_metal_tiled.w" >/dev/null
  ./bin/tungsten -o "$BENCH_DIR/matmul_metal_bf16" "$BENCH_DIR/matmul_metal_bf16.w" >/dev/null
  echo "  (done)"
fi

# Detect hardware once.
DEVICE="$(sysctl -n machdep.cpu.brand_string)"
GPU_CORES="$(system_profiler SPDisplaysDataType 2>/dev/null | awk '/Total Number of Cores:/ {print $5; exit}' || echo unknown)"
TS="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# Collect JSON-lines results into a temp file.
RAW="$(mktemp)"
trap 'rm -f "$RAW"' EXIT

echo "==== Sweep: $DEVICE, GPU cores=$GPU_CORES ===="
for spec in "${BACKENDS[@]}"; do
  IFS=':' read -r impl bin _rest <<< "$spec"
  if [[ ! -x "$bin" ]]; then
    echo "  [skip $impl: missing binary $bin]"
    continue
  fi
  for i in "${!SIZES[@]}"; do
    N="${SIZES[$i]}"
    K="${ITERS[$i]}"
    line=$("$bin" "$N" "$K" 2>/dev/null | tr -d '\n' | tr -s ' ')
    # Each bench prints "{"impl":...,"N":<n>,"K":<k>,"median_ms":<x>,"gflops":<y>}"
    # but with intervening newlines we collapsed. Extract gflops with sed.
    gflops=$(echo "$line" | sed -nE 's/.*"gflops":[[:space:]]*([0-9.]+).*/\1/p')
    median=$(echo "$line" | sed -nE 's/.*"median_ms":[[:space:]]*([0-9.]+).*/\1/p')
    printf "  %-12s N=%-5d  %8.1f GFLOPS  %8.3f ms/call\n" "$impl" "$N" "${gflops:-0}" "${median:-0}"
    echo "    {\"backend\":\"$impl\",\"N\":$N,\"K\":$K,\"gflops\":${gflops:-0},\"median_ms\":${median:-0}}," >> "$RAW"
  done
done

# Strip trailing comma from the JSON-lines.
RAW_JSON=$(sed '$ s/,$//' "$RAW")

# Build the recommended policy: per-N winner, deduplicated into thresholds.
# We exclude *-batch variants from the SINGLE-CALL policy — batch backends
# amortize K matmuls into one sync barrier so their per-call numbers are
# inflated relative to a one-shot sgemm dispatch. They remain in the raw
# results JSON for callers that DO batch.
echo "==== Picking per-N winners (single-call only — -batch excluded) ===="
prev_winner=""
declare -a POLICY_ARR
for i in "${!SIZES[@]}"; do
  N="${SIZES[$i]}"
  winner=$(grep "\"N\":$N," "$RAW" | grep -v '"backend":"[a-z-]*-batch"' | sort -t: -k5 -nr | head -1 | sed -nE 's/.*"backend":"([^"]+)".*/\1/p')
  winner_gflops=$(grep "\"N\":$N," "$RAW" | grep -v '"backend":"[a-z-]*-batch"' | sort -t: -k5 -nr | head -1 | sed -nE 's/.*"gflops":([0-9.]+).*/\1/p')
  echo "  N=$N → $winner ($winner_gflops GFLOPS)"
  if [[ "$winner" != "$prev_winner" ]]; then
    POLICY_ARR+=("    {\"n_max\": $N, \"backend\": \"$winner\", \"gflops\": $winner_gflops}")
    prev_winner="$winner"
  else
    last_idx=$((${#POLICY_ARR[@]} - 1))
    POLICY_ARR[$last_idx]="    {\"n_max\": $N, \"backend\": \"$winner\", \"gflops\": $winner_gflops}"
  fi
done

# Also pick the best BATCHED backend (one entry per N), for callers that
# can batch (e.g. transformer training inner loop).
echo "==== Picking per-N batch winners ===="
declare -a BATCH_POLICY_ARR
prev_batch=""
for i in "${!SIZES[@]}"; do
  N="${SIZES[$i]}"
  # Only consider -batch backends; if none, skip.
  bwinner=$(grep "\"N\":$N," "$RAW" | grep '"backend":"[a-z-]*-batch"' | sort -t: -k5 -nr | head -1 | sed -nE 's/.*"backend":"([^"]+)".*/\1/p')
  bgflops=$(grep "\"N\":$N," "$RAW" | grep '"backend":"[a-z-]*-batch"' | sort -t: -k5 -nr | head -1 | sed -nE 's/.*"gflops":([0-9.]+).*/\1/p')
  if [[ -z "$bwinner" ]]; then continue; fi
  echo "  N=$N → $bwinner ($bgflops GFLOPS)"
  if [[ "$bwinner" != "$prev_batch" ]]; then
    BATCH_POLICY_ARR+=("    {\"n_max\": $N, \"backend\": \"$bwinner\", \"gflops\": $bgflops}")
    prev_batch="$bwinner"
  else
    bi=$((${#BATCH_POLICY_ARR[@]} - 1))
    BATCH_POLICY_ARR[$bi]="    {\"n_max\": $N, \"backend\": \"$bwinner\", \"gflops\": $bgflops}"
  fi
done

# Last threshold is "anything above the largest size we measured" —
# mark as the catch-all by setting n_max to a huge value.
last_idx=$((${#POLICY_ARR[@]} - 1))
POLICY_ARR[$last_idx]="$(echo "${POLICY_ARR[$last_idx]}" | sed 's/n_max": [0-9]*/n_max": 1000000/')"
if [[ ${#BATCH_POLICY_ARR[@]} -gt 0 ]]; then
  bi=$((${#BATCH_POLICY_ARR[@]} - 1))
  BATCH_POLICY_ARR[$bi]="$(echo "${BATCH_POLICY_ARR[$bi]}" | sed 's/n_max": [0-9]*/n_max": 1000000/')"
fi

join_lines() {
  local IFS=$'\n'
  local first=1
  for line in "$@"; do
    if [[ $first -eq 1 ]]; then echo -n "$line"; first=0
    else echo -e ",\n$line"; fi
  done
}

POLICY_JSON=$(join_lines "${POLICY_ARR[@]}")
BATCH_JSON=$(join_lines "${BATCH_POLICY_ARR[@]:-}")

cat > "$OUT_FILE" <<EOF
{
  "version": 1,
  "ts": "$TS",
  "device": "$DEVICE",
  "gpu_cores": "$GPU_CORES",
  "dtype": "f32",
  "policy_single": [
$POLICY_JSON
  ],
  "policy_batch": [
$BATCH_JSON
  ],
  "results": [
$RAW_JSON
  ]
}
EOF

echo
echo "==== Wrote $OUT_FILE ===="
echo
echo "Single-call policy (one sgemm at a time):"
echo "$POLICY_JSON" | sed 's/^    //'
echo
echo "Batched policy (K sgemms before sync):"
echo "$BATCH_JSON" | sed 's/^    //'
