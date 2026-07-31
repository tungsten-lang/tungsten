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
implicit_c = cover3.disks[2].implicit_coordinate(
  2, [1])
implicit_d = cover3.disks[2].implicit_coordinate(
  2, [2])
padic_geometry_check("implicit.prefix_c_certified",
                     implicit_c.certified?, true)
padic_geometry_check("implicit.prefix_c_center",
                     implicit_c.center_coordinates.to_s,
                     "\[1, 3, 0\]")
padic_geometry_check("implicit.prefix_c_digits",
                     implicit_c.free_digits.to_s,
                     "\[1\]")
padic_geometry_check("implicit.prefix_c_depth",
                     implicit_c.depth, 2)
padic_geometry_check("implicit.prefix_c_step",
                     implicit_c.free_step, 9)
padic_geometry_check("implicit.prefix_c_valuation",
                     implicit_c.solved_valuation, 5)
padic_geometry_check("implicit.prefix_c_unit",
                     implicit_c.solved_unit_residue, 1)
padic_geometry_check("implicit.prefix_d_center",
                     implicit_d.center_coordinates.to_s,
                     "\[1, 6, 0\]")
padic_geometry_check("implicit.prefix_d_valuation",
                     implicit_d.solved_valuation, 5)
implicit_nested = implicit_c.refine(2)
padic_geometry_check("implicit.nested_certified",
                     implicit_nested.certified?, true)
padic_geometry_check("implicit.nested_center",
                     implicit_nested.center_coordinates.to_s,
                     "\[1, 21, 0\]")
padic_geometry_check("implicit.nested_depth",
                     implicit_nested.depth, 3)
invalid_digit_rejected = false
begin
  cover3.disks[2].implicit_coordinate(2, [3])
rescue error
  invalid_digit_rejected = true
padic_geometry_check("implicit.invalid_digit_loud",
                     invalid_digit_rejected, true)

singular_cells3 = cover3.singular_cells
padic_geometry_check("cell.p3_singular_classes",
                     singular_cells3.size, 4)
origin_cell3 = singular_cells3[0]
padic_geometry_check("cell.origin_certified",
                     origin_cell3.certified?, true)
padic_geometry_check("cell.origin_center",
                     origin_cell3.center_coordinates.to_s,
                     "\[0, 0, 1\]")
padic_geometry_check("cell.origin_content",
                     origin_cell3.content_valuation, 3)
padic_geometry_check("cell.origin_reduction",
                     origin_cell3.reduction_polynomial.to_s,
                     "u^3 - v^3")
padic_geometry_check("cell.origin_points",
                     origin_cell3.residue_points.to_s,
                     "\[\[0, 0\], \[1, 1\], \[2, 2\]\]")
padic_geometry_check("cell.origin_singular",
                     origin_cell3.singular_residue_point_count, 3)
padic_geometry_check("cell.origin_kernel_boundary",
                     origin_cell3.certificate.kernel_checked?, false)
padic_geometry_check("cell.origin_exact_substitution",
                     origin_cell3.certificate.
                       substitution_kernel_checked?, true)
origin_refinement3 = origin_cell3.refine
padic_geometry_check("cell.refinement_certified",
                     origin_refinement3.certified?, true)
padic_geometry_check("cell.refinement_complete",
                     origin_refinement3.certificate.
                       complete_cover_checked?, true)
padic_geometry_check("cell.first_children",
                     (origin_refinement3.children.map ->
                       item.center_coordinates).to_s,
                     "\[\[0, 0, 1\], \[3, 3, 1\], \[6, 6, 1\]\]")
padic_geometry_check("cell.first_smooth_branches",
                     origin_refinement3.smooth_branch_count, 0)
padic_geometry_check("cell.lifted_empty_classes",
                     singular_cells3.copy(1, 3).all? ->
                       item.empty?, true)
central_refinement3 = (
  origin_refinement3.children[0].refine)
padic_geometry_check("cell.central_children",
                     (central_refinement3.children.map ->
                       item.center_coordinates).to_s,
                     "\[\[0, 9, 1\], \[9, 18, 1\], \[18, 0, 1\]\]")
padic_geometry_check("cell.central_survivor",
                     central_refinement3.children[0].
                       reduction_polynomial.to_s,
                     "u - v")
padic_geometry_check("cell.central_empty_children",
                     central_refinement3.children.copy(
                       1, 2).all? -> item.empty?, true)
positive_cell3 = central_refinement3.children[0]
positive_disks3 = positive_cell3.refine.smooth_disks
padic_geometry_check("cell.positive_hensel_disks",
                     positive_disks3.size, 3)
padic_geometry_check("cell.positive_hensel_certified",
                     positive_disks3.all? ->
                       item.certified?, true)
padic_geometry_check("cell.positive_hensel_center",
                     positive_disks3[0].
                       center_coordinates.to_s,
                     "\[0, 9, 1\]")
negative_cell3 = origin_refinement3.children[2]
negative_disks3 = negative_cell3.refine.smooth_disks
padic_geometry_check("cell.negative_hensel_disks",
                     negative_disks3.size, 3)
padic_geometry_check("cell.negative_hensel_center",
                     negative_disks3[2].
                       center_coordinates.to_s,
                     "\[24, 24, 1\]")

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
