# Smith normal form: invariant factors, unimodular transforms U A V = D,
# integer kernels and cokernels, and finitely generated abelian groups.
#   bin/tungsten run spec/core/algebra_smith_normal_form_spec.w
#   bin/tungsten compile spec/core/algebra_smith_normal_form_spec.w \
#     --out /tmp/algebra-smith-normal-form-spec

use algebra

-> snf_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> snf_same?(left, right)
  SmithNormalForm.same_vector?(left, right)

-> snf_same_matrix?(left, right)
  SmithNormalForm.same_matrix?(left, right)

-> snf_zero_vector?(vector)
  i = 0
  while i < vector.size
    return false if vector[i] != 0
    i += 1
  true

-> snf_zero_matrix?(matrix)
  i = 0
  while i < matrix.size
    return false if !snf_zero_vector?(matrix[i])
    i += 1
  true

# U A V = D replayed by hand, independently of the certificate.
-> snf_product_ok?(decomposition)
  product = SmithNormalForm.multiply(
    SmithNormalForm.multiply(decomposition.left, decomposition.matrix),
    decomposition.right)
  snf_same_matrix?(product, decomposition.diagonal)

-> snf_transforms_unimodular?(decomposition)
  left_det = ExactIntegerLinearAlgebra.determinant(decomposition.left)
  right_det = ExactIntegerLinearAlgebra.determinant(decomposition.right)
  return false if SmithNormalForm.abs(left_det) != 1
  return false if SmithNormalForm.abs(right_det) != 1
  rows = decomposition.rows
  cols = decomposition.cols
  return false if !snf_same_matrix?(
    SmithNormalForm.multiply(decomposition.left, decomposition.left_inverse),
    SmithNormalForm.identity(rows))
  return false if !snf_same_matrix?(
    SmithNormalForm.multiply(decomposition.right, decomposition.right_inverse),
    SmithNormalForm.identity(cols))
  SmithNormalForm.unimodular?(decomposition.left) && SmithNormalForm.unimodular?(decomposition.right)

# Every kernel basis vector is annihilated by the matrix.
-> snf_kernel_annihilated?(matrix, decomposition)
  vectors = decomposition.kernel
  i = 0
  while i < vectors.size
    return false if !snf_zero_vector?(SmithNormalForm.apply(matrix, vectors[i]))
    return false if !decomposition.in_kernel?(vectors[i])
    i += 1
  vectors.size == decomposition.kernel_rank

# --- The textbook 3x3 example: SNF diag(2, 6, 12) ------------------------
# Determinantal divisors: D1 = gcd of entries = 2, D2 = gcd of 2x2 minors
# = 12, D3 = |det| = 144, so d = (2, 12/2, 144/12) = (2, 6, 12).
wiki = [[2, 4, 4], [-6, 6, 12], [10, -4, -16]]
snf_check("wiki.invariant_factors",
          snf_same?(SmithNormalForm.invariant_factors(wiki), [2, 6, 12]))
snf_check("wiki.mod_det_lane",
          snf_same?(SmithNormalForm.invariant_factors_mod_det(wiki), [2, 6, 12]))
snf_check("wiki.rank", SmithNormalForm.rank(wiki) == 3)
snf_check("wiki.torsion", snf_same?(SmithNormalForm.torsion(wiki), [2, 6, 12]))
snf_check("wiki.lattice_index", SmithNormalForm.lattice_index(wiki) == 144)
snf_check("wiki.determinant", ExactIntegerLinearAlgebra.determinant(wiki) == -144)
snf_check("wiki.not_unimodular", !SmithNormalForm.unimodular?(wiki))

wiki_dec = SmithNormalForm.decompose(wiki)
snf_check("wiki.decompose.factors", snf_same?(wiki_dec.invariant_factors, [2, 6, 12]))
snf_check("wiki.decompose.rank", wiki_dec.rank == 3 && wiki_dec.rows == 3 && wiki_dec.cols == 3)
snf_check("wiki.decompose.uav_equals_d", snf_product_ok?(wiki_dec))
snf_check("wiki.decompose.transforms_unimodular", snf_transforms_unimodular?(wiki_dec))
snf_check("wiki.decompose.diagonal",
          snf_same_matrix?(wiki_dec.diagonal, [[2, 0, 0], [0, 6, 0], [0, 0, 12]]))
