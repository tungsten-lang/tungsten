# PolyFast typed reduction lane: output identity against the slow path,
# bail behavior, and key encoding round-trips.

use algebra

failures = 0
-> check_named(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    failures += 1

+ SpecRandom
  -> new(@seed)
  -> next_int(bound)
    @seed = (@seed * 1103515245 + 12345) % 2147483648
    @seed % bound

rng = SpecRandom.new(41)

# Key encoding round-trip.
ring3 = PolynomialRing.new([:x, :y, :z], FiniteField.new(32003), :grevlex)
i = 0
roundtrip_ok = true
while i < 200
  exps = [rng.next_int(64), rng.next_int(64), rng.next_int(64)]
  key = PolyFast.pack_key(exps, 0)
  back = PolyFast.unpack_key(key, 3, 0)
  j = 0
  while j < 3
    roundtrip_ok = false if back[j] != exps[j]
    j += 1
  i += 1
check_named("key.roundtrip", roundtrip_ok)

# Key order equals grevlex order.
order_ok = true
i = 0
while i < 300
  ea = [rng.next_int(20), rng.next_int(20), rng.next_int(20)]
  eb = [rng.next_int(20), rng.next_int(20), rng.next_int(20)]
  ka = PolyFast.pack_key(ea, 0)
  kb = PolyFast.pack_key(eb, 0)
  cmp_ref = ring3.monomial_compare(ea, eb)
  cmp_key = 0
  cmp_key = 1 if ka > kb
  cmp_key = 0 - 1 if ka < kb
  order_ok = false if cmp_ref != cmp_key
  i += 1
check_named("key.order.matches_grevlex", order_ok)

# Key order equals the monomial order for lex and grlex modes too.
lex_ring = PolynomialRing.new([:x, :y, :z], FiniteField.new(32003), :lex)
grlex_ring = PolynomialRing.new([:x, :y, :z], FiniteField.new(32003), :grlex)
modes_ok = true
i = 0
while i < 300
  ea = [rng.next_int(20), rng.next_int(20), rng.next_int(20)]
  eb = [rng.next_int(20), rng.next_int(20), rng.next_int(20)]
  m = 1
  while m <= 2
    ring_m = m == 1 ? lex_ring : grlex_ring
    ka = PolyFast.pack_key(ea, m)
    kb = PolyFast.pack_key(eb, m)
    cmp_ref = ring_m.monomial_compare(ea, eb)
    cmp_key = 0
    cmp_key = 1 if ka > kb
    cmp_key = 0 - 1 if ka < kb
    modes_ok = false if cmp_ref != cmp_key
    rt = PolyFast.unpack_key(ka, 3, m)
    j = 0
    while j < 3
      modes_ok = false if rt[j] != ea[j]
      j += 1
    m += 1
  i += 1
check_named("key.order.matches_lex_grlex", modes_ok)

# Random normal forms: fast lane output == slow path remainder.
-> random_poly(ring, rng, terms, max_exp)
  g = ring.generators
  poly = ring.zero
  t = 0
  while t < terms
    mono = ring.one
    i = 0
    while i < g.size
      mono = mono * g[i]**rng.next_int(max_exp + 1)
      i += 1
    poly = poly + mono * (rng.next_int(32002) + 1)
    t += 1
  poly

arities = [[:x, :y], [:x, :y, :z], [:a, :b, :c, :d]]
orders = [:grevlex, :lex, :grlex]
case_idx = 0
all_match = true
fast_hits = 0
arities.each -> (names)
  orders.each -> (ord)
    ring = PolynomialRing.new(names, FiniteField.new(32003), ord)
    trial = 0
    while trial < 25
      dividend = random_poly(ring, rng, 8, 6)
      divisors = []
      k = 0
      while k < 3
        d = ring.zero
        while d.zero?
          d = random_poly(ring, rng, 3, 4)
        divisors.push(d)
        k += 1
      slow = dividend.divide(divisors)[1]
      fast = PolyFast.normal_form(dividend, divisors)
      if fast == nil
        all_match = false
      else
        fast_hits += 1
        all_match = false if !(fast == slow)
      trial += 1
      case_idx += 1
check_named("normal_form.matches_slow_225_cases", all_match)
check_named("normal_form.fast_lane_engaged", fast_hits == 225)

# Zero dividend and constant divisor edge cases route consistently.
ring = PolynomialRing.new([:x, :y], FiniteField.new(101), :grevlex)
x = ring.generator(0)
y = ring.generator(1)
nf = (x * y + 1).normal_form([ring.one])
check_named("normal_form.unit_divisor", nf.zero?)

# Encoding bound: exponent > 63 must refuse the lane (nil) and the public
# normal_form must still answer via the slow path.
big = x**100 + y
small_basis = [x - y]
check_named("bail.exponent_bound", PolyFast.normal_form(big, small_basis) == nil)
nf2 = big.normal_form(small_basis)
check_named("bail.slow_path_answers", nf2 == y**100 + y)

# Rational field is ineligible: lane refuses, public API still works.
qring = PolynomialRing.new([:u, :v], RationalField.new, :grevlex)
u = qring.generator(0)
v = qring.generator(1)
check_named("bail.rational_field", PolyFast.normal_form(u * v, [u]) == nil)
check_named("bail.rational_slow_ok", (u * v).normal_form([u]).zero?)

if failures == 0
  << "poly_fast_spec: all checks passed"
else
  << "poly_fast_spec: " + failures.to_s + " FAILURES"
