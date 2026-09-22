## parity xfail both engines reject a second call of the same function with a different arity; compiled reports E_LOWER_ARITY before any output, the interpreter prints the earlier exact call and then raises at the extra-argument call
# Arity: one function called at two argument counts. The extra call is
# rejected. The compiled engine reports it at compile time; the
# interpreter reports it when that call runs.
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
