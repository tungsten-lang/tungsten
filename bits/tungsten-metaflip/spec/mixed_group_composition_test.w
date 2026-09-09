use ../lib/metaflip/fleet/refinement_worker
use ../lib/metaflip/composition/mixed_bank

slots = 10 ## i64
if env("METAFLIP_TEST_GRIDS") == "1"
  slots = 13

if ARGV.size() == 1 && ARGV[0] == "--unit-leaves-test"
  bank = i64[22*3*128]
  prices = i64[22]
  out = i64[3*128]
  parity = i64[4096]
  n = 1 ## i64
  while n <= 16
    m = 1 ## i64
    while m <= 16
      p = 1 ## i64
      while p <= 16
        if n == 1 || m == 1 || p == 1
          out[0] = 777
          rank = ffmb_extract(bank, 22*3*128, prices, 22, n, m, p, out, 3*128, 0) ## i64
          if n*m <= 63 && m*p <= 63 && n*p <= 63
            if rank != n*m*p || ffrf_exact(out, 128, rank, n, m, p, parity) != 1
              exit(1)
          elsif rank != 0 || out[0] != 777
            exit(1)
        p += 1
      m += 1
    n += 1
  if ffmb_unit(1, 63, 1) != 1 || ffmb_unit(1, 64, 1) != 0 || ffmb_unit(0, 1, 1) != 0 || ffmb_unit(1, 1, 0-1) != 0
    exit(1)
  << "PASS unit leaves: complete naive witnesses, optional width rejection and positive-mask boundary"
  exit(0)

if ARGV.size() == 1 && ARGV[0] == "--grid-bounds-test"
  parent = i64[12]
  leaves = i64[39*128]
  prices = i64[13]
  heads = i64[4]
  axes = i64[4]
  scratch = i64[24]
  memo = i64[65536]
  choice = i64[65536]
  status = i64[7]
  out = i64[384]
  mode = 0 ## i64
  while mode < 11
    i = 0 ## i64
    while i < 13
      prices[i] = 1
      i += 1
    i = 0
    while i < 39*128
      leaves[i] = 1
      i += 1
    i = 0
    while i < 4
      parent[i] = 1 << (i/2)
      parent[4+i] = 1 << (i%2)
      parent[8+i] = 1 << i
      heads[i] = 0
      axes[i] = 3
      i += 1
    lw = 39*128 ## i64
    cw = 13 ## i64
    if mode == 0
      lw -= 1
    if mode == 1
      cw = 10
    if mode == 2
      axes[0] = 6
    if mode == 3
      parent[3] = 1
    if mode == 4
      parent[3] = 3
    if mode == 5
      parent[4+3] = 1
    if mode == 6
      heads[3] = 3
      axes[3] = 0-1
    if mode == 7
      prices[10] = 0-1
    if mode == 8
      leaves[30*128] = 0
    if mode == 9
      leaves[38*128] = 65536
    if mode == 10
      prices[12] = 129
    out[0] = 777
    if ffmg_compose(parent, 12, 4, 4, 2, 1, 2, 2, 2, 2, leaves, lw, 128, prices, cw, heads, axes, 4, out, 384) != 0-1 || out[0] != 777
      << "bad grid guard=" + mode.to_s()
      exit(1)
    mode += 1
  heads[0] = 777
  if ffmx_plan(parent, 12, 4, 4, prices, 13, heads, axes, 4, scratch, 24, memo, choice, 65536, status, 7, 50000) != 0-1 || heads[0] != 777
    exit(1)
  prices[12] = 1
  if ffmx_plan(parent, 12, 4, 4, prices, 13, heads, axes, 4, scratch, 24, memo, choice, 65536, status, 6, 50000) != 0-1 || heads[0] != 777
    exit(1)
  << "PASS grid guards"
  exit(0)

