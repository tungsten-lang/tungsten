# Modular multivariate GCD over finite fields.

use algebra

-> check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif want.class_name == "Polynomial"
    equal = want.eql?(got)
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> rnd_poly(ring, degrees, st)
  acc = ring.zero
  exponents = []
  degrees.each -> exponents.push(0)
  done = false
  while !done
    st[0] = (st[0] * 1103515245 + 12345) % 2147483648
    powers = []
    exponents.each -> powers.push(item)
    acc = acc + ring.monomial((st[0] / 7) % ring.field.order, powers)
    i = 0
    while i < exponents.size
      exponents[i] += 1
      if exponents[i] <= degrees[i]
        break
      exponents[i] = 0
      i += 1
    done = i == exponents.size
  acc

big = FiniteField.new(10007)
small = FiniteField.new(101)

# Two variables over F_10007.
ring2 = PolynomialRing.new([:x, :y], big, :grevlex)
x, y = ring2.generators
shared2 = x * y + y * y + 3
a2 = (x + y + 1) * shared2
b2 = (x * x - y + 7) * shared2
check("bivariate planted factor", a2.modular_gcd(b2), shared2.monic)
check("gcd dispatches to modular", a2.gcd(b2), shared2.monic)
check("bivariate coprime", (x + 1).modular_gcd(y + 2), ring2.one)
check("bivariate zero argument", a2.modular_gcd(ring2.zero), a2.monic)
check("bivariate univariate content", (x * y * y + x * y).modular_gcd(x * x * y + x * x), (x * y + x).monic)
check("agrees with remainder sequence",
      a2.modular_gcd(b2),
      a2.gcd_recursive(b2, a2.highest_active_variable(b2)).monic)

# Leading-coefficient and content handling.
lc_shared = (y + 5) * x + y * y + 1
a_lc = (y * x + 1) * lc_shared * (y + 3)
b_lc = (x + y) * lc_shared * (y + 3)
check("content in main variable", a_lc.modular_gcd(b_lc), (lc_shared * (y + 3)).monic)

# Three variables over F_10007 and F_101.
ring3 = PolynomialRing.new([:x, :y, :z], big, :grevlex)
gx, gy, gz = ring3.generators
phi = gy * gy - gx * gz * gz + gx * gy * 3 + 5
st = [7]
a3 = phi * rnd_poly(ring3, [2, 1, 1], st)
b3 = phi * rnd_poly(ring3, [2, 1, 1], st)
check("trivariate planted factor", a3.modular_gcd(b3), phi.monic)
check("trivariate agrees with remainder sequence",
      a3.modular_gcd(b3),
      a3.gcd_recursive(b3, a3.highest_active_variable(b3)).monic)
check("trivariate coprime", (gx + gy).modular_gcd(gz + 1), ring3.one)

ring3s = PolynomialRing.new([:x, :y, :z], small, :grevlex)
sx, sy, sz = ring3s.generators
phi_s = sy * sy + sx * sz + 2
a3s = phi_s * (sx * sy + sz + 1)
b3s = phi_s * (sx + sy * sz + 3)
check("small field trivariate", a3s.modular_gcd(b3s), phi_s.monic)
check("small field dispatch", a3s.gcd(b3s), phi_s.monic)

# Field too small for interpolation falls back to the remainder sequence.
tiny = PolynomialRing.new([:x, :y], FiniteField.new(2), :grevlex)
tx, ty = tiny.generators
t_shared = tx * ty + tx + ty + 1
check("tiny field fallback", (t_shared * (tx + ty)).gcd(t_shared * (tx * tx + ty)), t_shared.monic)

# Inputs of the size where the remainder sequence needs more than ten
# minutes; the modular route finishes them in well under a second (wall-clock
# guard: the whole spec runs under `bin/tungsten` in seconds).
st = [11]
large_a = phi * rnd_poly(ring3, [12, 4, 4], st)
large_b = phi * rnd_poly(ring3, [12, 4, 4], st)
check("large planted factor", large_a.modular_gcd(large_b), phi.monic)
<< "large gcd: terms " + large_a.terms.size.to_s + "/" + large_b.terms.size.to_s
<< "ALL PASS"
