use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/ring_definition_corpus.sat")
if session.failures != 0
  raise "compact corpus ring identities failed"
["veronese_identity", "diagonal_zero", "bch_contact", "p3_serre", "g2_serre", "fricke_identity", "vieta_x", "vieta_z", "e_three", "eleven_forms", "eleven_farkas"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:ring"]
    raise "corpus ring identity missing, open or changed trust: " + name
<< "Compact corpus ring identities passed"
