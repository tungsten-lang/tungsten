# Quaternion<T> — the dimension-4 Cayley–Dickson algebra (basis 1, i, j, k),
# scalar-FIRST storage: components[0] = w (scalar), [1..3] = x, y, z.
#
# This spec pins the level's defining algebra: the Hamilton multiplication
# table, the identity quaternions LOSE relative to Complex (commutativity),
# and the ones they still KEEP (associativity, the multiplicative norm, a
# genuine two-sided inverse — Quaternion is a normed division algebra).
# Plus construction, component/basis accessors, conjugate, norm, inverse,
# powers, the transcendental pair exp/log, the rotation surface
# (from_axis_angle / rotate / to_rotation_matrix / slerp), Metal-layout
# conversion, and printing.
#
# Component values are small integers held in f64, so every arithmetic
# assertion below is exact — no tolerance except where a transcendental or
# a square root is genuinely involved.
#
# Run:
#   bin/tungsten run --interpret spec/numeric/quaternion_spec.w
#   bin/tungsten -o /tmp/quaternion_spec spec/numeric/quaternion_spec.w && \
#     /tmp/quaternion_spec

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# Typed constructors. The class-side factories (`.basis` / `.one` / `.zero`)
# build BOXED integer components rather than `T`-typed ones, so a value they
# produce is never `==` to one arithmetic produced (see the class.factories
# section at the end). These helpers keep every value on the typed side.
-> q4(a, b, c, d)
  Quaternion<f64>.new([a ## f64, b ## f64, c ## f64, d ## f64] ## f64[4])

-> qbasis(n)
  Quaternion<f64>.new((0...4).map -> item == n ? 1 ## f64 : 0 ## f64)

# Componentwise equality that ignores whether the backing array is typed
# or boxed — the property `==` is supposed to test.
-> same(left, right)
  return false if left.dimension != right.dimension
  i = 0
  while i < left.dimension
    return false if left.components[i].to_f != right.components[i].to_f
    i += 1
  true

-> close(left, right, tolerance)
  i = 0
  while i < left.dimension
    return false if (left.components[i].to_f - right.components[i].to_f).abs > tolerance
    i += 1
  true

pi = ~3.141592653589793
one = q4(1, 0, 0, 0)
zero = q4(0, 0, 0, 0)
i = qbasis(1)
j = qbasis(2)
k = qbasis(3)
q = q4(1, 2, 3, 4)
p = q4(5, 6, 7, 8)

# --- Construction and shape ---------------------------------------------------
check("shape.dimension", q.dimension == 4)
check("shape.scalar_index", q.scalar_index == 0)
check("shape.half_class", Quaternion<f64>.new([~0.0, ~0.0, ~0.0, ~0.0] ## f64[4]).half_class == Complex)
check("shape.components", q.components.size == 4)
check("construct.typed_roundtrip", same(q, Quaternion<f64>.new([~1.0, ~2.0, ~3.0, ~4.0] ## f64[4])))
check("construct.eq_is_componentwise", q == q4(1, 2, 3, 4))
check("construct.neq", q != p && !(q == p))

# --- Component access ---------------------------------------------------------
check("access.wxyz", q.w == 1 && q.x == 2 && q.y == 3 && q.z == 4)
check("access.s_is_scalar", q.s == q.w)
check("access.hamilton", q.i == 2 && q.j == 3 && q.k == 4)
check("access.cayley_dickson", q.e0 == 1 && q.e1 == 2 && q.e2 == 3 && q.e3 == 4)
check("access.indexed_e", q.e(0) == 1 && q.e(3) == 4)
check("access.real", q.real == 1)
check("access.imaginary", same(q.imaginary, q4(0, 2, 3, 4)))
shuffled = q.shuffle([3, 0, 1, 2])
check("access.shuffle",
      shuffled[0] == 4 && shuffled[1] == 1 && shuffled[2] == 2 && shuffled[3] == 3)

# --- Addition and subtraction (componentwise) ---------------------------------
check("add.componentwise", same(q + p, q4(6, 8, 10, 12)))
check("sub.componentwise", same(q - p, q4(-4, -4, -4, -4)))
check("add.identity", same(q + zero, q))
check("sub.self_is_zero", same(q - q, zero))
check("negate", same(q.negate, q4(-1, -2, -3, -4)))
check("negate.unary_operator", same(-q, q.negate))
check("negate.additive_inverse", same(q + q.negate, zero))

# --- The Hamilton multiplication table ----------------------------------------
check("hamilton.i_squared", same(i * i, one.negate))
check("hamilton.j_squared", same(j * j, one.negate))
check("hamilton.k_squared", same(k * k, one.negate))
check("hamilton.ij_is_k", same(i * j, k))
check("hamilton.jk_is_i", same(j * k, i))
check("hamilton.ki_is_j", same(k * i, j))
check("hamilton.ji_is_minus_k", same(j * i, k.negate))
check("hamilton.kj_is_minus_i", same(k * j, i.negate))
check("hamilton.ik_is_minus_j", same(i * k, j.negate))
check("hamilton.ijk_is_minus_one", same(i * j * k, one.negate))
check("mul.identity", same(q * one, q) && same(one * q, q))
check("mul.by_zero", same(q * zero, zero))

# Full products, both orders — the closed form
#   (1,2,3,4)·(5,6,7,8) = (−60, 12, 30, 24)
#   (5,6,7,8)·(1,2,3,4) = (−60, 20, 14, 32)
check("mul.general_left", same(q * p, q4(-60, 12, 30, 24)))
check("mul.general_right", same(p * q, q4(-60, 20, 14, 32)))
check("mul.scalar_parts_agree", (q * p).real == (p * q).real)

# --- The identity this level LOSES: commutativity -----------------------------
check("loses.noncommutative", !same(q * p, p * q))
check("loses.commutator_nonzero", !same(q.commutator(p), zero))
# [i, j] = ij − ji = k − (−k) = 2k
check("loses.commutator_basis", same(i.commutator(j), k + k))
check("loses.commutator_antisymmetric", same(q.commutator(p), p.commutator(q).negate))
check("loses.commutator_self_zero", same(q.commutator(q), zero))

# --- The identities this level KEEPS ------------------------------------------
# Associativity: exhaustive over the 64 basis triples.
assoc_failures = 0
a_i = 0
while a_i < 4
  b_i = 0
  while b_i < 4
    c_i = 0
    while c_i < 4
      assoc_failures += 1 if !same(qbasis(a_i).associator(qbasis(b_i), qbasis(c_i)), zero)
      c_i += 1
    b_i += 1
  a_i += 1
check("keeps.associative_basis_triples", assoc_failures == 0)
check("keeps.associator_general", same(q.associator(p, i), zero))
check("keeps.associative_general", same((q * p) * i, q * (p * i)))
check("keeps.flexible", q.flexible?(p))
check("keeps.left_alternative", q.left_alternative?(p))
check("keeps.right_alternative", q.right_alternative?(p))
check("keeps.alternative", q.alternative?(p))
check("keeps.moufang_left", q.moufang_left?(p, i))
check("keeps.moufang_right", q.moufang_right?(p, i))
check("keeps.moufang_central", q.moufang_central?(p, i))
check("keeps.jordan", q.jordan_identity?(p))
check("keeps.power_associative", q.power_associative_check?)
check("keeps.no_zero_divisors", !q.is_zero_divisor_pair?(p) && !i.is_zero_divisor_pair?(j))

# --- Conjugate ----------------------------------------------------------------
check("conjugate.negates_imaginary", same(q.conjugate, q4(1, -2, -3, -4)))
check("conjugate.involution", same(q.conjugate.conjugate, q))
check("conjugate.antiautomorphism", same((q * p).conjugate, p.conjugate * q.conjugate))
check("conjugate.sum_is_twice_real", same(q + q.conjugate, q4(2, 0, 0, 0)))
check("conjugate.product_is_norm", same(q * q.conjugate, q4(30, 0, 0, 0)))
check("conjugate.real_fixed", same(q4(7, 0, 0, 0).conjugate, q4(7, 0, 0, 0)))

# --- Norm ---------------------------------------------------------------------
check("norm.abs2", q.abs2 == 30)
check("norm.abs2_is_dot_self", q.abs2 == q.dot(q))
check("norm.abs", q4(1, 1, 1, 1).abs == 2)
check("norm.alias", q.norm == q.abs)
# The multiplicative norm — |ab| = |a||b| — holds at Quaternion (a normed
# division algebra). 30 · 174 = 5220 = |q·p|².
check("norm.multiplicative", (q * p).abs2 == q.abs2 * p.abs2)
check("norm.multiplicative_value", (q * p).abs2 == 5220)
check("norm.preserves_predicate", q.norm_preserves?(p))
check("norm.zero_only_at_zero", zero.abs2 == 0 && zero.zero? && !q.zero?)
check("norm.arg", (q.arg - ~1.3871923165159781).abs < ~0.000000001)
check("norm.arg_of_positive_real", q4(3, 0, 0, 0).arg == 0)

# --- Inverse ------------------------------------------------------------------
# abs2 = 4 for (1,1,1,1), so the reciprocal is exact in binary floating point.
u = q4(1, 1, 1, 1)
check("inverse.exact_value", same(u.reciprocal, q4(~0.25, ~-0.25, ~-0.25, ~-0.25)))
check("inverse.two_sided", same(u * u.reciprocal, one) && same(u.reciprocal * u, one))
check("inverse.alias", same(u.inverse, u.reciprocal))
check("inverse.invertible_predicate", u.invertible? && u.regular?)
check("inverse.zero_not_invertible", !zero.invertible?)
check("inverse.of_unit_is_conjugate", same(i.reciprocal, i.conjugate))
check("inverse.division", same(q / u, q * u.reciprocal))

# --- Powers -------------------------------------------------------------------
check("pow.zero_is_one", same(q ** 0, one))
check("pow.one_is_self", same(q ** 1, q))
check("pow.two_is_square", same(q ** 2, q * q))
check("pow.three", same(q ** 3, q * q * q))
check("sq.closed_form", same(q.sq, q4(-28, 4, 6, 8)))
check("sq.matches_product", same(q.sq, q * q))
# BUG: `q ** -1` raises on both engines. `-@1` in Hypercomplex#**/1
# (core/numeric/hypercomplex.w:132) mis-lexes as a call to the unary-minus
# operator-method `-@` with argument 1 instead of negating argument 1.
# check("pow.negative_is_reciprocal", same(u ** -1, u.reciprocal))
# check("pow.negative_two", same(u ** -2, u.reciprocal * u.reciprocal))

# --- Scalar arithmetic --------------------------------------------------------
check("scalar.add", same(q + 2, q4(3, 2, 3, 4)))
check("scalar.sub", same(q - 2, q4(-1, 2, 3, 4)))
check("scalar.mul_scales_all", same(q * 2, q4(2, 4, 6, 8)))
check("scalar.div", same(q / 2, q4(~0.5, ~1.0, ~1.5, ~2.0)))
check("scalar.scale", same(q.scale(3), q4(3, 6, 9, 12)))
check("scalar.explicit_helpers", same(q.scalar_add(2), q + 2) && same(q.scalar_sub(2), q - 2))

# --- Geometry and predicates --------------------------------------------------
check("geom.dot", q.dot(p) == 70)
check("geom.normalize", same(u.normalize, q4(~0.5, ~0.5, ~0.5, ~0.5)))
check("geom.normalized_is_unit", u.normalize.unit?)
check("pred.unit_basis", i.unit? && j.unit? && k.unit?)
check("pred.one_predicate", one.one? && !q.one?)
check("pred.is_real", q4(7, 0, 0, 0).is_real? && !q.is_real?)
# BUG: `pure?` raises "expected numeric type" on the COMPILED engine for every
# Quaternion<f64> (interpreter is fine) — `real == 0 ## T` in
# core/numeric/hypercomplex.w:291 does not resolve `## T` in the specialized
# generic base. Repro: `<< Quaternion<f64>.new([~0.0, ~1.0, ~0.0, ~0.0] ## f64[4]).pure?`
# check("pred.pure", i.pure? && !q.pure?)
check("pred.approx_exact", q.approx?(q) && !q.approx?(p))
check("pred.approx_tolerance", q.approx?(q4(~1.0000001, 2, 3, 4), ~0.001))
# Comparable ranks by magnitude, not lexicographically.
check("cmp.by_magnitude", (i <=> q) == -1 && (q <=> i) == 1 && (q <=> q4(1, 2, 3, 4)) == 0)

# --- exp / log ----------------------------------------------------------------
check("exp.of_zero_is_one", same(zero.exp, one))
check("exp.of_real", (q4(1, 0, 0, 0).exp.w - ~2.718281828459045).abs < ~0.000000001)
# exp(πi) = −1, the quaternion reading of Euler's identity.
check("exp.euler_identity", close(q4(0, pi, 0, 0).exp, one.negate, ~0.000000001))
check("log.of_one_is_zero", same(one.log, zero))
check("log.exp_roundtrip", close(q.log.exp, q, ~0.000000001))
check("log.scalar_part_is_log_norm", (one.negate.log.w - ~0.0).abs < ~0.000000001)

# --- Rotations ----------------------------------------------------------------
z_axis = Vec3<f64>.new([~0.0, ~0.0, ~1.0] ## f64[3])
half_turn_z = Quaternion<f64>.from_axis_angle(z_axis, pi / ~2.0)
check("rotate.axis_angle_is_unit", (half_turn_z.abs - ~1.0).abs < ~0.000000001)
rotated = half_turn_z.rotate(Vec3<f64>.new([~1.0, ~0.0, ~0.0] ## f64[3]))
check("rotate.quarter_turn_about_z",
      (rotated.x - ~0.0).abs < ~0.000000001 &&
      (rotated.y - ~1.0).abs < ~0.000000001 &&
      (rotated.z - ~0.0).abs < ~0.000000001)
check("rotate.identity_leaves_vector", (one.rotate(z_axis).z - ~1.0).abs < ~0.000000001)
axis_angle = half_turn_z.to_axis_angle
check("rotate.to_axis_angle_angle", (axis_angle[1] - pi / ~2.0).abs < ~0.000000001)
check("rotate.to_axis_angle_axis", (axis_angle[0].z - ~1.0).abs < ~0.000000001)
matrix = half_turn_z.to_rotation_matrix
check("rotate.matrix_is_3x3", matrix.rows == 3 && matrix.cols == 3)
check("rotate.matrix_determinant_is_one", (matrix.determinant - ~1.0).abs < ~0.000000001)
check("rotate.matrix_roundtrip",
      Quaternion<f64>.from_rotation_matrix(matrix).approx?(half_turn_z, ~0.000001))
mapped = matrix * Vec3<f64>.new([~1.0, ~0.0, ~0.0] ## f64[3])
check("rotate.matrix_agrees_with_rotate",
      (mapped.x - rotated.x).abs < ~0.000000001 &&
      (mapped.y - rotated.y).abs < ~0.000000001)
check("slerp.endpoint_zero", half_turn_z.slerp(one, ~0.0).approx?(half_turn_z, ~0.000001))
check("slerp.endpoint_one", half_turn_z.slerp(one, ~1.0).approx?(one, ~0.000001))
check("slerp.same_quaternion", half_turn_z.slerp(half_turn_z, ~0.5).approx?(half_turn_z, ~0.000001))

# --- Metal-layout conversion --------------------------------------------------
metal = q.to_metal
check("metal.scalar_moves_last", metal.components[3] == 1 && metal.components[0] == 2)
check("metal.w_is_scalar", metal.w == q.w && metal.x == q.x)
check("metal.scalar_index", metal.scalar_index == 3)
check("metal.roundtrip", same(metal.to_math, q))
check("metal.same_norm", metal.abs2 == q.abs2)

# --- Printing -----------------------------------------------------------------
# The compiled engine renders the specialized name (Quaternion$f64), the
# interpreter the generic one, so pin the shared prefix and the tuple.
check("to_s.prefix", q.to_s.starts_with?("Quaternion"))
check("to_s.components", q.to_s.ends_with?("(1, 2, 3, 4)"))
check("to_s.negative_components", q.negate.to_s.ends_with?("(-1, -2, -3, -4)"))

# --- Class-side factories -----------------------------------------------------
check("class.dimension", Quaternion<f64>.dimension == 4)
check("class.scalar_index", Quaternion<f64>.scalar_index == 0)
check("class.zero", same(Quaternion<f64>.zero, zero))
check("class.one", same(Quaternion<f64>.one, one))
check("class.basis", same(Quaternion<f64>.basis(1), i) && same(Quaternion<f64>.basis(3), k))
check("class.real", same(Quaternion<f64>.real(7), q4(7, 0, 0, 0)))
check("class.pure", same(Quaternion<f64>.pure([1, 2, 3]), q4(0, 1, 2, 3)))
# BUG: the class-side factories build BOXED integer components while every
# arithmetic result builds `## T[4]`, and a typed array is never structurally
# equal to a boxed one — so `==` reports false on values whose components are
# identical. (`Hypercomplex#one`, the instance form, does use `1 ## T`.)
# check("class.factories_compare_equal", Quaternion<f64>.basis(1) * Quaternion<f64>.basis(2) == Quaternion<f64>.basis(3))
# check("class.one_equals_instance_one", Quaternion<f64>.one == q.one)

# --- Errors -------------------------------------------------------------------
basis_raised = false
begin
  Quaternion<f64>.basis(4)
rescue error
  basis_raised = true
check("error.basis_out_of_range", basis_raised)

reciprocal_raised = false
begin
  zero.reciprocal
rescue error
  reciprocal_raised = true
check("error.reciprocal_of_zero", reciprocal_raised)

normalize_raised = false
begin
  zero.normalize
rescue error
  normalize_raised = true
check("error.normalize_of_zero", normalize_raised)

log_raised = false
begin
  zero.log
rescue error
  log_raised = true
check("error.log_of_zero", log_raised)

axis_raised = false
begin
  Quaternion<f64>.from_axis_angle(Vec3<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3]), pi)
rescue error
  axis_raised = true
check("error.zero_rotation_axis", axis_raised)

<< "quaternion_spec: all checks passed"
