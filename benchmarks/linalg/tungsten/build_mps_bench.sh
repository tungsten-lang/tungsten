#!/usr/bin/env bash
# Build matmul_mps.w with the MPS bridge spliced in via TUNGSTEN_C_INCLUDES.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$REPO"

# Splice mps_bridge.m + framework link. The framework is system-provided,
# no -I/-L needed.
export TUNGSTEN_C_INCLUDES="$REPO/runtime/mps_bridge.m"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-framework MetalPerformanceShaders"

OUT="$REPO/benchmarks/linalg/tungsten/matmul_mps"
SRC="$REPO/benchmarks/linalg/tungsten/matmul_mps.w"

echo "==== Building matmul_mps ===="
"$REPO/bin/tungsten" -o "$OUT" "$SRC"
echo "==== Build OK: $(stat -f %z "$OUT") bytes ===="

if [[ "${BUILD_ONLY:-0}" == "1" ]]; then
  exit 0
fi

echo
echo "==== MPS sweep ===="
SIZES=(2048 4096 8192)
ITERS=(10 3 2)
for i in "${!SIZES[@]}"; do
  N="${SIZES[$i]}"
  K="${ITERS[$i]}"
  "$OUT" "$N" "$K" | tr '\n' ' '
  echo
done
