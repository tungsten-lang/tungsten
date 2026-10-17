# spec: compiled
# Source identifiers spelled like the compiler's own LLVM locals. Parameters
# used to be emitted verbatim as `%<name>`, sharing one namespace with the
# `%t<N>` temporaries wire.w mints, so `-> run(k, t0, t1)` defined `%t0` twice
# and clang rejected the module ("multiple definition of local value named
# 't0'"; found in bits/tungsten-robolab). Escape analysis also mapped
# registers back to parameters by stripping the `%`, which never matched a
# transliterated name like `α` (`%_u0003b1_`): the caller freed a string the
# callee had stored. Parameter registers now live under `%.` (naming.w
# llvm_param_reg), disjoint from every compiler-minted local.
#
# Run: bin/tungsten -o /tmp/prns spec/compiler/param_register_namespace_spec.w && /tmp/prns
#      bin/tungsten run --interpret spec/compiler/param_register_namespace_spec.w

-> check(label, got, want)
  if got == want
    << "PASS " + label
  else
    << "FAIL " + label + " got " + got.to_s() + " want " + want.to_s()

# The original report: float params t0/t1 in an instance method.
+ Sweep
  -> run(k, t0, t1)
    s = ~0.0
    t = t0 + ~0.0025
    while t < t1
      s = s + t
      t = t + ~0.005
    s

  -> .span(t0, t1)
    t1 - t0

  -> wide(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12)
    t0 + t1 * 2 + t2 * 3 + t3 * 4 + t4 * 5 + t5 * 6 + t6 * 7 + t7 * 8 + t8 * 9 + t9 * 10 + t10 * 11 + t11 * 12 + t12 * 13

swept = Sweep.new.run(1, ~0.0, ~0.02)
check("method.float_params", (swept * 10000).round(), 400)
check("class_method.params", Sweep.span(3, 10), 7)
check("method.t0_to_t12", Sweep.new.wide(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1), 91)

# The same 13-parameter method through runtime dispatch, which enters it by its
# argv entry (lowering/definitions.w lower_method_argv_entry): that entry's own
# parameters live in the %. namespace too.
mixed = [Sweep.new, 0]
check("method.t0_to_t12.dynamic", mixed[0].wide(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1), 91)

# Top-level fns: t0..t12, reassigned, defaulted, and keyword params.
-> fsum(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12)
  [t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12].sum()

-> freassign(t0, t1)
  t0 = t0 + 1
  t1 = t1 * 2
  t0 + t1

-> fdefault(t0, t1 = 10)
  t0 + t1

-> fkw(t0, t1: 5)
  t0 * t1

check("fn.t0_to_t12", fsum(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12), 78)
check("fn.reassigned", freassign(1, 3), 8)
check("fn.default_used", fdefault(1), 11)
check("fn.default_given", fdefault(1, 2), 3)
check("fn.keyword_default", fkw(3), 15)
check("fn.keyword_given", fkw(3, t1: 7), 21)

# Raw-ABI typed fn and a raw static method (plus its boxed wrapper).
fn raw_mix(t0, t1, t2) (i64 i64 i64) i64
  t3 = t0 * 100
  t4 = t1 * 10
  t3 + t4 + t2

+ RawProbe
  -> .mix(t0, t1) (i64 u64) i64
    t0 * 1000 + t1

  -> .fmix(t0, t1) (f64 f64) f64
    t0 * t1

check("typed_fn.raw_params", raw_mix(1, 2, 3), 123)
check("static_raw.wrapper", RawProbe.mix(4, 2), 4002)
check("static_raw.float", RawProbe.fmix(~1.5, ~2.0), ~3.0)

# Locals t0..t12 in a fn body and at top level.
-> flocals(n)
  t0 = n
  t1 = t0 + 1
  t2 = t1 + 1
  t3 = t2 + 1
  t4 = t3 + 1
  t5 = t4 + 1
  t6 = t5 + 1
  t7 = t6 + 1
  t8 = t7 + 1
  t9 = t8 + 1
  t10 = t9 + 1
  t11 = t10 + 1
  t12 = t11 + 1
  t0 + t12

check("fn.locals", flocals(1), 14)

t0 = 2
t1 = t0 * 3
t12 = t1 + t0
check("main.locals", t12, 8)

# Block params, iterator loop vars, closures over params, explicit &block.
check("block.param", [1, 2, 3].map(->(t0) t0 * 2), [2, 4, 6])
check("block.two_params", [1, 2, 3, 4].reduce(0, ->(t0, t1) t0 + t1), 10)

acc = 0
(1..4).each ->(t3)
  acc = acc + t3
check("loop.each_var", acc, 10)

times_acc = 0
5.times ->(t7)
  times_acc = times_acc + t7
check("loop.times_var", times_acc, 10)

-> capture(t0, t1)
  f = ->(t2) t0 + t1 + t2
  f.call(100)

-> capture_mutate(t0)
  [1, 2, 3].each ->(t1)
    t0 = t0 + t1
  t0

-> apply_twice(t0, &t1)
  t1.call(t1.call(t0))

-> yielder(t0)
  yield t0 + 1

check("closure.captures_params", capture(1, 2), 103)
check("closure.mutates_param", capture_mutate(10), 16)
check("block.explicit_param", apply_twice(3) ->(t2) t2 * 10, 300)
check("block.yield", yielder(4) ->(t9) t9 * t9, 25)

# Other compiler-minted local spellings as parameter names.
-> fnames(__entry, argc, argv, vs, v32)
  __entry + argc + argv + vs + v32

check("fn.minted_names", fnames(1, 2, 3, 4, 5), 15)

# A callee that stores its parameter makes the caller's fresh string escape.
# The escape summary must find the parameter by its exact register, whatever
# its spelling; otherwise the caller frees `s`, the number formatter below
# recycles the block, and box[0] reads back "1234561".
-> keep(box, α)
  box.push(α)
  nil

-> fill(box, n)
  s = "abc" + n.to_s() + "def"
  keep(box, s)
  nil

-> keep_t(box, t0, t1)
  box.push(t1)
  nil

-> fill_t(box, n)
  s = "xyz" + n.to_s() + "uvw"
  keep_t(box, 0, s)
  nil

box = []
fill(box, 7)
other = (1234560 + box.size()).to_s()
check("escape.unicode_param_stored", box[0], "abc7def")
check("escape.unicode_later_string", other, "1234561")

tbox = []
fill_t(tbox, 5)
tother = (7654320 + tbox.size()).to_s()
check("escape.temp_named_param_stored", tbox[0], "xyz5uvw")
check("escape.temp_named_later_string", tother, "7654321")
