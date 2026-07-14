# Regression coverage for straight-line Octonion and Sedenion products.
#
# The public operators use generated coefficient formulas; mul_recursive is
# retained as the compact Cayley-Dickson reference. Exhaustive basis products
# prove that both implementations have the same bilinear multiplication table.
# Dense integer-valued f64 inputs keep all arithmetic exactly representable,
# making the random checks component-exact rather than tolerance-based.
#
# Run: bin/tungsten -o /tmp/hypercomplex_mul_spec \
#        spec/numeric/hypercomplex_mul_spec.w && /tmp/hypercomplex_mul_spec

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

-> same_components(left, right, n)
  i = 0
  while i < n
    return false if left.components[i] != right.components[i]
    i += 1
  true

-> close_components(left, right, n, tolerance)
  i = 0
  while i < n
    return false if (left.components[i] - right.components[i]).abs > tolerance
    i += 1
  true

-> sample(seed, index)
  (((seed * (index * 97 + 31) + index * 193 + 17) % 17) - 8) ## f64

-> oct_sample(seed)
  Octonion<f64>.new([
    sample(seed, 0), sample(seed, 1), sample(seed, 2), sample(seed, 3),
    sample(seed, 4), sample(seed, 5), sample(seed, 6), sample(seed, 7)
  ])

-> sed_sample(seed)
  Sedenion<f64>.new([
    sample(seed, 0), sample(seed, 1), sample(seed, 2), sample(seed, 3),
    sample(seed, 4), sample(seed, 5), sample(seed, 6), sample(seed, 7),
    sample(seed, 8), sample(seed, 9), sample(seed, 10), sample(seed, 11),
    sample(seed, 12), sample(seed, 13), sample(seed, 14), sample(seed, 15)
  ])

oct_basis_failures = 0
i = 0
while i < 8
  j = 0
  while j < 8
    a = Octonion<f64>.basis(i)
    b = Octonion<f64>.basis(j)
    oct_basis_failures += 1 if !same_components(a * b, a.mul_recursive(b), 8)
    j += 1
  i += 1
check("octonion basis table", oct_basis_failures, 0)

sed_basis_failures = 0
i = 0
while i < 16
  j = 0
  while j < 16
    a = Sedenion<f64>.basis(i)
    b = Sedenion<f64>.basis(j)
    sed_basis_failures += 1 if !same_components(a * b, a.mul_recursive(b), 16)
    j += 1
  i += 1
check("sedenion basis table", sed_basis_failures, 0)

dense_failures = 0
seed = 104729
i = 0
while i < 250
  seed = (seed * 48271) % 2147483647
  oa = oct_sample(seed)
  seed = (seed * 48271) % 2147483647
  ob = oct_sample(seed)
  dense_failures += 1 if !same_components(oa * ob, oa.mul_recursive(ob), 8)

  seed = (seed * 48271) % 2147483647
  sa = sed_sample(seed)
  seed = (seed * 48271) % 2147483647
  sb = sed_sample(seed)
  dense_failures += 1 if !same_components(sa * sb, sa.mul_recursive(sb), 16)
  i += 1
check("dense exact products", dense_failures, 0)

# Exercise a second concrete specialization; these small integer coefficients
# and their products are also exactly representable in f32.
oa32 = Octonion<f32>.new([
  1.0, -2.0, 3.0, -4.0, 5.0, -6.0, 7.0, -8.0
] ## f32[8])
ob32 = Octonion<f32>.new([
  -8.0, 7.0, -6.0, 5.0, -4.0, 3.0, -2.0, 1.0
] ## f32[8])
check("octonion f32 exact product", same_components(oa32 * ob32, oa32.mul_recursive(ob32), 8), true)

sa32 = Sedenion<f32>.new([
  1.0, -2.0, 3.0, -4.0, 5.0, -6.0, 7.0, -8.0,
  8.0, -7.0, 6.0, -5.0, 4.0, -3.0, 2.0, -1.0
] ## f32[16])
sb32 = Sedenion<f32>.new([
  -3.0, 1.0, 4.0, -1.0, 5.0, -9.0, 2.0, 6.0,
  -5.0, 3.0, -5.0, 8.0, 9.0, -7.0, 9.0, -3.0
] ## f32[16])
check("sedenion f32 exact product", same_components(sa32 * sb32, sa32.mul_recursive(sb32), 16), true)

# Reassociation can change the low bits for non-exact floating arithmetic,
# but both paths must remain numerically equivalent.
ofa = Octonion<f64>.new([
  ~0.1, ~-0.2, ~0.3, ~-0.4, ~0.5, ~-0.6, ~0.7, ~-0.8
])
ofb = Octonion<f64>.new([
  ~0.9, ~0.8, ~-0.7, ~-0.6, ~0.5, ~0.4, ~-0.3, ~-0.2
])
check("octonion fractional tolerance", close_components(ofa * ofb, ofa.mul_recursive(ofb), 8, ~0.000000000001), true)

sfa = Sedenion<f64>.new([
  ~0.1, ~-0.2, ~0.3, ~-0.4, ~0.5, ~-0.6, ~0.7, ~-0.8,
  ~0.9, ~-1.0, ~1.1, ~-1.2, ~1.3, ~-1.4, ~1.5, ~-1.6
])
sfb = Sedenion<f64>.new([
  ~-1.6, ~1.5, ~-1.4, ~1.3, ~-1.2, ~1.1, ~-1.0, ~0.9,
  ~-0.8, ~0.7, ~-0.6, ~0.5, ~-0.4, ~0.3, ~-0.2, ~0.1
])
check("sedenion fractional tolerance", close_components(sfa * sfb, sfa.mul_recursive(sfb), 16, ~0.000000000001), true)
