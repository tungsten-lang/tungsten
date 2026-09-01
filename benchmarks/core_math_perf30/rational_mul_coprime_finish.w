# Matched probe for Rational multiplication's representation finalizer.
# Inputs are canonicalized before the timed loop.  Multiplication performs the
# required cross-cancellation; the candidate only removes the redundant gcd on
# the already-coprime full-width products.

-> bench(bits, iterations)
  p = (1 << bits) + 12345 ## big
  q = (1 << (bits - 1)) + 54321 ## big
  r = (1 << (bits - 2)) + 11111 ## big
  s = (1 << (bits - 3)) + 33333 ## big
  a = Rational.new(p, q)
  b = Rational.new(r, s)

  value = a * b
  i = 0 ## i64
  t0 = clock()
  while i < iterations
    value = a * b
    i += 1
  elapsed = clock() - t0
  checksum = (value.numerator % 1000000007) + (value.denominator % 1000000007)
  ns_per = elapsed * ~1000000000.0 / iterations.to_f()
  << bits.to_s() + "\t" + iterations.to_s() + "\t" + ns_per.to_s() + "\t" + checksum.to_s()

bench(128, 20000)
bench(512, 10000)
bench(2048, 4000)
bench(8192, 1000)
