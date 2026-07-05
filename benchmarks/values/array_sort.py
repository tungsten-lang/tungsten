import time

t0 = time.perf_counter()

n = 2_000_000
arr = [0] * n
seed = 42
for i in range(n):
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    arr[i] = seed

arr.sort()

t1 = time.perf_counter()
print(f"first={arr[0]} last={arr[n - 1]}")
print(f"elapsed: {t1 - t0:.3f}s")
