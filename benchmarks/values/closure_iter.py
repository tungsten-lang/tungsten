import time
from functools import reduce

t0 = time.perf_counter()

n = 2_000_000

# map -> filter -> map -> reduce
mapped1 = [x * 3 + 1 for x in range(n)]
filtered = [x for x in mapped1 if x % 2 == 0]
mapped2 = [x // 2 for x in filtered]
total = sum(mapped2)

t1 = time.perf_counter()
print(total)
print(f"elapsed: {t1 - t0:.3f}s")
