# Increment / compound-assignment target coverage, all engines.
#
# `x++` / `x--` are parser rewrites of `x += 1` / `x -= 1` (identical AST),
# and both forms must accept the same target shapes as plain `=`:
# locals, hash/array subscripts (including variable indexes and nesting),
# and receiver setters (obj.attr). Before 8/8 the Ruby engine rejected
# every subscript/setter compound assign at parse ("unexpected token +="),
# and the stage interpreter rejected the setter form at runtime
# ("Invalid compound assignment target"); compiled supported them all.
#
# Known engine nuance (pre-existing): with a side-effecting receiver or
# index expression (`a[f()] += 1`), the compiled and Ruby engines evaluate
# the receiver/index for the read AND the write (twice), while the stage
# interpreter evaluates them once. Values here are effect-free, so all
# three agree.
#
# Run: `bin/tungsten -o /tmp/incspec spec/core/increment_assign_spec.w && /tmp/incspec`
# Engine parity: also run interpreted and via --ruby.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

h = {}
h["a"] = 1
h["a"] += 1
check("hash subscript +=", h["a"], 2)
h["b"] = 5
h["b"]++
check("hash subscript ++", h["b"], 6)
h["b"]--
check("hash subscript --", h["b"], 5)
h["m"] = 3
h["m"] *= 4
check("hash subscript *=", h["m"], 12)

x = 10
x++
check("local ++", x, 11)
x -= 2
check("local -=", x, 9)

a = [10, 20, 30]
a[1] += 5
check("array subscript +=", a[1], 25)
a[2]++
check("array subscript ++", a[2], 31)
i = 1
a[i] -= 3
check("array variable index -=", a[1], 22)

+ Counter
  -> new
    @n = 0
  -> n
    @n
  -> n=(v)
    @n = v

c = Counter.new
c.n += 7
check("setter +=", c.n, 7)
c.n++
check("setter ++", c.n, 8)
c.n--
check("setter --", c.n, 7)

nested = {}
nested["x"] = {}
nested["x"]["y"] = 1
nested["x"]["y"] += 2
check("nested hash subscript +=", nested["x"]["y"], 3)

<< "PASS increment_assign_spec"
