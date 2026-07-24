import time
t0 = time.perf_counter()
n = 400000
parts = []
for _ in range(n):
    parts.append("abcdefghijklmnopqrstuvwxyz")
s = "".join(parts)
t1 = time.perf_counter()
print(len(s))
print("elapsed: %.6fs" % (t1 - t0))
