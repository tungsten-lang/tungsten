# Exact dense polynomial multiplication over F_p by 3-prime NTT + CRT,
# checked against schoolbook convolution.
#   bin/tungsten run spec/core/algebra_ntt_spec.w
#   bin/tungsten compile spec/core/algebra_ntt_spec.w --out /tmp/algebra-ntt-spec

use core/algebra/ntt

-> ntt_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> ntt_same?(left, right)
  return false if left.size != right.size
  i = 0
  while i < left.size
    return false if left[i] != right[i]
    i += 1
  true

# Reference convolution: coefficients stay below p, products below 2^62.
-> ntt_schoolbook(a, b, p)
  out = []
  i = 0
  while i < a.size + b.size - 1
    out.push(0)
    i += 1
  i = 0
  while i < a.size
    j = 0
    while j < b.size
      out[i + j] = (out[i + j] + a[i] * b[j]) % p
      j += 1
    i += 1
  out

# Deterministic pseudo-random coefficients in [0, p).
-> ntt_lcg(count, p, seed)
  out = []
  state = seed
  i = 0
  while i < count
    state = (state * 1103515245 + 12345) % 2147483648
    out.push(state % p)
    i += 1
  out

-> ntt_all_below?(values, p)
  i = 0
  while i < values.size
    return false if values[i] < 0 || values[i] >= p
    i += 1
  true

# --- The three primes and their primitive root ------------------------------
primes = NttMultiply.primes
ntt_check("primes.values",
          primes[0] == 998244353 && primes[1] == 167772161 && primes[2] == 469762049)
ntt_check("primes.prime", primes[0].prime? && primes[1].prime? && primes[2].prime?)
ntt_check("primes.shape",
          998244353 == 119 * 8388608 + 1 && 167772161 == 5 * 33554432 + 1 &&
          469762049 == 7 * 67108864 + 1)
# 2^23 | p - 1 for every prime, so transforms up to length 2^23 exist.
ntt_check("primes.two_adic_depth",
          (primes[0] - 1) % 8388608 == 0 && (primes[1] - 1) % 8388608 == 0 &&
          (primes[2] - 1) % 8388608 == 0)
# 3 is a primitive root: 3^((p-1)/q) != 1 for every prime q | p - 1.
# p0 - 1 = 2^23 * 7 * 17, p1 - 1 = 2^25 * 5, p2 - 1 = 2^26 * 7.
p0 = primes[0]
p1 = primes[1]
p2 = primes[2]
ntt_check("primes.root_p0",
          NttMultiply.powmod(3, p0 - 1, p0) == 1 &&
          NttMultiply.powmod(3, (p0 - 1) / 2, p0) != 1 &&
          NttMultiply.powmod(3, (p0 - 1) / 7, p0) != 1 &&
          NttMultiply.powmod(3, (p0 - 1) / 17, p0) != 1)
ntt_check("primes.root_p1",
          NttMultiply.powmod(3, p1 - 1, p1) == 1 &&
          NttMultiply.powmod(3, (p1 - 1) / 2, p1) != 1 &&
          NttMultiply.powmod(3, (p1 - 1) / 5, p1) != 1)
ntt_check("primes.root_p2",
          NttMultiply.powmod(3, p2 - 1, p2) == 1 &&
          NttMultiply.powmod(3, (p2 - 1) / 2, p2) != 1 &&
          NttMultiply.powmod(3, (p2 - 1) / 7, p2) != 1)

# --- powmod -----------------------------------------------------------------
ntt_check("powmod.small", NttMultiply.powmod(3, 10, 7) == 4)
ntt_check("powmod.zero_exponent", NttMultiply.powmod(2, 0, 5) == 1)
ntt_check("powmod.cube", NttMultiply.powmod(5, 3, 13) == 8)
ntt_check("powmod.fermat", NttMultiply.powmod(123456, p0 - 1, p0) == 1)
ntt_check("powmod.inverse", (NttMultiply.powmod(7, p1 - 2, p1) * 7) % p1 == 1)

