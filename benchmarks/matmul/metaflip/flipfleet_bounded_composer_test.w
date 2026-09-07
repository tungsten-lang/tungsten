use flipfleet_block_composer

-> ffbb_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  << "PASS " + name
  0

-> ffbb_naive(n, m, p) (i64 i64 i64)
  result = FFBCScheme.new(n,m,p,n*m*p)
  t = 0 ## i64
  i = 0 ## i64
  while i < n
    j = 0 ## i64
    while j < m
      k = 0 ## i64
      while k < p
        ffbc_toggle_bit(result.us(),t*result.uw(),i*m+j)
        ffbc_toggle_bit(result.vs(),t*result.vw(),j*p+k)
        ffbc_toggle_bit(result.ws(),t*result.ww(),i*p+k)
        t += 1
        k += 1
      j += 1
    i += 1
  result.set_rank(t)
  result

-> ffbb_equal(a, b) (i64[] i64[]) i64
  if a.size() != b.size()
    return 0
  i = 0 ## i64
  while i < a.size()
    if a[i] != b[i]
      return 0
    i += 1
  1

-> ffbb_compare(outer,n,m,p,minimum,maximum,leaves) (FFBCScheme i64 i64 i64 i64 i64 Array) i64
  slow = ffbc_best_bounded_recipe(outer,n,m,p,minimum,maximum,leaves)
  fast = ffbc_best_bounded_recipe_fast(outer,n,m,p,minimum,maximum,leaves)
  ffbb_expect("bounded slow/fast covered",slow != nil && fast != nil)
  ffbb_expect("same formula and first tie",slow[3] == fast[3] && ffbb_equal(slow[0],fast[0]) == 1 && ffbb_equal(slow[1],fast[1]) == 1 && ffbb_equal(slow[2],fast[2]) == 1)
  oriented = ffbc_best_oriented_bounded_recipe(outer,n,m,p,minimum,maximum,leaves)
  ffbb_expect("orientation contains direct choice",oriented != nil && oriented[3] <= fast[3])
  product = ffbc_compose_oriented_recipe(outer,n,m,p,leaves,oriented)
  ffbb_expect("bounded product exact",product != nil && ffbc_verify_exact(product) == 1 && product.rank() <= oriented[3])
  0

leaves = []
n = 1 ## i64
while n <= 3
  m = n ## i64
  while m <= 3
    p = m ## i64
    while p <= 3
      leaf = ffbb_naive(n,m,p)
      ffbb_expect("naive leaf",ffbc_verify_exact(leaf) == 1)
      leaves.push(leaf)
      p += 1
    m += 1
  n += 1
outer7 = ffbc_load_exact("bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt",2,2,2,32)
outer47 = ffbc_load_exact("bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_4x4_rank47_d450_gf2.txt",4,4,4,64)
ffbb_expect("outer witnesses",outer7 != nil && outer47 != nil)
leaves.push(outer7)
ffbb_compare(outer7,3,4,5,1,3,leaves)
ffbb_compare(outer7,1,3,4,0,3,leaves)
ffbb_compare(outer47,6,7,8,1,3,leaves)
ffbb_expect("ineligible positive allocation",ffbc_best_oriented_bounded_recipe(outer47,3,7,8,1,3,leaves) == nil)
ffbb_expect("missing leaf rejected",ffbc_best_bounded_recipe_fast(outer7,6,6,6,1,3,[]) == nil)