if ARGV.size() == 3 && ARGV[0] == "--plans"
  raw = File.read_prefix(ARGV[1], 1048577)
  if raw == nil || raw.size() >= 1048576
    exit(1)
  parent = i64[3*512]
  costs = i64[13]
  heads = i64[512]
  axes = i64[512]
  scratch = i64[6*512]
  memo = i64[65536]
  choice = i64[65536]
  status = i64[7]
  result = StringBuffer(32768)
  lines = raw.strip().split("\n")
  row = 0 ## i64
  while row < lines.size()
    fields = lines[row].split(" ")
    if fields.size() < slots+2
      exit(1)
    rank = ffw_parse_decimal_i64(fields[0]) ## i64
    budget = ffw_parse_decimal_i64(fields[slots+1]) ## i64
    if rank < 1 || rank > 512 || fields.size() != slots+2+3*rank
      exit(1)
    i = 0 ## i64
    while i < slots
      costs[i] = ffw_parse_decimal_i64(fields[1+i])
      i += 1
    i = 0
    while i < rank
      f = 0 ## i64
      while f < 3
        parent[f*512+i] = ffw_parse_decimal_i64(fields[slots+2+3*i+f])
        f += 1
      i += 1
    price = 0 ## i64
    if slots == 13
      price = ffmx_plan(parent, 3*512, 512, rank, costs, 13, heads, axes, 512, scratch, 6*512, memo, choice, 65536, status, 7, budget)
    else
      price = ffmg_plan(parent, 3*512, 512, rank, costs, 10, heads, axes, 512, scratch, 6*512, memo, choice, 65536, status, 4, budget)
    if price < 1
      exit(1)
    result.append(price.to_s() + " " + status[0].to_s() + " " + status[1].to_s() + " " + status[2].to_s() + " " + status[3].to_s())
    if slots == 13
      result.append(" " + status[4].to_s() + " " + status[5].to_s() + " " + status[6].to_s())
    i = 0
    while i < rank
      result.append(" " + heads[i].to_s() + " " + axes[i].to_s())
      i += 1
    result.append("\n")
    row += 1
  if !write_file(ARGV[2], result.to_s())
    exit(1)
  exit(0)

if ARGV.size() == 1 && ARGV[0] == "--bounds-test"
  parent = i64[3*8]
  leaves = i64[30*128]
  costs = i64[10]
  heads = i64[8]
  axes = i64[8]
  scratch = i64[6*8]
  memo = i64[65536]
  choice = i64[65536]
  status = i64[4]
  out = i64[384]
  mode = 0 ## i64
  while mode < 24
    i = 0 ## i64
    while i < 24
      parent[i] = 1
      i += 1
    i = 0
    while i < 30*128
      leaves[i] = 1
      i += 1
    i = 0
    while i < 10
      costs[i] = 1
      i += 1
    i = 0
    while i < 8
      heads[i] = i
      axes[i] = 0-1
      i += 1
    pw = 24 ## i64
    lw = 30*128 ## i64
    cw = 10 ## i64
    gw = 8 ## i64
    ow = 384 ## i64
    if mode == 0
      pw = 23
    if mode == 1
      lw -= 1
    if mode == 2
      cw = 9
    if mode == 3
      gw = 7
    if mode == 4
      ow = 1
    if mode == 5
      parent[0] = 0
    if mode == 6
      parent[0] = 2
    if mode == 7
      parent[0] = 0-1
    if mode == 8
      leaves[0] = 0
    if mode == 9
      leaves[0] = 16
    if mode == 10
      costs[0] = 0-1
    if mode == 11
      costs[9] = 0
    if mode == 12
      costs[9] = 129
    if mode == 13
      heads[0] = 1
    if mode == 14
      heads[7] = 0-1
    if mode == 15
      axes[0] = 3
    if mode == 16
      axes[0] = 0
    if mode == 17
      heads[1] = 0
    if mode == 18
      heads[1] = 0
      axes[0] = 0
    if mode == 19
      i = 0
      while i < 5
        heads[i] = 0
        axes[i] = 0
        i += 1
    if mode == 20
      heads[1] = 0
      heads[2] = 1
      axes[0] = 0
      axes[1] = 0
      axes[2] = 0
    if mode == 21
      i = 0
      while i < 3
        heads[i] = 0
        axes[i] = 0
        i += 1
      costs[4] = 0-1
    if mode == 22
      leaves[27*128] = 0
    if mode == 23
      heads[7] = 8
    out[0] = 777
    if ffmg_compose(parent, pw, 8, 8, 1, 1, 1, 2, 2, 2, leaves, lw, 128, costs, cw, heads, axes, gw, out, ow) != 0-1 || out[0] != 777
      << "bad compose guard=" + mode.to_s()
      exit(1)
    mode += 1
  costs[9] = 0
  heads[0] = 777
  if ffmg_plan(parent, 24, 8, 8, costs, 10, heads, axes, 8, scratch, 48, memo, choice, 65536, status, 4, 50000) != 0-1 || heads[0] != 777
    exit(1)
  costs[9] = 1
  if ffmg_plan(parent, 24, 8, 8, costs, 10, heads, axes, 8, scratch, 48, memo, choice, 65536, status, 3, 50000) != 0-1 || heads[0] != 777
    exit(1)
  << "PASS mixed group guards"
  exit(0)