snf_check("wiki.decompose.certified", wiki_dec.certified?)
snf_check("wiki.decompose.certificate_kind",
          wiki_dec.certificate.proof_kind == :smith_normal_form_replay &&
          wiki_dec.certificate.kernel_checked?)
snf_check("wiki.cokernel",
          wiki_dec.cokernel == FinitelyGeneratedAbelianGroup.new(0, [2, 6, 12]))
snf_check("wiki.cokernel_orders", snf_same?(wiki_dec.cokernel_orders, [2, 6, 12]))
snf_check("wiki.cokernel_generators", wiki_dec.cokernel_generators.size == 3)
snf_check("wiki.kernel_trivial", wiki_dec.kernel_rank == 0 && wiki_dec.kernel.size == 0)
snf_check("wiki.image_index", wiki_dec.image_index == 144 && !wiki_dec.image_saturated?)
snf_check("wiki.no_functionals", wiki_dec.cokernel_functionals.size == 0)
# Every column of A is in the image; the class of any image vector is zero.
snf_check("wiki.columns_in_image",
          wiki_dec.in_image?(SmithNormalForm.column(wiki, 0)) &&
          wiki_dec.in_image?(SmithNormalForm.column(wiki, 1)) &&
          wiki_dec.in_image?(SmithNormalForm.column(wiki, 2)))
snf_check("wiki.image_class_zero",
          snf_zero_vector?(wiki_dec.cokernel_class(SmithNormalForm.apply(wiki, [1, -2, 3]))))
snf_check("wiki.unit_vector_not_in_image", !wiki_dec.in_image?([1, 0, 0]))
# 144 Z^3 lies in the image because 144 is the exponent... no: 12 is.
snf_check("wiki.exponent_twelve",
          wiki_dec.in_image?([12, 0, 0]) && wiki_dec.in_image?([0, 12, 0]) &&
          wiki_dec.in_image?([0, 0, 12]))

# --- Rank-deficient: [[1,2,3],[4,5,6],[7,8,9]] -----------------------------
# D1 = 1, every 2x2 minor is a multiple of 3 (D2 = 3), det = 0:
# factors (1, 3), rank 2, kernel spanned by (1, -2, 1), cokernel Z (+) Z/3.
magic = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
snf_check("magic.factors", snf_same?(SmithNormalForm.invariant_factors(magic), [1, 3]))
snf_check("magic.rank", SmithNormalForm.rank(magic) == 2)
snf_check("magic.lattice_index_zero", SmithNormalForm.lattice_index(magic) == 0)
magic_dec = SmithNormalForm.decompose(magic)
snf_check("magic.uav", snf_product_ok?(magic_dec) && snf_transforms_unimodular?(magic_dec))
snf_check("magic.certified", magic_dec.certified?)
snf_check("magic.kernel_rank", magic_dec.kernel_rank == 1)
snf_check("magic.kernel_annihilated", snf_kernel_annihilated?(magic, magic_dec))
magic_kernel = magic_dec.kernel[0]
snf_check("magic.kernel_is_1_-2_1",
          SmithNormalForm.abs(magic_kernel[0]) == 1 &&
          magic_kernel[2] == magic_kernel[0] &&
          magic_kernel[1] == 0 - 2 * magic_kernel[0])
snf_check("magic.in_kernel", magic_dec.in_kernel?([1, -2, 1]) && !magic_dec.in_kernel?([1, 0, 0]))
magic_coordinates = magic_dec.kernel_coordinates([2, -4, 2])
snf_check("magic.kernel_coordinates",
          magic_coordinates.size == 1 && SmithNormalForm.abs(magic_coordinates[0]) == 2)
kernel_coordinates_raised = false
begin
  magic_dec.kernel_coordinates([1, 0, 0])
rescue error
  kernel_coordinates_raised = true
snf_check("magic.kernel_coordinates_rejects_non_kernel", kernel_coordinates_raised)
snf_check("magic.cokernel", magic_dec.cokernel == FinitelyGeneratedAbelianGroup.new(1, [3]))
snf_check("magic.cokernel_free_rank", magic_dec.cokernel_free_rank == 1)
snf_check("magic.cokernel_orders", snf_same?(magic_dec.cokernel_orders, [3, 0]))
# The functional detecting the free part is a left null vector of A,
# again proportional to (1, -2, 1).
magic_functionals = magic_dec.cokernel_functionals
snf_check("magic.functional_count", magic_functionals.size == 1)
snf_check("magic.functional_annihilates_image",
          snf_zero_matrix?(SmithNormalForm.multiply([magic_functionals[0]], magic)))
