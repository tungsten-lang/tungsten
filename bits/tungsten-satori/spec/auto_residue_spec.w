use ../lib/satori
use proof_source

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.load_prelude
s.run_file("bits/tungsten-satori/spec/auto_residue.sat")
if s.failures != 0
  raise "branch-local residue proofs failed"
proof_source_blocks("bits/tungsten-satori/spec/auto_residue.sat").each -> (block)
  name = block[0]
  if name == "supplied_residue"
    next
  th = s.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags.include?("axiom:supplied_residue") != ["from_hint", "expression_hint"].include?(name)
    raise "missing proof or unexpected dependency: " + name
  if !th.tags.all?(-> (tag) ["oracle:ring", "oracle:arith", "axiom:supplied_residue"].include?(tag))
    raise "unexpected trust tag: " + name
path = "bits/tungsten-satori/spec/auto_residue_failure.sat"
proof_source_blocks(path).each -> (block)
  before = s.failures
  s.run_source(block[1].join("\n"))
  if s.failures != before + 1 || s.theorems[block[0]] != nil
    raise "incorrect residue proof: " + block[0]
<< "Branch-local residues passed"
