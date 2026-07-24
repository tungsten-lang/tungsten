import time

t0 = time.perf_counter()

total = 0
for n in range(1, 1_000_001):
    x = n
    steps = 0
    while x != 1:
        if x % 2 == 0:
            x = x // 2
        else:
            x = 3 * x + 1
        steps += 1
    total += steps

t1 = time.perf_counter()
print(total)
print(f"elapsed: {t1 - t0:.3f}s")
