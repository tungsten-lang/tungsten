# Sort 2,000,000 pseudo-random i32 values.
# Fill a raw i32[] by index (a[i] = ...), then sort — the fast idiom.
t0 = clock
n = 2000000
arr = i32[n]
seed = 42 ## i64
i = 0 ## i64
while i < n
  seed = (((seed * 1103515245) & 0xFFFFFFFF) + 12345) & 0x7FFFFFFF
  arr[i] = seed
  i = i + 1
arr = arr.sort
t1 = clock
<< "first=[arr[0]] last=[arr[n - 1]]"
<< "elapsed: [t1 - t0]s"
