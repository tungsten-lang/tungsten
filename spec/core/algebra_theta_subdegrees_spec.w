# Opt-in exact characteristic-zero theta subdegrees for shell-width.
#
#   TUNGSTEN_THETA_SUBDEGREES=1 \
#     bin/tungsten run spec/core/algebra_theta_subdegrees_spec.w

use algebra

-> theta_subdegree_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

if env("TUNGSTEN_THETA_SUBDEGREES") == "1"
  C ⊂ ℙ²_ℚ (B, S, Z) : 16B³Z + 48BS²Z − 3S⁴ + 8S³Z + 162S²Z² + 729Z⁴ = 0
  infinity = Line.new(C.space, [0, 0, 1])
  setup = C.two_descent_setup(
    distinguished_bitangent: infinity)
  setup.certify_bitangent_scheme
  certificate = setup.certify_theta_subdegrees

  theta_subdegree_check("subdegrees.certified",
                        certificate.certified?, true)
  theta_subdegree_check("subdegrees.factor_degrees",
                        certificate.relative_factor_degrees.to_s,
                        "\[1, 2, 2, 2, 2, 3, 3, 6, 6\]")
  theta_subdegree_check("subdegrees.stabilizer",
                        certificate.stabilizer_subdegrees.to_s,
                        "\[1, 1, 2, 2, 2, 2, 3, 3, 6, 6\]")
  theta_subdegree_check("subdegrees.orbits",
                        certificate.orbit_signature.to_s,
                        "\[1, 6, 9, 12\]")
  theta_subdegree_check("subdegrees.recomposition",
                        certificate.recomposed_projection.eql?(
                          certificate.relative_projection),
                        true)

  galois = setup.certify_theta_galois_subgroup
  theta_subdegree_check("galois.certified",
                        galois.certified?, true)
  theta_subdegree_check("galois.class",
                        galois.identified_candidate.class_id, 693)
  theta_subdegree_check("galois.order",
                        galois.identified_candidate.group.order, 36)
  theta_subdegree_check("galois.up_to_conjugacy",
                        galois.identified_up_to_conjugacy?, true)
  theta_subdegree_check("galois.labeling_boundary",
                        galois.global_arithmetic_labeling_certified?,
                        false)
  theta_subdegree_check("galois.table_boundary",
                        galois.subgroup_table_completeness_checked?,
                        false)
else
  theta_subdegree_check("subdegrees.opt_in",
                        env("TUNGSTEN_THETA_SUBDEGREES"), nil)

<< "algebra_theta_subdegrees_spec: all checks passed"
