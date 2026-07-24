t0 = clock

e = ~0.0
0...100000 ->
  e = ~0.0
  factorial = ~1.0
  0..100 ->
    e = e + ~1.0 / factorial
    factorial = factorial * (i + 1)

t1 = clock
<< (e * ~1000000.0).to_i
<< "elapsed: [t1 - t0]s"