if (ARGV.size() == 9 || ARGV.size() == 10) && ARGV[0] == "--compose"
  root = ARGV[1]
  cap = ffrf_capacity() ## i64
  parent = i64[3*cap]
  meta = i64[4]
  parity = i64[4096]
  bank = i64[22*3*128]
  costs = i64[22]
  temp = i64[3*128]
  if ffrf_load(root, ARGV[2], parent, cap, meta, parity) != 1 || ffmb_load_bank(root, ARGV[3], bank, 22*3*128, costs, 22, temp, parity) != 1
    exit(1)
  a = ffw_parse_decimal_i64(ARGV[4]) ## i64
  b = ffw_parse_decimal_i64(ARGV[5]) ## i64
  c = ffw_parse_decimal_i64(ARGV[6]) ## i64
  budget = ffw_parse_decimal_i64(ARGV[8]) ## i64
  leaves = i64[39*128]
  prices = i64[13]
  if slots == 13
    if ffmb_grid_context(bank, 22*3*128, costs, 22, a, b, c, leaves, 39*128, prices, 13) != 1
      exit(1)
  else
    if ffmb_group_context(bank, 22*3*128, costs, 22, a, b, c, leaves, 30*128, prices, 10) != 1
      exit(1)
  heads = i64[512]
  axes = i64[512]
  plan = i64[6*512]
  memo = i64[65536]
  choice = i64[65536]
  status = i64[7]
  price = 0 ## i64
  if slots == 13
    price = ffmx_plan(parent, 3*cap, cap, meta[3], prices, 13, heads, axes, 512, plan, 6*512, memo, choice, 65536, status, 7, budget)
  else
    price = ffmg_plan(parent, 3*cap, cap, meta[3], prices, 10, heads, axes, 512, plan, 6*512, memo, choice, 65536, status, 4, budget)
  # Force a four-member group to test substitution even where pair/triple
  # ties cause the optimizer to choose another equally priced partition.
  if ARGV.size() == 10
    axis = ffw_parse_decimal_i64(ARGV[9]) ## i64
    if meta[3] != 4 || axis < 0 || axis > slots-8
      exit(1)
    i = 0 ## i64
    while i < 4
      heads[i] = 0
      axes[i] = axis
      i += 1
    price = prices[7+axis]
  out = i64[3*32*16384]
  rank = ffmg_compose(parent, 3*cap, cap, meta[3], meta[0], meta[1], meta[2], a, b, c, leaves, 3*slots*128, 128, prices, slots, heads, axes, 512, out, 3*32*16384) ## i64
  n = meta[0]*a ## i64
  m = meta[1]*b ## i64
  p = meta[2]*c ## i64
  scratch = i64[32768]
  if price < 1 || rank < 1 || rank > price || ffpk_exact(out, 3*32*16384, rank, n, m, p, scratch, 32768, 0) != 1
    exit(1)
  body = StringBuffer(16384)
  body.append(price.to_s() + " " + status[0].to_s() + " " + status[1].to_s() + " " + status[2].to_s() + " " + status[3].to_s())
  if slots == 13
    body.append(" " + status[4].to_s() + " " + status[5].to_s() + " " + status[6].to_s())
  i = 0 ## i64
  while i < meta[3]
    body.append(" " + heads[i].to_s() + " " + axes[i].to_s())
    i += 1
  body.append("\n")
  if !write_file(ARGV[7], ffpk_blob(out, rank, n, m, p)) || !write_file(ARGV[7] + ".plan", body.to_s())
    exit(1)
  << "PASS groups price=" + price.to_s() + " rank=" + rank.to_s() + " probes=" + status[0].to_s() + " fallback=" + status[1].to_s()
  exit(0)
exit(2)
