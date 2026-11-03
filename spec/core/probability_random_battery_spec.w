# Deterministic smoke batteries for both bundled pseudo-random generators.

use probability

-> battery_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

legacy = Probability.random_battery(Probability.rng(909), 20000, 16)
counter = Probability.random_battery(
  Probability.counter_rng(909, 2), 20000, 16)

battery_check("legacy.pass", legacy.heuristic_pass?)
battery_check("counter.pass", counter.heuristic_pass?)
battery_check("contract.not_certified",
  !legacy.certified? && !counter.certified?)
battery_check("moments",
  legacy.mean > ~0.49 && legacy.mean < ~0.51 &&
  counter.variance > ~0.08 && counter.variance < ~0.087)
battery_check("serial",
  ProbabilityLinearAlgebra.absolute(legacy.serial_correlation) < ~0.04 &&
  ProbabilityLinearAlgebra.absolute(counter.serial_correlation) < ~0.04)
battery_check("chi_square",
  legacy.chi_square < ~50.0 && counter.chi_square < ~50.0)

# Batch evaluation is the allocation-friendly scalar distribution surface.
normal = Probability.normal
logs = normal.log_probabilities([~-1.0, ~0.0, ~1.0])
battery_check("distribution.batch",
  logs.size == 3 && logs[0] == logs[2] && logs[1] > logs[0])

<< "probability_random_battery_spec: all checks passed"
