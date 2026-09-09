# Constructive leaves for all 27 scale triples in {2,3,4}^3, plus each
# doubled-coordinate pair. Canonical coordinate permutations need 22 leaves.
# Unit-coordinate leaves are generated exactly, without changing this bank.
use ../fleet/refinement_artifacts
use ../compose
use mixed_pairs
use mixed_groups
use mixed_grids

-> ffmb_shape(slot, dims) (i64 i64[]) i64
  index = 0 ## i64
  layer = 0 ## i64
  while layer < 3
    n = 2 ## i64
    while n <= 4
      m = n ## i64
      while m <= 4
        p = m ## i64
        end = 4 ## i64
        if layer > 0
          p = 4+2*layer
          end = p
        while p <= end
          if index == slot
            dims[0] = n
            dims[1] = m
            dims[2] = p
            return 1
          index += 1
          p += 1
        m += 1
      n += 1
    layer += 1
  0

-> ffmb_slot(n, m, p) (i64 i64 i64) i64
  if n > m
    t = n ## i64
    n = m
    m = t
  if m > p
    t = m ## i64
    m = p
    p = t
  if n > m
    t = n ## i64
    n = m
    m = t
  dims = i64[3]
  slot = 0 ## i64
  while slot < 22
    z = ffmb_shape(slot, dims) ## i64
    if dims[0] == n && dims[1] == m && dims[2] == p
      return slot
    slot += 1
  0-1

-> ffmb_unit(n, m, p) (i64 i64 i64) i64
  if n < 1 || m < 1 || p < 1 || n > 63 || m > 63 || p > 63 || (n != 1 && m != 1 && p != 1)
    return 0
  if n*m > 63 || m*p > 63 || n*p > 63 || n*m*p > 128
    return 0
  1

-> ffmb_available(n, m, p) (i64 i64 i64) i64
  if ffmb_unit(n, m, p) == 1 || ffmb_slot(n, m, p) >= 0
    return 1
  0

# The caller has loaded and exact-checked the canonical bank. This map also
# validates masks and the requested permutation before writing its output.
-> ffmb_extract(bank, bank_words, costs, cost_words, n, m, p, out, out_words, offset) (i64[] i64 i64[] i64 i64 i64 i64 i64[] i64 i64) i64
  if bank_words < 22*3*128 || cost_words < 22 || offset < 0 || offset > 22*3*128 || out_words < offset+3*128
    return 0
  if ffmb_unit(n, m, p) == 1
    # The literal matrix-product triples are full witnesses, not price-only
    # substitutes. Width checks above avoid shifting into the i64 sign bit.
    rank = n*m*p ## i64
    one = 1 ## i64
    term = 0 ## i64
    while term < rank
      i = term / (m*p) ## i64
      j = (term / p)%m ## i64
      k = term%p ## i64
      out[offset+term] = one << (i*m+j)
      out[offset+128+term] = one << (j*p+k)
      out[offset+256+term] = one << (i*p+k)
      term += 1
    return rank
  slot = ffmb_slot(n, m, p) ## i64
  if slot < 0
    return 0
  rank = costs[slot] ## i64
  if rank < 1 || rank > 128
    return 0
  dims = i64[3]
  want = i64[3]
  perm = i64[3]
  used = i64[3]
  z = ffmb_shape(slot, dims) ## i64
  want[0] = n
  want[1] = m
  want[2] = p
  f = 0 ## i64
  while f < 3
    j = 0 ## i64
    while j < 3
      if used[j] == 0 && dims[j] == want[f]
        used[j] = 1
        perm[f] = j
        break
      j += 1
    if j == 3
      return 0
    i = 0 ## i64
    while i < rank
      value = bank[(slot*3+f)*128+i] ## i64
      if value <= 0 || (value >> ffpk_width(dims[0], dims[1], dims[2], f)) != 0
        return 0
      i += 1
    f += 1
  f = 0
  while f < 3
    left = 0 ## i64
    right = 1 ## i64
    if f == 1
      left = 1
    if f > 0
      right = 2
    r = perm[left] ## i64
    c = perm[right] ## i64
    source = 2 ## i64
    if r+c == 1
      source = 0
    if r+c == 3
      source = 1
    i = 0 ## i64
    while i < rank
      value = bank[(slot*3+source)*128+i] ## i64
      if r > c
        value = ffsc_transpose(value, dims[c], dims[r])
      out[offset+f*128+i] = value
      i += 1
    f += 1
  rank

