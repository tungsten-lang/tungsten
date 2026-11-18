use ../lib/satori

source = Session.new(".")
source.quiet = true
source.no_cache = true
source.run_import("core")
source.run_source("@\[auto] + cached_identity (x : α) : x = x\n  rfl\n")
if source.failures != 0 || source.auto_rules.size != 1
  raise "cache registration fixture failed"
writer = SatcWriter.new
original = source.theorems["cached_identity"]
writer.add_thm("cached_identity", original)
writer.add_auto("cached_identity")
path = "/tmp/satori-auto-registration.satc"
File.atomic_write(path, writer.serialize("auto-registration"))
restored = Session.new(".")
restored.quiet = true
restored.no_cache = true
restored.run_import("core")
if !restored.satc_try_load("auto-registration", path)
  raise "registration cache replay failed"
rule = restored.auto_rules["cached_identity"]
if rule == nil || rule != restored.theorems["cached_identity"] || !tm_eq(rule.concl, original.concl) || rule.tags != original.tags || rule.hyps.size != 0
  raise "cache did not restore the checked registration"
x = mk_var("different", ty_nat)
goal = Goal.new([["different", x]], [], restored.k.eq_tm(x, x))
prover = Prover.new(restored)
choices = prover.auto_registered_hints(goal)
proof = prover.auto_hint_proof(goal, choices, [], [24, 4], [])
if choices.size != 1 || proof == nil || proof.tags.size != 0
  raise "replayed rule could not produce a checked proof"
<< "Auto registration cache replay passed"
