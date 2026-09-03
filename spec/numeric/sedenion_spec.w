# Sedenion<T> — the dimension-16 Cayley–Dickson algebra (basis 1, e1…e15),
# the doubling of Octonion and the first level with ZERO DIVISORS.
#
# What this level loses, and what this spec pins:
#   * zero divisors — nonzero a, b with a·b = 0. Verified witness in this
#     implementation's table: (e1 + e10)·(e5 + e14) = 0.
#   * alternativity — a(ab) ≠ (aa)b for the same witness pair.
#   * the multiplicative norm — |ab| ≠ |a|·|b| (it is 0 vs 4 for the witness).
#   * the Moufang identities — witness (e1 + e9) with (e1 + e2), (e3 + e4).
# What survives from the floor of the tower: flexibility, (a²)a = a(a²)
# power-associativity, and a·ā = |a|²·1 — so `reciprocal` is still a genuine
# two-sided inverse even for a zero divisor (a zero divisor is not a
# non-invertible element; it is an element whose product with some other
# nonzero element vanishes because the algebra is not associative).
#
# Run:
#   bin/tungsten run --interpret spec/numeric/sedenion_spec.w
#   bin/tungsten -o /tmp/sedenion_spec spec/numeric/sedenion_spec.w && \
#     /tmp/sedenion_spec

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> s16(values)
  Sedenion<f64>.new((0...16).map -> values[item] ## f64)

-> sb(n)
  Sedenion<f64>.new((0...16).map -> item == n ? 1 ## f64 : 0 ## f64)

-> same(left, right)
  return false if left.dimension != right.dimension
  i = 0
  while i < left.dimension
    return false if left.components[i].to_f != right.components[i].to_f
    i += 1
  true

-> zeros
  s16([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

one = sb(0)
zero = zeros
a = s16([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
b = s16([16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1])

# The verified zero-divisor pair.
zd_left = sb(1) + sb(10)
zd_right = sb(5) + sb(14)

# --- Construction and shape ---------------------------------------------------
check("shape.dimension", a.dimension == 16)
check("shape.scalar_index", a.scalar_index == 0)
check("shape.half_class", a.half_class == Octonion)
check("shape.components", a.components.size == 16)
check("construct.eq_is_componentwise", a == s16([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]))
check("construct.neq", a != b)

# --- Component access ---------------------------------------------------------
check("access.named_low", a.e0 == 1 && a.e1 == 2 && a.e7 == 8)
check("access.named_high", a.e8 == 9 && a.e12 == 13 && a.e15 == 16)
check("access.indexed", a.e(0) == 1 && a.e(15) == 16)
check("access.real", a.real == 1)
check("access.imaginary", a.imaginary.components[0].to_f == ~0.0 && a.imaginary.components[15].to_f == ~16.0)

# --- Addition and subtraction -------------------------------------------------
check("add.componentwise", same(a + b, s16([17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17])))
check("sub.self_is_zero", same(a - a, zero))
check("negate.additive_inverse", same(a + a.negate, zero))
check("negate.unary_operator", same(-a, a.negate))

# --- Multiplication -----------------------------------------------------------
check("mul.identity", same(a * one, a) && same(one * a, a))
check("mul.by_zero", same(a * zero, zero))
check("mul.units_square_to_minus_one", same(sb(9) * sb(9), one.negate))
check("mul.low_half_matches_octonion", same(sb(1) * sb(2), sb(3)))
check("mul.crosses_halves", same(sb(1) * sb(8), sb(9)))
check("mul.crosses_halves_signed", same(sb(1) * sb(10), sb(11).negate))
check("mul.fast_is_the_operator", same(a * b, a.mul_fast(b)))
check("mul.recursive_agrees", same(a * b, a.mul_recursive(b)))
check("mul.left_distributive", same(a * (b + one), a * b + a))
check("mul.right_distributive", same((b + one) * a, b * a + a))
check("sq.matches_product", same(a.sq, a * a))
check("sq.of_basis_unit", same(sb(13).sq, one.negate))

anticommute_failures = 0
i = 1
while i < 16
  j = 1
  while j < 16
    anticommute_failures += 1 if i != j && !same(sb(i) * sb(j), (sb(j) * sb(i)).negate)
    j += 1
  i += 1
check("mul.distinct_units_anticommute", anticommute_failures == 0)

# --- ZERO DIVISORS: the defining loss of this level ---------------------------
check("zero_divisors.witness_product_is_zero", (zd_left * zd_right).zero?)
check("zero_divisors.operands_are_nonzero", !zd_left.zero? && !zd_right.zero?)
check("zero_divisors.predicate", zd_left.is_zero_divisor_pair?(zd_right))
check("zero_divisors.second_witness", (sb(1) + sb(10)).is_zero_divisor_pair?(sb(7) + sb(12)))
check("zero_divisors.third_witness", (sb(1) + sb(11)).is_zero_divisor_pair?(sb(4) + sb(14)))
check("zero_divisors.witness_is_symmetric", (zd_right * zd_left).zero?)
check("zero_divisors.absent_in_octonion_subalgebra",
      !(sb(1) + sb(2)).is_zero_divisor_pair?(sb(3) + sb(4)))
# The norm no longer composes: |a|² = |b|² = 2 but |ab|² = 0.
check("zero_divisors.norm_not_multiplicative", zd_left.abs2 == 2 && zd_right.abs2 == 2 && (zd_left * zd_right).abs2 == 0)
check("zero_divisors.norm_preserves_is_false", !zd_left.norm_preserves?(zd_right))

# --- Alternativity and Moufang are lost ---------------------------------------
check("loses.left_alternative", !zd_left.left_alternative?(zd_right))
check("loses.right_alternative", !zd_left.right_alternative?(zd_right))
check("loses.alternative", !zd_left.alternative?(zd_right))
check("loses.moufang_left", !(sb(1) + sb(9)).moufang_left?(sb(1) + sb(2), sb(3) + sb(4)))
check("loses.associativity", !sb(1).associator(sb(2), sb(4)).zero?)
check("loses.noncommutative", !same(a * b, b * a))

# --- The floor identities still hold ------------------------------------------
flexible_failures = 0
power_failures = 0
i = 1
while i < 16
  j = 1
  while j < 16
    flexible_failures += 1 if !sb(i).flexible?(sb(j))
    j += 1
  power_failures += 1 if !(sb(i) + sb(0)).power_associative_check?
  i += 1
check("keeps.flexible_basis_pairs", flexible_failures == 0)
check("keeps.power_associative_basis", power_failures == 0)
check("keeps.flexible_general", a.flexible?(b))
check("keeps.power_associative_general", a.power_associative_check?)
check("keeps.flexible_on_zero_divisors", zd_left.flexible?(zd_right))

# --- Conjugate and norm -------------------------------------------------------
check("conjugate.involution", same(a.conjugate.conjugate, a))
check("conjugate.negates_imaginary", a.conjugate.components[0].to_f == ~1.0 && a.conjugate.components[15].to_f == ~-16.0)
check("conjugate.antiautomorphism", same((a * b).conjugate, b.conjugate * a.conjugate))
check("conjugate.product_is_norm", same(a * a.conjugate, s16([1496, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])))
# Σ k² for k = 1..16 = 1496.
check("norm.abs2", a.abs2 == 1496)
check("norm.abs2_is_dot_self", a.abs2 == a.dot(a))
check("norm.dot", a.dot(b) == 816)
check("norm.abs", (sb(0) + sb(1) + sb(2) + sb(3)).abs == 2)

# --- Inverse: a·ā = |a|², even for a zero divisor -----------------------------
u = sb(0) + sb(1) + sb(2) + sb(3)
check("inverse.two_sided", same(u * u.reciprocal, one) && same(u.reciprocal * u, one))
check("inverse.exact_value", same(u.reciprocal, s16([~0.25, ~-0.25, ~-0.25, ~-0.25, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])))
check("inverse.of_unit_is_conjugate", same(sb(11).reciprocal, sb(11).conjugate))
# A zero divisor still has a genuine two-sided inverse: the algebra is not
# associative, so a·b = 0 does not require a or b to be singular.
check("inverse.zero_divisor_still_has_inverse",
      same(zd_left * zd_left.reciprocal, one) && same(zd_left.reciprocal * zd_left, one))
check("inverse.division", same(a / u, a * u.reciprocal))
# BUG: `invertible?` DIVERGES BETWEEN ENGINES at dimension 16 — interpreter
# false, compiled true — although `self * reciprocal` is exactly `one` on both.
# `Hypercomplex#invertible?` compares with `==`, which compares the boxed
# 16-element array `one` builds against the typed `f64[16]` the product builds;
# the interpreter's array `==` reports false at this size. Repro:
#   -> sb(n)
#     Sedenion<f64>.new((0...16).map -> item == n ? 1 ## f64 : 0 ## f64)
#   u = sb(0) + sb(1) + sb(2) + sb(3)
#   << u.invertible?              # interpreter: false, compiled: true
# check("inverse.invertible_predicate", u.invertible? && zd_left.invertible?)
# check("inverse.zero_not_invertible", !zero.invertible?)

# --- Powers, scalars, predicates ----------------------------------------------
check("pow.zero_is_one", same(a ** 0, one))
check("pow.two_is_square", same(a ** 2, a * a))
check("pow.three", same(a ** 3, a * a * a))
check("scalar.add", (a + 10).components[0].to_f == ~11.0 && (a + 10).components[1].to_f == ~2.0)
check("scalar.mul", same(a * 2, a + a))
check("scalar.scale", same(a.scale(2), a + a))
check("pred.zero", zero.zero? && !a.zero?)
check("pred.is_real", s16([9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]).is_real? && !a.is_real?)
check("pred.approx", a.approx?(a) && !a.approx?(b))
check("cmp.by_magnitude", (sb(1) <=> a) == -1 && (a <=> sb(1)) == 1)

# --- Printing -----------------------------------------------------------------
check("to_s.prefix", a.to_s.starts_with?("Sedenion"))
check("to_s.components", a.to_s.ends_with?("(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)"))

# --- Class-side factories -----------------------------------------------------
check("class.dimension", Sedenion<f64>.dimension == 16)
check("class.zero", same(Sedenion<f64>.zero, zero))
check("class.one", same(Sedenion<f64>.one, one))
check("class.basis", same(Sedenion<f64>.basis(14), sb(14)))
check("class.real", same(Sedenion<f64>.real(5), s16([5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])))
check("class.pure", same(Sedenion<f64>.pure([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]),
                         s16([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])))

# --- Errors -------------------------------------------------------------------
basis_raised = false
begin
  Sedenion<f64>.basis(16)
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

<< "sedenion_spec: all checks passed"
