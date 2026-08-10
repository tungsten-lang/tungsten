max = 18446744073709551615 ## u64
high = 9223372036854775808 ## u64

if (mulhi(max, max) ## u64) != (18446744073709551614 ## u64)
  << "FAIL mulhi max*max"
  exit(1)
if (mulhi(high, 2 ## u64) ## u64) != (1 ## u64)
  << "FAIL mulhi high*2"
  exit(1)
if (mulhi(123, 456) ## u64) != (0 ## u64)
  << "FAIL mulhi low product"
  exit(1)
if (addcarry(max, 1 ## u64) ## u64) != (1 ## u64)
  << "FAIL addcarry overflow"
  exit(1)
if (addcarry(high, 1 ## u64) ## u64) != (0 ## u64)
  << "FAIL addcarry no overflow"
  exit(1)
if (subborrow(0 ## u64, 1 ## u64) ## u64) != (1 ## u64)
  << "FAIL subborrow borrowed"
  exit(1)
if (subborrow(max, high) ## u64) != (0 ## u64)
  << "FAIL subborrow no borrow"
  exit(1)

<< "PASS carry intrinsic parity"
