import time
t0 = time.perf_counter()
n = 1000000
rounds = 200
a = [0] * n
chk = 0
for r in range(rounds):
    for i in range(n):
        a[i] = i * 2654435761 + r
    chk ^= a[(r * 7) % n]
t1 = time.perf_counter()
print(chk)
print("elapsed: %.6fs" % (t1 - t0))
