use ../fleet/refinement_artifacts
use ../compose
use groups

-> ffbg_seed(k, scale) (i64 i64)
  if scale == 3
    if k == 3
      return "matmul_3x3_rank23_d139_gf2.txt"
    if k == 4
      return "matmul_3x3x4_rank29_d249_peterson_2026_aws_disjoint_gf2.txt"
    if k == 5
      return "matmul_3x3x5_rank36_d287_gf2.txt"
  if scale == 4
    if k == 3
      return "matmul_3x4x4_rank38_d280_live_density_leader_gf2.txt"
    if k == 4
      return "matmul_4x4_rank47_d450_gf2.txt"
    if k == 5
      return "matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt"
    if k == 6
      return "matmul_4x4x6_rank73_d690_gl_frontier_gf2.txt"
  ""

-> ffbg_copy_leaf(bank, cap, k, work, rank) (i64[] i64 i64 i64[] i64) i64
  f = 0 ## i64
  while f < 3
    i = 0 ## i64
    while i < rank
      bank[(k-1)*3*cap+f*cap+i] = work[f*cap+i]
      i += 1
    f += 1
  1

# Immutable manifests bind every leaf, including the exact naive singleton.
# Their hashes locate bytes; each member still crosses the full tensor gate.
-> ffbg_load_bank(root, identity, scale, bank, words, cap, costs, cost_words, work, parity) (String String i64 i64[] i64 i64 i64[] i64 i64[] i64[]) i64
  if ffrf_hash_valid(identity) != 1 || scale < 2 || scale > 4 || cap < 1 || cap > 4096 || words < 18*cap || cost_words < 7
    return 0
  raw = File.read_prefix(root + "/composition/banks/" + identity, 1025)
  if raw == nil || Crypto:SHA256.hexdigest(raw) != identity
    return 0
  fields = raw.strip().split(" ")
  if fields.size() != 8 || fields[0] != "MFC_BANK1" || fields[1] != scale.to_s()
    return 0
  canonical = "MFC_BANK1 " + scale.to_s()
  meta = i64[4]
  k = 1 ## i64
  while k <= 6
    leaf = fields[k+1]
    if ffrf_load(root, leaf, work, cap, meta, parity) != 1 || meta[0] != k || meta[1] != scale || meta[2] != scale
      return 0
    costs[k] = meta[3]
    z = ffbg_copy_leaf(bank, cap, k, work, costs[k]) ## i64
    canonical = canonical + " " + leaf
    k += 1
  if raw != canonical + "\n"
    return 0
  1

# Build from shipped witnesses and exact disjoint-row block sums. The pair
# identity is supplied by the existing certified small-leaf constructor.
-> ffbg_bank(root, runtime, scale, pair_id, bank, words, cap, costs, work, parity) (String String i64 String i64[] i64 i64 i64[] i64[] i64[])
  if scale < 2 || scale > 4 || cap < 128 || cap > 4096 || words < 18*cap || ffrf_hash_valid(pair_id) != 1
    return ""
  if !File.mkdir_p(root + "/composition/banks") || !File.mkdir_p(root + "/composition/bank-latest")
    return ""
  marker = root + "/composition/bank-latest/" + scale.to_s()
  old = File.read_prefix(marker, 66)
  if old != nil
    identity = old.strip()
    if ffbg_load_bank(root, identity, scale, bank, words, cap, costs, 7, work, parity) != 1
      return ""
    raw = File.read_prefix(root + "/composition/banks/" + identity, 1025)
    fields = raw.strip().split(" ")
    if fields[3] == pair_id
      return identity
  body = "MFC_BANK1 " + scale.to_s()
  us = i64[128]
  vs = i64[128]
  ws = i64[128]
  meta = i64[4]
  k = 1 ## i64
  while k <= 6
    if File.exists?(root + "/stop")
      return ""
    rank = 0 ## i64
    if k == 1
      i = 0 ## i64
      while i < scale
        j = 0 ## i64
        while j < scale
          work[rank] = 1 << i
          work[cap+rank] = 1 << (i*scale+j)
          work[2*cap+rank] = 1 << j
          rank += 1
          j += 1
        i += 1
    elsif k == 2
      if ffrf_load(root, pair_id, work, cap, meta, parity) != 1 || meta[0] != 2 || meta[1] != scale || meta[2] != scale
        return ""
      rank = meta[3]
    else
      seed = ffbg_seed(k, scale)
      if seed != ""
        rank = ffsc_load(runtime + "/seeds/gf2/" + seed, us, vs, ws, 128)
        if rank < 1
          return ""
        i = 0 ## i64
        while i < rank
          if k > scale
            work[i] = ffsc_transpose(ws[i], scale, k)
            work[cap+i] = us[i]
            work[2*cap+i] = ffsc_transpose(vs[i], scale, k)
          else
            work[i] = us[i]
            work[cap+i] = vs[i]
            work[2*cap+i] = ws[i]
          i += 1
        if ffrf_exact(work, cap, rank, k, scale, scale, parity) != 1
          return ""
      split = 0 ## i64
      a = 1 ## i64
      while a < k
        if rank == 0 || costs[a]+costs[k-a] < rank
          rank = costs[a]+costs[k-a]
          split = a
        a += 1
      if split > 0
        rank = 0
        part = 0 ## i64
        while part < 2
          size = split ## i64
          offset = 0 ## i64
          if part == 1
            size = k-split
            offset = split*scale
          i = 0
          while i < costs[size]
            work[rank] = bank[(size-1)*3*cap+i] << offset
            work[cap+rank] = bank[(size-1)*3*cap+cap+i]
            work[2*cap+rank] = bank[(size-1)*3*cap+2*cap+i] << offset
            rank += 1
            i += 1
          part += 1
    if ffrf_exact(work, cap, rank, k, scale, scale, parity) != 1
      return ""
    identity = ffrf_store(root, work, cap, rank, k, scale, scale, "composition")
    if identity == ""
      return ""
    costs[k] = rank
    z = ffbg_copy_leaf(bank, cap, k, work, rank) ## i64
    body = body + " " + identity
    k += 1
  body = body + "\n"
  identity = Crypto:SHA256.hexdigest(body)
  path = root + "/composition/banks/" + identity
  before = File.read_prefix(path, 1025)
  if before != nil && before != body
    return ""
  if before == nil && ffrf_atomic(path, body, "composition") != 1
    return ""
  if ffrf_atomic(marker, identity + "\n", "composition") != 1
    return ""
  identity
