# Units and quantities: unary minus on a quantity.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "neg.lit [-(3 m)]"
q = 3 m
<< "neg.var [-q]"
<< "neg.mul [q * -1]"
