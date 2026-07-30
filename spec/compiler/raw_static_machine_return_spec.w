# Regression for raw machine-returning static calls feeding unhinted locals.
# The u64 parameter and i64 return deliberately differ: the call consumes a raw
# unsigned word but its result is a raw signed index, matching BitOps'
# trailing-zero helpers.

+ RawStaticMachineReturnProbe
  -> .scan(_value) (u64) i64
    1

+ RawStaticBoxedReturnProbe
  # A raw parameter makes the call use the raw-argument ABI, but a `bool`
  # result is still a boxed WValue and must not prove local rawness.
  -> .scan(_value) (u64) bool
    true

+ RawStaticUnsignedReturnProbe
  -> .identity(value) (u64) u64
    value

# None of these locals needs an inline `## i64` hint. Exact static-call ABI
# analysis retains `bit` in the raw candidate fixed point, which in turn keeps
# position/best/next_position in native slots.
-> raw_static_machine_selector(remaining, seed) (u16[] u64) i64
  best = 65536
  next_position = 0 - 1
  word = 0
  bit = RawStaticMachineReturnProbe.scan(seed)
  position = word * 63 + bit
  if remaining[position] < best
    best = remaining[position]
    next_position = position
  next_position

-> raw_static_boxed_return(seed) (u64) bool
  result = RawStaticBoxedReturnProbe.scan(seed)
  result

-> raw_static_unsigned_roundtrip(seed) (u64) u64
  result = RawStaticUnsignedReturnProbe.identity(seed)
  result

values = u16[2]
values[1] = 7
seeds = u64[1]
seeds[0] = 8
got = raw_static_machine_selector(values, seeds[0])
if got != 1
  << "FAIL raw static machine return: got " + got.to_s()
  exit(1)

boxed_got = raw_static_boxed_return(seeds[0])
if boxed_got != true
  << "FAIL raw static boxed return: got " + boxed_got.to_s()
  exit(1)

# Keep this above SmallArray's 255-slot stack-promotion limit.  That separate
# path currently nanboxes a high-bit u64 element as a signed small integer,
# which would test SmallArray boxing rather than this call boundary.
unsigned_values = u64[256]
unsigned_values[0] = 18446744073709551615
unsigned_got = raw_static_unsigned_roundtrip(unsigned_values[0])
if unsigned_got != unsigned_values[0]
  << "FAIL raw static unsigned return: got " + unsigned_got.to_s()
  exit(1)

<< "PASS raw static machine return"
