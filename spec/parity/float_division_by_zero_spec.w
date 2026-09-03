## parity xfail interpreter raises "division by zero" for ~1.0 / ~0.0; compiled prints inf
# Floats: division by a float zero.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "flt.inf [~1.0 / ~0.0]"
<< "flt.neginf [-~1.0 / ~0.0]"
<< "flt.nan [~0.0 / ~0.0]"
