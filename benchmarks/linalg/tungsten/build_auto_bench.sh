#!/usr/bin/env bash
# Build the sgemm_auto demo. Links MLX so the dispatcher can call it.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$REPO"

MLXC_PREFIX="$(brew --prefix mlx-c)"
MLX_PREFIX="$(brew --prefix mlx)"

export TUNGSTEN_C_INCLUDES="$REPO/runtime/mlx_bridge.c"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-I$MLXC_PREFIX/include"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-I$MLX_PREFIX/include"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-L$MLXC_PREFIX/lib"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-lmlxc"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-Wl,-rpath,$MLXC_PREFIX/lib"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-Wl,-rpath,$MLX_PREFIX/lib"

OUT="$REPO/benchmarks/linalg/tungsten/matmul_auto"
SRC="$REPO/benchmarks/linalg/tungsten/matmul_auto.w"

echo "==== Building matmul_auto ===="
"$REPO/bin/tungsten" -o "$OUT" "$SRC"
echo "==== Built $(stat -f %z "$OUT") bytes ===="

if [[ "${BUILD_ONLY:-0}" == "1" ]]; then
  exit 0
fi

echo
echo "==== Sweep ===="
for spec in "128:200" "256:100" "512:50" "1024:20" "2048:10" "4096:3" "8192:2"; do
  N="${spec%:*}"
  K="${spec#*:}"
  "$OUT" "$N" "$K" | tr '\n' ' '
  echo
done
