# Language basics: print, arithmetic, strings, interpolation.
#
# Run: `bin/tungsten -o /tmp/basics spec/core/basics_spec.w && /tmp/basics`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# -- Arithmetic --
check("arith.add", 2 + 3, 5)
check("arith.sub", 10 - 4, 6)
check("arith.mul", 3 * 7, 21)
check("arith.div", 15 / 3, 5)
check("arith.mod", 17 % 5, 2)
check("arith.compound", (2 + 3) * 4 - 1, 19)

# -- Comparisons / booleans --
check("cmp.lt", 1 < 2, true)
check("cmp.gt", 3 > 2, true)
check("cmp.eq", 4 == 4, true)
check("cmp.ne", 4 != 5, true)
check("bool.and", true && true, true)
check("bool.or", false || true, true)
check("bool.not", !false, true)

# -- Strings --
check("str.concat", "hel" + "lo", "hello")
check("str.repeat", "ab" * 3, "ababab")
check("str.size", "hello".size, 5)
check("str.empty", "".size, 0)
check("str.eq", "abc" == "abc", true)
check("str.ne", "abc" == "abd", false)
check("str.include", "hello".include?("ell"), true)
check("str.include.miss", "hello".include?("xyz"), false)

# -- Interpolation (lowers to to_s + concat, not +) --
name = "Tungsten"
n = 42
check("interp.str", "hi [name]", "hi Tungsten")
check("interp.int", "n is [n]!", "n is 42!")

# -- Variables / assignment --
x = 10
y = 20
z = x + y
check("var.sum", z, 30)
x += 5
check("var.compound_assign", x, 15)

<< "basics_spec: all checks passed"
