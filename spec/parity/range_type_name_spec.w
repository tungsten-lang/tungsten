# Ranges: type() reports Range for inclusive and exclusive ranges.
# The interpreter stores a range as a tagged hash; type() still
# reports the language class.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "type.range [type(1..2)]"
<< "type.excl [type(1...2)]"
r = 1..3
<< "type.var [type(r)]"
