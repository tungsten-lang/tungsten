# Strings: indexing a string with a range.
#
# Cross-engine parity spec (scripts/parity.sh).

s = "abcdef"
<< "range [s[1..3]]"
<< "range.excl [s[1...3]]"
