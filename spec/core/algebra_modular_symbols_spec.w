# Exact weight-two Manin-symbol quotients for Gamma_0(N).
#
# Dimensions are differential fixtures from Sage 10.9. The finite checker
# exhausts P^1(Z/NZ), the Manin relations, and their cusp boundaries while
# exposing Manin's presentation theorem as the trust boundary.

use algebra

-> symbols_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

m1 = WeightTwoModularSymbols.new(1)
symbols_check("level1.generators", m1.projective_line.size, 1)
symbols_check("level1.relative_dimension", m1.relative_dimension, 0)
symbols_check("level1.boundary_rank", m1.boundary_rank, 0)
symbols_check("level1.cuspidal_dimension", m1.cuspidal_dimension, 0)
symbols_check("level1.certificate", m1.certificate.verified?, true)

# At the terminal FLT level the relative symbol is Eisenstein/boundary:
# the cuspidal modular-symbol space, like S_2(Gamma_0(2)), is zero.
m2 = Algebra.modular_symbols(2)
symbols_check("level2.generators", m2.projective_line.size, 3)
symbols_check("level2.relative_dimension", m2.relative_dimension, 1)
symbols_check("level2.boundary_rank", m2.boundary_rank, 1)
symbols_check("level2.cuspidal_dimension", m2.cuspidal_dimension, 0)
symbols_check("level2.cusps", m2.cusps.size, 2)

m11 = WeightTwoModularSymbols.new(11)
symbols_check("level11.generators", m11.projective_line.size, 12)
symbols_check("level11.relation_count", m11.relation_terms.size, 24)
symbols_check("level11.relative_dimension", m11.relative_dimension, 3)
symbols_check("level11.boundary_rank", m11.boundary_rank, 1)
symbols_check("level11.cuspidal_dimension", m11.cuspidal_dimension, 2)
symbols_check("level11.cuspidal_basis", m11.cuspidal_basis.size, 2)
symbols_check("level11.certificate", m11.certified?, true)
symbols_check("level11.proof_kind",
              m11.certificate.proof_kind, :trusted_theorem_import)
symbols_check("level11.kernel_boundary",
              m11.certificate.kernel_checked?, false)

# Square levels exercise the nontrivial Gamma_0 cusp labels, including the
# numerator twist by c/gcd(c,N).
m36 = WeightTwoModularSymbols.new(36)
symbols_check("level36.generators", m36.projective_line.size, 72)
symbols_check("level36.cusps", m36.cusps.size, 12)
symbols_check("level36.relative_dimension", m36.relative_dimension, 13)
symbols_check("level36.cuspidal_dimension", m36.cuspidal_dimension, 2)
symbols_check("level36.cuspidal_basis", m36.cuspidal_basis.size, 2)
symbols_check("level36.certificate", m36.certified?, true)

# Prime-level enumeration has a direct P^1(F_p) path and stays sparse at a
# frontier-sized regression level.
m389 = WeightTwoModularSymbols.new(389)
symbols_check("level389.generators", m389.projective_line.size, 390)
symbols_check("level389.relative_dimension", m389.relative_dimension, 65)
symbols_check("level389.cuspidal_dimension", m389.cuspidal_dimension, 64)
symbols_check("level389.sparse_relations",
              m389.relation_terms.size, 780)
symbols_check("level389.certificate", m389.certified?, true)

dense_basis_rejected = false
begin
  WeightTwoModularSymbols.new(100).cuspidal_basis
rescue error
  dense_basis_rejected = error.to_s.include?("dense RREF exceeds limit")
symbols_check("dense_basis.resource_bound", dense_basis_rejected, true)

enumeration_rejected = false
begin
  WeightTwoModularSymbols.new(100, 2, 100)
rescue error
  enumeration_rejected = error.to_s.include?("search exceeds limit")
symbols_check("enumeration.resource_bound", enumeration_rejected, true)

bad_weight = false
begin
  WeightTwoModularSymbols.new(11, 4)
rescue error
  bad_weight = error.to_s.include?("supports weight 2")
symbols_check("unsupported.weight", bad_weight, true)

bad_line_certificate = Gamma0ProjectiveLineCertificate.new("not a line")
symbols_check("projective_line.tamper_rejected",
              bad_line_certificate.verified?, false)
bad_space_certificate = WeightTwoModularSymbolsCertificate.new("not a space")
symbols_check("modular_symbols.tamper_rejected",
              bad_space_certificate.verified?, false)
