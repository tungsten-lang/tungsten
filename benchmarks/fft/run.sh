#!/usr/bin/env bash
# Compare Tungsten pure FFT vs NumPy (and SciPy if present).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$(dirname "$0")"

echo "== Tungsten =="
# clock ccall requires compiled binary
"$ROOT/bin/tungsten" -o /tmp/tungsten_fft_bench fft_bench.w
/tmp/tungsten_fft_bench

echo "== NumPy =="
python3 fft_numpy.py

if python3 -c "import scipy" 2>/dev/null; then
  echo "== SciPy =="
  python3 - <<'PY'
import time, numpy as np
from scipy.fft import fft
n=1024
x=np.sin(0.01*np.arange(n))
fft(x)
iters=50
t0=time.perf_counter()
for _ in range(iters):
    fft(x)
t1=time.perf_counter()
print(f"scipy_fft n={n} avg_ms={(t1-t0)*1000/iters:.4f}")
PY
fi
