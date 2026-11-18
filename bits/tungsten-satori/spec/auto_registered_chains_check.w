use ../lib/satori
use proof_source

-> registered_chain_progress(suffix, phase)
  prefix = Env.get("SATORI_TEST_PROGRESS")
  if prefix != nil
    File.atomic_write(prefix + "-" + suffix, phase + "\n")

-> check_registered_chains(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  registered_chain_progress(suffix, "prelude")
  # Replay the real arithmetic prerequisites and bound from source in this
  # interpreter. Each family needs only its own ordered-ring declarations.
  needed = ["le_antisymm", "not_le", "not_lt", "mul_nonneg", "mul_pos"]
  if suffix == "int"
    needed.push("lt_iff_add_one_le")
  session.prelude_mode = true
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/core.sat", needed.map(-> (name) name + "." + suffix)))
  session.prelude_mode = false
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/order.sat", ["sq_nonneg." + suffix]))
  registered_chain_progress(suffix, "quadratic lemma")
  rule = "quadratic_form.bound." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/quadratic.sat", [rule]))
  if session.failures != 0 || session.auto_rules[rule] == nil || session.auto_rules[rule].tags != ["oracle:arith"]
    raise "registered arithmetic prerequisite failed: " + rule
  good = ["upper", "strict", "offset", "scaled", "lower"].map -> (name) suffix + "_" + name
  good.each -> (name)
    registered_chain_progress(suffix, name)
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_registered_chains.sat", [name]))
  if session.failures != 0
    raise "registered arithmetic chain failed: " + suffix
  good.each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != ["oracle:arith"]
      raise "registered chain missing, open or has unexpected trust: " + name
  ["no_form", "no_upper", "wrong_upper", "strict_without_margin", "negative_scale", "missing_guard"].each -> (part)
    name = suffix + "_" + part
    registered_chain_progress(suffix, name)
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_registered_chains_failure.sat", [name]))
    if session.failures != before + 1 || session.theorems[name] != nil
      raise "registered arithmetic chain accepted a false claim: " + name
  registered_chain_progress(suffix, "passed")
  << "Registered arithmetic chains passed: " + suffix
