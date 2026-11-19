use ../lib/satori

source = Session.new(".")
source.quiet = true
source.no_cache = true
source.run_import("core")
source.run_source("@\[auto] + cached_identity (x : α) : x = x\n  rfl\n")
if source.failures != 0 || source.auto_rules.size != 1
  raise "cache registration fixture failed"
source.run_source("+ div_eq_zero_of_den_eq_zero.real (a b : ℝ) (h : b = 0) : a/b = 0 := by simp \[h]\n")
writer = SatcWriter.new
writer.add_thm("div_eq_zero_of_den_eq_zero.real", source.theorems["div_eq_zero_of_den_eq_zero.real"])
original = source.theorems["cached_identity"]
writer.add_thm("cached_identity", original)
writer.add_auto("cached_identity")
path = "/tmp/satori-auto-registration.satc"
File.atomic_write(path, writer.serialize("auto-registration"))
restored = Session.new(".")
restored.quiet = true
restored.no_cache = true
restored.run_import("core")
x = mk_var("different", ty_nat)
goal = Goal.new([["different", x]], [], restored.k.eq_tm(x, x))
prover = Prover.new(restored)
prover.auto_default_hints(goal)
if restored.auto_default_index == nil
  raise "default index did not warm before cache replay"
if !restored.satc_try_load("auto-registration", path)
  raise "registration cache replay failed"
if restored.auto_default_index != nil
  raise "cached theorem binding retained a stale default index"
restored.run_source("+ after_load (x y : ℝ) (hl : 0 ≤ y) (hu : y ≤ 0) : x/y = 0 := by auto\n")
if restored.failures != 0 || restored.theorems["after_load"].tags != ["oracle:arith"]
  raise "replayed default was unavailable to auto"
rule = restored.auto_rules["cached_identity"]
if rule == nil || rule != restored.theorems["cached_identity"] || !tm_eq(rule.concl, original.concl) || rule.tags != original.tags || rule.hyps.size != 0
  raise "cache did not restore the checked registration"
choices = prover.auto_registered_hints(goal)
proof = prover.auto_hint_proof(goal, choices, [], [24, 4], [])
if choices.size != 1 || proof == nil || proof.tags.size != 0
  raise "replayed rule could not produce a checked proof"
<< "Auto registration cache replay passed"
