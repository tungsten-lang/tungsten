# Tungsten.FREEZE_THE_SLAB!, Tungsten.NO_MORE_INTERNS! and
# Tungsten.THE_INTERNSHIP_IS_OVER! are synonyms of freeze_slab(): each
# freezes the string slab and evaluates to nil, they work as statements, as
# expressions and inside a fn, and runtime-built strings stay equal to their
# literals afterwards (Hash keys and interned `case` arms included).

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

-> slab_frozen
  frozen = ccall_nobox("w_slab_is_frozen") ## i64
  frozen

-> intern_inside_fn
  Tungsten.NO_MORE_INTERNS!
  "fn done"

-> arm(word)
  case word
  when "hello world" then 1
  when "goodbye world" then 2
  when "hello there" then 3
  else 0

literal = "hello world"
source = "HELLO WORLD"
table = {literal => 7}

Tungsten.FREEZE_THE_SLAB!
check("FREEZE_THE_SLAB! freezes", slab_frozen(), 1)
check("FREEZE_THE_SLAB! is nil", Tungsten.FREEZE_THE_SLAB!, nil)
check("NO_MORE_INTERNS! is nil", Tungsten.NO_MORE_INTERNS!, nil)
check("THE_INTERNSHIP_IS_OVER! is nil", Tungsten.THE_INTERNSHIP_IS_OVER!, nil)
Tungsten.THE_INTERNSHIP_IS_OVER!
check("NO_MORE_INTERNS! inside a fn", intern_inside_fn(), "fn done")
check("still frozen", slab_frozen(), 1)

dynamic = source.downcase()
check("literal equality", dynamic == literal, true)
check("hash lookup", table[dynamic], 7)
check("case arm", arm(dynamic), 1)
check("case arm, built from parts", arm("goodbye" + " " + "world"), 2)
check("case miss", arm(dynamic + "!"), 0)

<< "slab_freeze_directives_spec: all checks passed"
