# String#to_i past i64 is a BigInt, and the following arithmetic promotes.
# A known String receiver is typed :int so the compiled path does not
# unbox the heap value as a machine int.
#
# Cross-engine parity spec (scripts/parity.sh).
s = "99999999999999999999"
x = s.to_i
<< "to_i.plus [x + 1]"
<< "to_i.times [x * 2]"
<< "to_i.chain [s.to_i * 3]"
