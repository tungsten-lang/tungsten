# Units and quantities: arithmetic between quantities, scalars, comparison.
#
# Cross-engine parity spec (scripts/parity.sh): the interpreted and compiled
# transcripts of this program must agree byte-for-byte.

<< "add.ft.in [3 ft + 12 in]"
<< "sub.ft.in [3 ft - 12 in]"
<< "add.kg.g [1 kg + 500 g]"
<< "add.dec [0.1 m + 0.2 m]"
<< "scalar.mul [2 * 3 m]"
<< "mul.scalar [3 m * 2]"
<< "div.scalar [6 m / 2]"
<< "mul.float [~0.5 m * 2]"
<< "cmp.lt [1 km < 2 km]"
<< "cmp.gt [1 km > 900 m]"
<< "eq.mixed [1 km == 1000 m]"
<< "approx [1 km ≈ 1000 m]"
q = 3 m
<< "var.mul [q * q]"
<< "var.add [q + q]"
<< "var.tos " + q.to_s()
