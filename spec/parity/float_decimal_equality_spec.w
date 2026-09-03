# Floats vs decimals: exact equality, approximate equality (≈), mixed
# comparisons.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "flt.eq.dec [~0.5 == 0.5]"
<< "flt.eq.dec2 [~0.3 == 0.3]"
<< "flt.approx [~0.1 + ~0.2 ≈ ~0.3]"
<< "flt.exact [~0.1 + ~0.2 == ~0.3]"
<< "dec.exact [0.1 + 0.2 == 0.3]"
<< "dec.int.eq [2.0 == 2]"
<< "flt.int.eq [~2.0 == 2]"
f = ~2.0
d = 2.0
<< "flt.var.eq [f == d]"
<< "flt.var.approx [f ≈ d]"
<< "flt.lt [~0.1 < 0.2]"
