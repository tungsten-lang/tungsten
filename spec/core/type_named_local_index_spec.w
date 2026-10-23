# A local or parameter spelled like a typed-array element type (`u1`, `u8`,
# `i8`, `u4`) is a variable once it is bound, so `u1[i]` indexes it. The parser
# used to read `u1[1]` as the typed-array constructor (a one-element bool
# array) even right after `u1 = [~0.0, ~1.0, ~0.0]`, so `wa * u1[1]` died with
# "expected numeric type" on both engines. Found 2026-10-21 in a render script,
# where it looked like a flat float-literal array bug. A type name that is not
# bound in an enclosing scope still allocates a typed array.

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

-> scale(wa)
  u1 = [~0.0, ~1.0, ~0.0]
  wa * u1[1]

-> project(wa, wb, cb, sb)
  p0 = [~1.0, ~0.0, ~2.0]
  u1 = [~0.0, ~1.0, ~0.0]
  u2 = [cb, ~0.0, sb]
  [p0[0] + wa * u1[0] + wb * u2[0], p0[1] + wa * u1[1] + wb * u2[1]]

-> dot(u8, i8)
  u8[0] * i8[0] + u8[1] * i8[1]

# u8 is bound only inside dot, so here it is the constructor again.
-> fresh_bytes
  b = u8[4]
  b.size()

check("local u1 indexes", scale(~1.5), "1.5")
projected = project(~1.5, ~2.0, ~0.5, ~0.25)
check("float literal arrays", projected[0] == ~2.0 && projected[1] == ~1.5, "true")
check("type-named params index", dot([2, 3], [5, 7]), "31")
check("unbound type name allocates", fresh_bytes(), "4")

u4 = [10, 20, 30]
check("top-level u4 indexes", u4[2], "30")

-> read_top_level(k)
  u4[k]

check("function reads top-level u4", read_top_level(1), "20")
