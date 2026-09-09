use ../lib/metaflip/fleet/refinement_worker
use ../lib/metaflip/composition/group_bank

if ARGV.size() == 1 && ARGV[0] == "--plan-test"
  cap = 80 ## i64
  parent = i64[3*cap]
  costs = i64[7]
  costs[1] = 16
  costs[2] = 26
  costs[3] = 38
  costs[4] = 47
  costs[5] = 60
  costs[6] = 73
  order = i64[cap]
  sizes = i64[cap]
  scratch = i64[4*(cap+1)]
  seen = i64[cap]
  i = 0 ## i64
  while i < 3*cap
    parent[i] = 1
    i += 1
  if ffbg_plan(parent, 3*cap, cap, cap, 0, costs, 7, order, cap, sizes, cap, scratch, 4*(cap+1)) != 940 || ffbg_large(sizes, cap) != 1
    exit(1)
  i = 0
  while i < cap
    if order[i] < 0 || order[i] >= cap || seen[order[i]] != 0
      exit(1)
    seen[order[i]] = 1
    if i%4 == 0 && sizes[i] != 4
      exit(1)
    i += 1
  if ffbg_plan(parent, 3*cap-1, cap, cap, 0, costs, 7, order, cap, sizes, cap, scratch, 4*(cap+1)) != 0-1 || ffbg_plan(parent, 3*cap, cap, 0, 0, costs, 7, order, cap, sizes, cap, scratch, 4*(cap+1)) != 0-1
    exit(1)
  if ffbg_plan(parent, 3*cap, cap, cap, 3, costs, 7, order, cap, sizes, cap, scratch, 4*(cap+1)) != 0-1 || ffbg_plan(parent, 3*cap, cap, cap, 0, costs, 6, order, cap, sizes, cap, scratch, 4*(cap+1)) != 0-1
    exit(1)
  if ffbg_plan(parent, 3*cap, cap, cap, 0, costs, 7, order, cap-1, sizes, cap, scratch, 4*(cap+1)) != 0-1 || ffbg_plan(parent, 3*cap, cap, cap, 0, costs, 7, order, cap, sizes, cap-1, scratch, 4*(cap+1)) != 0-1 || ffbg_plan(parent, 3*cap, cap, cap, 0, costs, 7, order, cap, sizes, cap, scratch, 4*(cap+1)-1) != 0-1
    exit(1)
  costs[6] = 0
  if ffbg_plan(parent, 3*cap, cap, cap, 0, costs, 7, order, cap, sizes, cap, scratch, 4*(cap+1)) != 0-1
    exit(1)
  << "PASS grouped plan: bucket partition, exact price, bounds and invalid costs"
  exit(0)

if ARGV.size() == 4 && ARGV[0] == "--bank"
  root = ARGV[1]
  runtime = ARGV[2]
  scale = ffw_parse_decimal_i64(ARGV[3]) ## i64
  if !File.mkdir_p(root + "/objects") || !File.mkdir_p(root + "/composition/leaves")
    exit(1)
  cap = ffrf_capacity() ## i64
  work = i64[ffmc_scratch_words(cap)]
  source = i64[3*cap]
  parity = i64[4096]
  pair = ffbc_leaf(root, runtime, scale, work, source, parity)
  bank = i64[18*128]
  temp = i64[3*128]
  costs = i64[7]
  identity = ffbg_bank(root, runtime, scale, pair, bank, 18*128, 128, costs, temp, parity)
  if identity == ""
    exit(1)
  << identity
  exit(0)
if ARGV.size() == 7 && ARGV[0] == "--compose"
  root = ARGV[1]
  cap = ffrf_capacity() ## i64
  parent = i64[3*cap]
  meta = i64[4]
  parity = i64[4096]
  axis = ffw_parse_decimal_i64(ARGV[4]) ## i64
  scale = ffw_parse_decimal_i64(ARGV[5]) ## i64
  if ffrf_load(root, ARGV[2], parent, cap, meta, parity) != 1
    exit(1)
  bank = i64[18*128]
  work = i64[3*128]
  costs = i64[7]
  if ffbg_load_bank(root, ARGV[3], scale, bank, 18*128, 128, costs, 7, work, parity) != 1
    exit(1)
  order = i64[cap]
  sizes = i64[cap]
  plan = i64[4*(cap+1)]
  price = ffbg_plan(parent, 3*cap, cap, meta[3], axis, costs, 7, order, cap, sizes, cap, plan, 4*(cap+1)) ## i64
  out = i64[3*32*16384]
  rank = ffbg_compose(parent, 3*cap, cap, meta[3], meta[0], meta[1], meta[2], axis, scale, bank, 18*128, 128, costs, 7, order, cap, sizes, cap, plan, 4*(cap+1), out, 3*32*16384) ## i64
  n = meta[0]*ffbd_scale(axis, 0, scale) ## i64
  m = meta[1]*ffbd_scale(axis, 1, scale) ## i64
  p = meta[2]*ffbd_scale(axis, 2, scale) ## i64
  scratch = i64[32768]
  if rank < 1 || rank > price || ffpk_exact(out, 3*32*16384, rank, n, m, p, scratch, 32768, 0) != 1 || !write_file(ARGV[6], ffpk_blob(out, rank, n, m, p))
    exit(1)
  << "PASS grouped price=" + price.to_s() + " rank=" + rank.to_s() + " large=" + ffbg_large(sizes, meta[3]).to_s()
  exit(0)
exit(2)
