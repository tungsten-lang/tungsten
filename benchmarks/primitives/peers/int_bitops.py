#!/usr/bin/env python3
import time
M = (1 << 64) - 1
n = 10_000_000
s = 1
t0 = time.perf_counter()
for i in range(n):
    s = (((s << 13) & M) ^ (s >> 7) ^ i) & M
el = time.perf_counter() - t0
print(f"{s}\nops: {n}\nelapsed: {el:.6f}s")
