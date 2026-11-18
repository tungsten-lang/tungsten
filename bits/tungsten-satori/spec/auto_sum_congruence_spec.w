use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ", "sum_below.congr"]))
session.run_source(File.read("bits/tungsten-satori/spec/auto_sum_congruence.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "automatic sum congruence failed"
["natural", "integer", "rational", "real", "generic", "nested_type", "function_type", "everywhere", "larger_range", "guarded", "symmetric", "shifted", "nested", "alias", "beta", "term_arithmetic", "application", "same_instantiation"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "automatic sum congruence missing, open or has unexpected trust: " + name
["missing", "outside", "unequal_ranges", "wrong_function", "weak", "wrong_shift", "missing_nested_guard", "cycle", "fixed_types", "concrete_types", "wrong_list_type", "missing_premise", "wrong_instantiation"].each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_congruence_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "automatic sum congruence accepted an invalid type, range or premise: " + name
previous = session.failures
session.run_source("opaque hidden_f : ℕ → list α\nopaque hidden_g : ℕ → list α\naxiom hidden_equal : ∀ i, hidden_f i = hidden_g i\n+ marked (n : ℕ) : sum_below n hidden_f = sum_below n hidden_g := by auto \[hidden_equal]\n")
th = session.theorems["marked"]
if session.failures != previous || th == nil || th.hyps.size != 0 || th.tags != ["axiom:hidden_equal", "oracle:arith"]
  raise "automatic generic congruence lost the supplied equality assumption tag"
<< "Automatic sum congruence passed"
