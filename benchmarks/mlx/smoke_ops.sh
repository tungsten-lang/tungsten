#!/usr/bin/env bash
# Smoke MLX elementwise / softmax / sum against mlx-c (opt-in, ~180MB dylib).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"

MLXC_PREFIX="$(brew --prefix mlx-c 2>/dev/null || true)"
MLX_PREFIX="$(brew --prefix mlx 2>/dev/null || true)"
if [[ ! -d "${MLXC_PREFIX:-}/include/mlx/c" ]]; then
  echo "SKIP: brew install mlx-c mlx first"
  exit 0
fi

export TUNGSTEN_C_INCLUDES="$REPO/runtime/mlx_bridge.c"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-I$MLXC_PREFIX/include"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-I$MLX_PREFIX/include"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-L$MLXC_PREFIX/lib"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-L$MLX_PREFIX/lib"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-lmlxc:-lmlx"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-Wl,-rpath,$MLXC_PREFIX/lib"
export TUNGSTEN_C_INCLUDES="$TUNGSTEN_C_INCLUDES:-Wl,-rpath,$MLX_PREFIX/lib"

cat > /tmp/mlx_ops_smoke.w << 'EOF'
use core/blas
use core/mlx

n = 8
a = f32_array(n)
b = f32_array(n)
c = f32_array(n)
i = 0
while i < n
  a[i] = ~1.0
  b[i] = ~2.0
  i = i + 1
mlx_add(a, b, c, n)
<< c[0]
mlx_mul(a, b, c, n)
<< c[0]
s = mlx_sum(a, n)
<< s
out = f32_array(4)
# 2x2 softmax rows on [1,2,3,4]
m = f32_array(4)
m[0] = ~1.0
m[1] = ~2.0
m[2] = ~3.0
m[3] = ~4.0
o = f32_array(4)
mlx_softmax_rows(m, o, 2, 2)
<< o[0]
<< o[1]
mlx_eval
<< "MLX_OPS_OK"
EOF

bin/tungsten -o /tmp/mlx_ops_smoke /tmp/mlx_ops_smoke.w
/tmp/mlx_ops_smoke
