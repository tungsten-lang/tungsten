use ../lib/satori
use proof_source

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.load_prelude
s.run_file("bits/tungsten-satori/spec/polynomial_sign.sat")
if s.failures != 0
  raise "interval signs failed"
proof_source_blocks("bits/tungsten-satori/spec/polynomial_sign.sat").each -> (block)
  if !block[1][0].starts_with?("+ ")
    next
  th = s.theorems[block[0]]
  expected = block[0] == "guarded_hint" ? ["axiom:supplied_quartic", "oracle:arith"] : ["oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "unexpected dependency: " + block[0]
proof_source_blocks("bits/tungsten-satori/spec/polynomial_sign_failure.sat").each -> (block)
  before = s.failures
  s.run_source(block[1].join("\n"))
  if s.failures != before + 1 || s.theorems[block[0]] != nil
    raise "unexpected proof: " + block[0]
<< "Polynomial sign checks passed"
