# Dynamic dispatch reaches methods of ANY arity.
#
# The runtime calls a compiled method through a native spread entry
# (self + up to W_METHOD_SPREAD_MAX = 8 arguments). A wider method registers a
# compiler-emitted argv entry instead (lowering/definitions.w
# lower_method_argv_entry), so a dispatch the compiler cannot resolve
# statically no longer dies with "unsupported method dispatch ... (runtime
# supports up to 8)". Found in bits/tungsten-robolab: RunKnotsSkill could not
# run RunNaturalSkill's ordered plan because its nine-argument step_chunk is
# reached through the parent's self-call.
#
# Every shape below goes through runtime dispatch: receivers of mixed classes
# in an untyped Array, a parent method's self-call that a subclass overrides,
# class methods and constructors on a class held in a Hash, defaults and a
# splat on wide signatures, and a primitive (String) receiver. The loops
# revisit each call site so an inline-cache hit is exercised too. Checked on
# both engines (compiled and `run --interpret`).
#
# Run: `bin/tungsten -o /tmp/wad spec/compiler/wide_arity_dispatch_spec.w && /tmp/wad`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s + " want " + want.to_s

+ Plan
  -> run_plan(tag)
    step_chunk(tag, "b", 3, 4.5, nil, [6], 7, 8, :nine)

  -> step_chunk(a, b, c, d, e, f, g, h, i)
    ["base", a, b, c, d, e, f, g, h, i]

  -> eight(a, b, c, d, e, f, g, h)
    ["base8", a, b, c, d, e, f, g, h]

  -> ten(a, b, c, d, e, f, g, h, i, j)
    ["base10", a, b, c, d, e, f, g, h, i, j]

  -> twelve(a, b, c, d, e, f, g, h, i, j, k, l)
    ["base12", a, b, c, d, e, f, g, h, i, j, k, l]

  -> sixteen(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p)
    a + b + c + d + e + f + g + h + i + j + k + l + m + n + o + p

  -> defaults(a, b, c, d, e, f, g, h, i = 90, j = 100)
    [a, h, i, j]

  -> gather(a, b, c, d, e, f, g, h, *rest)
    [a, h, rest]

+ KnotPlan < Plan
  -> step_chunk(a, b, c, d, e, f, g, h, i)
    ["knot", a, b, c, d, e, f, g, h, i]

  -> eight(a, b, c, d, e, f, g, h)
    ["knot8", a, b, c, d, e, f, g, h]

  -> ten(a, b, c, d, e, f, g, h, i, j)
    ["knot10", a, b, c, d, e, f, g, h, i, j]

  -> twelve(a, b, c, d, e, f, g, h, i, j, k, l)
    ["knot12", a, b, c, d, e, f, g, h, i, j, k, l]

  -> sixteen(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p)
    a * b * c * d * e * f * g * h * i * j * k * l * m * n * o * p

+ Wide
  ro :sum, :last

  -> new(a, b, c, d, e, f, g, h, i, j)
    @sum = a + b + c + d + e + f + g + h + i + j
    @last = j

  -> .nine(a, b, c, d, e, f, g, h, i)
    ["static9", a, b, c, d, e, f, g, h, i]

  -> .twelve(a, b, c, d, e, f, g, h, i, j, k, l)
    ["static12", a, l]

+ WideTwelve < Wide
  -> new(a, b, c, d, e, f, g, h, i, j, k, l)
    @sum = a + b + c + d + e + f + g + h + i + j + k + l
    @last = l

+ String
  -> wrap8(a, b, c, d, e, f, g, h)
    self + ":" + [a, b, c, d, e, f, g, h].join(",")

  -> wrap9(a, b, c, d, e, f, g, h, i)
    self + ":" + [a, b, c, d, e, f, g, h, i].join(",")

# A parent method's self-call reaches the subclass override (the robolab shape).
check("self.9.base", Plan.new.run_plan(1), ["base", 1, "b", 3, 4.5, nil, [6], 7, 8, :nine])
check("self.9.override", KnotPlan.new.run_plan(1), ["knot", 1, "b", 3, 4.5, nil, [6], 7, 8, :nine])

# Mixed receivers in an untyped collection; each site is visited twice per class.
plans = [Plan.new, KnotPlan.new, Plan.new, KnotPlan.new]
got = []
plans.each ->(p)
  got.push(p.eight(1, 2, 3, 4, 5, 6, 7, 8)[0])
  got.push(p.step_chunk(1, 2, 3, 4, 5, 6, 7, 8, 9)[9])
  got.push(p.ten(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)[10])
  got.push(p.twelve(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)[12])
  got.push(p.sixteen(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 3))
check("coll.values", got, ["base8", 9, 10, 12, 19, "knot8", 9, 10, 12, 6, "base8", 9, 10, 12, 19, "knot8", 9, 10, 12, 6])
check("coll.9.all_args", plans[1].step_chunk("a", 2, 3, 4, 5, 6, 7, 8, "z"), ["knot", "a", 2, 3, 4, 5, 6, 7, 8, "z"])
check("coll.12.all_args", plans[0].twelve(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12), ["base12", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])

# Defaults and a splat on wide signatures.
check("defaults.omitted", plans[1].defaults(1, 2, 3, 4, 5, 6, 7, 8), [1, 8, 90, 100])
check("defaults.given", plans[1].defaults(1, 2, 3, 4, 5, 6, 7, 8, 9, 10), [1, 8, 9, 10])
check("splat.empty", plans[0].gather(1, 2, 3, 4, 5, 6, 7, 8), [1, 8, []])
check("splat.many", plans[0].gather(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11), [1, 8, [9, 10, 11]])

# Class methods and constructors on a class held in a Hash.
classes = {:wide => Wide, :twelve => WideTwelve}
k = classes[:wide]
k12 = classes[:twelve]
sums = []
[1, 2].each ->(round)
  check("static.9." + round.to_s, k.nine(1, 2, 3, 4, 5, 6, 7, 8, 9), ["static9", 1, 2, 3, 4, 5, 6, 7, 8, 9])
  check("static.12." + round.to_s, k.twelve(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12), ["static12", 1, 12])
  w10 = k.new(1, 2, 3, 4, 5, 6, 7, 8, 9, round)
  w12 = k12.new(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, round)
  sums.push(w10.sum)
  sums.push(w10.last)
  sums.push(w12.sum)
  sums.push(w12.last)
check("ctor.10_and_12", sums, [46, 1, 67, 1, 47, 2, 68, 2])

# A primitive receiver's (type-class) method, at and past the spread limit.
items = ["s", 1]
v = items[0]
check("primitive.8", v.wrap8(1, 2, 3, 4, 5, 6, 7, 8), "s:1,2,3,4,5,6,7,8")
check("primitive.9", v.wrap9(1, 2, 3, 4, 5, 6, 7, 8, 9), "s:1,2,3,4,5,6,7,8,9")
