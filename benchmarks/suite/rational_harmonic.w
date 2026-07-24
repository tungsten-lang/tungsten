t0 = clock

num = 0
den = 1

i = 1
while i <= 3000
  num = num * i + den
  den = den * i
  g = num.gcd(den)
  num = num / g
  den = den / g
  i = i + 1

digits = num.to_s().size()

t1 = clock
<< digits
<< "elapsed: [t1 - t0]s"
