# Geometric (Qbar, not merely rational) automorphisms of plane quartics.
# The full seven-variable stabilizer certificate is a compiled regression:
#   bin/tungsten compile spec/core/algebra_automorphisms_spec.w \
#     --out /tmp/algebra-automorphisms-spec
#   TUNGSTEN_AUTOMORPHISMS_FULL=1 /tmp/algebra-automorphisms-spec
#
# It is intentionally opt-in under the tree-walking interpreter, whose generic
# object representation currently needs about 10 GB for this Gröbner basis.

use algebra

-> automorphism_check(name, got, want)
  if got != want
    raise "FAIL " + name + " got " + got.to_s + " want " + want.to_s
  << "PASS " + name

p2 = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
coordinates = p2.coords
X = coordinates[0]
Y = coordinates[1]
Z = coordinates[2]

equation = X**3 * Z * 16
equation += X * Y**2 * Z * 48
equation -= Y**4 * 3
equation += Y**3 * Z * 8
equation += Y**2 * Z**2 * 162
equation += Z**4 * 729
curve = Curve.new(p2, equation)

if env("TUNGSTEN_AUTOMORPHISMS_FULL") == "1"
  group = curve.geometric_automorphisms
  certificate = group.certificate
  automorphism_check("group.name", group.name, "trivial")
  automorphism_check("group.order", group.order, 1)
  automorphism_check("group.certified", group.certified?, true)
  automorphism_check("certificate.geometric", certificate.geometric?, true)
  automorphism_check("certificate.certified", certificate.certified?, true)
  automorphism_check("certificate.hyperflex",
                     certificate.hyperflex, p2.point(1, 0, 0))
  automorphism_check("certificate.tangent",
                     certificate.tangent, Line.new(p2, Z))
  automorphism_check("certificate.no_affine_hyperflex",
                     certificate.affine_hyperflex_ideal.unit?, true)
  automorphism_check("certificate.stabilizer_groebner",
                     certificate.stabilizer_groebner_basis.
                       certified?, true)

  stabilizer = certificate.stabilizer_ideal
  parameter_ring = stabilizer.ring
  parameters = parameter_ring.generators
  expected_identity = [
    parameters[0] - 1,
    parameters[1],
    parameters[2],
    parameters[3] - 1,
    parameters[4],
    parameters[5] - 1,
    parameters[6] - 1
  ]
  expected_identity.each -> (relation)
    automorphism_check("stabilizer.contains." + relation.to_s,
                       certificate.stabilizer_groebner_basis.
                         contains?(relation), true)
else
  << "SKIP full stabilizer (set TUNGSTEN_AUTOMORPHISMS_FULL=1)"

# Do not silently report a rational stabilizer as the geometric group.  This
# quartic has an evident nontrivial geometric stabilizer and is outside the
# unique-normalized-hyperflex certificate, so the focused API fails loudly.
fermat = Curve.new(p2, X**4 + Y**4 + Z**4)
unsupported = false
begin
  fermat.geometric_automorphisms
rescue error
  unsupported = error.to_s.include?("normalized hyperflex")
automorphism_check("unsupported_quartic_is_loud", unsupported, true)

<< "algebra_automorphisms_spec: all checks passed"
