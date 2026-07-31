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

bad_cover = C.p_adic_smooth_residue_disks(13, 8)
padic_geometry_check("smooth_locus.certified",
                     bad_cover.certified?, true)
padic_geometry_check("smooth_locus.special_fiber_points",
                     bad_cover.special_fiber_points.size, 17)
padic_geometry_check("smooth_locus.disks",
                     bad_cover.smooth_point_count, 16)
padic_geometry_check("smooth_locus.singular_points",
                     bad_cover.singular_point_count, 1)
padic_geometry_check("smooth_locus.incomplete_cover",
                     bad_cover.complete_curve_cover?, false)
padic_geometry_check("smooth_locus.theorem_boundary",
                     bad_cover.certificate.kernel_checked?, false)
cuspidal_point = bad_cover.singular_points[0]
cuspidal_local = bad_cover.reduction_curve.singularity_at(
  cuspidal_point.dehomogenize(0), 0)
padic_geometry_check("smooth_locus.cusp_multiplicity",
                     cuspidal_local.multiplicity, 2)
padic_geometry_check("smooth_locus.cusp_tangent",
                     cuspidal_local.tangent_cone.to_s,
                     "4S^2")

cover3 = C.p_adic_smooth_residue_disks(3, 8)
padic_geometry_check("implicit.p3_smooth_disks",
                     cover3.smooth_point_count, 3)
implicit_a = cover3.disks[0].implicit_coordinate(2)
implicit_b = cover3.disks[1].implicit_coordinate(2)
padic_geometry_check("implicit.a_certified",
                     implicit_a.certified?, true)
padic_geometry_check("implicit.a_point",
                     implicit_a.reduction_point.to_s,
                     "\[0:1:0\]")
padic_geometry_check("implicit.a_valuation",
                     implicit_a.solved_valuation, 1)
padic_geometry_check("implicit.a_unit",
                     implicit_a.solved_unit_residue, 2)
padic_geometry_check("implicit.b_point",
                     implicit_b.reduction_point.to_s,
                     "\[1:2:0\]")
padic_geometry_check("implicit.b_valuation",
                     implicit_b.solved_valuation, 1)
padic_geometry_check("implicit.b_unit",
                     implicit_b.solved_unit_residue, 2)
implicit_exact_rejected = false
begin
  cover3.disks[2].implicit_coordinate(2)
rescue error
  implicit_exact_rejected = true
padic_geometry_check("implicit.exact_point_loud",
                     implicit_exact_rejected, true)

padic_geometry_check("cuspidal.two_primary_order",
                     PlaneQuarticCuspidalModelArithmetic.
                       two_adic_valuation(212), 2)

if env("TUNGSTEN_CUSPIDAL_MODEL") == "1"
  model = C.certify_cuspidal_regular_model(
    13, [1, 8, 1])
  padic_geometry_check("cuspidal.certified",
                       model.certified?, true)
  padic_geometry_check("cuspidal.regular_total_space",
                       model.source_value_valuation, 1)
  padic_geometry_check("cuspidal.normalization_genus",
                       model.normalization_genus, 2)
  padic_geometry_check("cuspidal.normalization_counts",
                       [model.normalization_point_count,
                        model.normalization_extension_point_count].to_s,
                       "\[17, 161\]")
  padic_geometry_check("cuspidal.normalization_zeta",
                       model.normalization_zeta_coefficients.to_s,
                       "\[1, 3, 0, 39, 169\]")
  padic_geometry_check("cuspidal.jacobian_order",
                       model.normalization_jacobian_order, 212)
  padic_geometry_check("cuspidal.local_dimension_bound",
                       model.dimension_upper_bound, 2)

<< "algebra_p_adic_geometry_spec: all checks passed"
