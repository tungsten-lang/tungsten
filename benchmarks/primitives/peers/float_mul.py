#!/usr/bin/env python3
import time
n = 10_000_000
f = 0.5
t0 = time.perf_counter()
for _ in range(n):
    f = 3.9 * f * (1.0 - f)
el = time.perf_counter() - t0
print(f"{f:.10f}\nops: {n}\nelapsed: {el:.6f}s")
