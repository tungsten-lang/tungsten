use ../lib/metaflip/fleet/refinement_worker
use ../lib/metaflip/composition/mixed_bank

if ARGV.size() == 3 && ARGV[0] == "--plans"
  raw = File.read_prefix(ARGV[1], 1048577)
  if raw == nil || raw.size() >= 1048576
    exit(1)
  parent = i64[3*512]
  costs = i64[4]
  mates = i64[512]
  axes = i64[512]
  scratch = i64[6*512]
  memo = i64[65536]
  choice = i64[65536]
  status = i64[3]
  result = StringBuffer(32768)
  lines = raw.strip().split("\n")
  row = 0 ## i64
  while row < lines.size()
    fields = lines[row].split(" ")
    if fields.size() < 6
      exit(1)
    rank = ffw_parse_decimal_i64(fields[0]) ## i64
    budget = ffw_parse_decimal_i64(fields[5]) ## i64
    if rank < 1 || rank > 512 || fields.size() != 6+3*rank
      exit(1)
    i = 0 ## i64
    while i < 4
      costs[i] = ffw_parse_decimal_i64(fields[1+i])
      i += 1
    i = 0
    while i < rank
      f = 0 ## i64
      while f < 3
        parent[f*512+i] = ffw_parse_decimal_i64(fields[6+3*i+f])
        f += 1
      i += 1
    price = ffmm_plan(parent, 3*512, 512, rank, costs, 4, mates, axes, 512, scratch, 6*512, memo, choice, 65536, status, 3, budget) ## i64
    if price < 1
      exit(1)
    result.append(price.to_s() + " " + status[0].to_s() + " " + status[1].to_s() + " " + status[2].to_s())
    i = 0
    while i < rank
      result.append(" " + mates[i].to_s() + " " + axes[i].to_s())
      i += 1
    result.append("\n")
    row += 1
  if !write_file(ARGV[2], result.to_s())
    exit(1)
  exit(0)

if ARGV.size() == 1 && ARGV[0] == "--bounds-test"
  parent = i64[3]
  costs = i64[4]
  leaves = i64[12]
  mates = i64[1]
  axes = i64[1]
  out = i64[3]
  scratch = i64[6]
  memo = i64[65536]
  choice = i64[65536]
  status = i64[3]
  i = 0 ## i64
  while i < 3
    parent[i] = 1
    i += 1
  i = 0
  while i < 4
    costs[i] = 1
    i += 1
  i = 0
  while i < 12
    leaves[i] = 1
    i += 1
  axes[0] = 0-1
  # Every malformed call must reject before mutating the destination tensor.
  mode = 0 ## i64
  while mode < 15
    pw = 3 ## i64
    cw = 4 ## i64
    lw = 12 ## i64
    mw = 1 ## i64
    ow = 3 ## i64
    parent[0] = 1
    leaves[0] = 1
    costs[0] = 1
    mates[0] = 0
    axes[0] = 0-1
    if mode == 0
      pw = 2
    if mode == 1
      cw = 3
    if mode == 2
      lw = 11
    if mode == 3
      mw = 0
    if mode == 4
      ow = 2
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
      costs[0] = 0
    if mode == 11
      costs[0] = 9223372036854775807
    if mode == 12
      mates[0] = 1
    if mode == 13
      axes[0] = 0
    if mode == 14
      axes[0] = 3
    out[0] = 777
    if ffmm_compose(parent, pw, 1, 1, 1, 1, 1, 2, 2, 2, leaves, lw, 1, costs, cw, mates, axes, mw, out, ow) != 0-1 || out[0] != 777
      exit(1)
    mode += 1
  parent[0] = 1
  costs[0] = 1
  mode = 0
  while mode < 9
    pw = 3 ## i64
    cw = 4 ## i64
    ow = 1 ## i64
    sw = 6 ## i64
    mw = 65536 ## i64
    tw = 3 ## i64
    budget = 10 ## i64
    rank = 1 ## i64
    if mode == 0
      pw = 2
    if mode == 1
      cw = 3
    if mode == 2
      ow = 0
    if mode == 3
      sw = 5
    if mode == 4
      mw = 65535
    if mode == 5
      tw = 2
    if mode == 6
      budget = 0
    if mode == 7
      rank = 0
    if mode == 8
      costs[0] = 129
    mates[0] = 777
    if ffmm_plan(parent, pw, 1, rank, costs, cw, mates, axes, ow, scratch, sw, memo, choice, mw, status, tw, budget) != 0-1 || mates[0] != 777
      exit(1)
    mode += 1
  << "PASS mixed bounds: 24 pre-mutation rejection gates"
  exit(0)

