use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("logic")
session.run_file("bits/tungsten-satori/spec/finite_range.sat")
if session.failures != 0
  raise "finite-range proofs failed"
lemmas = ["inj_bound", "inj_bound_le", "pigeonhole", "pigeonhole_le", "inj_bound_of_missing", "surjective_of_injective", "unique_preimage"].map -> (name) "nat." + name
cases = ["php", "php_inclusive", "empty_injection", "encoding_size", "five_into_two", "inclusive_collision", "singleton_target", "empty_target", "missing_last", "empty_missing", "permutation_preimage", "permutation_endpoint"]
(lemmas + cases).each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "finite-range theorem is missing, open or has unexpected trust: " + name
session.run_source("axiom bad_injection : ∀ x < 2, ∀ y < 2, (fun i => 0) x = (fun i => 0) y → x = y\n+ marked_size : 2 ≤ (1 : ℕ) := nat.inj_bound 2 1 (fun i => 0) (by decide) bad_injection\n")
marked = session.theorems["marked_size"]
if marked == nil || marked.hyps.size != 0 || marked.tags != ["axiom:bad_injection", "oracle:arith"]
  raise "finite injection lost its assumption tag"
session.run_file("bits/tungsten-satori/spec/finite_range_failure.sat")
if session.failures != 10
  raise "finite-range rules accepted invalid bounds or missing premises"
<< "Finite-range pigeonhole patterns passed"
