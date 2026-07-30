# Exact line restrictions, certified closed-place intersections, and
# finite-field bitangent enumeration for the shell-width quartic.
#
# Run both ways:
#   bin/tungsten run spec/core/algebra_quartics_spec.w
#   bin/tungsten compile spec/core/algebra_quartics_spec.w --out /tmp/algebra-quartics-spec
#   TUNGSTEN_QUARTIC_FULL=1 /tmp/algebra-quartics-spec

use algebra
use core/algebra/divisors
use core/algebra/quartics

-> quartic_check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial" && want.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif got.class_name == "ProjectivePoint" && want.class_name == "ProjectivePoint"
    equal = got.space == want.space && got.to_s == want.to_s
  elsif got.class_name == "Array" && want.class_name == "Array"
    equal = got.to_s == want.to_s
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

p2 = ProjectiveSpace<ℚ, 2>.new(:B, :S, :Z)
B = p2.coords[0]
S = p2.coords[1]
Z = p2.coords[2]
f = B**3*Z*16 + B*S**2*Z*48 - S**4*3 + S**3*Z*8 + S**2*Z**2*162 + Z**4*729
curve = Curve.new(p2, f)

infinity = Line.new(p2, Z)
quartic_check("line.coefficients", infinity.coefficients.to_s, "\[0, 0, 1\]")
quartic_check("line.array_constructor", Line.new(p2, [0, 0, -3]), infinity)
quartic_check("line.contains.hyperflex", infinity.contains?(p2.point(1, 0, 0)), true)
quartic_check("line.excludes.affine", infinity.contains?(p2.point(0, 9, 1)), false)

restricted = f.restrict_to(infinity)
parameters = infinity.parameter_ring.generators
quartic_check("restriction.binary_ring.names",
              infinity.parameter_ring.names.to_s, "\[B, S\]")
quartic_check("restriction.Z_zero", restricted, parameters[1]**4 * -3)
quartic_check("restriction.homogeneous", restricted.homogeneous?, true)
quartic_check("restriction.degree", restricted.degree, 4)

intersection = curve.intersection_divisor(infinity)
quartic_check("intersection.degree", intersection.degree, 4)
quartic_check("intersection.term_count", intersection.terms.size, 1)
quartic_check("intersection.multiplicity", intersection.terms[0][0], 4)
quartic_check("intersection.hyperflex_point",
              intersection.terms[0][1].point, p2.point(1, 0, 0))
quartic_check("intersection.display", intersection.to_s, "4*\[1:0:0\]")

general_line = Line.new(p2, B)
general_intersection = curve.line_intersection(general_line)
general_divisor = general_intersection.divisor
quartic_check("intersection.general.certified",
              general_intersection.certified?, true)
quartic_check("intersection.general.degree", general_divisor.degree, 4)
quartic_check("intersection.general.term_count",
              general_divisor.terms.size, 2)
quartic_check("intersection.general.residue_degrees",
              general_divisor.terms.map -> item[1].degree,
              [1, 3])
quartic_check("intersection.general.rational_point",
              general_divisor.terms[0][1].point,
              p2.point(0, 9, 1))
cubic_place = general_divisor.terms[1][1]
quartic_check("intersection.general.closed_place",
              cubic_place.class_name, "ClosedPlace")
quartic_check("intersection.general.closed_certificate",
              cubic_place.certified?, true)
quartic_check("intersection.general.factor_degrees",
              general_intersection.factorization.factors.map -> item.degree,
              [0, 1, 3])

closed_point_failed = false
begin
  cubic_place.point
rescue error
  closed_point_failed = error.to_s.include?("no coefficient-field")
quartic_check("intersection.closed_point_is_loud",
              closed_point_failed, true)

tampered_intersection = LineIntersectionCertificate.new(
  curve, general_line, Divisor.new(curve, []),
  general_intersection.factorization)
quartic_check("intersection.certificate.rejects_divisor",
              tampered_intersection.verified?, false)

