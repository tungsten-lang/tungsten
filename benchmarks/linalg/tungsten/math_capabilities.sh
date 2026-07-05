#!/usr/bin/env bash
# Math-capabilities benchmark — sweeps every available matmul backend
# across multiple dtypes (f32, f64, bf16) and produces
# ~/.tungsten/math-policy.json mapping (dtype, n) → best backend.
#
# Use this once per machine; the resulting policy file feeds the
# core/{sgemm,dgemm,bgemm}_auto dispatchers.
#
# Usage:
#   benchmarks/linalg/tungsten/math_capabilities.sh
#   benchmarks/linalg/tungsten/math_capabilities.sh --rebuild

set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$REPO"

BENCH_DIR="$REPO/benchmarks/linalg/tungsten"
OUT_DIR="$HOME/.tungsten"
OUT_FILE="$OUT_DIR/math-policy.json"
mkdir -p "$OUT_DIR"

# (dtype, impl, binary) tuples. Each binary takes (N, K_iters) and
# prints a single-line JSON {"impl":..., "N":..., "gflops":..., "median_ms":...}.
# All-impl array — we'll filter by dtype during the sweep.
declare -a CASES=(
  "f32:accelerate:$BENCH_DIR/matmul_accelerate"
  "f32:mlx:$BENCH_DIR/matmul_mlx"
  "f32:mlx-batch:$BENCH_DIR/matmul_mlx_batch"
  "f32:mps:$BENCH_DIR/matmul_mps"
  "f32:mpsg:$BENCH_DIR/matmul_mpsg"
  "f32:metal-tiled:$BENCH_DIR/matmul_metal_sgemm"        # reusable (what sgemm_auto dispatches)
  "f32:metal-bf16:$BENCH_DIR/matmul_metal_sgemm_bf16"    # reusable, conversion-inclusive
  "f32:metal-tiled-standalone:$BENCH_DIR/matmul_metal_tiled"    # peak (no per-call overhead)
  "f32:metal-bf16-standalone:$BENCH_DIR/matmul_metal_bf16"      # peak
  "f64:accelerate:$BENCH_DIR/matmul_accelerate_f64"
  "f64:mlx:$BENCH_DIR/matmul_mlx_f64"
  "bf16:mlx:$BENCH_DIR/matmul_mlx_bf16"
)

SIZES=(128 256 512 1024 2048 4096 8192)
ITERS=(500 200 100 50  10   3    2)

DEVICE="$(sysctl -n machdep.cpu.brand_string)"
GPU_CORES="$(system_profiler SPDisplaysDataType 2>/dev/null | awk '/Total Number of Cores:/ {print $5; exit}' || echo unknown)"
TS="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

RAW="$(mktemp)"
VALID_REJECT="$(mktemp)"
trap 'rm -f "$RAW" "$VALID_REJECT"' EXIT

# Pre-pass: validate each f32 backend's output against accelerate at N=128.
# If a backend's max_abs_err > strict tolerance AND --strict is set,
# it's excluded from the policy. By default we WARN but don't exclude
# (matches MLX's intentional precision/speed trade).
VALIDATOR="$BENCH_DIR/validate_backend"
if [[ -x "$VALIDATOR" ]]; then
  echo "==== Pre-pass: validating f32 backends at N=128 ===="
  for bk in accelerate metal-tiled metal-bf16 mlx; do
    line=$("$VALIDATOR" "$bk" 128 2>/dev/null | tr -d '\n' | tr -s ' ')
    err=$(echo "$line" | sed -nE 's/.*"max_abs_err":[[:space:]]*([0-9.]+).*/\1/p')
    ok=$(echo "$line" | sed -nE 's/.*"ok":[[:space:]]*([a-z]+).*/\1/p')
    printf "  %-12s max_abs_err=%s ok=%s\n" "$bk" "${err:-?}" "${ok:-?}"
    if [[ "$ok" == "false" ]]; then
      echo "$bk" >> "$VALID_REJECT"
    fi
  done
  echo
fi

