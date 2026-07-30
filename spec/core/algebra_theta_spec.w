# Canonical finite theta-characteristic incidence for genus three.

use algebra

-> theta_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

theta = Algebra.genus_three_theta_incidence
theta_check("theta.odd_count",
            theta.odd_characteristics.size, 28)
theta_check("theta.syzygetic_count",
            theta.syzygetic_quadruples.size, 315)
theta_check("theta.module_dimensions",
            theta.module_dimensions.to_s,
            "\[0, 1, 7, 21, 27, 28\]")
theta_check("theta.module_rank_certificates",
            theta.module_rank_certificates.all? ->
              item.verified?,
            true)
theta_check("theta.certificate",
            theta.certificate.verified?, true)
theta_check("theta.theorem_boundary",
            theta.certificate.proof_kind,
            :trusted_theorem_import)
theta_check("theta.not_kernel_theorem",
            theta.certificate.kernel_checked?, false)

first = theta.odd_characteristics[0]
theta_check("theta.form.odd", first.odd?, true)
theta_check("theta.form.quadratic_identity",
            first.certificate.verified?, true)
quadruple = theta.syzygetic_quadruples[0]
theta_check("theta.quadruple.sum_zero",
            theta.characteristic_sum(quadruple).to_s,
            "\[0, 0, 0, 0, 0, 0\]")

<< "algebra_theta_spec: all checks passed"
