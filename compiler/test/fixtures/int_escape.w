fn hot_loop(n)
  i = 0
  sum = 0
  while i < n
    sum += i * 2
    i += 1
  << "sum=[sum]"

hot_loop(100)
