# Smith normal form and the Eisenstein integers Z[omega].
#   bin/tungsten run spec/core/smith_eisenstein_spec.w

use algebra

-> smith_check(name, cond)
  raise "FAIL " + name if !cond
  << "PASS " + name

-> same_factors?(a, b)
  return false if a.size != b.size
  i = 0
  while i < a.size
    return false if a[i] != b[i]
    i += 1
  true

# --- Smith normal form ---
smith_check("snf.2468", same_factors?(SmithNormalForm.invariant_factors([[2, 4], [6, 8]]), [2, 4]))
smith_check("snf.1234", same_factors?(SmithNormalForm.invariant_factors([[1, 2], [3, 4]]), [1, 2]))
# diag(2,3): Z/2 (+) Z/3 = Z/6, so the chain is 1 | 6
smith_check("snf.crt", same_factors?(SmithNormalForm.invariant_factors([[2, 0], [0, 3]]), [1, 6]))
smith_check("snf.identity", same_factors?(SmithNormalForm.invariant_factors([[1, 0], [0, 1]]), [1, 1]))
smith_check("snf.zero", SmithNormalForm.invariant_factors([[0, 0], [0, 0]]).size == 0)
smith_check("snf.rank_deficient", SmithNormalForm.rank([[1, 2], [2, 4]]) == 1)
smith_check("snf.unimodular", SmithNormalForm.unimodular?([[2, 1], [1, 1]]))
smith_check("snf.not_unimodular", !SmithNormalForm.unimodular?([[2, 0], [0, 3]]))
smith_check("snf.index", SmithNormalForm.lattice_index([[2, 0], [0, 3]]) == 6)
smith_check("snf.torsion", same_factors?(SmithNormalForm.torsion([[2, 0], [0, 3]]), [6]))
smith_check("snf.rectangular", SmithNormalForm.rank([[1, 2, 3], [4, 5, 6]]) == 2)

# --- Eisenstein integers ---
one = EisensteinInteger.one
w = EisensteinInteger.omega
smith_check("eis.cube_root", w * w * w == one)
# The defining relation: 1 + w + w^2 = 0.
smith_check("eis.minimal_poly", one + w + w * w == EisensteinInteger.zero)
smith_check("eis.norm", EisensteinInteger.new(2, 1).norm == 3)
smith_check("eis.norm_ramified", EisensteinInteger.new(1, 0 - 1).norm == 3)
z = EisensteinInteger.new(4, 3)
v = EisensteinInteger.new(2, 0 - 1)
smith_check("eis.norm_multiplicative", (z * v).norm == z.norm * v.norm)
smith_check("eis.units_six", EisensteinInteger.units.size == 6)
all_unit = true
EisensteinInteger.units.each ->(u)
  all_unit = false if u.norm != 1
smith_check("eis.units_norm_one", all_unit)
# Six-fold rotation: order 6, and w has order 3 within it.
smith_check("eis.rot_order6", EisensteinInteger.new(3, 1).rotated_60(6) == EisensteinInteger.new(3, 1))
smith_check("eis.rot_half_is_negate", EisensteinInteger.new(3, 1).rotated_60(3) == EisensteinInteger.new(3, 1).negate)
pair = z.divmod(v)
smith_check("eis.divmod_identity", pair[0] * v + pair[1] == z)
smith_check("eis.divmod_smaller", pair[1].norm < v.norm)
smith_check("eis.gcd_self", z.gcd(z).norm == z.norm)
smith_check("eis.associates", z.associates.size == 6)
# 2 is inert (2 = 2 mod 3); 3 ramifies; 7 splits (7 = 1 mod 3).
smith_check("eis.inert_2", EisensteinInteger.new(2, 0).prime?)
smith_check("eis.ramified_3_not_prime", !EisensteinInteger.new(3, 0).prime?)
smith_check("eis.split_7_not_prime", !EisensteinInteger.new(7, 0).prime?)
smith_check("eis.prime_above_3", EisensteinInteger.new(1, 0 - 1).prime?)
smith_check("eis.unit_not_prime", !one.prime?)
<< "snf + eisenstein complete"
