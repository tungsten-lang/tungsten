use ../lib/satori

k = KKernel.new
x = mk_var("x", ty_nat)
predicate = mk_lam(x, k.truth_tm)
rejected = false
begin
  k.select_rule(predicate, k.false_tm, k.truth)
rescue e
  rejected = e.to_s.contains?("witness has wrong type")
if !rejected
  raise "selection accepted a witness of the wrong type"

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_source("+ raw (x : ℕ) : ε (fun y => y = x) = x := by exact epsilon_spec (fun y => y = x) ⟨x, by rfl⟩")
raw = session.theorems["raw"]
if raw == nil || raw.tags.size != 0 || raw.hyps.size != 0
  raise "raw choice failed to produce a closed kernel theorem"
body = session.k.spec(x, raw).concl
session.run_source("+ round_trip (x : ℕ) : " + tm_show(body) + " := by exact raw x")
again = session.theorems["round_trip"]
if again == nil || !tm_eq(raw.concl, again.concl)
  raise "printed choice application failed to round trip"
<< "choice kernel and printer passed"