if ARGV.size() == 3 && ARGV[0] == "--bank"
  root = ARGV[1]
  runtime = ARGV[2]
  if !File.mkdir_p(root + "/objects") || !File.mkdir_p(root + "/composition/leaves")
    exit(1)
  cap = ffrf_capacity() ## i64
  work = i64[ffmc_scratch_words(cap)]
  source = i64[3*cap]
  parity = i64[4096]
  pair3 = ffbc_leaf(root, runtime, 3, work, source, parity)
  pair4 = ffbc_leaf(root, runtime, 4, work, source, parity)
  bank = i64[22*3*128]
  costs = i64[22]
  temp = i64[3*128]
  identity = ffmb_bank(root, runtime, pair3, pair4, bank, 22*3*128, costs, 22, temp, parity)
  if identity == ""
    exit(1)
  << identity
  exit(0)

if ARGV.size() == 9 && ARGV[0] == "--compose"
  root = ARGV[1]
  cap = ffrf_capacity() ## i64
  parent = i64[3*cap]
  meta = i64[4]
  parity = i64[4096]
  if ffrf_load(root, ARGV[2], parent, cap, meta, parity) != 1
    exit(1)
  bank = i64[22*3*128]
  costs = i64[22]
  temp = i64[3*128]
  if ffmb_load_bank(root, ARGV[3], bank, 22*3*128, costs, 22, temp, parity) != 1
    exit(1)
  a = ffw_parse_decimal_i64(ARGV[4]) ## i64
  b = ffw_parse_decimal_i64(ARGV[5]) ## i64
  c = ffw_parse_decimal_i64(ARGV[6]) ## i64
  budget = ffw_parse_decimal_i64(ARGV[8]) ## i64
  leaves = i64[12*128]
  prices = i64[4]
  if ffmb_context(bank, 22*3*128, costs, 22, a, b, c, leaves, 12*128, prices, 4) != 1
    exit(1)
  mates = i64[512]
  axes = i64[512]
  plan = i64[6*512]
  memo = i64[65536]
  choice = i64[65536]
  status = i64[3]
  price = ffmm_plan(parent, 3*cap, cap, meta[3], prices, 4, mates, axes, 512, plan, 6*512, memo, choice, 65536, status, 3, budget) ## i64
  out = i64[3*32*16384]
  rank = ffmm_compose(parent, 3*cap, cap, meta[3], meta[0], meta[1], meta[2], a, b, c, leaves, 12*128, 128, prices, 4, mates, axes, 512, out, 3*32*16384) ## i64
  n = meta[0]*a ## i64
  m = meta[1]*b ## i64
  p = meta[2]*c ## i64
  scratch = i64[32768]
  if price < 1 || rank < 1 || rank > price || ffpk_exact(out, 3*32*16384, rank, n, m, p, scratch, 32768, 0) != 1
    exit(1)
  body = StringBuffer(16384)
  body.append(price.to_s() + " " + status[0].to_s() + " " + status[1].to_s() + " " + status[2].to_s())
  i = 0 ## i64
  while i < meta[3]
    body.append(" " + mates[i].to_s() + " " + axes[i].to_s())
    i += 1
  body.append("\n")
  if !write_file(ARGV[7], ffpk_blob(out, rank, n, m, p)) || !write_file(ARGV[7] + ".plan", body.to_s())
    exit(1)
  << "PASS mixed price=" + price.to_s() + " rank=" + rank.to_s() + " states=" + status[0].to_s() + " fallback=" + status[1].to_s()
  exit(0)
exit(2)
