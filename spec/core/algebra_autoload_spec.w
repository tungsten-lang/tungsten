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
autoload_check("relative irreducibility class",
               NumberFieldRelativeModularIrreducibilityCertificate.class_name,
               "Class")
autoload_check("tower irreducibility class",
               NumberFieldTowerIrreducibilityCertificate.class_name,
               "Class")
autoload_check("exact LLL class",
               ExactGramLatticeReduction.class_name, "Class")
autoload_check("ideal generator search class",
               NumberFieldIdealGeneratorSearch.class_name, "Class")
autoload_check("ideal generator bounds class",
               NumberFieldIdealGeneratorBounds.class_name, "Class")
autoload_check("Minkowski factor base class",
               NumberFieldMinkowskiFactorBase.class_name, "Class")
autoload_check("S-class proof class",
               NumberFieldSClassTwoTorsionProof.class_name, "Class")
autoload_check("L(2,S) coordinates class",
               NumberFieldL2SCoordinates.class_name, "Class")
autoload_check("product S-class proof class",
               EtaleProductSClassTwoTorsionProof.class_name, "Class")
autoload_check("ideal factorization class",
               AlgebraIdealFactorization.class_name, "Class")
autoload_check("BPS function data class",
               PlaneQuarticBPSFunctionData.class_name, "Class")

plane = Algebra.rational_projective_plane
autoload_check("projective", plane.dimension, 2)
autoload_check("projective homogeneous map class",
               ProjectiveHomogeneousMap.class_name, "Class")
autoload_check("projective height defect class",
               ProjectiveHeightDefectBound.class_name, "Class")
autoload_check("projective canonical height class",
               ProjectiveCanonicalHeightEnclosure.class_name, "Class")
autoload_check("curve class", Curve.class_name, "Class")
autoload_check("C_ab model class", CAbCurveModel.class_name, "Class")
autoload_check("C_ab Riemann-Roch class",
               CAbRiemannRochSpace.class_name, "Class")
autoload_check("C_ab function subspace class",
               CAbFunctionSubspace.class_name, "Class")
autoload_check("C_ab evaluation kernel class",
               CAbEvaluationKernel.class_name, "Class")
autoload_check("C_ab multiplier preimage class",
               CAbMultiplierPreimage.class_name, "Class")
autoload_check("C_ab point divisor class",
               CAbEffectivePointDivisor.class_name, "Class")
autoload_check("C_ab divisor space class",
               CAbDivisorSpace.class_name, "Class")
autoload_check("C_ab KM representative class",
               CAbKhuriMakdisiRepresentative.class_name, "Class")
autoload_check("C_ab KM AddFlip class",
               CAbKhuriMakdisiAddFlip.class_name, "Class")
autoload_check("C_ab KM affine zero class",
               CAbKhuriMakdisiAffineZero.class_name, "Class")
autoload_check("C_ab place divisor class",
               CAbEffectivePlaceDivisor.class_name, "Class")
autoload_check("C_ab KM difference class",
               CAbKhuriMakdisiDifference.class_name, "Class")
autoload_check("C_ab KM place difference class",
               CAbKhuriMakdisiPlaceDifference.class_name, "Class")
autoload_check("C_ab KM zero-test class",
               CAbKhuriMakdisiZeroTest.class_name, "Class")
autoload_check("C_ab KM sum class",
               CAbKhuriMakdisiSum.class_name, "Class")
autoload_check("C_ab KM equality class",
               CAbKhuriMakdisiEquality.class_name, "Class")
autoload_check("C_ab KM scalar class",
               CAbKhuriMakdisiScalarMultiple.class_name, "Class")
autoload_check("C_ab KM order class",
               CAbKhuriMakdisiOrder.class_name, "Class")
autoload_check("C_ab KM nondivisibility class",
               CAbKhuriMakdisiNondivisibility.class_name, "Class")
autoload_check("closed-place reduction class",
               ClosedPlaceReduction.class_name, "Class")
autoload_check("prime-field subspace class",
               PrimeFieldSubspace.class_name, "Class")
autoload_check("ideal class", Ideal.class_name, "Class")

<< "algebra_autoload_spec: all checks passed"
