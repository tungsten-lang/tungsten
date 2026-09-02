# Whole-corpus single-process runner for profiling: orders every pattern in
# the manifest at a reduced budget. argv: <manifest> <budget_scale_pct>
lines = File.read(ARGV[0]).split("\n")
scale = ARGV[1].to_i
total = 0
li = 0
while li < lines.size
  parts = lines[li].split("\t")
  if parts.size >= 5
    toks = File.read(parts[4]).split(" ")
    n = toks[0].to_i
    m = toks[1].to_i
    ri = []
    ci = []
    k = 0
    while k < m
      ri.push(toks[2 + 2 * k].to_i)
      ci.push(toks[3 + 2 * k].to_i)
      k += 1
    pattern = SparsePattern.new(n, n, ri, ci)
    analysis = SparseAnalysis.new(pattern)
    restarts = 600000 / m
    restarts = 48 if restarts > 48
    ils = 600000000
    ils = 1500000000 if n > 10000
    ils = ils * scale / 100
    order = analysis.best_ordering(restarts, ils, 7, nil)
    pred = analysis.predictions_for_order(order)
    total += pred[1]
    << parts[1] + " " + pred[1].to_s
  li += 1
<< "suite total flops " + total.to_s
Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
