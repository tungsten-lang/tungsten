# SSI-derived sparse-ordering candidate benchmark.
#
# One binary exposes each candidate as a separate lane.  Every lane starts
# from the same immutable pattern, validates its permutation, and reports the
# exact symbolic fill/flop prediction beside quotient-graph AMD.  Run modes in
# fresh processes and alternate their order for matched timing.
#
#   bin/tungsten compile --release --native \
#     --out /tmp/ssi_ordering_campaign \
#     benchmarks/linalg/tungsten/ssi_ordering_campaign.w
#   /tmp/ssi_ordering_campaign amd grid 30 1 20000000
#   /tmp/ssi_ordering_campaign minl grid 30 1 20000000
#
# Families:
#   grid SIZE       SIZE x SIZE five-point grid
#   band SIZE       SIZE vertices, deterministic half-bandwidth 6
#   arrow SIZE      path with two dense hub vertices
#   blocks SIZE     four disconnected SIZE x SIZE grids
#   bridge SIZE     two SIZE x SIZE grids joined by one bridge edge
#   twins SIZE      chain of SIZE eight-vertex cliques (supervariables)
#   shell SIZE      32-vertex core with SIZE live-degree-three shell vertices
#   random SIZE     deterministic sparse graph, about six edges/vertex
#
# Modes:
#   natural scan heap amd amd_alpha1 amd_alpha5 amd_alpha16 amd_nodense
#   amd_nonagg amd_nonagg_nodense amd_fifo amf amf_nodense game nd levelset rcm
#   sloan21 sloan12 predcorr
#   supervar rgreedy minl minl_alt window8 window10 telos rgsub
#   pair descent anneal best0 best best_diverse best0_alpha best_alpha

use core/sparse

-> edge(ri, ci, a, b)
  if a != b
    ri.push(a)
    ci.push(b)

-> grid_pattern(g, copies = 1)
  one = g * g
  n = one * copies
  ri = []
  ci = []
  copy = 0
  while copy < copies
    base = copy * one
    i = 0
    while i < one
      row = i / g
      col = i % g
      edge(ri, ci, base + i, base + i + 1) if col + 1 < g
      edge(ri, ci, base + i, base + i + g) if row + 1 < g
      i += 1
    copy += 1
  [n, ri, ci]

-> band_pattern(n)
  ri = []
  ci = []
  i = 0
  while i < n
    d = 1
    while d <= 6 && i + d < n
      edge(ri, ci, i, i + d)
      d += 1
    i += 1
  [n, ri, ci]

-> arrow_pattern(n)
  ri = []
  ci = []
  i = 0
  while i + 1 < n
    edge(ri, ci, i, i + 1)
    i += 1
  h1 = n - 1
  h2 = n - 2
  i = 0
  while i + 2 < n
    edge(ri, ci, i, h1)
    edge(ri, ci, i, h2) if (i & 1) == 0
    i += 1
  [n, ri, ci]

-> bridge_pattern(g)
  data = grid_pattern(g, 2)
  n = data[0]
  ri = data[1]
  ci = data[2]
  edge(ri, ci, g * g - 1, g * g)
  [n, ri, ci]

-> twins_pattern(groups)
  width = 8
  n = groups * width
  ri = []
  ci = []
  g = 0
  while g < groups
    base = g * width
    i = 0
    while i < width
      j = i + 1
      while j < width
        edge(ri, ci, base + i, base + j)
        j += 1
      i += 1
    if g > 0
      # Complete join of neighboring cliques preserves identical closed
      # neighborhoods within each clique.
      i = 0
      while i < width
        j = 0
        while j < width
          edge(ri, ci, base - width + i, base + j)
          j += 1
        i += 1
    g += 1
  [n, ri, ci]

-> shell_pattern(shell_n)
  core = 32
  n = core + shell_n
  ri = []
  ci = []
  i = 0
  while i < core
    j = i + 1
    while j < core
      edge(ri, ci, i, j)
      j += 1
    i += 1
  i = 0
  while i < shell_n
    v = core + i
    edge(ri, ci, v, i % core)
    edge(ri, ci, v, (i * 5 + 1) % core)
    edge(ri, ci, v, (i * 11 + 3) % core)
    i += 1
  [n, ri, ci]