# --- Stage roots: primitive 2^(s+1)-th roots and their inverses -------------
roots8 = NttMultiply.stage_roots(p0, 8, false)
inverse8 = NttMultiply.stage_roots(p0, 8, true)
ntt_check("roots.count", roots8.size == 3 && inverse8.size == 3)
ntt_check("roots.stage0_is_minus_one", roots8[0] == p0 - 1)
ntt_check("roots.stage1_fourth_root",
          (roots8[1] * roots8[1]) % p0 == p0 - 1)
r2 = roots8[2]
r2_squared = (r2 * r2) % p0
ntt_check("roots.stage2_eighth_root",
          (r2_squared * r2_squared) % p0 == p0 - 1 && r2_squared != p0 - 1)
ntt_check("roots.inverses",
          (roots8[0] * inverse8[0]) % p0 == 1 &&
          (roots8[1] * inverse8[1]) % p0 == 1 &&
          (roots8[2] * inverse8[2]) % p0 == 1)
ntt_check("roots.length_one", NttMultiply.stage_roots(p0, 1, false).size == 1)

# --- Forward then inverse transform is the identity -------------------------
signal = i64[8]
i = 0
while i < 8
  signal[i] = (i * i * 7 + 3) % p0
  i += 1
original = []
i = 0
while i < 8
  original.push(signal[i])
  i += 1
ntt_transform(signal, 8, p0, roots8)
transformed = []
i = 0
while i < 8
  transformed.push(signal[i])
  i += 1
ntt_check("transform.changes_data", !ntt_same?(transformed, original))
# Evaluation at the root 1 (index 0) is the plain coefficient sum.
coefficient_sum = 0
i = 0
while i < 8
  coefficient_sum = (coefficient_sum + original[i]) % p0
  i += 1
ntt_check("transform.dc_term_is_sum", transformed[0] == coefficient_sum)
ntt_transform(signal, 8, p0, inverse8)
ntt_scale(signal, 8, p0, NttMultiply.powmod(8, p0 - 2, p0))
recovered = []
i = 0
while i < 8
  recovered.push(signal[i])
  i += 1
ntt_check("transform.round_trip", ntt_same?(recovered, original))

# --- Products against schoolbook --------------------------------------------
ntt_check("multiply.binomial_square",
          ntt_same?(NttMultiply.multiply_mod_p([1, 1], [1, 1], 7), [1, 2, 1]))
# (1 + 2x + 3x^2)(4 + 5x + 6x^2) = 4 + 13x + 28x^2 + 27x^3 + 18x^4.
ntt_check("multiply.small_97",
          ntt_same?(NttMultiply.multiply_mod_p([1, 2, 3], [4, 5, 6], 97), [4, 13, 28, 27, 18]))
ntt_check("multiply.reduces_mod_p",
          ntt_same?(NttMultiply.multiply_mod_p([1, 2, 3], [4, 5, 6], 5), [4, 3, 3, 2, 3]))
ntt_check("multiply.constants", ntt_same?(NttMultiply.multiply_mod_p([5], [6], 7), [2]))
ntt_check("multiply.by_zero",
          ntt_same?(NttMultiply.multiply_mod_p([0, 0], [1, 2, 3], 7), [0, 0, 0, 0]))
ntt_check("multiply.length", NttMultiply.multiply_mod_p([1, 2, 3], [1, 2, 3, 4, 5], 11).size == 7)
# (x - 1)(x^2 + x + 1) = x^3 - 1 over F_11: coefficients [-1, 1] * [1, 1, 1].
ntt_check("multiply.cyclotomic",
          ntt_same?(NttMultiply.multiply_mod_p([10, 1], [1, 1, 1], 11), [10, 0, 0, 1]))
# Non-power-of-two input sizes pad to the next power of two.
a3 = [3, 1, 4]
b5 = [1, 5, 9, 2, 6]
ntt_check("multiply.padding",
          ntt_same?(NttMultiply.multiply_mod_p(a3, b5, 101), ntt_schoolbook(a3, b5, 101)))
ntt_check("multiply.commutes",
          ntt_same?(NttMultiply.multiply_mod_p(b5, a3, 101), NttMultiply.multiply_mod_p(a3, b5, 101)))

