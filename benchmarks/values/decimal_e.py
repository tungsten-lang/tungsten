import time
from decimal import Decimal, getcontext

getcontext().prec = 50

t0 = time.perf_counter()

e = Decimal("0")
for rep in range(100000):
    e = Decimal("0")
    factorial = Decimal("1")
    for i in range(101):
        e = e + Decimal("1") / factorial
        factorial = factorial * (i + 1)

result = int(e * 1000000)

t1 = time.perf_counter()
print(result)
print(f"elapsed: {t1 - t0:.3f}s")
