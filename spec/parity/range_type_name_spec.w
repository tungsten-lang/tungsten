## parity xfail type(1..2) is "Hash" interpreted (ranges are hash-backed in interpreter.w) but "Range" compiled
# Ranges: the runtime type name of a range value.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "type.range [type(1..2)]"
<< "type.excl [type(1...2)]"
r = 1..3
<< "type.var [type(r)]"
