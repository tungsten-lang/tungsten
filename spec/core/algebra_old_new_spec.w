# Exact degeneracy maps and the weight-two old/new Hecke quotient.
#
# Matrix and characteristic-polynomial fixtures are differential records from
# Sage 10.9.  The "new" object is the canonical quotient by the old subspace,
# avoiding an arbitrary embedded complement.

use algebra

-> old_new_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

x = Poly<ℚ>.new(:x).generator

source11 = WeightTwoModularSymbols.new(11)
target22 = WeightTwoModularSymbols.new(22)
degeneracy = WeightTwoDegeneracyMap.new(source11, target22, 2)
expected_d1 = [
  [1, 0, 0, 0, 0, -1, -1],
  [0, 1, 0, -3, 1, 1, -1],
  [0, 1, 1, -1, -1, 0, 0]
]
old_new_check(
  "degeneracy.11_to_22.d1",
  ModularSymbolsLinearAlgebra.same_matrix?(
    degeneracy.relative_matrix_one, expected_d1),
  true)
old_new_check("degeneracy.coset_count", degeneracy.cosets.size, 3)
old_new_check("degeneracy.certificate", degeneracy.certified?, true)

new11 = source11.old_new_decomposition
old_new_check("level11.old_dimension", new11.old_dimension, 0)
old_new_check("level11.new_dimension", new11.new_dimension, 2)
old_new_check("level11.new_T2",
              new11.new_characteristic_polynomial(2),
              x**2 + x*4 + 4)

new22 = target22.old_new_decomposition
old_new_check("level22.old_dimension", new22.old_dimension, 4)
old_new_check("level22.new_dimension", new22.new_dimension, 0)
old_new_check("level22.old_T3",
              new22.old_characteristic_polynomial(3),
              x**4 + x**3*4 + x**2*6 + x*4 + 1)
old_new_check("level22.new_T3",
              new22.new_characteristic_polynomial(3), 1)

# Level 33 has both old and new parts, so this checks the actual Hecke-module
# quotient rather than either zero-dimensional edge case.
new33 = WeightTwoModularSymbols.new(
  33, 2, 100_000_000).old_new_decomposition
old_new_check("level33.old_dimension", new33.old_dimension, 4)
old_new_check("level33.new_dimension", new33.new_dimension, 2)
old_new_check("level33.old_T2",
              new33.old_characteristic_polynomial(2),
              x**4 + x**3*8 + x**2*24 + x*32 + 16)
old_new_check("level33.new_T2",
              new33.new_characteristic_polynomial(2),
              x**2 - x*2 + 1)
old_new_check("level33.certificate", new33.certified?, true)

bad_levels = false
begin
  WeightTwoDegeneracyMap.new(source11, target22, 3)
rescue error
  bad_levels = error.to_s.include?("differ by the selected prime")
old_new_check("degeneracy.bad_levels_rejected", bad_levels, true)

bad_certificate = WeightTwoOldNewCertificate.new("not a decomposition")
old_new_check("old_new.tamper_rejected",
              bad_certificate.verified?, false)
