# Arity: `-> name/N` methods bind @1..@N; exact-arity calls.
#
# Cross-engine parity spec (scripts/parity.sh).

-> h/2
  "h:[@1],[@2]"

-> one/1
  "one:[@1]"

<< "exact [h(1, 2)]"
<< "exact.one [one(9)]"
