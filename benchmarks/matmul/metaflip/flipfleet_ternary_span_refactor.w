# Bounded exact local span refactoring for strict {-1,0,1} FlipFleet terms.
#
# A selected three- or four-term subtotal supplies up to four signed generator
# vectors on each tensor axis.  We enumerate every nonzero coefficient tuple
# in {-1,0,1}^k, retain only ambient vectors that are still strict ternary,
# and quotient the unavoidable v ~ -v gauge.  Every rank-one product of the
# three resulting vector catalogues, with both scalar signs, is then a local
# replacement candidate.
#
# Two modular tensor evaluations are only hash selectors.  Every hash match is
# checked coefficient-by-coefficient over the complete ambient local tensor,
# so collisions cannot admit a false identity.  Hash buckets retain chains of
# every candidate, so collisions cannot hide a real identity either.  The
# bounded search is therefore complete for this explicitly enumerated signed
# generator-span catalogue.
#
# Supported exact searches are 3->2, 3<->3, and 4->3.  A second entry point
# fixes one replacement to the opposite of an external live term; a successful
# 3<->3 identity then cancels that external term and compacts the global rank
# by two.  Four-term catalogues can contain as many as 128,000 signed products,
# so callers choose an explicit candidate cap and receive an over-cap result
# rather than an accidental unbounded allocation.
#
# meta (minimum 20 i64s):
#   [0..2] projective U/V/W vector counts
#   [3]    signed rank-one candidate count
#   [4]    pair probes
#   [5]    dual-hash matches
#   [6]    complete local integer gates
#   [7]    result cardinality
#   [8]    over-cap windows
#   [9]    original-multiset solutions rejected
#   [10]   source terms
#   [11]   requested replacement terms
#   [12]   hash-table capacity
#   [13]   external terms tested by collision search
#   [14]   external terms representable in the local catalogue
#   [15]   external slot of a collision result, or -1
#   [16]   strict vector combinations tested across all three axes
#   [17]   strict projective vectors retained across all three axes
#   [18]   malformed input
#   [19]   require a replacement disjoint from the source multiset

use flipfleet_ternary_worker

+ FFTSRWorkspace
  -> new(max_candidates)
    limit = max_candidates ## i64
    if limit < 16
      limit = 16
    @config = i64[3]
    @config[0] = limit
    capacity = 16 ## i64
    while capacity < 2 * limit
      capacity = capacity * 2
    @config[1] = capacity
    @config[2] = capacity - 1
    @up = i64[40]
    @un = i64[40]
    @vp = i64[40]
    @vn = i64[40]
    @wp = i64[40]
    @wn = i64[40]
    @hash1 = i64[limit]
    @hash2 = i64[limit]
    @heads = i32[capacity]
    @nexts = i32[limit]

  -> max_candidates()
    @config[0]
  -> table_capacity()
    @config[1]
  -> table_mask()
    @config[2]
  -> up()
    @up
  -> un()
    @un
  -> vp()
    @vp
  -> vn()
    @vn
  -> wp()
    @wp
  -> wn()
    @wn
  -> hash1()
    @hash1
  -> hash2()
    @hash2
  -> heads()
    @heads
  -> nexts()
    @nexts

-> fftsr_clear_meta(meta) (i64[]) i64
  i = 0 ## i64
  while i < 20
    meta[i] = 0
    i += 1
  meta[15] = 0 - 1
  1

-> fftsr_supported(k, want) (i64 i64) i64
  if k == 3 && (want == 2 || want == 3)
    return 1
  if k == 4 && want == 3
    return 1
  0

-> fftsr_pow3(k) (i64) i64
  value = 1 ## i64
  i = 0 ## i64
  while i < k
    value = value * 3
    i += 1
  value

-> fftsr_combo_coefficient(code, position) (i64 i64) i64
  value = code ## i64
  i = 0 ## i64
  while i < position
    value = value / 3
    i += 1
  (value % 3) - 1

