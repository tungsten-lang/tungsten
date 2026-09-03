## parity xfail -~0.0 prints "0" interpreted but "-0" compiled
# Floats: negative zero.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "negzero [-~0.0]"
<< "negzero.eq [-~0.0 == ~0.0]"
<< "negzero.mul [~0.0 * -1]"
