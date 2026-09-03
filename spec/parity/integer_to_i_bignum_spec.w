## parity xfail String#to_i past i64 promotes to a bignum, but the compiled conversion lowers to a raw i64 and inference types it :i64, so the following arithmetic unboxes the bignum as machine bits (7766279631452241920 for 10^20 + 1); the interpreter promotes
# Known divergence pinned so it cannot regress silently: fix by lowering
# String#to_i to a boxed, promotable result and typing it :int.
s = "99999999999999999999"
x = s.to_i
<< "to_i.plus [x + 1]"
<< "to_i.times [x * 2]"
<< "to_i.chain [s.to_i * 3]"
