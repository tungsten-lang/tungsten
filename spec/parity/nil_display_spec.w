## parity xfail nil prints as "nil" interpreted but as the empty string compiled — in interpolation, `<< nil`, and inside arrays/hashes ([nil, 1] vs [, 1])
# Printing: nil in interpolation, as a bare value, inside containers, from
# a missing hash key and a missing method argument.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "interp [nil]"
x = nil
<< "var [x]"
<< "arr [[nil, 1]]"
<< "hash [{a: nil}]"
h = {a: 1}
<< "missing.key [h[:nope]]"
-> k(a, b)
  "k:[a],[b]"
<< "missing.arg [k(1)]"
<< "env.unset [env("TUNGSTEN_PARITY_UNSET_XYZ")]"
<< nil
<< "end"