echo "==== Device: $DEVICE  GPU cores: $GPU_CORES ===="
for spec in "${CASES[@]}"; do
  IFS=':' read -r dtype impl bin _rest <<< "$spec"
  if [[ ! -x "$bin" ]]; then
    echo "  [skip $dtype/$impl: missing $bin]"
    continue
  fi
  for i in "${!SIZES[@]}"; do
    N="${SIZES[$i]}"
    K="${ITERS[$i]}"
    line=$("$bin" "$N" "$K" 2>/dev/null | tr -d '\n' | tr -s ' ')
    gflops=$(echo "$line" | sed -nE 's/.*"gflops":[[:space:]]*([0-9.]+).*/\1/p')
    median=$(echo "$line" | sed -nE 's/.*"median_ms":[[:space:]]*([0-9.]+).*/\1/p')
    printf "  [%-4s] %-12s N=%-5d  %8.1f GFLOPS  %8.3f ms/call\n" "$dtype" "$impl" "$N" "${gflops:-0}" "${median:-0}"
    echo "    {\"dtype\":\"$dtype\",\"backend\":\"$impl\",\"N\":$N,\"K\":$K,\"gflops\":${gflops:-0},\"median_ms\":${median:-0}}," >> "$RAW"
  done
done

RAW_JSON=$(sed '$ s/,$//' "$RAW")

# Pick winners per (dtype, N). For single-call policy exclude -batch.
declare -a DTYPES=("f32" "f64" "bf16")
POLICY_BLOCKS=""

for dt in "${DTYPES[@]}"; do
  echo "==== Single-call winners ($dt) ===="
  declare -a ARR=()
  prev=""
  for i in "${!SIZES[@]}"; do
    N="${SIZES[$i]}"
    # Extract gflops, sort numerically, take winner. Avoid sort -t: column
    # arithmetic — the JSON ":" separators mismatch field positions.
    # Exclude -batch (throughput-style, can't dispatch single-call) AND
    # -standalone (reference benches; not exposed as reusable functions
    # for the dispatcher to call).
    winner=$(grep "\"dtype\":\"$dt\".*\"N\":$N," "$RAW" \
             | grep -v '"backend":"[a-z-]*-batch"' \
             | grep -v '"backend":"[a-z0-9-]*-standalone"' \
             | awk -F'"gflops":' '{ g=$2+0; print g"\t"$0 }' \
             | sort -k1 -g -r \
             | head -1 \
             | sed -nE 's/.*"backend":"([^"]+)".*/\1/p')
    gflops=$(grep "\"dtype\":\"$dt\".*\"N\":$N," "$RAW" \
             | grep -v '"backend":"[a-z-]*-batch"' \
             | grep -v '"backend":"[a-z0-9-]*-standalone"' \
             | awk -F'"gflops":' '{ g=$2+0; print g"\t"$0 }' \
             | sort -k1 -g -r \
             | head -1 \
             | sed -nE 's/.*"gflops":([0-9.]+).*/\1/p')
    if [[ -z "$winner" ]]; then continue; fi
    echo "  N=$N → $winner ($gflops GFLOPS)"
    if [[ "$winner" != "$prev" ]]; then
      ARR+=("    {\"n_max\": $N, \"backend\": \"$winner\", \"gflops\": $gflops}")
      prev="$winner"
    else
      last=$((${#ARR[@]} - 1))
      ARR[$last]="    {\"n_max\": $N, \"backend\": \"$winner\", \"gflops\": $gflops}"
    fi
  done
  if [[ ${#ARR[@]} -eq 0 ]]; then continue; fi
  # Mark last entry as catch-all
  last=$((${#ARR[@]} - 1))
  ARR[$last]="$(echo "${ARR[$last]}" | sed 's/n_max": [0-9]*/n_max": 1000000/')"

  # Join
  block=""
  for j in "${!ARR[@]}"; do
    if [[ $j -eq 0 ]]; then block="${ARR[$j]}"
    else block="$block,
${ARR[$j]}"
    fi
  done

  if [[ -z "$POLICY_BLOCKS" ]]; then
    POLICY_BLOCKS="    \"$dt\": [
$block
    ]"
  else
    POLICY_BLOCKS="$POLICY_BLOCKS,
    \"$dt\": [
$block
    ]"
  fi
done

cat > "$OUT_FILE" <<EOF
{
  "version": 1,
  "ts": "$TS",
  "device": "$DEVICE",
  "gpu_cores": "$GPU_CORES",
  "policy_by_dtype": {
$POLICY_BLOCKS
  },
  "results": [
$RAW_JSON
  ]
}
EOF

echo
echo "==== Wrote $OUT_FILE ===="
echo
echo "Per-dtype single-call policy:"
echo "$POLICY_BLOCKS"
