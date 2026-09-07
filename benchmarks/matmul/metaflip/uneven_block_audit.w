# Offline exact comparison using the existing uneven-block composer. The
# minimum-formula tie search is not an exhaustive tensor-rank optimizer.
use flipfleet_block_composer

if ARGV.size() != 7 && ARGV.size() != 9
  << "usage: uneven-audit OUTER N M P LEAVES TARGETS OUTDIR (optional: MIN MAX)"
  exit(2)
bounded = ARGV.size() == 9
minimum = 1 ## i64
maximum = 16 ## i64
if bounded
  minimum = ARGV[7].to_i()
  maximum = ARGV[8].to_i()
  if minimum < 0 || maximum < minimum || maximum > 16
    << "invalid allocation bounds"
    exit(2)
outer = ffbc_load_exact(ARGV[0], ARGV[1].to_i(), ARGV[2].to_i(), ARGV[3].to_i(), 4096)
if outer == nil
  << "invalid outer"
  exit(1)
leaftext = read_file(ARGV[4])
targettext = read_file(ARGV[5])
if leaftext == nil || targettext == nil
  << "missing manifest"
  exit(2)
leaves = []
leaflines = leaftext.strip().split("\n")
i = 0 ## i64
while i < leaflines.size()
  f = leaflines[i].split(" ")
  if f.size() != 4
    exit(2)
  leaf = ffbc_load_exact(f[0], f[1].to_i(), f[2].to_i(), f[3].to_i(), 4096)
  if leaf == nil
    << "invalid leaf " + f[0]
    exit(1)
  leaves.push(leaf)
  i += 1
if bounded
  # A missing leaf must not silently turn an exhaustive allocation scan
  # into a scan of an unspecified covered subset.
  prices = ffbc_leaf_rank_table(leaves, maximum)
  stride = maximum + 1 ## i64
  n = 1 ## i64
  while n <= maximum
    m = 1 ## i64
    while m <= maximum
      p = 1 ## i64
      while p <= maximum
        if prices[(n * stride + m) * stride + p] < 0
          << "missing bounded leaf " + n.to_s() + "x" + m.to_s() + "x" + p.to_s()
          exit(2)
        p += 1
      m += 1
    n += 1
targetlines = targettext.strip().split("\n")
i = 0
while i < targetlines.size()
  line = targetlines[i]
  f = line.split("x")
  if f.size() != 3
    exit(2)
  n = f[0].to_i() ## i64
  m = f[1].to_i() ## i64
  p = f[2].to_i() ## i64
  if n < 1 || m < 1 || p < 1 || n > 32 || m > 32 || p > 32
    << "target outside bounded audit"
    exit(2)
  active_leaves = leaves
  if !bounded
    # No balanced block can exceed ceil(max target axis / min outer axis),
    # in any S3 orientation. Removing larger leaves preserves every lookup
    # and its tie order, and avoids re-verifying unreachable leaves for each
    # minimum-formula materialisation. The exact composer is unchanged.
    largest = n ## i64
    if m > largest
      largest = m
    if p > largest
      largest = p
    parts = outer.n() ## i64
    if outer.m() < parts
      parts = outer.m()
    if outer.p() < parts
      parts = outer.p()
    leaf_cap = (largest + parts - 1) / parts ## i64
    active_leaves = []
    li = 0 ## i64
    while li < leaves.size()
      leaf = leaves[li]
      if leaf.n() <= leaf_cap && leaf.m() <= leaf_cap && leaf.p() <= leaf_cap
        active_leaves.push(leaf)
      li += 1
  path = ARGV[6] + "/" + line + ".txt"
  if read_file(path) != nil
    << "refusing output overwrite"
    exit(2)
  t0 = ccall("__w_clock_ms") ## i64
  recipe = nil
  if bounded
    recipe = ffbc_best_oriented_bounded_recipe(outer,n,m,p,minimum,maximum,active_leaves)
  else
    recipe = ffbc_best_exact_oriented_balanced_recipe(outer,n,m,p,active_leaves)
  if recipe == nil
    << "no covered allocation " + line
    exit(1)
  scheme = ffbc_compose_oriented_recipe(outer,n,m,p,active_leaves,recipe)
  if scheme == nil || scheme.rank() > recipe[3]
    << "inexact allocation " + line
    exit(1)
  if !bounded && scheme.rank() != recipe[8]
    << "balanced exact-rank mismatch " + line
    exit(1)
  if ffbc_write(path,scheme) != scheme.rank()
    exit(1)
  elapsed = ccall("__w_clock_ms") - t0 ## i64
  selection = "min-exact-formula-ties"
  if bounded
    selection = "first-formula-min"
  << "UNEVEN shape=" + line + " formula=" + recipe[3].to_s() + " exact=" + scheme.rank().to_s() + " source=" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + " orientation=" + recipe[7].to_s() + " alloc_n=" + recipe[0].join(",") + " alloc_m=" + recipe[1].join(",") + " alloc_p=" + recipe[2].join(",") + " selection=" + selection + " minimum=" + minimum.to_s() + " maximum=" + maximum.to_s() + " leaf_pool=" + active_leaves.size().to_s() + " elapsed_ms=" + elapsed.to_s()
  i += 1
