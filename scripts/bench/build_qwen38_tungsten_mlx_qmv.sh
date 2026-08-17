#!/usr/bin/env bash
# Build and run the Qwen3.8 QMV comparison with the optional MLX C bridge.

set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
mlxc_prefix="$(brew --prefix mlx-c)"
mlx_prefix="$(brew --prefix mlx)"
out="${TMPDIR:-/tmp}/qwen38-tungsten-mlx-qmv"

if [[ ! -d "$mlxc_prefix/include/mlx/c" ]]; then
  echo "ERROR: mlx-c is not installed (brew install mlx-c mlx)" >&2
  exit 1
fi

export TUNGSTEN_C_INCLUDES="$repo/runtime/mlx_bridge.c"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-I$mlxc_prefix/include"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-I$mlx_prefix/include"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-L$mlxc_prefix/lib"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-lmlxc"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-Wl,-rpath,$mlxc_prefix/lib"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-Wl,-rpath,$mlx_prefix/lib"
# Optional C includes are part of the cache identity by path but are not in
# its mtime manifest. Disable the final-binary cache so bridge edits are used.
export TUNGSTEN_INCREMENTAL=0

cd "$repo"
rm -f "$out"
bin/tungsten compile scripts/bench/qwen38_tungsten_mlx_qmv.w \
  --release --out "$out"
exec "$out" "$@"
