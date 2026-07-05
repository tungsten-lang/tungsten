t0 = clock()

n = 2000000

# map: x -> x * 3 + 1, filter: x % 2 == 0, map: x -> x / 2, reduce: sum
total = 0
i = 0
while i < n
  v = i * 3 + 1
  if v % 2 == 0
    total = total + v / 2
  i = i + 1

t1 = clock()
<< total
<< "elapsed: " + (t1 - t0).to_s() + "s"
