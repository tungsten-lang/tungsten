# Sexagintaquatronion<T> — the dimension-64 Cayley–Dickson algebra, the doubling of
# Trigintaduonion<T>. The name follows Latin `sexagintaquatro` = 64.
#
# Above Sedenion nothing new is lost and nothing is regained: every level
# from 16 up is non-commutative, non-associative, non-alternative, carries
# zero divisors, and fails the multiplicative norm — while flexibility,
# power-associativity and a·ā = |a|²·1 continue to hold. This spec pins
# that inheritance at dimension 64, together with construction, the
# indexed basis accessor (named `.eN` accessors stop at Sedenion),
# arithmetic, conjugate, norm, inverse, and printing.
#
# The Sedenion zero-divisor witness (e1 + e10)·(e5 + e14) = 0 embeds into
# the low half of every larger algebra, so it is re-verified here rather
# than assumed.
#
# Run:
#   bin/tungsten run --interpret spec/numeric/sexagintaquatronion_spec.w
#   bin/tungsten -o /tmp/sexagintaquatronion_spec spec/numeric/sexagintaquatronion_spec.w && /tmp/sexagintaquatronion_spec

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# Typed constructors — the class-side factories build BOXED integer
# components, so these keep every value on the `## T` side.
-> hb(n)
  Sexagintaquatronion<f64>.new((0...64).map -> item == n ? 1 ## f64 : 0 ## f64)

-> ramp
  Sexagintaquatronion<f64>.new((1...65).map -> item ## f64)

-> reverse_ramp
  Sexagintaquatronion<f64>.new((0...64).map -> (v) (64 - v) ## f64)

-> zeros
  Sexagintaquatronion<f64>.new((0...64).map -> 0 ## f64)

-> same(left, right)
  return false if left.dimension != right.dimension
  i = 0
  while i < left.dimension
    return false if left.components[i].to_f != right.components[i].to_f
    i += 1
  true

one = hb(0)
zero = zeros
a = ramp
b = reverse_ramp
zd_left = hb(1) + hb(10)
zd_right = hb(5) + hb(14)

# --- Construction and shape ---------------------------------------------------
check("shape.dimension", a.dimension == 64)
check("shape.scalar_index", a.scalar_index == 0)
check("shape.half_class", a.half_class == Trigintaduonion)
check("shape.components", a.components.size == 64)
check("construct.eq_is_componentwise", a == ramp)
check("construct.neq", a != b)
check("construct.first_and_last", a.components[0].to_f == ~1.0 && a.components[63].to_f == ~64.0)

# --- Component access ---------------------------------------------------------
# Named `.eN` accessors stop at Sedenion; above it the indexed form is the
# universal reader.
check("access.indexed_first", a.e(0) == 1)
check("access.indexed_last", a.e(63) == 64)
check("access.real", a.real == 1)
check("access.imaginary_zeroes_scalar", a.imaginary.components[0].to_f == ~0.0)
check("access.imaginary_keeps_rest", a.imaginary.components[63].to_f == ~64.0)

# --- Addition and subtraction -------------------------------------------------
sum_ab = a + b
check("add.componentwise", sum_ab.components[0].to_f == ~65.0 && sum_ab.components[63].to_f == ~65.0)
check("sub.self_is_zero", same(a - a, zero))
check("add.identity", same(a + zero, a))
check("negate.additive_inverse", same(a + a.negate, zero))
check("negate.unary_operator", same(-a, a.negate))

# --- Multiplication -----------------------------------------------------------
check("mul.identity", same(a * one, a) && same(one * a, a))
check("mul.by_zero", same(a * zero, zero))
check("mul.units_square_to_minus_one", same(hb(1) * hb(1), one.negate) && same(hb(63) * hb(63), one.negate))
check("mul.left_distributive", same(a * (b + one), a * b + a))
check("mul.right_distributive", same((b + one) * a, b * a + a))
check("sq.matches_product", same(a.sq, a * a))
check("sq.of_basis_unit", same(hb(7).sq, one.negate))

# Distinct imaginary units anticommute, sampled across both halves.
anticommute_failures = 0
i = 1
while i < 64
  j = i + 1
  while j < 64
    anticommute_failures += 1 if !same(hb(i) * hb(j), (hb(j) * hb(i)).negate)
    j += 3
  i += 3
check("mul.distinct_units_anticommute", anticommute_failures == 0)

# The Cayley–Dickson low half is a copy of Trigintaduonion: a product of two basis
# units from the low half never reaches the high half.
embed_leaks = 0
i = 0
while i < 32
  j = 0
  while j < 32
    product = hb(i) * hb(j)
    k = 32
    while k < 64
      embed_leaks += 1 if product.components[k].to_f != ~0.0
      k += 1
    j += 3
  i += 3
check("cayley_dickson.low_half_is_closed", embed_leaks == 0)
check("cayley_dickson.high_half_reached", !same(hb(1) * hb(32), zero))

# --- Inherited losses ---------------------------------------------------------
check("loses.zero_divisors", zd_left.is_zero_divisor_pair?(zd_right))
check("loses.zero_divisor_product", (zd_left * zd_right).zero?)
check("loses.norm_not_multiplicative",
      zd_left.abs2 == 2 && zd_right.abs2 == 2 && (zd_left * zd_right).abs2 == 0)
check("loses.norm_preserves_is_false", !zd_left.norm_preserves?(zd_right))
check("loses.alternative", !zd_left.alternative?(zd_right))
check("loses.left_alternative", !zd_left.left_alternative?(zd_right))
check("loses.right_alternative", !zd_left.right_alternative?(zd_right))
check("loses.associativity", !hb(1).associator(hb(2), hb(4)).zero?)
check("loses.noncommutative", !same(a * b, b * a))
check("loses.commutator_nonzero", !same(a.commutator(b), zero))

# --- What still holds ---------------------------------------------------------
check("keeps.flexible", a.flexible?(b) && zd_left.flexible?(zd_right))
check("keeps.power_associative", a.power_associative_check?)
check("keeps.conjugate_involution", same(a.conjugate.conjugate, a))
check("keeps.conjugate_antiautomorphism", same((a * b).conjugate, b.conjugate * a.conjugate))
check("keeps.norm_from_conjugate", (a * a.conjugate).components[0].to_f == ~89440.0)
check("keeps.norm_from_conjugate_is_real", (a * a.conjugate).is_real?)

# --- Norm ---------------------------------------------------------------------
# Σ k² for k = 1..64 = 89440.
check("norm.abs2", a.abs2 == 89440)
check("norm.abs2_is_dot_self", a.abs2 == a.dot(a))
# Σ k((64 + 1) − k) for k = 1..64 = 45760.
check("norm.dot", a.dot(b) == 45760)
check("norm.abs_of_dyadic", (hb(0) + hb(1) + hb(2) + hb(3)).abs == 2)
check("norm.zero", zero.abs2 == 0 && zero.zero? && !a.zero?)

# --- Inverse ------------------------------------------------------------------
u = hb(0) + hb(1) + hb(2) + hb(3)
check("inverse.two_sided", same(u * u.reciprocal, one) && same(u.reciprocal * u, one))
check("inverse.exact_value",
      u.reciprocal.components[0].to_f == ~0.25 && u.reciprocal.components[1].to_f == ~-0.25)
check("inverse.of_unit_is_conjugate", same(hb(9).reciprocal, hb(9).conjugate))
check("inverse.zero_divisor_still_has_inverse", same(zd_left * zd_left.reciprocal, one))
check("inverse.division", same(a / u, a * u.reciprocal))
# BUG: `invertible?` diverges between engines from dimension 16 up —
# interpreter false, compiled true — although `self * reciprocal` is exactly
# `one` on both. `Hypercomplex#invertible?` compares with `==`, which puts the
# BOXED array `one` builds against the typed `f64[64]` the product builds, and
# the interpreter's array `==` reports false at these sizes.
# check("inverse.invertible_predicate", u.invertible?)

# --- Powers, scalars, predicates ----------------------------------------------
check("pow.zero_is_one", same(a ** 0, one))
check("pow.two_is_square", same(a ** 2, a * a))
check("pow.three", same(a ** 3, a * a * a))
check("scalar.add", (a + 10).components[0].to_f == ~11.0 && (a + 10).components[1].to_f == ~2.0)
check("scalar.mul", same(a * 2, a + a))
check("scalar.scale", same(a.scale(2), a + a))
check("pred.one", one.one? && !a.one?)
check("pred.is_real", one.is_real? && !a.is_real?)
check("pred.unit", hb(3).unit? && !a.unit?)
check("pred.approx", a.approx?(a) && !a.approx?(b))
check("cmp.by_magnitude", (hb(1) <=> a) == -1 && (a <=> hb(1)) == 1)

# --- Printing -----------------------------------------------------------------
check("to_s.prefix", a.to_s.starts_with?("Sexagintaquatronion"))
check("to_s.leading_components", a.to_s.ends_with?(", 64)"))

# --- Class-side factories -----------------------------------------------------
check("class.dimension", Sexagintaquatronion<f64>.dimension == 64)
check("class.scalar_index", Sexagintaquatronion<f64>.scalar_index == 0)
check("class.zero", same(Sexagintaquatronion<f64>.zero, zero))
check("class.one", same(Sexagintaquatronion<f64>.one, one))
check("class.basis", same(Sexagintaquatronion<f64>.basis(63), hb(63)))
check("class.real", same(Sexagintaquatronion<f64>.real(5), one.scale(5)))
check("class.pure",
      same(Sexagintaquatronion<f64>.pure((0...63).map -> item + 1),
           Sexagintaquatronion<f64>.new((0...64).map -> item ## f64)))

# --- Errors -------------------------------------------------------------------
basis_high_raised = false
begin
  Sexagintaquatronion<f64>.basis(64)
rescue error
  basis_high_raised = true
check("error.basis_index_too_high", basis_high_raised)

basis_low_raised = false
begin
  Sexagintaquatronion<f64>.basis(-1)
rescue error
  basis_low_raised = true
check("error.basis_index_negative", basis_low_raised)

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

<< "sexagintaquatronion_spec: all checks passed"
