## parity xfail interpreter raises "expected int, got numeric" on unary minus of a Quantity; compiled prints -3 m
# Units and quantities: unary minus on a quantity.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "neg.lit [-(3 m)]"
q = 3 m
<< "neg.var [-q]"
<< "neg.mul [q * -1]"
