# Certified good-reduction residue disks for the shell-width quartic.

use algebra

-> padic_geometry_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

C ⊂ ℙ²_ℚ (B, S, Z) : 16B³Z + 48BS²Z − 3S⁴ + 8S³Z + 162S²Z² + 729Z⁴ = 0
cover = C.p_adic_residue_disks(5, 8)

padic_geometry_check("cover.certified", cover.certified?, true)
padic_geometry_check("cover.point_count",
                     cover.reduction_curve.point_count, 8)
padic_geometry_check("cover.disk_count",
                     cover.disks.size, 8)
padic_geometry_check("cover.smooth_disks",
                     cover.disks.all? -> item.smooth?, true)
padic_geometry_check("cover.special_fiber_replay",
                     cover.certificate.finite_special_fiber_replayed?,
                     true)
padic_geometry_check("cover.theorem_boundary",
                     cover.certificate.kernel_checked?, false)
padic_geometry_check("cover.local_image_boundary",
                     cover.local_descent_image_certified?, false)

bad = false
begin
  C.p_adic_residue_disks(13, 8)
rescue error
  bad = true
padic_geometry_check("cover.bad_reduction_loud", bad, true)

<< "algebra_p_adic_geometry_spec: all checks passed"
