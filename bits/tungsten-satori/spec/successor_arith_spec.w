use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(File.read("bits/tungsten-satori/spec/successor_arith.sat"))
if session.failures != 0
  raise "successor arithmetic failed"
["successor_eq", "successor_gt", "successor_twice", "successor_square", "successor_contra", "successor_lower", "successor_induction", "nat_function", "nat_guarded", "int_function", "int_guarded", "rat_function", "rat_guarded", "real_function", "real_guarded"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "successor arithmetic missing, open or has unexpected trust: " + name
["wrong_successor", "wrong_offset", "wrong_nested", "missing_step", "wrong_index", "wrong_strict", "missing_range"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/successor_arith_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "successor arithmetic accepted an invalid goal: " + name
session.run_source("axiom succ_eq_add_one.nat (n : ℕ) : succ n = n+2\n+ marked_successor (n : ℕ) : succ n = n+2 := by linarith\n")
th = session.theorems["marked_successor"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:succ_eq_add_one.nat", "oracle:arith"]
  raise "successor normalization lost its named assumption tag"
<< "Successor arithmetic passed"
