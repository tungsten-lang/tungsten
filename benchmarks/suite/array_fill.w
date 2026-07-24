# Array store throughput: 200 rounds of filling a raw i64[1,000,000]
# by index (a[i] = ...) — 200,000,000 indexed writes total.
t0 = clock
n = 1000000
rounds = 200 ## i64
a = i64[n]
chk = 0 ## i64
r = 0 ## i64
while r < rounds
  i = 0 ## i64
  while i < n
    a[i] = i * 2654435761 + r
    i = i + 1
  chk = chk ^ a[r * 7 % n]
  r = r + 1
t1 = clock
<< chk
<< "elapsed: [t1 - t0]s"
