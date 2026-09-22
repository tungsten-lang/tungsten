# Floats: division by a float zero is IEEE 754 (signed infinity, NaN).
#
# Cross-engine parity spec (scripts/parity.sh).

<< "flt.inf [~1.0 / ~0.0]"
<< "flt.neginf [-~1.0 / ~0.0]"
<< "flt.nan [~0.0 / ~0.0]"
