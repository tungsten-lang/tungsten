# Repro: interpreter Array#sum(init) IGNORED its init argument — the
# builtins.w `sum` (which outranks the Enumerable#sum(init) trait default
# so it can mirror the native IC row) discarded args, so sum(10) == sum()
# and [].sum(5) == 0. The compiled engine's WN_sum IC row had the same
# dropped-arg bug, fixed earlier in e857a36; this pins the interpreter
# twin (and the compiled behavior) to Ruby Enumerable#sum(init).

<< "sum_init=" + [1, 2, 3].sum(10).to_s
<< "sum_plain=" + [1, 2, 3].sum.to_s
<< "sum_empty_init=" + [].sum(5).to_s
<< "sum_float_init=" + [1.5, 2.5].sum(1).to_s
