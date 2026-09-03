## parity xfail one function called with two different arities: interpreter drops/nils the extras at each site; compiled fails at lowering with "WIRE call contract mismatch" (i64(i64,i64) in @main vs i64(i64,i64,i64) in @main)
# Arity: the same method called with different argument counts in one
# program (a single wrong-arity call site compiles fine — see
# arity_extra_args_named_spec).
#
# Cross-engine parity spec (scripts/parity.sh).

-> h/2
  "h:[@1],[@2]"

-> k(a, b)
  "k:[a],[b]"

<< "slash.exact [h(1, 2)]"
<< "slash.extra [h(1, 2, 3)]"
<< "named.exact [k(1, 2)]"
<< "named.extra [k(1, 2, 3)]"
