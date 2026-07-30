# Focused fixed-width popcount benchmark.
#
# Build:
#   bin/tungsten -o /tmp/count-ones-bench benchmarks/bit_ops/count_ones.w
#
# Run:
#   /tmp/count-ones-bench u32 mixed bitops 10000000
#   /tmp/count-ones-bench u32 mixed kernighan 10000000
#
# Output is RESULT|case|nanoseconds-per-word|checksum.  Compare implementations
# only when width, density, and iteration count are identical.

use ../../core/bit_ops

WORD_COUNT = 4096
WORD_MASK = WORD_COUNT - 1

-> kernighan_u32(value) (u32) i64
  count = 0
  x = value
  while x != 0
    x = x & (x - 1)
    count += 1
  count

-> kernighan_u64(value) (u64) i64
  count = 0
  x = value
  while x != 0
    x = x & (x - 1)
    count += 1
  count

-> build_u32(density)
  words = u32[WORD_COUNT]
  state = u32[1]
  state[0] = 0x243F6A88
  i = 0
  while i < WORD_COUNT
    state[0] = state[0] * 1664525 + 1013904223
    if density == "sparse"
      words[i] = 1 << (state[0] & 31)
    elsif density == "dense"
      words[i] = 0xFFFFFFFF ^ (1 << (state[0] & 31))
    else
      words[i] = state[0]
    i += 1
  words

-> build_u64(density)
  words = u64[WORD_COUNT]
  state = u64[1]
  state[0] = 0x243F6A8885A308D3
  i = 0
  while i < WORD_COUNT
    state[0] = state[0] * 6364136223846793005 + 1442695040888963407
    if density == "sparse"
      words[i] = (1 ## u64) << (state[0] & 63)
    elsif density == "dense"
      words[i] = (0xFFFFFFFFFFFFFFFF ## u64) ^ ((1 ## u64) << (state[0] & 63))
    else
      words[i] = state[0]
    i += 1
  words

-> time_u32(words, implementation, iterations)
  checksum = 0
  i = 0
  started = clock()
  if implementation == "bitops" || implementation == "swar"
    while i < iterations
      checksum += BitOps.count_ones_u32(words[i & WORD_MASK])
      i += 1
  else
    while i < iterations
      checksum += kernighan_u32(words[i & WORD_MASK])
      i += 1
  [clock() - started, checksum]

-> time_u64(words, implementation, iterations)
  checksum = 0
  i = 0
  started = clock()
  if implementation == "bitops" || implementation == "swar"
    while i < iterations
      checksum += BitOps.count_ones_u64(words[i & WORD_MASK])
      i += 1
  else
    while i < iterations
      checksum += kernighan_u64(words[i & WORD_MASK])
      i += 1
  [clock() - started, checksum]

args = argv()
width = args.size > 0 ? args[0] : "u32"
density = args.size > 1 ? args[1] : "mixed"
implementation = args.size > 2 ? args[2] : "bitops"
iterations = args.size > 3 ? args[3].to_i : 10_000_000

if width != "u32" && width != "u64"
  raise "width must be u32 or u64"
if density != "sparse" && density != "mixed" && density != "dense"
  raise "density must be sparse, mixed, or dense"
if implementation != "bitops" && implementation != "swar" && implementation != "kernighan"
  raise "implementation must be bitops or kernighan"
if iterations <= 0
  raise "iterations must be positive"

# Untimed warmup forces both the loader and the selected compiled path hot.
warmup_iterations = iterations < 100_000 ? iterations : 100_000
if width == "u32"
  words = build_u32(density)
  time_u32(words, implementation, warmup_iterations)
  result = time_u32(words, implementation, iterations)
else
  words = build_u64(density)
  time_u64(words, implementation, warmup_iterations)
  result = time_u64(words, implementation, iterations)

ns = result[0] * 1_000_000_000 / iterations
<< "RESULT|[width].[density].[implementation]|[ns]|[result[1]]"
