use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("logic")
session.run_file("bits/tungsten-satori/spec/amortized.sat")
if session.failures != 0
  raise "amortized cost proofs failed"
kernel_only = ["run.final_nil", "run.final_cons", "run.total_nil", "run.total_cons", "allowed_equivalent", "final_equivalent", "total_equivalent", "final_order", "costs_before_step", "pair_state", "finite_step", "finite_nonneg", "integer_refund"]
arith = ["finite_telescope", "finite_ratio", "finite_ratio_empty", "finite_ratio_positive_start", "real_step", "real_growth", "real_potential", "integer_signed"]
ring = ["rational_scaled", "real_scaled", "integer_scaled"]
["rat", "real", "int"].each -> (suffix)
  ring.push("run.total_scale." + suffix)
  ["potential", "ratio", "ratio_bound", "ratio_zero"].each -> (name)
    arith.push("run." + name + "." + suffix)
(kernel_only + arith + ring).each -> (name)
  expected = []
  if arith.include?(name)
    expected = ["oracle:arith"]
  elsif ring.include?(name)
    expected = ["oracle:ring"]
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "amortized theorem is missing, open or has unexpected trust: " + name
session.run_source("axiom false_cost_step : ∀ s : ℕ, True → ∀ x : ℕ, True → True ∧ (1 : ℚ) + 0 - 0 ≤ 0 * 0\n+ marked_cost : (1 : ℚ) ≤ 0 := run.ratio_zero.rat (fun (s x : ℕ) => s) (fun s x => (1 : ℚ)) (fun s x => (0 : ℚ)) (fun s => (0 : ℚ)) 0 (fun s => True) (fun x => True) false_cost_step (by intro s hs; decide) \[0] 0 (by trivial) (by trivial) (by rfl)\n")
marked = session.theorems["marked_cost"]
if marked == nil || marked.hyps.size != 0 || marked.tags != ["axiom:false_cost_step", "oracle:arith"]
  raise "amortized bound lost an assumption tag"
session.run_file("bits/tungsten-satori/spec/amortized_failure.sat")
if session.failures != 9
  raise "amortized rules accepted an invalid order, domain or missing premise"
<< "Amortized cost patterns passed"
