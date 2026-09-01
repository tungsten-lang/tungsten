use core/linalg

-> expect(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> close?(actual, expected)
  delta = (actual - expected).abs
  delta < ~0.000000001

eigenvalues = LinAlg.eigh_values([[~2.0, ~1.0], [~1.0, ~2.0]])
expect("linalg.eigh values", eigenvalues.size() == 2 && close?(eigenvalues[0], ~1.0) && close?(eigenvalues[1], ~3.0))

singular = LinAlg.singular_values([[~3.0, ~0.0], [~0.0, ~4.0], [~0.0, ~0.0]])
expect("linalg.singular_values tall", singular.size() == 2 && close?(singular[0], ~4.0) && close?(singular[1], ~3.0))

wide = LinAlg.singular_values([[~3.0, ~0.0, ~0.0], [~0.0, ~4.0, ~0.0]])
expect("linalg.singular_values wide", wide.size() == 2 && close?(wide[0], ~4.0) && close?(wide[1], ~3.0))

rank_deficient = LinAlg.singular_values([[~1.0, ~2.0], [~2.0, ~4.0]])
expect("linalg.singular_values rank deficient", rank_deficient[0] > ~4.9 && rank_deficient[1] < ~0.000000001)
expect("linalg.spectral empty", LinAlg.eigh_values([]) == [] && LinAlg.singular_values([]) == [])