-> fftsr_vector_present(positive, negative, count, p, n) (i64[] i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if positive[i] == p && negative[i] == n
      return 1
    i += 1
  0

# Enumerate the exact bounded signed generator span.  Source vectors are
# flattened as k positive masks followed by k negative masks in separate
# arrays.  Projective canonicalization keeps the first ambient coefficient +1.
-> fftsr_enumerate_vectors(source_p, source_n, k, dim, out_p, out_n, meta) (i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  if k < 1 || k > 4 || dim < 1 || dim > 49
    return 0
  count = 0 ## i64
  code = 0 ## i64
  limit = fftsr_pow3(k) ## i64
  while code < limit
    positive = 0 ## i64
    negative = 0 ## i64
    valid = 1 ## i64
    nonzero = 0 ## i64
    bit = 0 ## i64
    while bit < dim && valid == 1
      value = 0 ## i64
      term = 0 ## i64
      while term < k
        value += fftsr_combo_coefficient(code,term) * fft_coefficient(source_p[term],source_n[term],bit)
        term += 1
      if value < 0 - 1 || value > 1
        valid = 0
      if value == 1
        positive = positive | (1 << bit)
        nonzero = 1
      if value == 0 - 1
        negative = negative | (1 << bit)
        nonzero = 1
      bit += 1
    meta[16] = meta[16] + 1
    if valid == 1 && nonzero == 1
      if fft_first_sign(positive,negative) < 0
        swap = positive ## i64
        positive = negative
        negative = swap
      if fftsr_vector_present(out_p,out_n,count,positive,negative) == 0
        if count < 40
          out_p[count] = positive
          out_n[count] = negative
          count += 1
    code += 1
  meta[17] = meta[17] + count
  count

-> fftsr_modulus(which) (i64) i64
  value = 1000003 ## i64
  if which != 0
    value = 1000033
  value

-> fftsr_mod(value, modulus) (i64 i64) i64
  result = value % modulus ## i64
  if result < 0
    result += modulus
  result

# Deterministic nonzero evaluation points.  The products stay below 10^12
# between modular reductions, safely inside signed i64.
-> fftsr_weight(which, axis, index) (i64 i64 i64) i64
  modulus = fftsr_modulus(which) ## i64
  x = index + 1 + 53 * axis + 211 * which ## i64
  fftsr_mod(x * x + (97 + 38 * axis) * x + 1009 + 1291 * which,modulus) + 1

-> fftsr_vector_evaluation(positive, negative, dim, axis, which) (i64 i64 i64 i64 i64) i64
  modulus = fftsr_modulus(which) ## i64
  value = 0 ## i64
  bit = 0 ## i64
  while bit < dim
    coefficient = fft_coefficient(positive,negative,bit) ## i64
    if coefficient != 0
      value = fftsr_mod(value + coefficient * fftsr_weight(which,axis,bit),modulus)
    bit += 1
  value

-> fftsr_term_hash(up,un,vp,vn,wp,wn,dim,which) (i64 i64 i64 i64 i64 i64 i64 i64) i64
  modulus = fftsr_modulus(which) ## i64
  a = fftsr_vector_evaluation(up,un,dim,0,which) ## i64
  b = fftsr_vector_evaluation(vp,vn,dim,1,which) ## i64
  c = fftsr_vector_evaluation(wp,wn,dim,2,which) ## i64
  fftsr_mod(fftsr_mod(a * b,modulus) * c,modulus)

-> fftsr_candidate_decode(id, nv, nw, decoded) (i64 i64 i64 i64[]) i64
  decoded[3] = id & 1
  value = id / 2 ## i64
  decoded[2] = value % nw
  value = value / nw
  decoded[1] = value % nv
  decoded[0] = value / nv
  1

-> fftsr_candidate_masks(workspace, nv, nw, id, masks) (FFTSRWorkspace i64 i64 i64 i64[]) i64
  decoded = i64[4]
  z = fftsr_candidate_decode(id,nv,nw,decoded) ## i64
  up = workspace.up()
  un = workspace.un()
  vp = workspace.vp()
  vn = workspace.vn()
  wp = workspace.wp()
  wn = workspace.wn()
  masks[0] = up[decoded[0]]
  masks[1] = un[decoded[0]]
  masks[2] = vp[decoded[1]]
  masks[3] = vn[decoded[1]]
  if decoded[3] == 0
    masks[4] = wp[decoded[2]]
    masks[5] = wn[decoded[2]]
  if decoded[3] != 0
    masks[4] = wn[decoded[2]]
    masks[5] = wp[decoded[2]]
  1

-> fftsr_hash_bucket(h1, h2, mask) (i64 i64 i64) i64
  (h1 * 1009 + h2 * 9176 + h1 * h2) & mask

-> fftsr_prepare(sup,sun,svp,svn,swp,swn,n,k,workspace,meta) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 FFTSRWorkspace i64[]) i64
  if workspace == nil || k < 1 || k > 4 || n < 2 || n > 7
    meta[18] = meta[18] + 1
    return 0 - 1
  dim = n * n ## i64
  up = workspace.up()
  un = workspace.un()
  vp = workspace.vp()
  vn = workspace.vn()
  wp = workspace.wp()
  wn = workspace.wn()
  nu = fftsr_enumerate_vectors(sup,sun,k,dim,up,un,meta) ## i64
  nv = fftsr_enumerate_vectors(svp,svn,k,dim,vp,vn,meta) ## i64
  nw = fftsr_enumerate_vectors(swp,swn,k,dim,wp,wn,meta) ## i64
  meta[0] = nu
  meta[1] = nv
  meta[2] = nw
  meta[10] = k
  count = 2 * nu * nv * nw ## i64
  meta[3] = count
  if count < 1 || count > workspace.max_candidates()
    meta[8] = meta[8] + 1
    return 0

  hash1 = workspace.hash1()
  hash2 = workspace.hash2()
  heads = workspace.heads()
  nexts = workspace.nexts()
  capacity = workspace.table_capacity() ## i64
  meta[12] = capacity
  i = 0 ## i64
  while i < capacity
    heads[i] = 0
    i += 1
  masks = i64[6]
  id = 0 ## i64
  while id < count
    z = fftsr_candidate_masks(workspace,nv,nw,id,masks) ## i64
    hash1[id] = fftsr_term_hash(masks[0],masks[1],masks[2],masks[3],masks[4],masks[5],dim,0)
    hash2[id] = fftsr_term_hash(masks[0],masks[1],masks[2],masks[3],masks[4],masks[5],dim,1)
    bucket = fftsr_hash_bucket(hash1[id],hash2[id],workspace.table_mask()) ## i64
    nexts[id] = heads[bucket]
    heads[bucket] = id + 1
    id += 1
  count

-> fftsr_target_hash(sup,sun,svp,svn,swp,swn,k,dim,which) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64) i64
  modulus = fftsr_modulus(which) ## i64
  value = 0 ## i64
  i = 0 ## i64
  while i < k
    value = fftsr_mod(value + fftsr_term_hash(sup[i],sun[i],svp[i],svn[i],swp[i],swn[i],dim,which),modulus)
    i += 1
  value

