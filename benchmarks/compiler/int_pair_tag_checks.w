# Generated-code microbenchmark for the boxed binary-operation Int guard.
# Keep a and b as unannotated parameters so lowering emits the private
# __w_*_fast helpers; the benchmark measures their all-Int fast arms.

-> bench_int_pair_checks(n, a, b)
  i = 0 ## i64
  acc = 0
  t0 = clock()
  while i < n
    a = (a + b) & 1048575
    b = (b ^ 12345) | 1
    c = a * 3
    d = c / 7
    e = d % 97
    f = e << 3
    g = f >> 2
    if g >= b
      acc = (acc + g) & 1048575
    else
      acc = (acc - g) & 1048575
    i += 1
  t1 = clock()
  << "int_pair\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + (acc + a + b).to_s()

args = argv()
n = args.size() > 0 ? args[0].to_i() : 10000000
bench_int_pair_checks(n, 17, 29)
