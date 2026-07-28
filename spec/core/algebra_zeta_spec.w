# Exact finite-curve and zeta-function regressions for the shell-width
# quartic. These values are independently reproduced by
# /Users/erik/math/shell_width_remaining_canonical.py.

use algebra

-> zeta_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> brute_cubic_root_count(field, a0, a1, a2, a3)
  count = 0
  value = 0
  while value < field.order
    result = field.add(
      field.multiply(
        field.add(
          field.multiply(
            field.add(field.multiply(a3, value), a2), value),
          a1),
        value),
      a0)
    count += 1 if field.zero?(result)
    value += 1
  count

p2 = ProjectiveSpace<ℚ, 2>.new(:B, :S, :Z)
B = p2.coords[0]
S = p2.coords[1]
Z = p2.coords[2]
f = B**3*Z*16 + B*S**2*Z*48 - S**4*3 + S**3*Z*8 + S**2*Z**2*162 + Z**4*729
curve = Curve.new(p2, f)

c5 = curve.reduce(5)
zeta_check("reduce.field", c5.field.to_s, "𝔽_5")
zeta_check("reduce.contains.infinity", c5.contains?(c5.space.point([1, 0, 0])), true)
zeta_check("reduce.contains.affine", c5.contains?(c5.space.point([0, 4, 1])), true)
zeta_check("count.F5", c5.point_count, 8)
zeta_check("trace.F5", c5.frobenius_trace, -2)
zeta_check("count.F25", c5.extension_curve(2).point_count, 34)
zeta_check("count.F125", c5.extension_curve(3).point_count, 122)

# The fixed-register cubic quotient kernel must agree with literal root
# enumeration, including repeated-root fibers and extension-field elements.
kernel_mismatches = 0
a0 = 0
while a0 < 5
  a1 = 0
  while a1 < 5
    a2 = 0
    while a2 < 5
      fast = c5.cubic_finite_root_count(a0, a1, a2, 1, 5)
      slow = brute_cubic_root_count(c5.field, a0, a1, a2, 1)
      kernel_mismatches += 1 if fast != slow
      a2 += 1
    a1 += 1
  a0 += 1
zeta_check("cubic_kernel.F5_exhaustive", kernel_mismatches, 0)

c25 = c5.extension_curve(2)
kernel_mismatches = 0
sample = 0
while sample < c25.field.order
  a0 = sample
  a1 = c25.field.add(sample, 3)
  a2 = c25.field.multiply(sample, sample)
  fast = c25.cubic_finite_root_count(a0, a1, a2, 1, c25.field.order)
  slow = brute_cubic_root_count(c25.field, a0, a1, a2, 1)
  kernel_mismatches += 1 if fast != slow
  sample += 1
zeta_check("cubic_kernel.F25_samples", kernel_mismatches, 0)

z5 = c5.zeta
zeta_check("zeta.F5.counts", z5.counts.to_s, "\[8, 34, 122\]")
zeta_check("zeta.F5.numerator",
  z5.numerator.coefficients.to_s, "\[1, 2, 6, 8, 30, 50, 125\]")
zeta_check("zeta.F5.jacobian_order", z5.numerator.at(1), 222)
zeta_check("zeta.F5.integer_value", z5.numerator.at(1).class_name, "Integer")
zeta_check("weil.F5", c5.weil_cubic.coefficients.to_s,
  "\[-12/1, -9/1, 2/1, 1/1\]")

c7 = curve.reduce(7)
z7 = c7.zeta
zeta_check("zeta.F7.counts", z7.counts.to_s, "\[10, 66, 388\]")
zeta_check("trace.F7", c7.frobenius_trace, -2)
zeta_check("zeta.F7.numerator",
  z7.numerator.coefficients.to_s, "\[1, 2, 10, 32, 70, 98, 343\]")
zeta_check("zeta.F7.jacobian_order", z7.numerator.at(1), 556)
zeta_check("torsion.bound", z5.numerator.at(1).gcd(z7.numerator.at(1)), 2)

weil5 = c5.weil_cubic
weil7 = c7.weil_cubic
weil_field = NumberField.new(weil5.polynomial)
zeta_check("weil.F5.irreducible", weil5.irreducible?, true)
zeta_check("weil.F5.field_discriminant", weil5.field_discriminant, 3624)
zeta_check("weil.F5.root_in_own_field", weil5.roots_in(weil_field).size, 1)
zeta_check("weil.F7.field_discriminant", weil7.field_discriminant, 229)
zeta_check("weil.F7.no_root_in_F5_field", weil7.roots_in(weil_field).size, 0)

denominator_failed = false
begin
  q2 = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
  X = q2.coords[0]
  Y = q2.coords[1]
  Z = q2.coords[2]
  bad_denominator_curve = Curve.new(q2, X**2 * Rational.new(1, 5) + Y*Z)
  bad_denominator_curve.reduce(5)
rescue error
  denominator_failed = "[error]".include?("division by zero")
zeta_check("reduction.denominator_is_loud", denominator_failed, true)

<< "algebra_zeta_spec: all checks passed"
