# End-to-end exact arithmetic for the active shell-width quartic workflow.
# The focused layer specs carry edge cases; this file pins the identities that
# connect those layers in the research program.
#
#   bin/tungsten run spec/core/algebra_shell_width_quartic_spec.w
#   bin/tungsten compile spec/core/algebra_shell_width_quartic_spec.w \
#     --out /tmp/algebra-shell-width-quartic-spec

use algebra

-> shell_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

C ⊂ ℙ²_ℚ (B, S, Z) : 16B³Z + 48BS²Z − 3S⁴ + 8S³Z + 162S²Z² + 729Z⁴ = 0

C.assert_homogeneous(4)
shell_check("curve.nonsingular", C.nonsingular?, true)
shell_check("curve.genus", C.genus, 3)
shell_check("curve.hyperelliptic", C.hyperelliptic?, false)

space = C.space
known_points = [
  space[1:0:0],
  space[0:9:1],
  space[-3:-3:1]
]
known_points.each -> (point)
  shell_check("curve.known_point." + point.to_s, C.contains?(point), true)

automorphisms = C.geometric_automorphisms
shell_check("curve.geometric_automorphism_order", automorphisms.order, 1)
shell_check("curve.geometric_automorphism_certificate",
            automorphisms.certified?, true)

searched_points = C.rational_points(height: 100)
shell_check("curve.point_search",
            (searched_points.map -> item.to_s).join("|"),
            "\[1:0:0\]|\[3:3:-1\]|\[0:9:1\]")

i27 = C.dixmier_ohno.last
expected_i27 = 0 - (2 ** 40) * (3 ** 42) * (13 ** 2)
shell_check("quartic.I27", i27, Rational.new(expected_i27))
shell_check("quartic.bad_primes",
            i27.to_i.factor.primes.to_s,
            "\[2, 3, 13\]")

c5 = C.reduce(5)
c7 = C.reduce(7)
l5 = c5.zeta.numerator
l7 = c7.zeta.numerator
shell_check("zeta.F5", l5.coefficients.to_s,
            "\[1, 2, 6, 8, 30, 50, 125\]")
shell_check("zeta.F7", l7.coefficients.to_s,
            "\[1, 2, 10, 32, 70, 98, 343\]")
shell_check("jacobian.F5", l5.at(1), 222)
shell_check("jacobian.F7", l7.at(1), 556)
shell_check("torsion.bound", l5.at(1).gcd(l7.at(1)), 2)

h5 = c5.weil_cubic
h7 = c7.weil_cubic
field5 = NumberField.new(h5.polynomial)
shell_check("weil.F5.field_discriminant", h5.field_discriminant, 3624)
shell_check("weil.F7.field_discriminant", h7.field_discriminant, 229)
shell_check("weil.F5.root_in_K", h5.roots_in(field5).size, 1)
shell_check("weil.F7.root_in_K", h7.roots_in(field5).size, 0)

g5 = l5.galois_group
shell_check("galois.F5.name", g5.name, "W(C3)")
shell_check("galois.F5.order", g5.order, 48)
shell_check("galois.F5.certified", g5.certified?, true)

p0 = c5.place(known_points[0])
p1 = c5.place(known_points[1])
twice_difference = (p1 - p0) * 2
shell_check("divisor.twice_nonprincipal",
            twice_difference.principal_result.nonprincipal?, true)
shell_check("divisor.certificate",
            twice_difference.principal_result.certified?, true)

infinity = Line.new(space, [0, 0, 1])
shell_check("hyperflex.restriction",
            C.equation.restrict_to(infinity).to_s,
            "-3S^4")
shell_check("hyperflex.intersection",
            C.intersection_divisor(infinity).to_s,
            "4*\[1:0:0\]")
shell_check("bitangents.F5", c5.bitangents.size, 1)
shell_check("bitangents.F7", c7.bitangents.size, 1)

shell_check("trace.F5", c5.frobenius_trace, -2)
shell_check("trace.F7", c7.frobenius_trace, -2)

<< "algebra_shell_width_quartic_spec: all checks passed"