snf_check("magic.functional_is_1_-2_1",
          SmithNormalForm.abs(magic_functionals[0][0]) == 1 &&
          magic_functionals[0][2] == magic_functionals[0][0] &&
          magic_functionals[0][1] == 0 - 2 * magic_functionals[0][0])
# The image is spanned by c0 = (1,4,7) and c1 - c0 = (1,1,1); (0,1,2) lies
# in its saturation (1 - 2b + c = 0) but not in the image, while 3(0,1,2) =
# c0 - (1,1,1) does.
snf_check("magic.image_membership",
          magic_dec.in_image?([1, 4, 7]) && magic_dec.in_image?([0, 0, 0]) &&
          magic_dec.in_image?([1, 1, 1]) && magic_dec.in_image?([0, 3, 6]) &&
          !magic_dec.in_image?([1, 0, 0]) && !magic_dec.in_image?([0, 1, 2]))
snf_check("magic.image_not_saturated", magic_dec.image_index == 3)
# The class of (0,1,2) has order 3 in the cokernel.
magic_class = magic_dec.cokernel_class([0, 1, 2])
snf_check("magic.torsion_class_order_three",
          magic_class.size == 2 && magic_class[1] == 0 &&
          (magic_class[0] == 1 || magic_class[0] == 2))

# --- Diagonal inputs and the divisibility chain ---------------------------
snf_check("chain.diag_2_3", snf_same?(SmithNormalForm.invariant_factors([[2, 0], [0, 3]]), [1, 6]))
snf_check("chain.diag_2_3_4",
          snf_same?(SmithNormalForm.invariant_factors([[2, 0, 0], [0, 3, 0], [0, 0, 4]]), [1, 2, 12]))
snf_check("chain.diag_4_6", snf_same?(SmithNormalForm.invariant_factors([[4, 0], [0, 6]]), [2, 12]))
snf_check("chain.diag_4_2_order", snf_same?(SmithNormalForm.invariant_factors([[4, 0], [0, 2]]), [2, 4]))
snf_check("chain.symmetric_6_4", snf_same?(SmithNormalForm.invariant_factors([[6, 4], [4, 6]]), [2, 10]))
snf_check("chain.negative_entries", snf_same?(SmithNormalForm.invariant_factors([[-2, 0], [0, -3]]), [1, 6]))
snf_check("chain.1234", snf_same?(SmithNormalForm.invariant_factors([[1, 2], [3, 4]]), [1, 2]))
# [[4,6],[6,9]] has rank one, gcd of entries 1, kernel (3, -2).
rank_one = SmithNormalForm.decompose([[4, 6], [6, 9]])
snf_check("rank_one.factors", snf_same?(rank_one.invariant_factors, [1]))
snf_check("rank_one.kernel",
          rank_one.kernel_rank == 1 && rank_one.in_kernel?([3, -2]) &&
          snf_kernel_annihilated?([[4, 6], [6, 9]], rank_one))
snf_check("rank_one.cokernel", rank_one.cokernel == FinitelyGeneratedAbelianGroup.free(1))
snf_check("rank_one.certified", rank_one.certified?)

# --- Rectangular shapes ---------------------------------------------------
wide = [[1, 2, 3], [4, 5, 6]]
wide_dec = SmithNormalForm.decompose(wide)
snf_check("wide.factors", snf_same?(wide_dec.invariant_factors, [1, 3]))
snf_check("wide.shape", wide_dec.rows == 2 && wide_dec.cols == 3 && wide_dec.rank == 2)
snf_check("wide.uav", snf_product_ok?(wide_dec) && snf_transforms_unimodular?(wide_dec))
snf_check("wide.kernel", wide_dec.kernel_rank == 1 && wide_dec.in_kernel?([1, -2, 1]) &&
          snf_kernel_annihilated?(wide, wide_dec))
snf_check("wide.cokernel", wide_dec.cokernel == FinitelyGeneratedAbelianGroup.cyclic(3))
snf_check("wide.certified", wide_dec.certified?)
tall = SmithNormalForm.transpose(wide)
snf_check("tall.transpose", snf_same_matrix?(tall, [[1, 4], [2, 5], [3, 6]]))
tall_dec = SmithNormalForm.decompose(tall)
snf_check("tall.factors", snf_same?(tall_dec.invariant_factors, [1, 3]))
snf_check("tall.kernel_trivial", tall_dec.kernel_rank == 0)
snf_check("tall.cokernel", tall_dec.cokernel == FinitelyGeneratedAbelianGroup.new(1, [3]))
snf_check("tall.uav", snf_product_ok?(tall_dec) && snf_transforms_unimodular?(tall_dec) &&
          tall_dec.certified?)
