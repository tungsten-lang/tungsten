# Lucas-Lehmer fast-path verification for Int#prime? on Mersenne numbers.
# All exponents below produce bigints > 2^64, so they exercise the new
# w_ic_bigint_prime_q -> Lucas-Lehmer path (not the u64 tier).

mprimes = [89, 107, 127, 521, 607, 1279, 2203, 2281, 3217, 4423]  # M_p prime -> true
mcomps  = [67, 101, 1009, 4099]                                   # prime exp, M_p composite -> false
mcompe  = [99, 129, 1000]                                         # composite exp -> false (guard)

mprimes.each ->
  << "prime  exp " + item.to_s + " -> " + (2 ** item - 1).prime?.to_s

mcomps.each ->
  << "comp   exp " + item.to_s + " -> " + (2 ** item - 1).prime?.to_s

mcompe.each ->
  << "compE  exp " + item.to_s + " -> " + (2 ** item - 1).prime?.to_s
