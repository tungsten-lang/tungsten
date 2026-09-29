# Integers: untyped arithmetic that crosses the i64 boundary.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "max.i64.plus [9223372036854775807 + 1]"
<< "min.i64 [-9223372036854775808]"
<< "mul.big2 [123456789012 * 987654321098]"
<< "mul.big2.type [type(123456789012 * 987654321098)]"
