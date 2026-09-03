## parity xfail both engines now reject missing required arguments, but the compiled engine rejects at COMPILE time (E_LOWER_ARITY, no program output) while the interpreter raises at the call after earlier output
# Arity: calling with fewer arguments than parameters binds the missing
# ones to nil on every engine today (documented behaviour, not an
# endorsement). Values are printed through == nil so the nil display
# rule (nil_display_spec) does not leak into this spec.
#
# Cross-engine parity spec (scripts/parity.sh).

-> h/2
  "h:[@1],[@2 == nil]"

-> k(a, b)
  "k:[a],[b == nil]"

-> g(a, b = 10)
  "g:[a],[b]"

<< "slash.missing [h(1)]"
<< "named.missing [k(1)]"
<< "default.used [g(1)]"
<< "default.given [g(1, 2)]"
