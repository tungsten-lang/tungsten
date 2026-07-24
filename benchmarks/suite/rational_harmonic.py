import time
import math

t0 = time.perf_counter()

num = 0
den = 1
for i in range(1, 3001):
    # num/den + 1/i = (num*i + den) / (den*i)
    num = num * i + den
    den = den * i
    # GCD reduce
    g = math.gcd(num, den)
    num = num // g
    den = den // g

digits = len(str(num))

t1 = time.perf_counter()
print(digits)
print(f"elapsed: {t1 - t0:.3f}s")
