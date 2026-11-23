use ../lib/satori

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.load_prelude
s.run_file("bits/tungsten-satori/spec/ergonomics_and_bundled_laws_spec.sat")
if s.failures != 0
  raise "ergonomics_and_bundled_laws_spec failed: " + s.failures.to_s

# Soundness gate 1: an invalid instance of a law-bearing class MUST be rejected.
bad_src = "instance bad_int_acg : AddCommGroupTest ℤ := AddCommGroupTest.mk 0 (fun x y => x - y) (fun x => x)\n"
s.run_source(bad_src)
if s.failures != 1
  raise "invalid instance should have failed law check"
if s.elab.instances["AddCommGroupTest"].any?(-> (e) e[0] == "bad_int_acg")
  raise "invalid instance must not be registered"

# Soundness gate 2: uninhabited law-bearing class on unit cannot derive False.
unit_src = "class NonTrivial α := (z : α) (o : α) (ne_zo : z ≠ o)\n"
s.run_source(unit_src + "instance bad_unit : NonTrivial (ℕ × ℕ) := NonTrivial.mk (0, 0) (0, 0)\n")
if s.failures != 2
  raise "trivial NonTrivial instance should have failed law check"

# Soundness gate 3: kernel ring_norm must reject division by zero and false ground-cast equalities.
s.run_source("+ bad_div_zero (x : ℝ) : x / (2 - 2) = 0 := by ring\n")
if s.failures != 3
  raise "ring must reject division by zero constant"
s.run_source("+ bad_ground_cast : ((2 : ℕ) : ℝ) = ((3 : ℕ) : ℝ) := by ring\n")
if s.failures != 4
  raise "ring must reject false ground-cast equality"
lb = 91.chr
rb = 93.chr
s.run_source("+ bad_rw_if_by (n : ℕ) : (if n = 0 then (1 : ℕ) else 2) = 2 := by rw " + lb + "if_neg (by omega)" + rb + "\n")
if s.failures != 5
  raise "rw if_neg (by omega) must fail when condition is unprovable"

<< "Ergonomics and bundled law soundness spec passed"
