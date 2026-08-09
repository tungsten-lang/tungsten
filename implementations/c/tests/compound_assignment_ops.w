x = 10
x &= 12
raise "stage0 &= failed" if x != 8
x |= 3
raise "stage0 |= failed" if x != 11
x ^= 2
raise "stage0 ^= failed" if x != 9
x <<= 3
raise "stage0 <<= failed" if x != 72
x >>= 2
raise "stage0 >>= failed" if x != 18

power = 3
power **= 4
raise "stage0 **= failed" if power != 81

<< "compound assignment ops: ok"