row = SmithNormalForm.decompose([[2, 4, 6]])
snf_check("row.factors", snf_same?(row.invariant_factors, [2]))
snf_check("row.kernel", row.kernel_rank == 2 && snf_kernel_annihilated?([[2, 4, 6]], row))
snf_check("row.cokernel", row.cokernel == FinitelyGeneratedAbelianGroup.cyclic(2))
snf_check("row.rectangular_rank", SmithNormalForm.rank([[2, 4, 6]]) == 1)
column = SmithNormalForm.decompose([[2], [4], [6]])
snf_check("column.factors", snf_same?(column.invariant_factors, [2]))
snf_check("column.cokernel", column.cokernel == FinitelyGeneratedAbelianGroup.new(2, [2]))
snf_check("column.functionals", column.cokernel_functionals.size == 2 &&
          snf_zero_matrix?(SmithNormalForm.multiply(column.cokernel_functionals, [[2], [4], [6]])))

# --- Zero and identity ----------------------------------------------------
zero_dec = SmithNormalForm.decompose([[0, 0, 0], [0, 0, 0]])
snf_check("zero.factors", SmithNormalForm.invariant_factors([[0, 0, 0], [0, 0, 0]]).size == 0)
snf_check("zero.rank", zero_dec.rank == 0 && zero_dec.kernel_rank == 3)
snf_check("zero.cokernel", zero_dec.cokernel == FinitelyGeneratedAbelianGroup.free(2))
snf_check("zero.certified", zero_dec.certified?)
snf_check("zero.lattice_index", SmithNormalForm.lattice_index([[0, 0], [0, 0]]) == 0)
identity3 = SmithNormalForm.identity(3)
identity_dec = SmithNormalForm.decompose(identity3)
snf_check("identity.factors", snf_same?(identity_dec.invariant_factors, [1, 1, 1]))
snf_check("identity.unimodular", SmithNormalForm.unimodular?(identity3))
snf_check("identity.cokernel_trivial", identity_dec.cokernel.trivial?)
snf_check("identity.saturated", identity_dec.image_saturated?)
snf_check("identity.lattice_index", SmithNormalForm.lattice_index(identity3) == 1)
snf_check("unimodular.2_1_1_1", SmithNormalForm.unimodular?([[2, 1], [1, 1]]))
snf_check("unimodular.rectangular_false", !SmithNormalForm.unimodular?([[1, 0, 0], [0, 1, 0]]))

# --- Group presentations through from_relations ---------------------------
snf_check("relations.z2_z4",
          FinitelyGeneratedAbelianGroup.from_relations([[2, 0], [0, 4]]) ==
            FinitelyGeneratedAbelianGroup.new(0, [2, 4]))
snf_check("relations.z6",
          FinitelyGeneratedAbelianGroup.from_relations([[2, 0], [0, 3]]) ==
            FinitelyGeneratedAbelianGroup.cyclic(6))
snf_check("relations.free",
          FinitelyGeneratedAbelianGroup.from_relations([[0]]) ==
            FinitelyGeneratedAbelianGroup.free(1))
snf_check("relations.z_plus_z3",
          FinitelyGeneratedAbelianGroup.from_relations([[3, 0], [0, 0]]) ==
            FinitelyGeneratedAbelianGroup.new(1, [3]))
snf_check("relations.matches_decompose",
          FinitelyGeneratedAbelianGroup.from_relations(wiki) == wiki_dec.cokernel &&
          FinitelyGeneratedAbelianGroup.from_relations(magic) == magic_dec.cokernel)

# --- FinitelyGeneratedAbelianGroup ----------------------------------------
snf_check("group.cyclic_zero_is_z",
          FinitelyGeneratedAbelianGroup.cyclic(0) == FinitelyGeneratedAbelianGroup.free(1))
snf_check("group.cyclic_one_trivial", FinitelyGeneratedAbelianGroup.cyclic(1).trivial?)
snf_check("group.cyclic_negative",
          FinitelyGeneratedAbelianGroup.cyclic(-6) == FinitelyGeneratedAbelianGroup.cyclic(6))
