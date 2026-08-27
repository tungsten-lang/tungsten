# Public coding-theory names must be discoverable through core/tungsten
# without an explicit `use coding_theory`.

-> autoload_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

field = FiniteField.new(5)
domain = CodingTheory.canonical_domain(field, 3)
code = ReedSolomonCode.new(domain, 2)
word = code.encode([1, 1])

autoload_check("facade", CodingTheory.class_name == "Class")
autoload_check("domain", domain.class_name == "FiniteFieldEvaluationDomain")
autoload_check("Reed-Solomon", word.at(0) == 1 && word.at(2) == 3)
autoload_check("interleaved class",
               InterleavedReedSolomonCode.class_name == "Class")
autoload_check("metrics class", CodingTheoryMetrics.class_name == "Class")
autoload_check("bounds class", JohnsonBound.class_name == "Class")
autoload_check("alignment class",
               AffineLineAlignmentThresholds.class_name == "Class")
autoload_check("interchange class",
               CodingTheoryInterchange.class_name == "Class")

<< "coding_theory_autoload_spec: all checks passed"
