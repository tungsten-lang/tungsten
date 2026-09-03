## parity xfail both engines now reject extra arguments, but the compiled engine rejects at COMPILE time (E_LOWER_ARITY, no program output) while the interpreter raises at the call after earlier output
# Arity: calling a named-parameter method with too many arguments — every
# engine drops the extras today (documented behaviour, not an endorsement).
#
# Cross-engine parity spec (scripts/parity.sh).

-> k(a, b)
  "k:[a],[b]"

-> g(a, b = 10)
  "g:[a],[b]"

<< "named.extra [k(1, 2, 3)]"
<< "default.extra [g(1, 2, 3)]"
