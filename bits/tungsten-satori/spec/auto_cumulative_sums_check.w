use ../lib/satori
use proof_source

-> check_auto_cumulative_sums(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  rules = ["sum_below_zero", "sum_below_succ", "sum_below.eq_of_recurrence"]
  signed = ["int", "rat", "real"].include?(suffix)
  if signed
    rules.push("sum_telescope." + suffix)
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", rules))
  names = [suffix + "_direct", suffix + "_reverse"]
  if signed
    names = names + ["telescope", "telescope_reverse", "endpoint", "bound"].map -> (name) suffix + "_" + name
  definitions = []
  if suffix == "generic"
    definitions = ["local_total"]
    names = names + ["defined_total", "defined_reverse"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_cumulative_sums.sat", definitions + names))
  if session.failures != 0
    raise "automatic cumulative sums failed: " + suffix
  (names + ["sum_below.eq_of_recurrence"]).each -> (name)
    th = session.theorems[name]
    expected = []
    if name.include?("telescope")
      expected = ["oracle:ring"]
    if name.ends_with?("_endpoint") || name.ends_with?("_bound") || name.ends_with?("_telescope_reverse")
      expected = ["oracle:arith", "oracle:ring"]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "cumulative sum missing, open or has unexpected trust: " + name
  bad = [suffix + "_missing_base", suffix + "_missing_step"]
  if suffix == "generic"
    bad.push("generic_wrong_index")
  if suffix == "nat"
    bad.push("natural_telescope")
  if signed
    bad = bad + ["wrong_sign", "wrong_endpoint", "wrong_stride"].map -> (name) suffix + "_" + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_cumulative_sums_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "cumulative sums accepted missing premises or wrong endpoints: " + name
  if suffix == "generic"
    session.run_source("opaque input_term : ℕ → ℚ\nopaque partial_total : ℕ → ℚ\naxiom total_base : partial_total 0 = 0\naxiom total_step : ∀ i, partial_total (i+1) = partial_total i+input_term i\n")
    previous = session.failures
    session.run_source("+ unsupplied_total (n : ℕ) : partial_total n = sum_below n input_term := by auto\n")
    if session.failures != previous + 1 || session.theorems["unsupplied_total"] != nil
      raise "cumulative sum used unsupplied user axioms"
    session.run_source("+ marked_total (n : ℕ) : partial_total n = sum_below n input_term := by auto \[total_base, total_step]\n")
    th = session.theorems["marked_total"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:total_base", "axiom:total_step"]
      raise "cumulative sum lost its base or step tag"
  << "Automatic cumulative sums passed: " + suffix
