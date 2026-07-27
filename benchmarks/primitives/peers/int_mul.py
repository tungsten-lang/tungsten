#!/usr/bin/env python3
import time
M = (1 << 64) - 1
n = 10_000_000
s = 1
t0 = time.perf_counter()
for _ in range(n):
    s = (s * 6364136223846793005 + 1) & M
el = time.perf_counter() - t0
print(f"{s}\nops: {n}\nelapsed: {el:.6f}s")
