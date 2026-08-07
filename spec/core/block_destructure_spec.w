# Block-param destructuring: a block declared with multiple params that is
# yielded a SINGLE Array element spreads the element across the params
# (Ruby proc semantics) — missing params become nil, extra elements drop.
# Implicit free-var blocks (`-> << a + b`) never destructure: implicit
# binding stays first-reference order.
#
# Covered paths: the inlined array `each` loop, closure-called iterators
# (map/select/reduce-style via w_closure_call_1 + closure arity), and both
# interpreters. Two-arg yields (hash each, each_with_index, reduce) are
# unaffected.
#
# Run both engines: `bin/tungsten spec/core/block_destructure_spec.w`
#            and: `bin/tungsten -o /tmp/bds spec/core/block_destructure_spec.w && /tmp/bds`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

pairs = [[1, 2], [3, 4], [5, 6]]

# -- inlined each --
sum = 0
pairs.each ->(a, b)
  sum += a * 10 + b
check("each.destructure", sum, 12 + 34 + 56)

# -- map (closure path) --
sums = pairs.map ->(a, b)
  a + b
check("map.destructure", sums.join(","), "3,7,11")

# -- select (closure path) --
kept = pairs.select ->(a, b)
  a + b > 5
check("select.destructure", kept.size(), 2)

# -- missing params become nil --
shorts = [[1], [2]]
nils = 0
shorts.each ->(a, b)
  nils += 1 if b == nil
check("each.missing_nil", nils, 2)

# -- extra elements drop --
first_two = [[1, 2, 3, 4]].map ->(a, b)
  a + b
check("map.extras_drop", first_two[0], 3)

# -- single-param blocks still get the whole element --
whole = pairs.map ->(p)
  p.size()
check("single_param_whole", whole.join(","), "2,2,2")

# -- two-arg yields unaffected: hash each and reduce --
h = {x: 1, y: 2}
hsum = 0
h.each ->(k, v)
  hsum += v
check("hash.two_arg_yield", hsum, 3)

rsum = [1, 2, 3].reduce(0) ->(acc, x)
  acc + x
check("reduce.two_arg_yield", rsum, 6)

# -- non-array element to a multi-param block: param 0 gets it verbatim --
mixed = 0
[7, 8].each ->(a, b)
  mixed += a
  mixed += 100 if b != nil
check("non_array_param0", mixed, 15)

# -- the motivating shape: peak pairs --
peaks = [[50.0, 1.0], [120.0, 0.5]]
lines = []
peaks.each ->(f, amp)
  lines += ["[f] Hz @ [amp]"]
check("peaks.shape", lines.join("; "), "50 Hz @ 1; 120 Hz @ 0.5")