-> fftsr_exact_local(sup,sun,svp,svn,swp,swn,k,n,workspace,nv,nw,ids,out_count) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 FFTSRWorkspace i64 i64 i64[] i64) i64
  dim = n * n ## i64
  decoded = i64[4]
  masks = i64[6]
  ai = 0 ## i64
  while ai < dim
    bi = 0 ## i64
    while bi < dim
      ci = 0 ## i64
      while ci < dim
        source = 0 ## i64
        term = 0 ## i64
        while term < k
          source += fft_coefficient(sup[term],sun[term],ai) * fft_coefficient(svp[term],svn[term],bi) * fft_coefficient(swp[term],swn[term],ci)
          term += 1
        replacement = 0 ## i64
        term = 0
        while term < out_count
          z = fftsr_candidate_masks(workspace,nv,nw,ids[term],masks) ## i64
          replacement += fft_coefficient(masks[0],masks[1],ai) * fft_coefficient(masks[2],masks[3],bi) * fft_coefficient(masks[4],masks[5],ci)
          term += 1
        if source != replacement
          return 0
        ci += 1
      bi += 1
    ai += 1
  1

-> fftsr_candidate_matches_source(workspace,nv,nw,id,sup,sun,svp,svn,swp,swn,source) (FFTSRWorkspace i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  masks = i64[6]
  z = fftsr_candidate_masks(workspace,nv,nw,id,masks) ## i64
  if masks[0] == sup[source] && masks[1] == sun[source] && masks[2] == svp[source] && masks[3] == svn[source] && masks[4] == swp[source] && masks[5] == swn[source]
    return 1
  0

-> fftsr_same_original(workspace,nv,nw,ids,count,sup,sun,svp,svn,swp,swn,k) (FFTSRWorkspace i64 i64 i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  if count != k
    return 0
  used = 0 ## i64
  i = 0 ## i64
  while i < count
    matched = 0 - 1 ## i64
    source = 0 ## i64
    while source < k && matched < 0
      if ((used >> source) & 1) == 0
        if fftsr_candidate_matches_source(workspace,nv,nw,ids[i],sup,sun,svp,svn,swp,swn,source) == 1
          matched = source
      source += 1
    if matched < 0
      return 0
    used = used | (1 << matched)
    i += 1
  1

-> fftsr_ids_disjoint(workspace,nv,nw,ids,count,sup,sun,svp,svn,swp,swn,k) (FFTSRWorkspace i64 i64 i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    source = 0 ## i64
    while source < k
      if fftsr_candidate_matches_source(workspace,nv,nw,ids[i],sup,sun,svp,svn,swp,swn,source) == 1
        return 0
      source += 1
    i += 1
  1

-> fftsr_materialize(workspace,nv,nw,ids,count,out_up,out_un,out_vp,out_vn,out_wp,out_wn) (FFTSRWorkspace i64 i64 i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  masks = i64[6]
  i = 0 ## i64
  while i < count
    z = fftsr_candidate_masks(workspace,nv,nw,ids[i],masks) ## i64
    out_up[i] = masks[0]
    out_un[i] = masks[1]
    out_vp[i] = masks[2]
    out_vn[i] = masks[3]
    out_wp[i] = masks[4]
    out_wn[i] = masks[5]
    i += 1
  count

-> fftsr_accept_ids(sup,sun,svp,svn,swp,swn,k,n,workspace,nv,nw,ids,count,meta) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 FFTSRWorkspace i64 i64 i64[] i64 i64[]) i64
  meta[6] = meta[6] + 1
  if fftsr_exact_local(sup,sun,svp,svn,swp,swn,k,n,workspace,nv,nw,ids,count) == 0
    return 0
  if count == k
    if fftsr_same_original(workspace,nv,nw,ids,count,sup,sun,svp,svn,swp,swn,k) == 1
      meta[9] = meta[9] + 1
      return 0
    if meta[19] != 0
      if fftsr_ids_disjoint(workspace,nv,nw,ids,count,sup,sun,svp,svn,swp,swn,k) == 0
        meta[9] = meta[9] + 1
        return 0
  1

# Search an already prepared catalogue.  fixed_id<0 selects the ordinary
# 2- or 3-term search.  fixed_id>=0 pins the first of exactly three outputs,
# which is used by the external-cancellation lane.
-> fftsr_search_prepared(sup,sun,svp,svn,swp,swn,k,n,want,fixed_id,workspace,meta,out_up,out_un,out_vp,out_vn,out_wp,out_wn) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 FFTSRWorkspace i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  count = meta[3] ## i64
  nv = meta[1] ## i64
  nw = meta[2] ## i64
  hash1 = workspace.hash1()
  hash2 = workspace.hash2()
  heads = workspace.heads()
  nexts = workspace.nexts()
  mask = workspace.table_mask() ## i64
  p1 = fftsr_modulus(0) ## i64
  p2 = fftsr_modulus(1) ## i64
  dim = n * n ## i64
  target1 = fftsr_target_hash(sup,sun,svp,svn,swp,swn,k,dim,0) ## i64
  target2 = fftsr_target_hash(sup,sun,svp,svn,swp,swn,k,dim,1) ## i64
  ids = i64[4]
  found = 0 ## i64

  if fixed_id < 0 && want == 2
    left = 0 ## i64
    while left < count && found == 0
      need1 = fftsr_mod(target1 - hash1[left],p1) ## i64
      need2 = fftsr_mod(target2 - hash2[left],p2) ## i64
      link = heads[fftsr_hash_bucket(need1,need2,mask)] ## i64
      while link != 0 && found == 0
        right = link - 1 ## i64
        if right >= left
          meta[4] = meta[4] + 1
          if hash1[right] == need1 && hash2[right] == need2
            meta[5] = meta[5] + 1
            ids[0] = left
            ids[1] = right
            if fftsr_accept_ids(sup,sun,svp,svn,swp,swn,k,n,workspace,nv,nw,ids,2,meta) == 1
              found = 2
        link = nexts[right]
      left += 1

  if fixed_id < 0 && want == 3
    left = 0
    while left < count && found == 0
      right = left
      while right < count && found == 0
        need1 = fftsr_mod(target1 - hash1[left] - hash1[right],p1) ## i64
        need2 = fftsr_mod(target2 - hash2[left] - hash2[right],p2) ## i64
        link = heads[fftsr_hash_bucket(need1,need2,mask)] ## i64
        meta[4] = meta[4] + 1
        while link != 0 && found == 0
          third = link - 1 ## i64
          if third >= right
            if hash1[third] == need1 && hash2[third] == need2
              meta[5] = meta[5] + 1
              ids[0] = left
              ids[1] = right
              ids[2] = third
              if fftsr_accept_ids(sup,sun,svp,svn,swp,swn,k,n,workspace,nv,nw,ids,3,meta) == 1
                found = 3
          link = nexts[third]
        right += 1
      left += 1

  if fixed_id >= 0 && want == 3
    left = 0
    while left < count && found == 0
      need1 = fftsr_mod(target1 - hash1[fixed_id] - hash1[left],p1) ## i64
      need2 = fftsr_mod(target2 - hash2[fixed_id] - hash2[left],p2) ## i64
      link = heads[fftsr_hash_bucket(need1,need2,mask)] ## i64
      while link != 0 && found == 0
        right = link - 1 ## i64
        if right >= left
          meta[4] = meta[4] + 1
          if hash1[right] == need1 && hash2[right] == need2
            meta[5] = meta[5] + 1
            ids[0] = fixed_id
            ids[1] = left
            ids[2] = right
            if fftsr_accept_ids(sup,sun,svp,svn,swp,swn,k,n,workspace,nv,nw,ids,3,meta) == 1
              found = 3
        link = nexts[right]
      left += 1

  if found > 0
    z = fftsr_materialize(workspace,nv,nw,ids,found,out_up,out_un,out_vp,out_vn,out_wp,out_wn) ## i64
  meta[7] = found
  found

-> fftsr_find_terms_ws(sup,sun,svp,svn,swp,swn,n,k,want,workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 FFTSRWorkspace i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  z = fftsr_clear_meta(meta) ## i64
  meta[11] = want
  if fftsr_supported(k,want) == 0
    meta[18] = meta[18] + 1
    return 0
  count = fftsr_prepare(sup,sun,svp,svn,swp,swn,n,k,workspace,meta) ## i64
  if count <= 0
    return 0
  fftsr_search_prepared(sup,sun,svp,svn,swp,swn,k,n,want,0-1,workspace,meta,out_up,out_un,out_vp,out_vn,out_wp,out_wn)

# Same exact search, but reject every same-rank endpoint that retains even one
# source term.  A 3<->3 result is therefore not a single ordinary pair flip.
-> fftsr_find_terms_disjoint_ws(sup,sun,svp,svn,swp,swn,n,k,want,workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 FFTSRWorkspace i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  z = fftsr_clear_meta(meta) ## i64
  meta[11] = want
  meta[19] = 1
  if fftsr_supported(k,want) == 0
    meta[18] = meta[18] + 1
    return 0
  count = fftsr_prepare(sup,sun,svp,svn,swp,swn,n,k,workspace,meta) ## i64
  if count <= 0
    return 0
  fftsr_search_prepared(sup,sun,svp,svn,swp,swn,k,n,want,0-1,workspace,meta,out_up,out_un,out_vp,out_vn,out_wp,out_wn)

-> fftsr_extract_current(st,selected,k,sup,sun,svp,svn,swp,swn) (i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if fft_valid(st) == 0 || k < 1 || k > 4
    return 0
  i = 0 ## i64
  while i < k
    if selected[i] < 0 || selected[i] >= st[5]
      return 0
    j = 0 ## i64
    while j < i
      if selected[j] == selected[i]
        return 0
      j += 1
    sup[i] = st[st[32] + selected[i]]
    sun[i] = st[st[33] + selected[i]]
    svp[i] = st[st[34] + selected[i]]
    svn[i] = st[st[35] + selected[i]]
    swp[i] = st[st[36] + selected[i]]
    swn[i] = st[st[37] + selected[i]]
    i += 1
  1

-> fftsr_find_current_ws(st,selected,k,want,workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta) (i64[] i64[] i64 i64 FFTSRWorkspace i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  sup = i64[4]
  sun = i64[4]
  svp = i64[4]
  svn = i64[4]
  swp = i64[4]
  swn = i64[4]
  if fftsr_extract_current(st,selected,k,sup,sun,svp,svn,swp,swn) == 0
    z = fftsr_clear_meta(meta) ## i64
    meta[18] = meta[18] + 1
    return 0
  fftsr_find_terms_ws(sup,sun,svp,svn,swp,swn,st[2],k,want,workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta)

-> fftsr_candidate_id_for_masks(workspace,nv,nw,count,want_up,want_un,want_vp,want_vn,want_wp,want_wn) (FFTSRWorkspace i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  masks = i64[6]
  id = 0 ## i64
  while id < count
    z = fftsr_candidate_masks(workspace,nv,nw,id,masks) ## i64
    if masks[0] == want_up && masks[1] == want_un && masks[2] == want_vp && masks[3] == want_vn && masks[4] == want_wp && masks[5] == want_wn
      return id
    id += 1
  0 - 1

# Search for a three-term local replacement containing the exact opposite of
# one external term.  external_* can be a complete scheme or a caller-chosen
# subset; selected_external marks source slots to skip when both lists refer
# to the same scheme, and may contain -1 for a standalone local fixture.
-> fftsr_find_collision_terms_ws(sup,sun,svp,svn,swp,swn,n,k,external_up,external_un,external_vp,external_vn,external_wp,external_wn,external_count,selected_external,workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] FFTSRWorkspace i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  z = fftsr_clear_meta(meta) ## i64
  meta[11] = 3
  if k != 3
    meta[18] = meta[18] + 1
    return 0
  count = fftsr_prepare(sup,sun,svp,svn,swp,swn,n,k,workspace,meta) ## i64
  if count <= 0
    return 0
  nv = meta[1] ## i64
  nw = meta[2] ## i64
  external = 0 ## i64
  while external < external_count
    skip = 0 ## i64
    i = 0 ## i64
    while i < k
      if selected_external[i] == external
        skip = 1
      i += 1
    if skip == 0
      meta[13] = meta[13] + 1
      fixed = fftsr_candidate_id_for_masks(workspace,nv,nw,count,
        external_up[external],external_un[external],external_vp[external],external_vn[external],
        external_wn[external],external_wp[external]) ## i64
      if fixed >= 0
        meta[14] = meta[14] + 1
        found = fftsr_search_prepared(sup,sun,svp,svn,swp,swn,k,n,3,fixed,workspace,meta,out_up,out_un,out_vp,out_vn,out_wp,out_wn) ## i64
        if found == 3
          meta[15] = external
          return 3
    external += 1
  0

-> fftsr_find_collision_current_ws(st,selected,workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta) (i64[] i64[] FFTSRWorkspace i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  sup = i64[4]
  sun = i64[4]
  svp = i64[4]
  svn = i64[4]
  swp = i64[4]
  swn = i64[4]
  if fftsr_extract_current(st,selected,3,sup,sun,svp,svn,swp,swn) == 0
    z = fftsr_clear_meta(meta) ## i64
    meta[18] = meta[18] + 1
    return 0
  external_up = i64[st[5]]
  external_un = i64[st[5]]
  external_vp = i64[st[5]]
  external_vn = i64[st[5]]
  external_wp = i64[st[5]]
  external_wn = i64[st[5]]
  i = 0 ## i64
  while i < st[5]
    external_up[i] = st[st[32] + i]
    external_un[i] = st[st[33] + i]
    external_vp[i] = st[st[34] + i]
    external_vn[i] = st[st[35] + i]
    external_wp[i] = st[st[36] + i]
    external_wn[i] = st[st[37] + i]
    i += 1
  fftsr_find_collision_terms_ws(sup,sun,svp,svn,swp,swn,st[2],3,external_up,external_un,external_vp,external_vn,external_wp,external_wn,st[5],selected,workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta)

# Exact splice with optional opposite-term cancellation.  The complete current
# scheme is backed up and integer-gated; any malformed replacement or failed
# global gate restores the original byte-for-byte term arrays.
-> fftsr_splice_current(st,selected,k,out_up,out_un,out_vp,out_vn,out_wp,out_wn,out_count,compact) (i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  if fft_valid(st) == 0 || k < 1 || k > 4 || out_count < 1 || out_count > 4
    return 0 - 1
  rank = st[5] ## i64
  old_up = i64[rank]
  old_un = i64[rank]
  old_vp = i64[rank]
  old_vn = i64[rank]
  old_wp = i64[rank]
  old_wn = i64[rank]
  i = 0 ## i64
  while i < rank
    old_up[i] = st[st[32] + i]
    old_un[i] = st[st[33] + i]
    old_vp[i] = st[st[34] + i]
    old_vn[i] = st[st[35] + i]
    old_wp[i] = st[st[36] + i]
    old_wn[i] = st[st[37] + i]
    i += 1
  valid = 1 ## i64
  i = 0
  while i < k
    if selected[i] < 0 || selected[i] >= rank
      valid = 0
    j = 0 ## i64
    while j < i
      if selected[i] == selected[j]
        valid = 0
      j += 1
    i += 1
  if valid == 0
    return 0 - 1

  write = 0 ## i64
  i = 0
  while i < rank
    removed = 0 ## i64
    j = 0
    while j < k
      if selected[j] == i
        removed = 1
      j += 1
    if removed == 0
      st[st[32] + write] = old_up[i]
      st[st[33] + write] = old_un[i]
      st[st[34] + write] = old_vp[i]
      st[st[35] + write] = old_vn[i]
      st[st[36] + write] = old_wp[i]
      st[st[37] + write] = old_wn[i]
      write += 1
    i += 1
  st[5] = write
  i = 0
  while i < out_count && valid == 1
    if fft_vector_valid(st,out_up[i],out_un[i]) == 0 || fft_vector_valid(st,out_vp[i],out_vn[i]) == 0 || fft_vector_valid(st,out_wp[i],out_wn[i]) == 0
      valid = 0
    cancelled = 0 ## i64
    if valid == 1 && compact != 0
      j = 0
      while j < st[5] && cancelled == 0
        if st[st[32]+j] == out_up[i] && st[st[33]+j] == out_un[i] && st[st[34]+j] == out_vp[i] && st[st[35]+j] == out_vn[i] && st[st[36]+j] == out_wn[i] && st[st[37]+j] == out_wp[i]
          z = fft_remove_slot(st,j) ## i64
          cancelled = 1
        j += 1
    if valid == 1 && cancelled == 0
      if st[5] >= st[4]
        valid = 0
      if valid == 1
        slot = st[5] ## i64
        st[st[32]+slot] = out_up[i]
        st[st[33]+slot] = out_un[i]
        st[st[34]+slot] = out_vp[i]
        st[st[35]+slot] = out_vn[i]
        st[st[36]+slot] = out_wp[i]
        st[st[37]+slot] = out_wn[i]
        st[5] = slot + 1
        if fft_canonicalize_slot(st,slot) == 0
          valid = 0
    i += 1
  if valid == 1
    if fft_verify_current_exact(st) == 0
      valid = 0
  if valid == 0
    st[5] = rank
    i = 0
    while i < rank
      st[st[32] + i] = old_up[i]
      st[st[33] + i] = old_un[i]
      st[st[34] + i] = old_vp[i]
      st[st[35] + i] = old_vn[i]
      st[st[36] + i] = old_wp[i]
      st[st[37] + i] = old_wn[i]
      i += 1
    st[20] = fft_current_density(st)
    return 0 - 1
  st[20] = fft_current_density(st)
  st[10] = st[10] + 1
  if rank > st[5]
    st[24] = st[24] + rank - st[5]
  adopted = fft_maybe_adopt(st) ## i64
  if adopted < 0
    return 0 - 1
  st[5]
