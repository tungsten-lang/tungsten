t0 = clock

a = 0
b = 1

n = 100000
while n > 0
  tmp = b
  b = a + b
  a = tmp
  n = n - 1

digits = b.to_s().length()

t1 = clock
<< digits
<< "elapsed: [t1 - t0]s"