-> ffmb_context(bank, bank_words, costs, cost_words, a, b, c, out, out_words, prices, price_words) (i64[] i64 i64[] i64 i64 i64 i64 i64[] i64 i64[] i64) i64
  if a < 1 || a > 4 || b < 1 || b > 4 || c < 1 || c > 4 || out_words < 12*128 || price_words < 4
    return 0
  i = 0 ## i64
  while i < 4
    n = a ## i64
    m = b ## i64
    p = c ## i64
    if i == 1
      p *= 2
    if i == 2
      n *= 2
    if i == 3
      m *= 2
    rank = ffmb_extract(bank, bank_words, costs, cost_words, n, m, p, out, out_words, i*3*128) ## i64
    if rank < 1
      return 0
    prices[i] = rank
    i += 1
  1

# Reuse the immutable pair bank for available size-3/4 groups. Unsupported
# shapes have price -1, never a price-only substitute for a missing witness.
-> ffmb_group_context(bank, bank_words, costs, cost_words, a, b, c, out, out_words, prices, price_words) (i64[] i64 i64[] i64 i64 i64 i64 i64[] i64 i64[] i64) i64
  if out_words < 30*128 || price_words < 10 || ffmb_context(bank, bank_words, costs, cost_words, a, b, c, out, out_words, prices, price_words) != 1
    return 0
  i = 4 ## i64
  while i < 10
    axis = (i-1)%3 ## i64
    size = 2+(i-1)/3 ## i64
    n = a ## i64
    m = b ## i64
    p = c ## i64
    if axis == 0
      p *= size
    if axis == 1
      n *= size
    if axis == 2
      m *= size
    prices[i] = 0-1
    if ffmb_available(n, m, p) == 1
      rank = ffmb_extract(bank, bank_words, costs, cost_words, n, m, p, out, out_words, i*3*128) ## i64
      if rank < 1
        return 0
      prices[i] = rank
    i += 1
  1

# Two expanded coordinates for UV/UW/VW grids; the same immutable bank
# supplies every available witness. Unavailable shapes remain disabled.
-> ffmb_grid_context(bank, bank_words, costs, cost_words, a, b, c, out, out_words, prices, price_words) (i64[] i64 i64[] i64 i64 i64 i64 i64[] i64 i64[] i64) i64
  if out_words < 39*128 || price_words < 13 || ffmb_group_context(bank, bank_words, costs, cost_words, a, b, c, out, out_words, prices, price_words) != 1
    return 0
  i = 10 ## i64
  while i < 13
    n = a ## i64
    m = b ## i64
    p = c ## i64
    fixed = ffmx_fixed(i-7) ## i64
    if fixed != 0
      n *= 2
    if fixed != 1
      m *= 2
    if fixed != 2
      p *= 2
    prices[i] = 0-1
    if ffmb_available(n, m, p) == 1
      rank = ffmb_extract(bank, bank_words, costs, cost_words, n, m, p, out, out_words, i*3*128) ## i64
      if rank < 1
        return 0
      prices[i] = rank
    i += 1
  1

-> ffmb_load_bank(root, identity, bank, words, costs, cost_words, work, parity) (String String i64[] i64 i64[] i64 i64[] i64[]) i64
  if ffrf_hash_valid(identity) != 1 || words < 22*3*128 || cost_words < 22
    return 0
  raw = File.read_prefix(root + "/composition/banks/" + identity, 2049)
  if raw == nil || raw.size() >= 2048 || Crypto:SHA256.hexdigest(raw) != identity
    return 0
  fields = raw.strip().split(" ")
  if fields.size() != 23 || fields[0] != "MFM_BANK1"
    return 0
  canonical = "MFM_BANK1"
  dims = i64[3]
  meta = i64[4]
  slot = 0 ## i64
  while slot < 22
    z = ffmb_shape(slot, dims) ## i64
    if ffrf_load(root, fields[slot+1], work, 128, meta, parity) != 1 || meta[0] != dims[0] || meta[1] != dims[1] || meta[2] != dims[2]
      return 0
    costs[slot] = meta[3]
    i = 0 ## i64
    while i < meta[3]
      f = 0 ## i64
      while f < 3
        bank[(slot*3+f)*128+i] = work[f*128+i]
        f += 1
      i += 1
    canonical = canonical + " " + fields[slot+1]
    slot += 1
  if raw != canonical + "\n"
    return 0
  1

-> ffmb_seed(slot) (i64)
  if slot == 0
    return "matmul_2x2_rank7_strassen_gf2.txt"
  if slot == 4
    return "matmul_2x3x4_rank20_d130_global_isotropy_gf2.txt"
  if slot == 6
    return "matmul_3x3_rank23_d139_gf2.txt"
  if slot == 7
    return "matmul_3x3x4_rank29_d249_peterson_2026_aws_disjoint_gf2.txt"
  if slot == 8
    return "matmul_3x4x4_rank38_d280_live_density_leader_gf2.txt"
  if slot == 9
    return "matmul_4x4_rank47_d450_gf2.txt"
  if slot == 14
    return "matmul_3x4x6_rank54_catalog_gf2.txt"
  if slot == 15
    return "matmul_4x4x6_rank73_d690_gl_frontier_gf2.txt"
  ""