-> random_pattern(n)
  ri = []
  ci = []
  state = 104729
  i = 0
  while i < n
    d = 0
    while d < 6
      state = (state * 48271) % 2147483647
      j = state % n
      j = (j + 1) % n if j == i
      if i < j
        edge(ri, ci, i, j)
      else
        edge(ri, ci, j, i)
      d += 1
    i += 1
  [n, ri, ci]

-> build_pattern(family, size)
  if family == "grid"
    grid_pattern(size)
  elsif family == "band"
    band_pattern(size)
  elsif family == "arrow"
    arrow_pattern(size)
  elsif family == "blocks"
    grid_pattern(size, 4)
  elsif family == "bridge"
    bridge_pattern(size)
  elsif family == "twins"
    twins_pattern(size)
  elsif family == "shell"
    shell_pattern(size)
  elsif family == "random"
    random_pattern(size)
  else
    raise "family must be grid, band, arrow, blocks, bridge, twins, shell, or random"

-> natural_order(n)
  out = []
  i = 0
  while i < n
    out.push(i)
    i += 1
  out

-> best_supervar(analysis, fallback)
  variants = analysis.supervar_orders(
    analysis.pattern.rows, analysis.typed_ri, analysis.typed_ci,
    analysis.pattern.nnz)
  best = fallback
  bestp = analysis.predictions_for_order(best)
  i = 0
  while i < variants.size
    pred = analysis.predictions_for_order(variants[i])
    if pred[1] < bestp[1] || (pred[1] == bestp[1] && pred[0] < bestp[0])
      best = variants[i]
      bestp = pred
    i += 1
  best

-> candidate(analysis, mode, budget, stream)
  n = analysis.pattern.rows
  ri = analysis.typed_ri
  ci = analysis.typed_ci
  m = analysis.pattern.nnz
  # These graph-profile candidates are independent of the AMD seed.  Keep
  # their isolated lane free of an unreported AMD recomputation so fresh-
  # process timings measure the candidate itself.
  return analysis.rcm_ordering if mode == "rcm"
  return analysis.sloan_ordering(2, 1) if mode == "sloan21"
  return analysis.sloan_ordering(1, 2) if mode == "sloan12"
  seed = analysis.min_degree_ordering
  sp = analysis.predictions_for_order(seed)
  if mode == "natural"
    natural_order(n)
  elsif mode == "scan"
    analysis.min_degree_ordering_scan
  elsif mode == "heap"
    analysis.min_degree_ordering_heap
  elsif mode == "amd"
    seed
  elsif mode == "amd_alpha1"
    analysis.amd_core(n, ri, ci, m, 1)
  elsif mode == "amd_alpha5"
    analysis.amd_core(n, ri, ci, m, 5)
  elsif mode == "amd_alpha16"
    analysis.amd_core(n, ri, ci, m, 16)
  elsif mode == "amd_nodense"
    analysis.amd_core(n, ri, ci, m, 0 - 1)
  elsif mode == "amd_nonagg"
    analysis.amd_core(n, ri, ci, m, 10, 0)
  elsif mode == "amd_nonagg_nodense"
    analysis.amd_core(n, ri, ci, m, 0 - 1, 0)
  elsif mode == "amd_fifo"
    analysis.amd_core(n, ri, ci, m, 10, 1, 1)
  elsif mode == "amf"
    analysis.amf_core(n, ri, ci, m, 25)
  elsif mode == "amf_nodense"
    analysis.amf_core(n, ri, ci, m, 0 - 1)
  elsif mode == "game"
    analysis.game_ordering_of(ri, ci, m)
  elsif mode == "nd"
    analysis.nd_ordering_of(n, ri, ci, m)
  elsif mode == "levelset"
    analysis.nd_levelset_of(n, ri, ci, m)
  elsif mode == "predcorr"
    analysis.predcorr_ordering_of(n, ri, ci, m, budget)
  elsif mode == "supervar"
    best_supervar(analysis, seed)
  elsif mode == "rgreedy"
    analysis.rgreedy_refine(n, ri, ci, m, seed, sp[1], budget, stream)[0]
  elsif mode == "minl"
    analysis.minl_descent(seed, sp[1], budget)[0]
  elsif mode == "minl_alt"
    analysis.minl_descent(seed, sp[1], budget, 1)[0]
  elsif mode == "window8"
    analysis.window_dp(seed, sp[1], 8, budget)[0]
  elsif mode == "window10"
    analysis.window_dp(seed, sp[1], 10, budget)[0]
  elsif mode == "telos"
    analysis.telos_descent(seed, sp[1], 6)[0]
  elsif mode == "rgsub"
    analysis.rgsub_refine(seed, budget, stream)[0]
  elsif mode == "descent"
    analysis.order_descent(seed, sp[1], budget, stream)[0]
  elsif mode == "pair"
    analysis.order_descent(seed, sp[1], budget, stream, 0)[0]
  elsif mode == "anneal"
    analysis.anneal_refine(seed, sp[1], budget, stream)[0]
  elsif mode == "best0"
    analysis.best_ordering(12, 0, stream)
  elsif mode == "best"
    analysis.best_ordering(12, budget, stream)
  elsif mode == "best_diverse"
    analysis.best_ordering(12, budget, stream, nil, 1)
  elsif mode == "best0_alpha"
    analysis.best_ordering(12, 0, stream, nil, 0, 1)
  elsif mode == "best_alpha"
    analysis.best_ordering(12, budget, stream, nil, 0, 1)
  else
    raise "unknown candidate mode"

