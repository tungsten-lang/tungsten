# spec: compiled -- exercises the ownership pass's integer releases
# Integer releases (compiler/lib/ownership.w int_temp_releases, owned_slot_releases,
# int_fresh_returns; runtime w_int_temp_release / w_int_result_seal /
# w_int_alias_seal): a BigInt that integer arithmetic produced is released once
# nothing can read it any more -- a temporary after its last read, a variable's
# old value after the next assignment.  Every shape that must keep a value alive
# is checked against an independently computed value: identity results that
# alias an operand, calls that hand an argument back, copies, containers, a
# method that keeps its argument, and non-integer operands.

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

kept_box = []

-> stash(o)
  kept_box.push(o)
  0

+ BigInt
  # keeps its argument: the caller must not release what it passed
  -> keep_arg(o)
    stash(o)

-> sq(v)
  v * v

-> same(v)
  v

-> bigger(a, b)
  if a > b
    return a
  b

-> len_of(v)
  v.bit_length

-> nested_sum(x, n)
  acc = 0
  i = 0
  while i < n
    acc = (acc + (x * x + i) % 1000003) % 1000003
    i += 1
  acc

-> compare_count(x, n)
  hits = 0
  i = 0
  while i < n
    hits += 1 if x * 3 > x * 2 + i
    i += 1
  hits

-> identity_kept(x)
  a = x + 0
  b = x * 1
  c = same(x * 1)
  [a, b, c]

-> helper_results(x, n)
  out = 0
  i = 0
  while i < n
    y = bigger(x * x, x + i)
    out = y % 1000003
    i += 1
  out

-> copies(x, n)
  a = 0
  b = 0
  i = 0
  while i < n
    a = x * x + i
    b = a
    a = a + 1
    i += 1
  [a, b]

-> pushed(x, n)
  arr = []
  i = 0
  while i < n
    arr.push(x * x + i)
    i += 1
  arr

-> kept_by_method(x)
  t = x * x
  t.keep_arg(x * 3)
  t

-> mixed_kinds(x)
  r = (x * x) / 3
  f = (x * x) * ~1.5
  [r, f]

-> squares_with_temps(x0, n, m)
  x = x0
  i = 0
  while i < n
    x = (sq(x) + len_of(x * 2)) % m
    i += 1
  x

-> squares_ref(x, n, m)
  return x if n == 0
  squares_ref(((x * x) + (x * 2).bit_length) % m, n - 1, m)

big = (3 ## int) ** 2000 + 12345
ref_nested = 0
i = 0
while i < 50
  ref_nested = (ref_nested + (big * big + i) % 1000003) % 1000003
  i += 1
check("nested temporaries", nested_sum(big, 50) == ref_nested)
check("compared temporaries", compare_count(big, 50) == 50)
ik = identity_kept(big)
check("identity results that alias the operand stay valid", ik[0] == big && ik[1] == big && ik[2] == big)
check("a helper returning one of its arguments", helper_results(big, 20) == (big * big) % 1000003)
cp = copies(big, 20)
check("a copied variable keeps its value", cp[1] == big * big + 19 && cp[0] == big * big + 20)
pa = pushed(big, 20)
check("values stored in a container stay valid", pa[0] == big * big && pa[19] == big * big + 19)
kt = kept_by_method(big)
check("a method that keeps its argument", kept_box[0] == big * 3 && kt == big * big)
mk = mixed_kinds(big)
check("non-integer results of integer temporaries", mk[0] * 3 == big * big && mk[1] > 0)
check("temporaries fed to calls in a loop", squares_with_temps(big, 30, (1 ## int) << 3000) == squares_ref(big, 30, (1 ## int) << 3000))

# Memory: 4,000 rounds of a 100,000-bit square with its temporaries kept every
# square, product, sum and remainder before (about 850 MB); now only a few live
# at once (about 6 MB).
m = ((1 ## int) << 100_000) - 1
r = squares_with_temps((3 ## int) ** 1000, 4000, m)
rss_kib = OS.capture("ps -o rss= -p $PPID").strip().to_i()
check("4,000 rounds at 100,000 bits stay under 30 MB (rss_kib=[rss_kib])", rss_kib > 0 && rss_kib < 30_720)
check("and the result is still an integer below the modulus", r >= 0 && r < m)
<< "int_temp_release_spec: all checks passed"