# Exact last-coordinate block sums fill the remaining bank slots. The small
# pair IDs come from the existing bounded native leaf builder, not prices.
-> ffmb_bank(root, runtime, pair3, pair4, bank, words, costs, cost_words, work, parity) (String String String String i64[] i64 i64[] i64 i64[] i64[])
  if words < 22*3*128 || cost_words < 22 || ffrf_hash_valid(pair3) != 1 || ffrf_hash_valid(pair4) != 1 || !File.mkdir_p(root + "/composition/banks")
    return ""
  marker = root + "/composition/mixed-bank-latest"
  old = File.read_prefix(marker, 66)
  if old != nil
    identity = old.strip()
    if ffmb_load_bank(root, identity, bank, words, costs, cost_words, work, parity) != 1
      return ""
    raw = File.read_prefix(root + "/composition/banks/" + identity, 2049)
    fields = raw.strip().split(" ")
    if fields[4] == pair3 && fields[6] == pair4
      return identity
  body = "MFM_BANK1"
  dims = i64[3]
  meta = i64[4]
  us = i64[128]
  vs = i64[128]
  ws = i64[128]
  partwork = i64[3*128]
  slot = 0 ## i64
  while slot < 22
    if File.exists?(root + "/stop")
      return ""
    z = ffmb_shape(slot, dims) ## i64
    n = dims[0] ## i64
    m = dims[1] ## i64
    p = dims[2] ## i64
    rank = 0 ## i64
    seed = ffmb_seed(slot)
    if seed != ""
      rank = ffsc_load(runtime + "/seeds/gf2/" + seed, us, vs, ws, 128)
      if rank < 1
        return ""
      i = 0 ## i64
      while i < rank
        work[i] = us[i]
        work[128+i] = vs[i]
        work[256+i] = ws[i]
        i += 1
    elsif slot == 3 || slot == 5
      identity = pair3
      if slot == 5
        identity = pair4
      if ffrf_load(root, identity, work, 128, meta, parity) != 1 || meta[0] != n || meta[1] != m || meta[2] != p
        return ""
      rank = meta[3]
    else
      split = p/2 ## i64
      if slot == 1
        split = 2
      if slot == 10 || slot == 12 || slot == 13
        split = 4
      if slot == 20
        split = 6
      part = 0 ## i64
      offset = 0 ## i64
      while part < 2
        size = split ## i64
        if part == 1
          size = p-split
        count = 0 ## i64
        if size == 1
          i = 0 ## i64
          while i < n
            j = 0 ## i64
            while j < m
              partwork[count] = 1 << (i*m+j)
              partwork[128+count] = 1 << j
              partwork[256+count] = 1 << i
              count += 1
              j += 1
            i += 1
        else
          count = ffmb_extract(bank, words, costs, cost_words, n, m, size, partwork, 3*128, 0)
        if count < 1 || rank+count > 128
          return ""
        i = 0 ## i64
        while i < count
          work[rank+i] = partwork[i]
          f = 1 ## i64
          while f < 3
            value = partwork[f*128+i] ## i64
            mapped = 0 ## i64
            while value > 0
              bit = ffmm_bit(value) ## i64
              mapped = mapped | (1 << ((bit / size)*p+bit%size+offset))
              value = value & (value-1)
            work[f*128+rank+i] = mapped
            f += 1
          i += 1
        rank += count
        offset += size
        part += 1
    if ffrf_exact(work, 128, rank, n, m, p, parity) != 1
      return ""
    identity = ffrf_store(root, work, 128, rank, n, m, p, "mixed-bank")
    if identity == ""
      return ""
    costs[slot] = rank
    i = 0 ## i64
    while i < rank
      f = 0 ## i64
      while f < 3
        bank[(slot*3+f)*128+i] = work[f*128+i]
        f += 1
      i += 1
    body = body + " " + identity
    slot += 1
  body = body + "\n"
  identity = Crypto:SHA256.hexdigest(body)
  path = root + "/composition/banks/" + identity
  before = File.read_prefix(path, 2049)
  if before != nil && before != body
    return ""
  if before == nil && ffrf_atomic(path, body, "mixed-bank") != 1
    return ""
  if ffrf_atomic(marker, identity + "\n", "mixed-bank") != 1
    return ""
  identity
