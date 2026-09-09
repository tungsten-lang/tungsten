use ../lib/metaflip/fleet/refinement_worker
use ../lib/metaflip/composition/mixed_bank

if ARGV.size() == 3 && ARGV[0] == "--plans"
  raw = File.read_prefix(ARGV[1], 1048577)
  if raw == nil || raw.size() >= 1048576
    exit(1)
  parent = i64[3*512]
  costs = i64[10]
  heads = i64[512]
  axes = i64[512]
  scratch = i64[6*512]
  memo = i64[65536]
  choice = i64[65536]
  status = i64[4]
  result = StringBuffer(32768)
  lines = raw.strip().split("\n")
  row = 0 ## i64
  while row < lines.size()
    fields = lines[row].split(" ")
    if fields.size() < 12
      exit(1)
    rank = ffw_parse_decimal_i64(fields[0]) ## i64
    budget = ffw_parse_decimal_i64(fields[11]) ## i64
    if rank < 1 || rank > 512 || fields.size() != 12+3*rank
      exit(1)
    i = 0 ## i64
    while i < 10
      costs[i] = ffw_parse_decimal_i64(fields[1+i])
      i += 1
    i = 0
    while i < rank
      f = 0 ## i64
      while f < 3
        parent[f*512+i] = ffw_parse_decimal_i64(fields[12+3*i+f])
        f += 1
      i += 1
    price = ffmg_plan(parent, 3*512, 512, rank, costs, 10, heads, axes, 512, scratch, 6*512, memo, choice, 65536, status, 4, budget) ## i64
    if price < 1
      exit(1)
    result.append(price.to_s() + " " + status[0].to_s() + " " + status[1].to_s() + " " + status[2].to_s() + " " + status[3].to_s())
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
  leaves = i64[30*128]
  prices = i64[10]
  if ffmb_group_context(bank, 22*3*128, costs, 22, a, b, c, leaves, 30*128, prices, 10) != 1
    exit(1)
  heads = i64[512]
  axes = i64[512]
  plan = i64[6*512]
  memo = i64[65536]
  choice = i64[65536]
  status = i64[4]
  price = ffmg_plan(parent, 3*cap, cap, meta[3], prices, 10, heads, axes, 512, plan, 6*512, memo, choice, 65536, status, 4, budget) ## i64
  # Force a four-member group to test substitution even where pair/triple
  # ties cause the optimizer to choose another equally priced partition.
  if ARGV.size() == 10
    axis = ffw_parse_decimal_i64(ARGV[9]) ## i64
    if meta[3] != 4 || axis < 0 || axis > 2
      exit(1)
    i = 0 ## i64
    while i < 4
      heads[i] = 0
      axes[i] = axis
      i += 1
    price = prices[7+axis]
  out = i64[3*32*16384]
  rank = ffmg_compose(parent, 3*cap, cap, meta[3], meta[0], meta[1], meta[2], a, b, c, leaves, 30*128, 128, prices, 10, heads, axes, 512, out, 3*32*16384) ## i64
  n = meta[0]*a ## i64
  m = meta[1]*b ## i64
  p = meta[2]*c ## i64
  scratch = i64[32768]
  if price < 1 || rank < 1 || rank > price || ffpk_exact(out, 3*32*16384, rank, n, m, p, scratch, 32768, 0) != 1
    exit(1)
  body = StringBuffer(16384)
  body.append(price.to_s() + " " + status[0].to_s() + " " + status[1].to_s() + " " + status[2].to_s() + " " + status[3].to_s())
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
