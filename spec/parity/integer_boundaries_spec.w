# Integers across the i48 / i64 / bignum boundaries: literal typing,
# promotion on overflow, demotion, big arithmetic.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "pow47 [2**47]"
<< "pow47.type [type(2**47)]"
<< "pow47m1.type [type(2**47 - 1)]"
<< "neg47.type [type(-(2**47))]"
<< "neg47m1.type [type(-(2**47) - 1)]"
<< "pow63 [2**63]"
<< "pow63.type [type(2**63)]"
<< "pow64 [2**64]"
<< "pow100 [2**100]"
<< "shl100.type [type(1 << 100)]"
<< "promote [140_737_488_355_327 + 1]"
<< "promote.type [type(140_737_488_355_327 + 1)]"
big = 1 << 100
<< "demote.type [type(big - big)]"
<< "max.i64 [9223372036854775807]"
<< "max.i64.type [type(9223372036854775807)]"
<< "cmp.big [2**64 > 2**63]"
<< "eq.big [2**64 == 18446744073709551616]"
<< "big.sub [2**64 - 2**64]"
<< "big.div [2**100 / 2**98]"
<< "big.mod [2**100 % 7]"
<< "big.tos [(2**70).to_s]"
<< "int.tof [(2**53).to_f]"
<< "succ [(2**47 - 1).succ]"
<< "even [(2**47).even?]"
<< "mul.big [123456789 * 987654321]"
<< "fact20 [(1..20).reduce(1) ->(a, b) a * b]"
<< "fact25 [(1..25).reduce(1) ->(a, b) a * b]"
