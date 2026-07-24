import time
import sys
sys.set_int_max_str_digits(100000)

t0 = time.perf_counter()

a = 0
b = 1
for i in range(100000):
    a, b = b, a + b

digits = len(str(b))

t1 = time.perf_counter()
print(digits)
print(f"elapsed: {t1 - t0:.3f}s")
