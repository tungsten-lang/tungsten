#!/usr/bin/env python3
"""NumPy FFT baseline for benchmarks/fft/run.sh"""
import time
import numpy as np

n = 1024
x = np.sin(0.01 * np.arange(n)).astype(np.float64)

# warmup
np.fft.fft(x)

iters = 50
t0 = time.perf_counter()
for _ in range(iters):
    np.fft.fft(x)
t1 = time.perf_counter()
print(f"numpy_fft n={n} avg_ms={(t1 - t0) * 1000 / iters:.4f}")
