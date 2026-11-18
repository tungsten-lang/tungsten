use ../lib/satori

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.run_file("bits/tungsten-satori/spec/polymorphic_pattern.sat")
if s.failures != 0
  raise "polymorphic pattern equations failed"
[["poly_sum", "β", 2], ["poly_product", "β", 2], ["poly_twice", "α", 1]].each -> (example)
  name = example[0]
  eqns = s.eqns_of(name)
  if eqns.size != example[2]
    raise "missing equations for " + name
  eqns.each -> (th)
    eq = s.k.dest_eq(s.d.spec_all(th).concl)
    result = type_of(eq[0])
    if result.tag != :v || result.name != example[1]
      raise "pattern equation lost its declared result type"
    if th.hyps.size != 0 || th.tags.size != 0
      raise "pattern equation is not an untagged closed theorem"
if s.eqns_of("poly_first").size != 2 || s.theorems.has_key?("poly_first.eq_3")
  raise "overlapping catch-all became an unconditional equation"
<< "Polymorphic pattern equations passed"
