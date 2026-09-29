import time
import numpy as np

n = 512
k_iters = 8
idx = np.arange(n * n, dtype=np.int64)
A = ((idx * 31 + 7) % 17).astype(np.float32).reshape(n, n) / 17.0
B = ((idx * 13 + 3) % 19).astype(np.float32).reshape(n, n) / 19.0
C = A @ B
t0 = time.perf_counter()
for _ in range(k_iters):
    C = A @ B
t1 = time.perf_counter()
print(int(C[0, 0] * 1_000_000))
print(f"elapsed: {t1 - t0}s")