-> validate_permutation(order, n)
  return false if order.size != n
  seen = u32[n]
  i = 0
  while i < n
    v = order[i]
    return false if v < 0 || v >= n || seen[v] != 0
    seen[v] = 1
    i += 1
  true

mode = ARGV[0] == nil ? "amd" : ARGV[0]
family = ARGV[1] == nil ? "grid" : ARGV[1]
size = ARGV[2] == nil ? 30 : ARGV[2].to_i
reps = ARGV[3] == nil ? 1 : ARGV[3].to_i
budget = ARGV[4] == nil ? 20000000 : ARGV[4].to_i
stream = ARGV[5] == nil ? 0 : ARGV[5].to_i

data = build_pattern(family, size)
n = data[0]
pattern = SparsePattern.new(n, n, data[1], data[2])
analysis = SparseAnalysis.new(pattern)
amd = analysis.min_degree_ordering
amd_pred = analysis.predictions_for_order(amd)

result = nil
t0 = clock()
r = 0
while r < reps
  result = candidate(analysis, mode, budget, stream)
  r += 1
t1 = clock()
raise "candidate returned a non-permutation" if !validate_permutation(result, n)
pred = analysis.predictions_for_order(result)
checksum = 0
i = 0
while i < n
  checksum = (checksum + (i + 1) * (result[i] + 1)) % 1000000007
  i += 1
ratio = (pred[1] + ~0.0) / (amd_pred[1] + ~0.0)
ratio_ppm = pred[1] * 1000000 / amd_pred[1]
ns = (t1 - t0) * ~1000000000.0 / reps
line = "BENCH ssi_ordering mode=" + mode
line += " family=" + family
line += " size=" + size.to_s
line += " n=" + n.to_s
line += " nnz=" + pattern.nnz.to_s
line += " reps=" + reps.to_s
line += " ns=" + ns.round(1).to_s
line += " fill=" + pred[0].to_s
line += " flops=" + pred[1].to_s
line += " amd_fill=" + amd_pred[0].to_s
line += " amd_flops=" + amd_pred[1].to_s
line += " flop_ratio=" + ratio.to_s
line += " flop_ppm=" + ratio_ppm.to_s
line += " checksum=" + checksum.to_s
<< line
