t0 = clock

n = 2000000
arr = i32[n]
seed = 42

i = 0
while i < n
  seed = (((seed * 1103515245) & 0xFFFFFFFF) + 12345) & 0x7FFFFFFF
  arr.push(seed)
  i = i + 1

arr = arr.sort

t1 = clock
<< "first=[arr[0]] last=[arr[n - 1]]"
<< "elapsed: [t1 - t0]s"
