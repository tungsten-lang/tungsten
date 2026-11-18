use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["le_induction.nat"]))
lemmas = ["nat.interval_induct", "sequence.descent_on.nat", "sequence.descent.nat", "sequence.descent_length.nat", "sequence.no_cyclic_descent.nat", "sequence.no_infinite_descent.nat"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/sequence_order.sat", lemmas))
good = ["bounded_drop", "global_drop", "length_bound", "no_cycle", "no_infinite", "empty_chain", "countdown", "strict_steps", "finite_not_infinite"]
session.run_source(proof_declarations("bits/tungsten-satori/spec/descent.sat", good))
if session.failures != 0
  raise "natural descent proofs failed"
(lemmas + good).each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "descent theorem missing, open or has unexpected trust: " + name
session.run_source("axiom false_descent : ∀ i < 1, (0 : ℕ) + 1 ≤ 0\n+ marked_descent : (1 : ℕ) ≤ 0 := sequence.descent_length.nat (fun i => 0) 1 false_descent\n")
th = session.theorems["marked_descent"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_descent", "oracle:arith"]
  raise "descent lost its step assumption tag"
["weak_step", "missing_last", "empty_cycle", "missing_cycle", "wrong_origin", "weak_infinite"].each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/descent_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "descent accepted an invalid premise: " + name
<< "Natural descent passed"
