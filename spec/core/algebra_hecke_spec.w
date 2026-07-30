# Exact prime Hecke operators on weight-two Gamma_0(N) modular symbols.
#
# Characteristic-polynomial fixtures are differential records from Sage 10.9.
# They include good primes and primes dividing the level; the latter exercise
# omission of nonprimitive Heilbronn images.

use algebra

-> hecke_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

x = Poly<ℚ>.new(:x).generator

h2 = HeilbronnCremonaMatrices.new(2)
h3 = HeilbronnCremonaMatrices.new(3)
h5 = HeilbronnCremonaMatrices.new(5)
hecke_check("heilbronn.p2.size", h2.size, 4)
hecke_check("heilbronn.p3.size", h3.size, 6)
hecke_check("heilbronn.p5.size", h5.size, 12)
hecke_check("heilbronn.p3.last", h3.matrices[5][3], -3)
hecke_check("heilbronn.certificate", h5.certified?, true)

m11 = WeightTwoModularSymbols.new(11)
t11_2 = m11.hecke_operator(2)
hecke_check("level11.T2.relative_charpoly",
            t11_2.relative_characteristic_polynomial,
            x**3 + x**2 - x*8 - 12)
hecke_check("level11.T2.cuspidal_charpoly",
            t11_2.characteristic_polynomial,
            x**2 + x*4 + 4)
hecke_check("level11.T2.matrix",
            ModularSymbolsLinearAlgebra.same_matrix?(
              t11_2.cuspidal_matrix,
              [[Rational.new(-2), Rational.new(0)],
               [Rational.new(0), Rational.new(-2)]]),
            true)
hecke_check("level11.T2.certificate", t11_2.certified?, true)
hecke_check("level11.T3.cuspidal_charpoly",
            m11.hecke_operator(3).characteristic_polynomial,
            x**2 + x*2 + 1)

# At p=2 | 14 some Heilbronn images are nonprimitive in P^1(Z/14Z).
# Dropping exactly those images gives the U_2 operator below.
m14 = WeightTwoModularSymbols.new(14)
t14_2 = m14.hecke_operator(2)
hecke_check("level14.U2.relative_charpoly",
            t14_2.relative_characteristic_polynomial,
            x**5 - x**4*2 - x**3*2 + x**2*4 + x - 2)
hecke_check("level14.U2.cuspidal_charpoly",
            t14_2.characteristic_polynomial,
            x**2 + x*2 + 1)
hecke_check("level14.T3.cuspidal_charpoly",
            m14.hecke_operator(3).characteristic_polynomial,
            x**2 + x*4 + 4)

# A non-scalar, two-newform cuspidal action catches row/column and
# cuspidal-restriction mistakes that repeated elliptic eigenvalues cannot.
m37 = WeightTwoModularSymbols.new(37)
hecke_check("level37.T3.cuspidal_charpoly",
            m37.hecke_operator(3).characteristic_polynomial,
            x**4 + x**3*4 - x**2*2 - x*12 + 9)

not_prime = false
begin
  m11.hecke_operator(4)
rescue error
  not_prime = error.to_s.include?("needs a prime")
hecke_check("operator.nonprime_rejected", not_prime, true)

bounded = false
begin
  WeightTwoModularSymbols.new(100).hecke_operator(2)
rescue error
  bounded = true
hecke_check("operator.resource_bound", bounded, true)

bad_certificate = WeightTwoHeckeOperatorCertificate.new("not an operator")
hecke_check("operator.tamper_rejected", bad_certificate.verified?, false)
