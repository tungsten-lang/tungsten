# Hypercomplex multiplication A/B benchmark.
#
# Compares the straight-line public product with the retained recursive
# Cayley-Dickson reference implementations. Public products run first so
# allocations from the recursive baselines cannot distort their timings.
#
#   bin/tungsten -o /tmp/hypercomplex_mul_ab \
#     benchmarks/values/hypercomplex_mul_ab.w
#   /tmp/hypercomplex_mul_ab 1000

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

-> same_components(left, right, n)
  i = 0
  while i < n
    return false if left.components[i] != right.components[i]
    i += 1
  true

k = ARGV[0] == nil ? 0 : ARGV[0].to_i
k = 1000 if k <= 0

oa = oct_sample(123457)
ob = oct_sample(765431)
sa = sed_sample(123457)
sb = sed_sample(765431)

# Measure both public straight-line paths before either recursive path grows
# the process heap with half objects, slices, map/zip results, and concats.
oct_direct_result = oa * ob
i = 0
t0 = clock()
while i < k
  oct_direct_result = oa * ob
  i += 1
t1 = clock()
oct_direct_ns = (t1 - t0) * ~1000000000.0 / k

sed_fast_result = sa * sb
i = 0
t0 = clock()
while i < k
  sed_fast_result = sa * sb
  i += 1
t1 = clock()
sed_fast_ns = (t1 - t0) * ~1000000000.0 / k

oct_recursive_result = oa.mul_recursive(ob)
i = 0
t0 = clock()
while i < k
  oct_recursive_result = oa.mul_recursive(ob)
  i += 1
t1 = clock()
oct_recursive_ns = (t1 - t0) * ~1000000000.0 / k

sed_recursive_result = sa.mul_recursive(sb)
i = 0
t0 = clock()
while i < k
  sed_recursive_result = sa.mul_recursive(sb)
  i += 1
t1 = clock()
sed_recursive_ns = (t1 - t0) * ~1000000000.0 / k

if same_components(oct_direct_result, oct_recursive_result, 8) && same_components(sed_fast_result, sed_recursive_result, 16)
  << "PASS exact result equivalence"
else
  << "FAIL result equivalence"

<< "octonion direct    ns/op:" << oct_direct_ns << " checksum:" << oct_direct_result.e0
<< "octonion recursive ns/op:" << oct_recursive_ns << " checksum:" << oct_recursive_result.e0
<< "octonion speedup:" << oct_recursive_ns / oct_direct_ns
<< "sedenion fast      ns/op:" << sed_fast_ns << " checksum:" << sed_fast_result.e0
<< "sedenion recursive ns/op:" << sed_recursive_ns << " checksum:" << sed_recursive_result.e0
<< "sedenion speedup:" << sed_recursive_ns / sed_fast_ns
