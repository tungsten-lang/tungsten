use ../lib/satori
use proof_source

-> check_auto_list_bound(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("prelude")
  rule = session.theorems["list.forall_cons"]
  if rule == nil || rule.hyps.size != 0 || rule.tags != []
    raise "memberwise head/tail rule is not kernel-only"
  defs = ["subtotal", "count", "nonnegative", "product", "big"].map -> (name) name + "." + suffix
  good = ["nonnegative", "member_nonnegative", "upper", "lower", "product", "threshold", "strict", "supplied", "guarded"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_list_bound.sat", defs + good))
  if session.failures != 0
    raise "automatic list bound failed: " + suffix
  good.each -> (name)
    tags = ["oracle:arith"]
    if suffix == "nat" && (name == "nat_nonnegative" || name == "nat_member_nonnegative")
      tags = []
    if name == "nat_product"
      tags = ["oracle:arith", "oracle:ring"]
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != tags
      raise "list bound missing, open or has unexpected trust: " + name
  bad = ["empty_strict", "missing_upper", "wrong_upper", "point_member", "wrong_list", "missing_base", "missing_step", "wrong_step", "missing_guard", "point_step"].map -> (name) suffix + "_" + name
  bad.each -> (name)
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_list_bound_failure.sat", [name]))
    if session.failures != before+1 || session.theorems[name] != nil
      raise "list bound accepted missing or invalid premises: " + name
  if suffix == "rat"
    session.run_source("opaque bounded_list : list ℚ → ℚ\naxiom bound_base : bounded_list \[] ≤ 0\naxiom bound_step : ∀ x xs, bounded_list (x :: xs) ≤ bounded_list xs+1\n")
    before = session.failures
    session.run_source("+ unsupplied_bound (xs : list ℚ) : bounded_list xs ≤ count.rat xs := by auto\n")
    if session.failures != before+1 || session.theorems["unsupplied_bound"] != nil
      raise "list bound used an unsupplied axiom"
    session.run_source("+ marked_bound (xs : list ℚ) : bounded_list xs ≤ count.rat xs := by auto \[bound_base, bound_step]\n+ local_marked_bound (xs : list ℚ) : bounded_list xs ≤ count.rat xs\n  have base := bound_base\n  have step := bound_step\n  auto\n")
    ["marked_bound", "local_marked_bound"].each -> (name)
      th = session.theorems[name]
      if th == nil || th.hyps.size != 0 || th.tags != ["axiom:bound_base", "axiom:bound_step", "oracle:arith"]
        raise "list bound lost supplied axiom tags"
  << "Automatic list bounds passed: " + suffix