snf_check("group.to_s",
          FinitelyGeneratedAbelianGroup.new(1, [3]).to_s == "Z (+) Z/3" &&
          FinitelyGeneratedAbelianGroup.new(2, []).to_s == "Z^2" &&
          FinitelyGeneratedAbelianGroup.new(0, [2, 6]).to_s == "Z/2 (+) Z/6" &&
          FinitelyGeneratedAbelianGroup.trivial.to_s == "0")
snf_check("group.order",
          FinitelyGeneratedAbelianGroup.new(0, [2, 6]).order == 12 &&
          FinitelyGeneratedAbelianGroup.free(1).order == 0 &&
          FinitelyGeneratedAbelianGroup.trivial.order == 1)
snf_check("group.torsion_order", FinitelyGeneratedAbelianGroup.new(1, [4]).torsion_order == 4)
snf_check("group.cyclic_predicate",
          FinitelyGeneratedAbelianGroup.new(0, [6]).cyclic? &&
          !FinitelyGeneratedAbelianGroup.new(0, [2, 2]).cyclic? &&
          FinitelyGeneratedAbelianGroup.free(1).cyclic? &&
          !FinitelyGeneratedAbelianGroup.new(1, [2]).cyclic? &&
          FinitelyGeneratedAbelianGroup.trivial.cyclic?)
snf_check("group.finite_and_torsion_free",
          FinitelyGeneratedAbelianGroup.new(0, [5]).finite? &&
          !FinitelyGeneratedAbelianGroup.free(1).finite? &&
          FinitelyGeneratedAbelianGroup.free(2).torsion_free? &&
          !FinitelyGeneratedAbelianGroup.new(0, [5]).torsion_free?)
snf_check("group.rank", FinitelyGeneratedAbelianGroup.new(3, [2]).rank == 3)
snf_check("group.inequality",
          !(FinitelyGeneratedAbelianGroup.free(1) == FinitelyGeneratedAbelianGroup.free(2)) &&
          !(FinitelyGeneratedAbelianGroup.new(0, [4]) == FinitelyGeneratedAbelianGroup.new(0, [2, 2])) &&
          !(FinitelyGeneratedAbelianGroup.free(1) == 1))
torsion_one_raised = false
begin
  FinitelyGeneratedAbelianGroup.new(0, [1])
rescue error
  torsion_one_raised = true
snf_check("group.rejects_torsion_order_one", torsion_one_raised)

# --- Certificate rejects tampered decompositions --------------------------
tampered_diagonal = SmithNormalForm.copy(wiki_dec.diagonal)
tampered_diagonal[0][0] = 1
tampered = SmithDecomposition.new(
  wiki, tampered_diagonal, wiki_dec.left, wiki_dec.left_inverse,
  wiki_dec.right, wiki_dec.right_inverse)
snf_check("tamper.diagonal_rejected", !tampered.certified?)
swapped = SmithDecomposition.new(
  wiki, wiki_dec.diagonal, wiki_dec.right, wiki_dec.right_inverse,
  wiki_dec.left, wiki_dec.left_inverse)
snf_check("tamper.swapped_transforms_rejected", !swapped.certified?)
wrong_inverse = SmithDecomposition.new(
  wiki, wiki_dec.diagonal, wiki_dec.left, wiki_dec.left,
  wiki_dec.right, wiki_dec.right_inverse)
snf_check("tamper.wrong_inverse_rejected", !wrong_inverse.certified?)
# diag(2, 3) with identity transforms satisfies U A V = D but breaks the
# divisibility chain 2 | 3.
chain_violation = SmithDecomposition.new(
  [[2, 0], [0, 3]], [[2, 0], [0, 3]], SmithNormalForm.identity(2),
  SmithNormalForm.identity(2), SmithNormalForm.identity(2), SmithNormalForm.identity(2))
snf_check("tamper.chain_violation_rejected", !chain_violation.certified?)
snf_check("tamper.foreign_object_rejected", !SmithDecompositionCertificate.new("nope").verified?)

# --- Helpers --------------------------------------------------------------
snf_check("helper.transpose", snf_same_matrix?(SmithNormalForm.transpose([[1, 2, 3]]), [[1], [2], [3]]))
snf_check("helper.augment",
          snf_same_matrix?(SmithNormalForm.augment([[1], [2]], [[3, 4], [5, 6]]),
                           [[1, 3, 4], [2, 5, 6]]))
