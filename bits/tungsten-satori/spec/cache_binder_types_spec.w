use ../lib/satori

# Cache deduplication sees open subterms before their enclosing binders. Their
# types must survive even when different numeric families share a bound index.
-> check_bound_types(term, scope)
  if term.tag == :bnd
    if term.idx >= scope.size || !ty_eq(term.ty, scope[term.idx])
      raise "cache changed a bound variable's type"
  elsif term.tag == :lam
    check_bound_types(term.b, [term.ty] + scope)
  elsif term.tag == :app
    check_bound_types(term.a, scope)
    check_bound_types(term.b, scope)

source = Session.new(".")
source.quiet = true
source.no_cache = true
source.run_import("core")
source.run_source("+ natural (x : ℕ) : x = x := by rfl\n+ integer (x : ℤ) : x = x := by rfl\n+ rational (x : ℚ) : x = x := by rfl\n+ real_value (x : ℝ) : x = x := by rfl\n+ mixed (f : ℕ → ℤ) (x : ℕ) : f x = f x := by rfl\n+ generic (f : α → β) (x : α) : f x = f x := by rfl\n")
if source.failures != 0
  raise "cache type fixtures failed"
writer = SatcWriter.new
names = ["natural", "integer", "rational", "real_value", "mixed", "generic"]
names.each -> (name)
  th = source.theorems[name]
  check_bound_types(th.concl, [])
  writer.add_thm(name, th)
path = "/tmp/satori-cache-binder-types.satc"
File.atomic_write(path, writer.serialize("binder-types"))
restored = Session.new(".")
restored.quiet = true
restored.no_cache = true
restored.run_import("core")
if !restored.satc_try_load("binder-types", path)
  raise "cache round trip failed"
names.each -> (name)
  before = source.theorems[name]
  after = restored.theorems[name]
  check_bound_types(after.concl, [])
  if !tm_eq(before.concl, after.concl) || after.tags != before.tags || after.hyps.size != 0
    raise "cache changed a typed theorem: " + name
# Specialization must produce the same checked theorem after reload.
x = mk_var("x", ty_int)
if !tm_eq(source.k.spec(x, source.theorems["integer"]).concl, restored.k.spec(x, restored.theorems["integer"]).concl)
  raise "cached integer specialization changed"
<< "cache binder types passed"
