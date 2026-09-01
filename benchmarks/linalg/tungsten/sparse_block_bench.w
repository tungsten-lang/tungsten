# SparseBlockFactor scheduling and retained-scratch crossover benchmark.
#
#   /tmp/sparse_block_bench auto 8 30 100
#   /tmp/sparse_block_bench sequential 8 30 100
#   /tmp/sparse_block_bench parallel 8 30 100

use core/sparse

mode = ARGV[0] == nil ? "auto" : ARGV[0]
blocks = ARGV[1] == nil ? 8 : ARGV[1].to_i
g = ARGV[2] == nil ? 30 : ARGV[2].to_i
reps = ARGV[3] == nil ? 100 : ARGV[3].to_i
bn = g * g
n = blocks * bn
ri = []
ci = []
vv = []
blk = 0
while blk < blocks
  base = blk * bn
  i = 0
  while i < bn
    ri.push(base + i)
    ci.push(base + i)
    vv.push(~4.0 + blk * ~0.125)
    row = i / g
    col = i % g
    if col + 1 < g
      ri.push(base + i)
      ci.push(base + i + 1)
      vv.push(~-1.0)
    if row + 1 < g
      ri.push(base + i)
      ci.push(base + i + g)
      vv.push(~-1.0)
    i += 1
  blk += 1

pattern = SparsePattern.new(n, n, ri, ci)
b = []
i = 0
while i < n
  b.push(~1.0 + (i % 11) * ~0.0625)
  i += 1
force = nil
force = false if mode == "sequential"
force = true if mode == "parallel"
raise "mode must be auto, sequential, or parallel" if mode != "auto" && force == nil

t0 = clock()
factor = SparseBlockFactor.new(pattern, vv, force)
t1 = clock()
out = ccall("w_array_new_aligned", -64, n)
k = 0
while k < reps
  factor.solve_into(b, out)
  k += 1
t2 = clock()
checksum = ~0.0
i = 0
while i < n
  checksum += out[i] * (i % 17 + 1)
  i += 1
<< "BENCH sparse_block mode=" + mode + " actual_parallel=" + factor.parallel.to_s + " blocks=" + blocks.to_s + " g=" + g.to_s + " n=" + n.to_s + " nnz=" + pattern.nnz.to_s + " factor_ms=" + ((t1 - t0) * ~1000.0).round(3).to_s + " solve_us=" + ((t2 - t1) * ~1000000.0 / reps).round(1).to_s + " checksum=" + checksum.round(4).to_s
factor.release
