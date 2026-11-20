use ../lib/satori
use ../lib/eval_ref

s = Session.new(".")
s.quiet = true
s.run_source("-> branch (c : ℕ) : ℕ → ℕ → ℕ\n  | 0, x => c + x\n  | i + 1, x => if x = 0 then c + i else branch c i (x - 1) + branch c i 0\n")
# Compare several recursion depths, outer captures and repeated predecessor calls.
claim = "∀ c < 4, ∀ i < 5, ∀ x < 4, branch c (i+1) (x+1) = branch c i x + branch c i 0"
s.run_source("+ steps : " + claim + " := by decide\n")
th = s.theorems["steps"]
if th == nil || !th.hyps.empty?() || !th.tags.empty?()
  raise "function-valued recursion did not reduce"
ref = KEvalRef.new(s.k)
if !ref.true?(ref.eval(th.concl))
  raise "reference reduction disagreed"

# A partial application may escape the evaluator and be applied later.
s.run_source("+ partial : branch 7 3 = branch 7 3 := by rfl\n")
term = dest_binop(s.theorems["partial"].concl, "=")[0]
[false, true].each -> (deep)
  value = KEval.new(s.k, deep).eval(term)
  arg = mk_nat(1)
  result = ref.eval(mk_app(value, arg))
  if !tm_eq(result, mk_nat(16))
    raise "reifying a partial application lost its environment"

# Only the outermost step is needed even when the fuel is very large.
s.run_source("+ early : branch 7 10000000 0 = 10000006 := by decide\n")
s.run_source("+ wrong : branch 7 3 1 = 15 := by decide\n")
if s.theorems["early"] == nil || s.theorems["wrong"] != nil || s.failures != 1
  raise "incorrect early exit or predecessor"

# The same lambda body can capture different functions and offsets.
s.run_source("-> shift (b : ℕ) (f : ℕ → ℕ) : ℕ → ℕ := fun x => f x + b\n")
s.run_source("-> tree : ℕ → (ℕ → ℕ) → ℕ\n  | 0, f => f 0\n  | i + 1, f => tree i (shift 1 f) + tree i (shift 3 f)\n")
s.run_source("+ captures : tree 2 (fun x => x) = 16 := by decide\n")
# Distinct term arguments can also have the same hash.
s.run_source("-> walk : ℕ → ℕ → ℕ\n  | 0, x => x\n  | i + 1, x => walk i x + walk i (x + " + HASH_MOD.to_s + ")\n")
s.run_source("+ collision : walk 1 0 = " + HASH_MOD.to_s + " := by decide\n")
["captures", "collision"].each -> (name)
  proved = s.theorems[name]
  if proved == nil || !proved.tags.empty?() || !ref.true?(ref.eval(proved.concl))
    raise "recursive application disagreed with reference reduction: " + name

# Overlapping recursive calls visit a triangular number of states.
s.run_source("-> paths : ℕ → ℕ → ℕ\n  | 0, x => 1\n  | i + 1, x => paths i x + paths i (x + 1)\n")
paths = s.k.mk_const("paths", ty_funs([ty_nat, ty_nat], ty_nat))
work = []
[6, 10].each -> (depth)
  term = mk_apps(paths, [mk_nat(depth), mk_nat(0)])
  evaluator = KEval.new(s.k)
  start = evaluator.fuel
  if !tm_eq(evaluator.eval(term), mk_nat(2 ** depth))
    raise "incorrect recursive path count"
  work.push(start - evaluator.fuel)
if work[1] >= 4 * work[0]
  raise "recursive path evaluation repeated shared states"

# Literal reductions are scoped to a kernel, including the identity of its
# definitions. A neutral argument must still reduce correctly after substitution.
first = Session.new(".")
second = Session.new(".")
first.quiet = true
second.quiet = true
first.run_source("-> sample (n : ℕ) : ℕ := n+1\n-> mirror (n : ℕ) : ℕ := 2*n\n")
second.run_source("-> sample (n : ℕ) : ℕ := n+3\n")
first.run_source("+ values : sample 5=6 ∧ mirror 5=10 := by decide\n+ repeat : sample (2+3)=6 := by decide\n")
second.run_source("+ distinct : sample 5=8 := by decide\n+ wrong : sample 5=6 := by decide\n")
if first.failures != 0 || second.failures != 1 || second.theorems["wrong"] != nil || second.theorems["distinct"] == nil
  raise "literal results crossed a definition or kernel"
v = mk_var("n", ty_nat)
sample = first.k.mk_const("sample", ty_fun(ty_nat, ty_nat))
open_value = first.k.compute(mk_app(sample, v)).concl.b
at_five = first.k.inst(first.k.refl(open_value), [[v, mk_nat(5)]]).concl.b
if !tm_eq(KEvalRef.new(first.k).eval(at_five), mk_nat(6))
  raise "a neutral application lost its input"
# Check repeated literal calls against substitution, including inputs outside
# the cache range, different definitions, signed fractions and a neutral input.
first.run_source("-> weigh (x y : ℕ) : ℕ := 3*x+y\n-> flip (x y : ℕ) : ℕ := x+3*y\n")
first.run_source("-> half (x y : ℕ) : ℚ := ((x : ℚ) - (y : ℚ))/2\n")
first.run_source("+ order : weigh 1 2=5 ∧ weigh 2 1=7 ∧ flip 1 2=7 ∧ weigh 1 2=5 := by decide\n")
first.run_source("+ edges : weigh 1 0=3 ∧ weigh 0 65536=65536 ∧ weigh 0 0=0 ∧ weigh 4294967296 0=12884901888 := by decide\n")
first.run_source("+ signed : half 2 3 = -1/2 ∧ half 3 2 = 1/2 ∧ half 2 3 = -1/2 := by decide\n")
# These inputs have the same term hash and map to the same cache slot.
offset = HASH_MOD + 1
first.run_source("+ hash_hit : weigh 1 0=3 ∧ weigh " + offset.to_s + " 0=" + (3*offset).to_s + " ∧ weigh 1 0=3 := by decide\n")
first.run_source("-> offset (x : ℕ) : ℤ := (x : ℤ)-7\n")
first.run_source("+ negative : offset 2 = -5 ∧ offset 3 = -4 ∧ offset 2 = -5 := by decide\n")
first.run_source("+ choice : ∀ b : Prop, (if b then (fun (x : ℕ) => x+1) else (fun (x : ℕ) => x+2)) 3 = (if b then 4 else 5) := by decide\n")
pair = first.k.mk_const("weigh", ty_funs([ty_nat, ty_nat], ty_nat))
open_pair = first.k.compute(mk_apps(pair, [v, mk_nat(2)])).concl.b
at_five = first.k.inst(first.k.refl(open_pair), [[v, mk_nat(5)]]).concl.b
reference = KEvalRef.new(first.k)
if !tm_eq(reference.eval(at_five), mk_nat(17))
  raise "a partially symbolic pair lost its input"
["order", "edges", "signed", "hash_hit", "negative", "choice"].each -> (name)
  proved = first.theorems[name]
  if proved == nil || !proved.hyps.empty?() || !proved.tags.empty?() || !reference.true?(reference.eval(proved.concl))
    raise "literal call disagreed with reference reduction: " + name
first.run_source("+ wrong_pair : weigh 1 0=3 ∧ weigh 0 65536=3 := by decide\n")
if first.failures != 1 || first.theorems["wrong_pair"] != nil
  raise "distinct argument pairs shared a result"
<< "Function-valued recursion passed"
