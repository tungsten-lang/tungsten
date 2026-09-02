# Exact symbolic fill/flop reduction: Tungsten loop and pair/scalar native lanes.

-> scalar_score(counts)
  fill = 0
  flops = 0
  i = 0
  while i < counts.size
    c = counts[i]
    fill += c
    flops += c * c
    i += 1
  [fill, flops]

mode = ARGV[0] == nil ? "native" : ARGV[0]
n = ARGV[1] == nil ? 100000 : ARGV[1].to_i
reps = ARGV[2] == nil ? 100 : ARGV[2].to_i
counts = u32[n]
i = 0
while i < n
  counts[i] = 1 + ((i * 48271 + 104729) % 2048)
  i += 1

checksum = 0
t0 = clock()
r = 0
if mode == "scalar"
  while r < reps
    score = scalar_score(counts)
    checksum += score[0] + score[1]
    r += 1
elsif mode == "native"
  while r < reps
    score = ccall("__w_u32_fill_flops", counts)
    checksum += score[0] + score[1]
    r += 1
elsif mode == "pair"
  while r < reps
    score = ccall("__w_u32_fill_flops", counts)
    checksum += score[1]
    r += 1
elsif mode == "flops"
  while r < reps
    checksum += ccall("__w_u32_flops", counts)
    r += 1
else
  raise "mode must be scalar, native, pair, or flops"
t1 = clock()

ns = (t1 - t0) * ~1000000000.0 / reps
line = "BENCH u32_score mode=" + mode
line += " n=" + n.to_s
line += " reps=" + reps.to_s
line += " ns=" + ns.round(1).to_s
line += " checksum=" + checksum.to_s
<< line
