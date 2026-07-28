# Fixed-width BitOps correctness regressions.
# Run:
#   bin/tungsten -o /tmp/bit-ops-spec spec/numeric/bit_ops_spec.w
#   /tmp/bit-ops-spec

-> check(name, got, want)
  if got != want
    raise "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

-> reference_u32(value) (u32) i64
  count = 0
  x = value
  while x != 0
    x = x & (x - 1)
    count += 1
  count

-> reference_u64(value) (u64) i64
  count = 0
  x = value
  while x != 0
    x = x & (x - 1)
    count += 1
  count

check("u32.zero", BitOps.count_ones_u32(0), 0)
check("u32.one", BitOps.count_ones_u32(1), 1)
check("u32.alternating", BitOps.count_ones_u32(0xAAAAAAAA), 16)
check("u32.high_bit", BitOps.count_ones_u32(0x80000000), 1)
check("u32.full", BitOps.count_ones_u32(0xFFFFFFFF), 32)
check("u32.mixed", BitOps.count_ones_u32(0xBF618C47), 17)

check("u64.zero", BitOps.count_ones_u64(0), 0)
check("u64.one", BitOps.count_ones_u64(1), 1)
check("u64.alternating", BitOps.count_ones_u64(0xAAAAAAAAAAAAAAAA), 32)
check("u64.high_bit", BitOps.count_ones_u64(0x8000000000000000), 1)
check("u64.full", BitOps.count_ones_u64(0xFFFFFFFFFFFFFFFF), 64)

# Deterministic differential coverage across sparse, dense, and mixed words.
x32_words = u32[1]
x32_words[0] = 0x243F6A88
i = 0
while i < 100_000
  x32_words[0] = x32_words[0] * 1664525 + 1013904223
  x32 = x32_words[0] ## u32
  check("u32.differential." + i.to_s(), BitOps.count_ones_u32(x32), reference_u32(x32))
  i += 1

x64_words = u64[1]
x64_words[0] = 0x243F6A8885A308D3
i = 0
while i < 100_000
  x64_words[0] = x64_words[0] * 6364136223846793005 + 1442695040888963407
  x64 = x64_words[0] ## u64
  check("u64.differential." + i.to_s(), BitOps.count_ones_u64(x64), reference_u64(x64))
  i += 1

<< "PASS BitOps count_ones u32/u64"
