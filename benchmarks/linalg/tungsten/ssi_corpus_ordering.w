# Run Tungsten's sparse-ordering portfolio on one SSI challenge pattern.
#
# Input format: n nnz row0 col0 row1 col1 ...

use core/sparse

path = ARGV[0]
raise "usage: ssi_corpus_ordering PATTERN.txt [stream] [budget] [restarts]" if path == nil

toks = File.read(path).split(" ")
raise "pattern header is incomplete" if toks.size < 2
n = toks[0].to_i
m = toks[1].to_i
raise "pattern dimensions must be non-negative" if n < 0 || m < 0
raise "pattern entry count does not match header" if toks.size != 2 + 2 * m

ri = []
ci = []
k = 0
while k < m
  ri.push(toks[2 + 2 * k].to_i)
  ci.push(toks[3 + 2 * k].to_i)
  k += 1

stream = ARGV.size > 1 ? ARGV[1].to_i : 7
budget = ARGV.size > 2 ? ARGV[2].to_i : 100000000
raise "budget must be non-negative" if budget < 0

restarts = m == 0 ? 1 : 600000 / m
restarts = 48 if restarts > 48
restarts = 1 if restarts < 1
restarts = ARGV[3].to_i if ARGV.size > 3
raise "restarts must be positive" if restarts < 1

pattern = SparsePattern.new(n, n, ri, ci)
analysis = SparseAnalysis.new(pattern)

t0 = clock()
order = analysis.best_ordering(restarts, budget, stream)
t1 = clock()

raise "ordering length does not match pattern" if order.size != n
seen = u32[n]
checksum = 0
k = 0
while k < n
  v = order[k]
  raise "ordering entry out of range" if v < 0 || v >= n
  raise "ordering contains a duplicate" if seen[v] != 0
  seen[v] = 1
  checksum = (checksum + (k + 1) * (v + 1)) % 1000000007
  k += 1

pred = analysis.predictions_for_order(order)
ns = (t1 - t0) * ~1000000000.0
line = "BENCH ssi_corpus_ordering"
line += " n=" + n.to_s
line += " nnz=" + m.to_s
line += " restarts=" + restarts.to_s
line += " stream=" + stream.to_s
line += " budget=" + budget.to_s
line += " ns=" + ns.round(1).to_s
line += " fill=" + pred[0].to_s
line += " flops=" + pred[1].to_s
line += " checksum=" + checksum.to_s
<< line
