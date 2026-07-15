# Regression: indexing a generic portfolio erases the static element type of
# the contained i64[].  Its subsequent dynamic `[]` therefore returns a boxed
# Integer.  Values outside the immediate i48 range are heap BigInts; storing
# that value into another i64[] must convert the Integer, never copy its WValue
# (heap-pointer) bits into the raw slot.

positive = 281474976710779 ## i64
negative = 0 - positive ## i64
immediate = 140737488355327 ## i64

seed = i64[3]
seed[0] = positive
seed[1] = negative
seed[2] = immediate

portfolio = []
portfolio.push(seed)
source = portfolio[0]

uploaded = i64[3]
uploaded[0] = source[0]
uploaded[1] = source[1]
uploaded[2] = source[2]

# The fused typed-array compound-store path crosses the same boxed boundary.
accumulator = i64[1]
accumulator[0] = 1
accumulator[0] += source[0]

# u64[] needs the unsigned conversion boundary so values above INT64_MAX keep
# their full bit pattern rather than passing through signed conversion.
wide = 18446744073709551615 ## u64
unsigned_seed = u64[1]
unsigned_seed[0] = wide
portfolio.push(unsigned_seed)
unsigned_source = portfolio[1]
unsigned_uploaded = u64[1]
unsigned_uploaded[0] = unsigned_source[0]

if uploaded[0] != positive
  << "FAIL nested i64[] positive got=" + uploaded[0].to_s()
  exit(1)
if uploaded[1] != negative
  << "FAIL nested i64[] negative got=" + uploaded[1].to_s()
  exit(1)
if uploaded[2] != immediate
  << "FAIL nested i64[] immediate got=" + uploaded[2].to_s()
  exit(1)
if accumulator[0] != positive + 1
  << "FAIL nested i64[] compound got=" + accumulator[0].to_s()
  exit(1)
if unsigned_uploaded[0] != wide
  << "FAIL nested u64[] positive got=" + unsigned_uploaded[0].to_s()
  exit(1)

<< "PASS nested i64[] boxed store"
