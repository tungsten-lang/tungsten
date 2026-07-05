import time

t0 = time.perf_counter()

n = 1_000_000
is_prime = [True] * (n + 1)
is_prime[0] = False
is_prime[1] = False

i = 2
while i * i <= n:
    if is_prime[i]:
        j = i * i
        while j <= n:
            is_prime[j] = False
            j += i
    i += 1

count = 0
for k in range(n + 1):
    if is_prime[k]:
        count += 1

t1 = time.perf_counter()
print(count)
print(f"elapsed: {t1 - t0:.3f}s")
