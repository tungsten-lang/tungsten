# Smith normal form: the HNF-first mod-determinant lane that `invariant_factors`
# routes square matrices with n >= 40 through, plus the explicit lane entry
# points.  Compiled lane only: `invariant_factors_hnf` calls
# ccall("w_probe_counter_add"), which the interpreter does not support.
#   bin/tungsten compile spec/core/algebra_smith_normal_form_hnf_spec.w \
#     --out /tmp/algebra-smith-normal-form-hnf-spec

use algebra

-> snf_hnf_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> snf_hnf_same?(left, right)
  SmithNormalForm.same_vector?(left, right)

# The textbook 3x3 with SNF diag(2, 6, 12) through every lane.
wiki = [[2, 4, 4], [-6, 6, 12], [10, -4, -16]]
snf_hnf_check("wiki.hnf_lane",
              snf_hnf_same?(SmithNormalForm.invariant_factors_hnf(wiki), [2, 6, 12]))
snf_hnf_check("wiki.mod_det_lane",
              snf_hnf_same?(SmithNormalForm.invariant_factors_mod_det(wiki), [2, 6, 12]))
snf_hnf_check("wiki.exact_lane",
              snf_hnf_same?(SmithNormalForm.pivot_diagonal(wiki, nil), [2, 6, 12]))

# --- The HNF-first lane engages at n >= 40 --------------------------------
# A = U D V with U lower and V upper unitriangular, so the invariant factors
# of A are those of D: 37 ones then 2, 6, 12.
big_n = 40
big_u = SmithNormalForm.identity(big_n)
big_v = SmithNormalForm.identity(big_n)
big_d = SmithNormalForm.identity(big_n)
i = 1
while i < big_n
  big_u[i][i - 1] = 1
  big_u[i][i - 2] = -2 if i >= 2
  big_v[i - 1][i] = -1
  big_v[i - 2][i] = 3 if i >= 2
  i += 1
big_d[37][37] = 2
big_d[38][38] = 6
big_d[39][39] = 12
big_a = SmithNormalForm.multiply(SmithNormalForm.multiply(big_u, big_d), big_v)
expected_big = []
i = 0
while i < 37
  expected_big.push(1)
  i += 1
expected_big.push(2)
expected_big.push(6)
expected_big.push(12)
snf_hnf_check("big.hnf_lane_factors", snf_hnf_same?(SmithNormalForm.invariant_factors(big_a), expected_big))
snf_hnf_check("big.rank", SmithNormalForm.rank(big_a) == 40)
snf_hnf_check("big.lattice_index", SmithNormalForm.lattice_index(big_a) == 144)
snf_hnf_check("big.torsion", snf_hnf_same?(SmithNormalForm.torsion(big_a), [2, 6, 12]))
snf_hnf_check("big.determinant", SmithNormalForm.abs(ExactIntegerLinearAlgebra.determinant(big_a)) == 144)
snf_hnf_check("big.explicit_hnf_lane", snf_hnf_same?(SmithNormalForm.invariant_factors_hnf(big_a), expected_big))
snf_hnf_check("big.explicit_mod_det_lane",
          snf_hnf_same?(SmithNormalForm.invariant_factors_mod_det(big_a), expected_big))
# A singular 40x40 falls back to the exact elimination inside the lane.
big_d[39][39] = 0
big_singular = SmithNormalForm.multiply(SmithNormalForm.multiply(big_u, big_d), big_v)
singular_factors = SmithNormalForm.invariant_factors(big_singular)
snf_hnf_check("big.singular_rank", singular_factors.size == 39)
snf_hnf_check("big.singular_factors",
          snf_hnf_same?(singular_factors, expected_big.slice(0, 39)))
snf_hnf_check("big.singular_index_zero", SmithNormalForm.lattice_index(big_singular) == 0)

# A dense 6x6 with mixed signs: all three lanes agree with the certified
# transform-tracking decomposition.
dense = [[3, -1, 4, 1, -5, 9],
         [2, 6, -5, 3, 5, -8],
         [-9, 7, 9, 3, 2, 3],
         [8, -4, 6, 2, 6, -4],
         [3, 3, 8, -3, 2, 7],
         [9, -5, 0, 2, 8, -8]]
dense_dec = SmithNormalForm.decompose(dense)
snf_hnf_check("dense.certified", dense_dec.certified?)
snf_hnf_check("dense.lanes_agree",
              snf_hnf_same?(SmithNormalForm.invariant_factors_mod_det(dense), dense_dec.invariant_factors) &&
              snf_hnf_same?(SmithNormalForm.invariant_factors_hnf(dense), dense_dec.invariant_factors))

<< "algebra_smith_normal_form_hnf_spec: all checks passed"
