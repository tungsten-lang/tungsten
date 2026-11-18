use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("logic")
session.run_file("bits/tungsten-satori/spec/sequence.sat")
if session.failures != 0
  raise "sequence proofs failed"
kernel_only = ["function.iterate_invariant", "sequence.shift", "sequence.eq_iterate", "sequence.invariant", "sequence.repeat_after_equal", "orbit_property", "recurrence_origin", "countdown_step", "toggle_step", "toggle_period"]
arith = ["sequence.stable", "sequence.forall_of_stable", "sequence.not_reachable_of_stable", "sequence.periodic_repeats", "sequence.periodic_tail", "sequence.periodic_run_bound", "natural_progress", "countdown_settled", "countdown_small", "countdown_unreachable", "toggle_far", "toggle_tail", "toggle_run", "empty_run", "periodic_lists"]
(kernel_only + arith).each -> (name)
  th = session.theorems[name]
  expected = kernel_only.include?(name) ? [] : ["oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "sequence theorem is missing, open or has unexpected trust: " + name
session.run_source("axiom bad_fixed : (3 : ℕ) = 2\n+ marked_stable : 3 = (2 : ℕ) := sequence.stable (fun x => x + 1) (fun n => n) (by intro n; rfl) 2 3 bad_fixed (by decide)\n")
marked = session.theorems["marked_stable"]
if marked == nil || marked.hyps.size != 0 || marked.tags != ["axiom:bad_fixed", "oracle:arith"]
  raise "sequence stability lost its assumption tag"
session.run_file("bits/tungsten-satori/spec/sequence_failure.sat")
if session.failures != 10
  raise "sequence rules accepted a wrong bound or missing premise"
<< "Sequence recurrence and periodicity patterns passed"