# The largest supported modulus stresses the CRT reconstruction: products
# reach (d+1)(p-1)^2 ~ 2^69 for 128 terms, well past a single prime.
# (Sizes are kept small so the tree-walking interpreter finishes quickly.)
p31 = 2147483647
ntt_check("large.p31_prime", p31.prime?)
f128 = ntt_lcg(128, p31, 12345)
g128 = ntt_lcg(128, p31, 67890)
product128 = NttMultiply.multiply_mod_p(f128, g128, p31)
ntt_check("large.p31_128_size", product128.size == 255)
ntt_check("large.p31_128_in_range", ntt_all_below?(product128, p31))
ntt_check("large.p31_128_schoolbook", ntt_same?(product128, ntt_schoolbook(f128, g128, p31)))
# Asymmetric lengths over a mid-sized prime.
f150 = ntt_lcg(150, 65537, 4242)
g100 = ntt_lcg(100, 65537, 2424)
ntt_check("large.65537_asymmetric",
          ntt_same?(NttMultiply.multiply_mod_p(f150, g100, 65537), ntt_schoolbook(f150, g100, 65537)))
# Small prime, longer inputs: every coefficient lands back in [0, p).
f300 = ntt_lcg(300, 7, 99)
g300 = ntt_lcg(300, 7, 98)
product7 = NttMultiply.multiply_mod_p(f300, g300, 7)
ntt_check("large.p7_range", ntt_all_below?(product7, 7))
ntt_check("large.p7_schoolbook", ntt_same?(product7, ntt_schoolbook(f300, g300, 7)))
# All-maximal coefficients hit the coefficient bound exactly: 1024 terms of
# p - 1 give (d+1)(p-1)^2 ~ 2^72, needing all three primes.
maximal = []
i = 0
while i < 1024
  maximal.push(p31 - 1)
  i += 1
maximal_product = NttMultiply.multiply_mod_p(maximal, maximal, p31)
# Coefficient k of (sum x^i)^2 is min(k, 2046 - k) + 1 copies of (p-1)^2 = 1 mod p.
maximal_ok = maximal_product.size == 2047
k = 0
while k < 2047 && maximal_ok
  copies = k < 1024 ? k + 1 : 2047 - k
  maximal_ok = false if maximal_product[k] != copies % p31
  k += 1
ntt_check("large.maximal_coefficients", maximal_ok)

# Ring axioms on length-128 inputs (only NTT products, no schoolbook).
f128b = ntt_lcg(128, p31, 1)
g128b = ntt_lcg(128, p31, 2)
h128b = ntt_lcg(128, p31, 3)
fg = NttMultiply.multiply_mod_p(f128b, g128b, p31)
gh = NttMultiply.multiply_mod_p(g128b, h128b, p31)
ntt_check("ring.commutative", ntt_same?(fg, NttMultiply.multiply_mod_p(g128b, f128b, p31)))
ntt_check("ring.associative",
          ntt_same?(NttMultiply.multiply_mod_p(fg, h128b, p31),
                    NttMultiply.multiply_mod_p(f128b, gh, p31)))
# Distributivity: f (g + h) = f g + f h.
g_plus_h = []
i = 0
while i < 128
  g_plus_h.push((g128b[i] + h128b[i]) % p31)
  i += 1
fh = NttMultiply.multiply_mod_p(f128b, h128b, p31)
fg_plus_fh = []
i = 0
while i < fg.size
  fg_plus_fh.push((fg[i] + fh[i]) % p31)
  i += 1
ntt_check("ring.distributive",
          ntt_same?(NttMultiply.multiply_mod_p(f128b, g_plus_h, p31), fg_plus_fh))
# Multiplying by the monomial x^k shifts coefficients.
shift = [0, 0, 0, 1]
shifted = NttMultiply.multiply_mod_p(f128b, shift, p31)
shift_ok = shifted.size == 131 && shifted[0] == 0 && shifted[1] == 0 && shifted[2] == 0
i = 0
while i < 128 && shift_ok
  shift_ok = false if shifted[i + 3] != f128b[i]
  i += 1
ntt_check("ring.monomial_shift", shift_ok)

<< "algebra_ntt_spec: all checks passed"
