# Public algebra names are discoverable through core/tungsten's autoload table.
# This file deliberately does not say `use algebra`: the object API should
# autoload, while mathematical source rewriting remains an explicit feature.

-> autoload_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

field = RationalField.new
autoload_check("field", field.to_s, "ℚ")

ring = PolynomialRing.new([:x], field)
x = ring.generator(0)
autoload_check("polynomial", (x**3 - x).discriminant, Rational.new(4))
order = MonogenicOrder.new(x**2 - x - 1)
autoload_check("monogenic order", order.maximal?, true)
autoload_check("product order class",
               EtaleProductOrder.class_name, "Class")
autoload_check("general order class",
               AlgebraOrder.class_name, "Class")
autoload_check("maximal certificate class",
               MaximalOrderCertificate.class_name, "Class")
autoload_check("prime ideal class",
               AlgebraPrimeIdeal.class_name, "Class")
autoload_check("prime decomposition class",
               AlgebraPrimeDecomposition.class_name, "Class")
autoload_check("integral ideal class",
               NumberFieldIdeal.class_name, "Class")
autoload_check("fractional ideal class",
               NumberFieldFractionalIdeal.class_name, "Class")
autoload_check("archimedean data class",
               NumberFieldArchimedeanData.class_name, "Class")
autoload_check("etale archimedean data class",
               EtaleProductArchimedeanData.class_name, "Class")
autoload_check("S-unit basis class",
               NumberFieldSUnitSquareClassBasis.class_name, "Class")
autoload_check("quadratic residue character class",
               NumberFieldQuadraticResidueCharacter.class_name, "Class")
autoload_check("modular irreducibility class",
               NumberFieldModularIrreducibilityCertificate.class_name,
               "Class")
autoload_check("Minkowski factor base class",
               NumberFieldMinkowskiFactorBase.class_name, "Class")
autoload_check("S-class proof class",
               NumberFieldSClassTwoTorsionProof.class_name, "Class")
autoload_check("product S-class proof class",
               EtaleProductSClassTwoTorsionProof.class_name, "Class")
autoload_check("ideal factorization class",
               AlgebraIdealFactorization.class_name, "Class")
autoload_check("BPS function data class",
               PlaneQuarticBPSFunctionData.class_name, "Class")

plane = Algebra.rational_projective_plane
autoload_check("projective", plane.dimension, 2)
autoload_check("curve class", Curve.class_name, "Class")
autoload_check("ideal class", Ideal.class_name, "Class")

<< "algebra_autoload_spec: all checks passed"
