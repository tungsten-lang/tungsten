#!/usr/bin/env bash
# Build benchmarks/linalg/tungsten/matmul_mlx.w with the mlx-c bridge
# spliced in via TUNGSTEN_C_INCLUDES, then run it across a size sweep.
#
# This is opt-in: linking libmlxc + libmlx pulls in ~180 MB of MLX
# runtime, so we don't want it in every Tungsten binary. The script
# pulls all the wiring (header path, lib path, library, rpath) into
# one TUNGSTEN_C_INCLUDES colon-separated string the way the compiler
# expects.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$REPO"

MLXC_PREFIX="$(brew --prefix mlx-c)"
MLX_PREFIX="$(brew --prefix mlx)"

if [[ ! -d "$MLXC_PREFIX/include/mlx/c" ]]; then
  echo "ERROR: mlx-c headers not found at $MLXC_PREFIX/include/mlx/c" >&2
  echo "Install with: brew install mlx-c" >&2
  exit 1
fi

# TUNGSTEN_C_INCLUDES is colon-separated. Each part is either a .c file
# to compile alongside, or a flag (-I, -L, -l, -Wl,...) to pass to clang.
export TUNGSTEN_C_INCLUDES="$REPO/runtime/mlx_bridge.c"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-I$MLXC_PREFIX/include"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-I$MLX_PREFIX/include"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-L$MLXC_PREFIX/lib"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-lmlxc"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-Wl,-rpath,$MLXC_PREFIX/lib"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-Wl,-rpath,$MLX_PREFIX/lib"

OUT="$REPO/benchmarks/linalg/tungsten/matmul_mlx"
SRC="$REPO/benchmarks/linalg/tungsten/matmul_mlx.w"

echo "==== Building matmul_mlx ===="
echo "TUNGSTEN_C_INCLUDES=$TUNGSTEN_C_INCLUDES"
echo
"$REPO/bin/tungsten" -o "$OUT" "$SRC"
echo
echo "==== Build OK: $(stat -f %z "$OUT") bytes ===="
echo

if [[ "${BUILD_ONLY:-0}" == "1" ]]; then
  exit 0
fi

echo "==== Sweep ===="
# (N, K_iters) — K scales ~1/N^3 so total work is comparable
SIZES=(128 256 512 1024 2048)
ITERS=(200 100 50 20 10)

for i in "${!SIZES[@]}"; do
  N="${SIZES[$i]}"
  K="${ITERS[$i]}"
  "$OUT" "$N" "$K"
  echo
done