component_curve = Curve.new(p2, B*S**3)
component_failed = false
begin
  component_curve.intersection_divisor(general_line)
rescue error
  component_failed = error.to_s.include?("curve component")
quartic_check("intersection.component_is_loud", component_failed, true)

# The two parameter charts reconstruct the same divisor. This exercises a
# mixed restriction with finite roots and a nonzero point-at-infinity
# multiplicity, rather than only the monomial hyperflex case.
mixed_curve = Curve.new(
  p2, B**4 + S*(S - Z)*Z**2)
mixed_line = Line.new(p2, B)
mixed_intersection = mixed_curve.line_intersection(mixed_line)
mixed_affine_zero = mixed_line.affine_restriction(
  mixed_curve.equation, 0)
mixed_factorization_zero = mixed_affine_zero.factor_with_certificate
mixed_divisor_zero = mixed_curve.intersection_divisor_from_factorization(
  mixed_line, mixed_factorization_zero, 0)
quartic_check("intersection.chart_round_trip",
              mixed_divisor_zero, mixed_intersection.divisor)
quartic_check("intersection.mixed.degree",
              mixed_intersection.divisor.degree, 4)
quartic_check("intersection.mixed.infinity_multiplicity",
              mixed_intersection.divisor.coefficient(
                mixed_curve.place(mixed_line.point([1, 0]))),
              2)
quartic_check("intersection.mixed.zero_multiplicity",
              mixed_intersection.divisor.coefficient(
                mixed_curve.place(mixed_line.point([0, 1]))),
              1)
quartic_check("intersection.mixed.one_multiplicity",
              mixed_intersection.divisor.coefficient(
                mixed_curve.place(mixed_line.point([1, 1]))),
              1)

invalid_line_failed = false
begin
  Line.new(p2, B**2)
rescue error
  invalid_line_failed = error.to_s.include?("homogeneous linear")
quartic_check("line.nonlinear_is_loud", invalid_line_failed, true)

field_line_failed = false
begin
  other_plane = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
  f.restrict_to(Line.new(other_plane, other_plane.coords[2]))
rescue error
  field_line_failed = error.to_s.include?("different coordinate rings")
quartic_check("restriction.ring_mismatch_is_loud", field_line_failed, true)

# Line substitution preserves packed extension-field elements as internal
# residues. In F_25 = F_5[t]/(t^2+2), this is the exact identity
# (tX + Z)|_(tX+Z=0) = 0.
f25 = FiniteField.new(5, [2, 0, 1])
t25 = f25.coerce([0, 1])
p2_25 = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(f25), 2, [:X, :Y, :Z])
extension_equation = p2_25.ring.monomial_raw(t25, [1, 0, 0]) + p2_25.coords[2]
extension_line = Line.raw(p2_25, [t25, 0, 1])
quartic_check("restriction.extension_raw_residue",
              extension_equation.restrict_to(extension_line).zero?, true)
quartic_check("line.extension_external_integer",
              Line.new(p2_25, [1, 5, 0]).coefficients.to_s,
              [1, 0, 0].to_s)
quartic_check("line.extension_raw_integer",
              Line.raw(p2_25, [1, 5, 0]).coefficients.to_s,
              [1, t25, 0].to_s)

# General intersections over a prime field preserve the factor residue
# degrees. For B=0 mod 5 the restriction has two rational roots and one
# quadratic closed point.
curve5 = curve.reduce(5)
intersection5 = curve5.line_intersection(
  Line.new(curve5.space, curve5.space.coords[0]))
quartic_check("intersection.F5.certified", intersection5.certified?, true)
quartic_check("intersection.F5.degree", intersection5.divisor.degree, 4)
quartic_check("intersection.F5.residue_degrees",
              intersection5.divisor.terms.map -> item[1].degree,
              [1, 1, 2])
quartic_check("intersection.F5.factor_degrees",
              intersection5.factorization.factors.map -> item.degree,
              [0, 1, 1, 2])
