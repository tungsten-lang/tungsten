#!/usr/bin/env bash
# Tungsten elementwise chain vs Python / NumPy / Numba / JAX.
# What are Numba/JAX? See doc/scientific-computing/fusion.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$(dirname "$0")"

echo "== Tungsten =="
"$ROOT/bin/tungsten" -o /tmp/tungsten_fusion_bench fusion_bench.w
/tmp/tungsten_fusion_bench

if [ "$(uname -s)" = "Darwin" ]; then
  echo "== Tungsten GPU (Metal, f32) =="
  { "$ROOT/bin/tungsten" -o /tmp/tungsten_fusion_gpu fusion_gpu_bench.w \
      && /tmp/tungsten_fusion_gpu; } || echo "gpu bench skipped (Metal unavailable?)"
fi

echo "== Python baselines =="
PY="$ROOT/.venv/bin/python3"
[ -x "$PY" ] || PY=python3
"$PY" fusion_baselines.py
