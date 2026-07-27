#!/usr/bin/env python3
# Sequential element write, nested reps times; loop-carried chk + final
# read-back keep the stores meaningful. Mirrors array_set.w.
import time
M = (1 << 64) - 1
reps = 10_000
tab = [0] * 1024
t0 = time.perf_counter()
chk = reps
for r in range(reps):
    for k in range(1024):
        tab[k] = chk ^ k
        chk = (chk + 1) & M
el = time.perf_counter() - t0
out = chk ^ tab[0] ^ tab[1023]
print(f"{out}\nops: {reps * 1024}\nelapsed: {el:.6f}s")