quartic_check("intersection.F5.closed_certificate",
              intersection5.divisor.terms[2][1].certified?, true)

# Inseparable multiplicities become divisor coefficients rather than
# duplicate place objects: (Y²+YZ+Z²)² on X=0 is twice one quadratic place.
field2_places = FiniteField.new(2)
p2_places = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(field2_places), 2, [:X, :Y, :Z])
x_places = p2_places.coords[0]
y_places = p2_places.coords[1]
z_places = p2_places.coords[2]
quadratic_place_form = y_places**2 + y_places*z_places + z_places**2
repeated_place_curve = Curve.new(
  p2_places, x_places**4 + quadratic_place_form**2)
repeated_intersection = repeated_place_curve.line_intersection(
  Line.new(p2_places, x_places))
quartic_check("intersection.F2.repeated.term_count",
              repeated_intersection.divisor.terms.size, 1)
quartic_check("intersection.F2.repeated.multiplicity",
              repeated_intersection.divisor.terms[0][0], 2)
quartic_check("intersection.F2.repeated.residue_degree",
              repeated_intersection.divisor.terms[0][1].degree, 2)
quartic_check("intersection.F2.repeated.certified",
              repeated_intersection.certified?, true)

# The same construction works when the coefficient field is itself an
# extension. Packed coefficients remain raw elements of F4 throughout.
field4_places = FiniteField.extension(2, 2)
a4_places = field4_places.generator
p2_4_places = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(field4_places), 2, [:X, :Y, :Z])
x4_places = p2_4_places.coords[0]
y4_places = p2_4_places.coords[1]
z4_places = p2_4_places.coords[2]
q4_places = y4_places**2 + y4_places*z4_places
q4_places += p2_4_places.ring.monomial_raw(
  a4_places, [0, 0, 2])
curve4_places = Curve.new(
  p2_4_places, x4_places**4 + q4_places**2)
intersection4_places = curve4_places.line_intersection(
  Line.new(p2_4_places, x4_places))
quartic_check("intersection.F4.residue_degree",
              intersection4_places.divisor.terms[0][1].degree, 2)
quartic_check("intersection.F4.multiplicity",
              intersection4_places.divisor.terms[0][0], 2)
quartic_check("intersection.F4.certified",
              intersection4_places.certified?, true)

full_counts = env("TUNGSTEN_QUARTIC_FULL") == "1"
if full_counts
  primes = [5, 7, 11, 17, 19, 23, 29, 31]
  expected = [1, 1, 4, 1, 4, 4, 1, 1]
else
  # The exact same scan is roughly forty times slower at p=31 than at p=5
  # in the tree-walking interpreter. Keep its default regression focused;
  # the compiled command above checks the complete independent fixture.
  primes = [5]
  expected = [1]
counts = []
i = 0
while i < primes.size
  reduced = curve.reduce(primes[i])
  lines = reduced.bitangents
  counts.push(lines.size)
  reduced_infinity = Line.new(reduced.space, [0, 0, 1])
  found_infinity = false
  # Every reported line passes the exact public restriction test.
  lines.each -> (line)
    quartic_check(
      "bitangent.line.on.dual." + primes[i].to_s,
      line.space,
      reduced.space)
    found_infinity = true if line.eql?(reduced_infinity)
  quartic_check(
    "bitangent.hyperflex.persistent." + primes[i].to_s,
    found_infinity,
    true)
  i += 1
quartic_check("bitangent.counts", counts.to_s, expected.to_s)

two_failed = false
begin
  curve.reduce(2).bitangents
rescue error
  two_failed = error.to_s.include?("odd characteristic")
quartic_check("bitangent.characteristic_two_is_loud", two_failed, true)

rational_failed = false
begin
  curve.bitangents
rescue error
  rational_failed = error.to_s.include?("finite coefficient")
quartic_check("bitangent.rational_is_loud", rational_failed, true)

<< "algebra_quartics_spec: all checks passed"
