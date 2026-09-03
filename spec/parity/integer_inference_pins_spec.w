# Pins for inference decisions that once produced silent wrong numbers in
# compiled code (see the evidence policy at the top of
# compiler/lib/lowering/inference.w). Every line must agree with the
# interpreter, which has no inference at all.

big = 2 ** 607 - 1
<< "pow.minus.digits [big.to_s.size]"
<< "shl.plus [(1 << 200) + 999]"
wide = 12345678901234567890123456789012345678901234567890123456789012345678901234567
<< "neg.wide.times [(0 - wide) * 3]"
<< "min.literal [-9223372036854775808]"
