# Exact replay of the finite shell-width theta subgroup candidates.

use algebra

-> theta_galois_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

certificate = Algebra.shell_width_theta_subgroup_identification
candidate = certificate.identified_candidate

theta_galois_check("table.records_replayed",
                    certificate.table.finite_records_replayed?, true)
theta_galois_check("table.completeness_boundary",
                    certificate.table.completeness_replayed?, false)
theta_galois_check("identification.verified",
                    certificate.verified?, true)
theta_galois_check("identification.unique",
                    certificate.survivors.size, 1)
theta_galois_check("identification.class",
                    candidate.class_id, 693)
theta_galois_check("identification.order",
                    candidate.group.order, 36)
theta_galois_check("identification.orbits",
                    candidate.orbit_sizes.to_s, "\[1, 6, 9, 12\]")
theta_galois_check("identification.subdegrees",
                    candidate.stabilizer_orbit_signatures_for_orbit_size(6)[0].to_s,
                    "\[1, 1, 2, 2, 2, 2, 3, 3, 6, 6\]")
theta_galois_check("identification.arithmetic_boundary",
                    certificate.arithmetic_invariants_checked?, false)
theta_galois_check("identification.global_boundary",
                    certificate.global_galois_group_certified?, false)

<< "algebra_theta_galois_spec: all checks passed"
