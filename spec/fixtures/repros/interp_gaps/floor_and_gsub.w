# Decimal literals (3.7) dispatch to core/numeric/decimal.w — an all-bodyless
# native facade. The interpreter "executed" those empty declarations
# (crashing on floor's `digits = scale` default) instead of falling through
# to the runtime like the compiled engine. Bodyless methods on runtime-backed
# receivers are now declarations, not empty bodies.
#
# String#gsub: plain-string patterns only, both engines — the compiled gsub
# IC row is the same literal replace-all handler as replace; the interpreter
# builtin now mirrors it. No regex substitution on either engine.
v1 = 3.7.floor
<< "floor=[v1]"
v2 = 3.2.ceil
<< "ceil=[v2]"
v3 = (0 - 2.3).floor
<< "negfloor=[v3]"
v4 = 2.6.round
<< "round=[v4]"
v5 = "a-b-a".gsub("a", "x")
<< "gsub=[v5]"
v6 = "hello world".gsub("o", "0")
<< "gsub2=[v6]"
v7 = "aaa".gsub("aa", "b")
<< "gsub3=[v7]"
v8 = "abc".gsub("z", "!")
<< "gsub-miss=[v8]"
