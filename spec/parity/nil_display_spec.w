# Printing: nil in interpolation, as a bare value, inside containers, from
# a missing hash key. `<<` uses #to_s, so nil is the empty string.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "interp [nil]"
x = nil
<< "var [x]"
<< "arr [[nil, 1]]"
<< "hash [{a: nil}]"
h = {a: 1}
<< "missing.key [h[:nope]]"
<< "env.unset [env("TUNGSTEN_PARITY_UNSET_XYZ")]"
<< nil
<< "end"
