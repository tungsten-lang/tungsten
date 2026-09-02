# Scalar Tungsten loop versus the fused native u32 bitset row kernel.
#
#   bin/tungsten compile --release --native --out /tmp/u32-bitset \
#     benchmarks/runtime/u32_bitset_kernel_bench.w
#   /tmp/u32-bitset scalar 1024 256 100
#   /tmp/u32-bitset native 1024 256 100
#   /tmp/u32-bitset raw 1024 256 100

-> scalar_andnot_count(a, aoff, b, boff, words) (u32[] i64 u32[] i64 i64) i64
  total = 0 ## i64
  i = 0 ## i64
  while i < words
    total += popcount(a[aoff + i] & (0xffffffff ^ b[boff + i]))
    i += 1
  total

mode = ARGV[0] == nil ? "native" : ARGV[0]
words = ARGV[1] == nil ? 1024 : ARGV[1].to_i
rows = ARGV[2] == nil ? 256 : ARGV[2].to_i
reps = ARGV[3] == nil ? 100 : ARGV[3].to_i

a = u32[words * rows]
b = u32[words * rows]
state = 104729 ## i64
i = 0
while i < words * rows
  state = (state * 48271) % 2147483647
  a[i] = state
  state = (state * 48271) % 2147483647
  b[i] = state
  i += 1

checksum = 0 ## i64
t0 = clock()
r = 0
while r < reps
  row = 0
  while row < rows
    off = row * words
    if mode == "scalar"
      checksum += scalar_andnot_count(a, off, b, off, words)
    elsif mode == "native"
      checksum += ccall("__w_u32_andnot_count", a, off, b, off, words)
    elsif mode == "raw"
      checksum += ccall_nobox("__w_u32_andnot_count_raw", a, off, b, off, words)
    else
      raise "mode must be scalar, native, or raw"
    row += 1
  r += 1
t1 = clock()

ns = (t1 - t0) * ~1000000000.0 / reps
line = "BENCH u32_bitset mode=" + mode
line += " words=" + words.to_s
line += " rows=" + rows.to_s
line += " reps=" + reps.to_s
line += " ns_per_sweep=" + ns.round(1).to_s
line += " ns_per_word=" + (ns / (words * rows)).to_s
line += " checksum=" + checksum.to_s
<< line
