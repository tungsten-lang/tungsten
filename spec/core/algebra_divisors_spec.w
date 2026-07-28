# Exact degree-one places and the certified 2(Q-P) obstruction.
# Run both ways:
#   bin/tungsten run spec/core/algebra_divisors_spec.w
#   bin/tungsten compile spec/core/algebra_divisors_spec.w --out /tmp/algebra-divisors-spec

use algebra
use core/algebra/divisors

-> divisor_check(name, got, want)
  equal = got == want
  if got.class_name == "ProjectivePoint" && want.class_name == "ProjectivePoint"
    equal = got.space == want.space && got.to_s == want.to_s
  elsif got.class_name == "Divisor" && want.class_name == "Divisor"
    equal = got.eql?(want)
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

rational_space = ProjectiveSpace<ℚ, 2>.new(:B, :S, :Z)
rational_point = rational_space.point(0, 9, 1)

field5 = FiniteField.new(5)
finite_space5 = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(field5), 2, [:B, :S, :Z])
B = finite_space5.coords[0]
S = finite_space5.coords[1]
Z = finite_space5.coords[2]
f = B**3*Z*16 + B*S**2*Z*48 - S**4*3 + S**3*Z*8 + S**2*Z**2*162 + Z**4*729
c5 = Curve.new(finite_space5, f)

# A point from another presentation of the same finite projective space is
# rehomed into the curve's own space. Raw integer coordinates use field
# coercion, so 9 is reduced to 4 in F_5.
source_space5 = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(field5), 2, [:X, :Y, :Z])

p0 = c5.place(source_space5.point(1, 0, 0))
p1 = c5.place(source_space5.point(0, 9, 1))
p2_known = c5.place(source_space5.point(-3, -3, 1))
rational_place = c5.place(rational_point)
divisor_check("place.curve", p0.curve, c5)
divisor_check("place.degree", p0.degree, 1)
divisor_check("place.rehome.space", p1.point.space, c5.space)
divisor_check("place.reduce.coordinates", p1.point, c5.space.point(0, 4, 1))
divisor_check("place.raw.coordinates",
              c5.place([0, 9, 1]).point, c5.space.point(0, 4, 1))
divisor_check("place.rational_reduction",
              rational_place.point, c5.space.point(0, 4, 1))
divisor_check("place.third_known", c5.contains?(p2_known.point), true)

difference = p1 - p0
divisor_check("divisor.degree.zero", difference.degree, 0)
divisor_check("divisor.coefficient.positive", difference.coefficient(p1), 1)
divisor_check("divisor.coefficient.negative", difference.coefficient(p0), -1)

# Scalar multiplication is exact. Tungsten's built-in numeric-left operators
# do not dispatch to source overloads, so the isolated layer uses (Q-P)*2.
twice = difference * 2
divisor_check("divisor.scalar.positive", twice.coefficient(p1), 2)
divisor_check("divisor.scalar.negative", twice.coefficient(p0), -2)
divisor_check("divisor.scalar.zero", (difference * 0).zero?, true)
divisor_check("divisor.scalar.negative_value",
              (difference * -2).coefficient(p1), -2)

# A hypothetical function with divisor 2Q-2P would have pole divisor of
# degree two, hence define a degree-two map to P^1. A smooth plane quartic is
# nonhyperelliptic, so this is a certified nonprincipality proof.
result = twice.principal_result
divisor_check("principality.nonprincipal", result.principal?, false)
divisor_check("principality.certified", result.certified?, true)
divisor_check("principality.theorem",
              result.theorem,
              "nonhyperelliptic degree-two-map obstruction")
divisor_check("principality.boolean", twice.principal?, false)

zero_divisor = p0 - p0
divisor_check("zero.normalized", zero_divisor.zero?, true)
divisor_check("zero.principal", zero_divisor.principal?, true)
divisor_check("zero.certified", zero_divisor.principal_result.certified?, true)

# General degree-zero divisors remain explicitly unsupported.
general_failed = false
begin
  difference.principal?
rescue error
  general_failed = "[error]".include?("only certified")
divisor_check("principality.general_is_loud", general_failed, true)

# In characteristic two, a degree-two function can be inseparable, so the
# nonhyperelliptic separable-map obstruction is deliberately not applied.
field2 = FiniteField.new(2)
p2_2 = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(field2), 2, [:X, :Y, :Z])
X2 = p2_2.coords[0]
Y2 = p2_2.coords[1]
char2_curve = Curve.new(p2_2, X2**4 + Y2**4)
char2_left = char2_curve.place([1, 1, 0])
char2_right = char2_curve.place([1, 1, 1])
char2_failed = false
begin
  ((char2_right - char2_left) * 2).principal?
rescue error
  char2_failed = "[error]".include?("characteristic two")
divisor_check("principality.characteristic_two_is_loud", char2_failed, true)

off_curve_failed = false
begin
  c5.place([0, 0, 1])
rescue error
  off_curve_failed = "[error]".include?("not on the curve")
divisor_check("place.off_curve_is_loud", off_curve_failed, true)

field7 = FiniteField.new(7)
p2_7 = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(field7), 2, [:B, :S, :Z])
B7 = p2_7.coords[0]
S7 = p2_7.coords[1]
Z7 = p2_7.coords[2]
f7 = B7**3*Z7*16 + B7*S7**2*Z7*48 - S7**4*3 + S7**3*Z7*8 + S7**2*Z7**2*162 + Z7**4*729
c7 = Curve.new(p2_7, f7)
p0_over_7 = c7.place([1, 0, 0])
ownership_failed = false
begin
  p1 - p0_over_7
rescue error
  ownership_failed = "[error]".include?("different curves")
divisor_check("place.curve_ownership_is_loud", ownership_failed, true)

field_failed = false
begin
  c5.place(p0_over_7.point)
rescue error
  field_failed = "[error]".include?("coefficient fields")
divisor_check("place.field_mismatch_is_loud", field_failed, true)

<< "algebra_divisors_spec: all checks passed"
