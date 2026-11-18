use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["cast_add.int", "int_cast_add.real", "cast_add.real", "cast_one.real", "cast_succ.real", "sum_below_zero", "sum_below_succ", "sum_const.real", "sum_below.congr", "sum_below.eq_of_recurrence", "sum_telescope.real", "sum_below.eq_const.real", "sum_below.eq_one.real", "sum_const_mul.real", "sum_add.real", "sum_sub.real", "mul_sub.real", "sum_nonneg.real", "le_induction.nat"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below.split.real", "sum_below.const_le.real", "sum_below.le_const.real", "sum_below.mono.real", "sum_below.succ_front.real", "sum_below.single_out.real", "sum_below.single.real", "sum_below.single_eq.real"]))
good = ["sum_split", "sum_scaled", "sum_nonneg_all", "sum_lo", "sum_hi", "sum_mono", "first_term", "selected_term", "excluded_term", "selected_entry", "selected_offset", "selected_pair", "selected_difference", "uniform_total", "count_ones", "cumulative", "increments", "recover_endpoint", "custom_increments", "custom_constant"]
session.run_source(proof_declarations("bits/tungsten-satori/examples/compact_sums.sat", ["shifted", "scaled", "running_total"] + good))
if session.failures != 0
  raise "compact sum examples failed"
good.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if ["sum_split", "sum_scaled", "first_term", "increments", "custom_increments"].include?(name)
    expected = ["oracle:ring"]
  if ["selected_pair", "selected_difference", "uniform_total", "count_ones", "recover_endpoint", "custom_constant"].include?(name)
    expected = ["oracle:arith", "oracle:ring"]
  if name == "cumulative"
    expected = []
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "compact sum example missing, open or has unexpected trust: " + name
<< "Compact sum examples passed"
