use ../lib/satori

s = Session.new(".")
s.quiet = true
s.load_prelude
s.run_file("bits/tungsten-satori/spec/list_evidence.sat")
if s.failures != 0 || s.theorems["assembled"].tags != ["oracle:ring"] || s.theorems["named_hint"].tags != ["axiom:seed"]
  raise "list assembly lost an item or its dependencies"

# More proved items than the symbol-based search will shortlist.
items = []
70.times -> (n)
  i = n.to_s
  items.push(i)
  s.run_source("+ cell" + i + " : twice " + i + " = 2 * cost " + i + " := by unfold twice; ring\n")
s.run_source("+ many : all (fun n => twice n = 2 * cost n) \[" + items.join(",") + "] := by auto\n")
if s.failures != 0 || s.theorems["many"].tags != ["oracle:ring"]
  raise "list assembly missed a proved item in a crowded index"

# A hash collision cannot serve as evidence for a different proposition.
first = s.theorems["cell0"].concl
i = HASH_MOD.to_s
s.run_source("axiom colliding : twice " + i + " = 2 * cost " + i + "\n")
other = s.theorems["colliding"].concl
if first.h != other.h || s.exact_premise(other) != nil
  raise "an exact premise must match the complete proposition"
s.bind_theorem("cell0", s.theorems["colliding"])
if s.exact_premise(first) != nil
  raise "selected a shadowed item proof"

s.run_file("bits/tungsten-satori/spec/list_evidence_failure.sat")
if s.failures != 6
  raise "expected six incomplete lists"
<< "List evidence passed"