snf_check("helper.subtract_identity",
          snf_same_matrix?(SmithNormalForm.subtract_identity([[3, 1], [1, 3]]), [[2, 1], [1, 2]]))
snf_check("helper.column", snf_same?(SmithNormalForm.column([[1, 2], [3, 4]], 1), [2, 4]))
snf_check("helper.apply", snf_same?(SmithNormalForm.apply([[1, 2], [3, 4]], [1, 1]), [3, 7]))
snf_check("helper.multiply",
          snf_same_matrix?(SmithNormalForm.multiply([[1, 2], [3, 4]], [[0, 1], [1, 0]]), [[2, 1], [4, 3]]))
copied = SmithNormalForm.copy(wiki)
copied[0][0] = 99
snf_check("helper.copy_is_deep", wiki[0][0] == 2)
xg = SmithNormalForm.xgcd(240, 46)
snf_check("helper.xgcd", xg[0] == 2 && 240 * xg[1] + 46 * xg[2] == 2)
xg_neg = SmithNormalForm.xgcd(-12, 18)
snf_check("helper.xgcd_negative", xg_neg[0] == 6 && -12 * xg_neg[1] + 18 * xg_neg[2] == 6)
snf_check("helper.nearest_quotient",
          SmithNormalForm.nearest_quotient(8, 3) == 3 &&
          SmithNormalForm.nearest_quotient(7, 2) == 3 &&
          SmithNormalForm.nearest_quotient(-8, 3) == -3 &&
          SmithNormalForm.nearest_quotient(-7, 2) == -3 &&
          SmithNormalForm.nearest_quotient(7, -2) == -3)
snf_check("helper.balanced_mod",
          SmithNormalForm.balanced_mod(7, 5) == 2 &&
          SmithNormalForm.balanced_mod(8, 5) == -2 &&
          SmithNormalForm.balanced_mod(5, 10) == 5 &&
          SmithNormalForm.balanced_mod(-5, 10) == -5 &&
          SmithNormalForm.balanced_mod(-7, 5) == -2 &&
          SmithNormalForm.balanced_mod(13, nil) == 13)
snf_check("helper.same_vector", snf_same?([1, 2], [1, 2]) && !snf_same?([1, 2], [1, 3]) && !snf_same?([1], [1, 1]))
snf_check("helper.kernel_shortcut",
          SmithNormalForm.kernel(magic).size == 1 &&
          SmithNormalForm.cokernel(magic) == FinitelyGeneratedAbelianGroup.new(1, [3]))

# --- Validation -----------------------------------------------------------
ragged_raised = false
begin
  SmithNormalForm.invariant_factors([[1, 2], [3]])
rescue error
  ragged_raised = true
snf_check("validate.ragged", ragged_raised)
rational_raised = false
begin
  SmithNormalForm.invariant_factors([[Rational.new(1, 2)]])
rescue error
  rational_raised = true
snf_check("validate.non_integer", rational_raised)
empty_raised = false
begin
  SmithNormalForm.invariant_factors([])
rescue error
  empty_raised = true
snf_check("validate.empty", empty_raised)

# --- A dense 6x6 with mixed signs: all invariants replayed ------------------
dense = [[3, -1, 4, 1, -5, 9],
         [2, 6, -5, 3, 5, -8],
         [-9, 7, 9, 3, 2, 3],
         [8, -4, 6, 2, 6, -4],
         [3, 3, 8, -3, 2, 7],
         [9, -5, 0, 2, 8, -8]]
dense_dec = SmithNormalForm.decompose(dense)
snf_check("dense.uav", snf_product_ok?(dense_dec) && snf_transforms_unimodular?(dense_dec))
snf_check("dense.certified", dense_dec.certified?)
snf_check("dense.rank_nullity", dense_dec.rank + dense_dec.kernel_rank == 6 &&
          dense_dec.cokernel_free_rank == 6 - dense_dec.rank)
dense_det = SmithNormalForm.abs(ExactIntegerLinearAlgebra.determinant(dense))
snf_check("dense.factor_product_is_det",
          (dense_det == 0 && dense_dec.rank < 6) ||
          (dense_det != 0 && dense_dec.image_index == dense_det))
snf_check("dense.mod_det_lane_agrees",
          snf_same?(SmithNormalForm.invariant_factors_mod_det(dense), dense_dec.invariant_factors))
snf_check("dense.kernel_annihilated", snf_kernel_annihilated?(dense, dense_dec))

<< "algebra_smith_normal_form_spec: all checks passed"
