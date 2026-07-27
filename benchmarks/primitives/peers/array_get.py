#!/usr/bin/env python3
# Sequential element read, nested reps times; tab[k]+r varies each outer pass
# so the reduction can't be shortcut. Mirrors array_get.w.
import time
M = (1 << 64) - 1
reps = 10_000
tab = [(j * 2654435761 + reps) & M for j in range(1024)]
t0 = time.perf_counter()
chk = reps
for r in range(reps):
    for k in range(1024):
        chk ^= (tab[k] + r) & M
el = time.perf_counter() - t0
print(f"{chk}\nops: {reps * 1024}\nelapsed: {el:.6f}s")
