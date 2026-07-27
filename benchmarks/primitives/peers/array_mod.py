#!/usr/bin/env python3
# Wraparound (masked-index) array read: tab[i & 1023]. Mirrors array_mod.w.
import time
M = (1 << 64) - 1
n = 10_000_000
tab = [(j * 2654435761) & M for j in range(1024)]
t0 = time.perf_counter()
chk = 0
for i in range(n):
    chk ^= tab[i & 1023]
el = time.perf_counter() - t0
print(f"{chk}\nops: {n}\nelapsed: {el:.6f}s")
