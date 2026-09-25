# One native cold child owns this FIFO. A task is one bounded basis context,
# coordinate projection, axis-mask family, walk, or shared-factor composition.
# The best projection
# of each axis gets two terminal basis sweeps. A strict rank drop at either
# sweep or mask boundary schedules projections, so productive chains continue.
# Successors go to the tail. Index pages bind full source identity + context;
# no rank-only filter and no individual task/index file per coordinate.
use counters
use pages
use projection
use refinement
use feedback
use ../wide/directed
use wide_pairs

# Stop creating fresh wide roots while this lane is above its high-water
# mark. Existing finite continuations still run; this is not a disk quota.
-> ffxt_turn(pending, primary_pending, completed) (i64 i64 i64) i64
  if pending < 1
    return 0
  if pending >= 256 || primary_pending <= 0 || completed%3 == 2
    return 1
  0

-> ffxt_mode(raw) (String) i64
  if raw == nil || raw == ""
    return 0-1
  fields = raw.strip().split(" ")
  if fields.size() != 3 || fields[0] != "MFT_TASK1" || ffrf_hash_valid(fields[1]) != 1
    return 0-1
  mode = ffpk_decimal(fields[2]) ## i64
  if mode < 0 || mode >= 3134 || raw != "MFT_TASK1 " + fields[1] + " " + mode.to_s() + "\n"
    return 0-1
  mode

-> ffxt_index_kind(mode) (i64)
  if mode < 18
    return "basis"
  if mode == 3126
    return "mask"
  if mode == 3127
    return "mask-first"
  if mode == 3128
    return "mask-last"
  if mode == 3129
    return "walk"
  if mode == 3130
    return "walk-continue"
  if mode == 3131
    return "compose-first"
  if mode == 3132
    return "compose-middle"
  if mode == 3133
    return "compose-last"
  if mode >= 3090
    return "postbasis"
  "project"

-> ffxt_index_ordinal(mode) (i64) i64
  if mode < 18
    return mode+1
  if mode >= 3126
    return 1
  if mode >= 3090
    return mode-3089
  mode-17

-> ffxt_bind(queue, raw, ticket) (String String i64) i64
  mode = ffxt_mode(raw) ## i64
  if mode < 0 || ticket < 1 || ticket > 1000000000000
    return 0
  fields = raw.strip().split(" ")
  index = queue + "index/" + fields[1] + "/"
  kind = ffxt_index_kind(mode)
  if !File.mkdir_p(index + kind + "-pages")
    return 0
  ffbq_put(index, kind, ffxt_index_ordinal(mode), ticket.to_s() + "\n")

# Append/index/counter order leaves at most one unacknowledged tail record.
# Recover before any new producer appends, including after a stopped worker.
-> ffxt_recover(queue) (String) i64
  submitted = ffmd_count(queue + "submitted") ## i64
  consumed = ffmd_count(queue + "consumed") ## i64
  if submitted < 0 || consumed < 0 || submitted >= 1000000000000
    return 0
  raw = ffbq_read(queue, "tasks", submitted+1)
  if raw != nil
    if ffxt_mode(raw) < 0 || ffbq_read(queue, "tasks", submitted+2) != nil || ffxt_bind(queue, raw, submitted+1) != 1
      return 0
    submitted += 1
    if ffrf_atomic(queue + "submitted", submitted.to_s() + "\n", "wide-transform") != 1
      return 0
  if consumed > submitted
    return 0
  if submitted > 0 && ffxt_bind(queue, ffbq_read(queue, "tasks", submitted), submitted) != 1
    return 0
  1

-> ffxt_offer(root, identity, mode) (String String i64) i64
  if File.exists?(root + "/stop")
    return 0-1
  queue = root + "/composition/transforms/"
  if ffrf_hash_valid(identity) != 1 || mode < 0 || mode >= 3134
    return 0
  names = ["tasks-pages", "results-pages", "index"]
  i = 0 ## i64
  while i < names.size()
    if !File.mkdir_p(queue + names[i])
      return 0
    i += 1
  if ffxt_recover(queue) != 1
    return 0
  raw = "MFT_TASK1 " + identity + " " + mode.to_s() + "\n"
  index = queue + "index/" + identity + "/"
  kind = ffxt_index_kind(mode)
  ordinal = ffxt_index_ordinal(mode) ## i64
  old = ffbq_read(index, kind, ordinal)
  submitted = ffmd_count(queue + "submitted") ## i64
  if old != nil
    ticket = ffpk_decimal(old.strip()) ## i64
    if ticket < 1 || ticket > submitted || old != ticket.to_s() + "\n" || ffbq_read(queue, "tasks", ticket) != raw
      return 0
    return 1
  # A context cannot be offered out of order within its source's family.
  if ordinal > 1
    prior = ffbq_read(index, kind, ordinal-1)
    if prior == nil || prior == ""
      return 0
  if submitted >= 999999999999 || ffbq_put(queue, "tasks", submitted+1, raw) != 1 || ffxt_bind(queue, raw, submitted+1) != 1
    return 0
  ffrf_atomic(queue + "submitted", (submitted+1).to_s() + "\n", "wide-transform")

-> ffxt_offer_masks(root, identity, n, m, p) (String String i64 i64 i64) i64
  if m >= 2 && m <= 32 && ffxt_offer(root, identity, 3126) != 1
    return 0
  if n >= 2 && n <= 32 && ffxt_offer(root, identity, 3127) != 1
    return 0
  if p >= 2 && p <= 32 && ffxt_offer(root, identity, 3128) != 1
    return 0
  1

-> ffxt_coordinates(n, m, p) (i64 i64 i64) i64
  count = 0 ## i64
  if n > 1
    count += n
  if m > 1
    count += m
  if p > 1
    count += p
  count

# A short probe is cheap on newly admitted multiword tensors; a longer
# continuation is offered only after a strict rank drop. The same cold child
# owns both modes, so live CPU/GPU islands are never blocked by a walk.
-> ffxt_walkable(n, m, p, rank) (i64 i64 i64 i64) i64
  if n < 2 || m < 2 || p < 2 || n > 32 || m > 32 || p > 32 || rank < 2 || rank > 8000
    return 0
  1

-> ffxt_offer_pairs(root, identity, n, m, p, rank) (String String i64 i64 i64 i64) i64
  if rank < 1 || rank > 900 || n < 2 || m < 2 || p < 2 || n > 32 || m > 32 || p > 32
    return 1
  blob = File.read_prefix(root + "/composition/objects/" + identity + ".tensor", 12632129)
  if blob == nil || Crypto:SHA256.hexdigest(blob) != identity
    return 0
  source = i64[3*32*900]
  info = i64[4]
  if ffpk_parse(blob,source,source.size(),info,4) != rank || info[0] != n || info[1] != m || info[2] != p
    return 0
  axis = 0 ## i64
  while axis < 3
    if pair_profile(source,rank,n,m,p,axis) >= 4 && ffxt_offer(root,identity,3131+axis) != 1
      return 0
    axis += 1
  1

# Only a strict best-rank drop at a sweep boundary starts another projection
# generation. Projected dimensions and rank both decrease along this edge;
# intermediate contexts cannot each fan out into their own projection family.
-> ffxt_reproject(mode, before, after, coordinates) (i64 i64 i64 i64) i64
  if (mode == 3107 || mode == 3125) && after > 0 && after < before && coordinates > 0
    return 1
  0

# Called only after original and cleanup gates. Project the verified cleanup
# result, never the unadmitted slab left by a verification-limited cleanup.
-> ffxt_intake(root, source, n, m, p) (String String i64 i64 i64) i64
  if env("METAFLIP_WIDE_TRANSFORMS") == "0"
    return 1
  raw = File.read_prefix(root + "/composition/cleanup/results/" + source, 320)
  if raw == nil
    return 0
  fields = raw.strip().split(" ")
  if fields.size() != 12 || fields[0] != "MFW_CLEAN1" || fields[1] != source || ffrf_hash_valid(fields[2]) != 1
    return 0
  offered = ffxt_offer(root, fields[2], 0) ## i64
  if offered != 1 || ffxt_coordinates(n, m, p) == 0
    return offered
  offered = ffxt_offer(root, fields[2], 18)
  if offered != 1
    return offered
  rank = ffpk_decimal(fields[6]) ## i64
  best = File.read_prefix(root + "/composition/best/" + n.to_s() + "x" + m.to_s() + "x" + p.to_s(), 100)
  if ffxt_walkable(n, m, p, rank) == 1 && best == rank.to_s() + " " + fields[2] + "\n"
    offered = ffxt_offer(root, fields[2], 3129)
    if offered != 1
      return offered
  if best == rank.to_s() + " " + fields[2] + "\n"
    return ffxt_offer_pairs(root,fields[2],n,m,p,rank)
  1

-> ffxt_same(left, right, words) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < words
    if left[i] != right[i]
      return 0
    i += 1
  1

# One exact axis shear/projection/cleanup context. The changed first-factor
# coordinate vanishes under projection; projection.w materializes the opposite
# incident factor's XORs. Published winners pass the whole-tensor gate.
-> ffxt_mask_rank(source, before, n, m, p, axis, removed, mask, scratch, words, out, stats, meta) (i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64 i64[] i64[] i64[]) i64
  projected = ffwp_axis_mask_project(source, 3*32*16384, before, n, m, p, axis, removed, mask, scratch, words, out, 3*32*16384) ## i64
  if projected < 1
    return 0
  nn = n ## i64
  mm = m ## i64
  pp = p ## i64
  if axis == 0
    nn -= 1
  elsif axis == 1
    mm -= 1
  else
    pp -= 1
  rank = ffwm_reduce(out, 3*32*16384, projected, nn, mm, pp, scratch, words, 20000000, stats, 6) ## i64
  if rank < 1
    return 0
  meta[3] += stats[0]
  if stats[2] != 0
    meta[4] = 1
  rank

# Bounded context family: all one-coordinate shears choose a deletion coordinate,
# then empty/two/three-coordinate masks are evaluated there. This is a search
# heuristic, not a claim that other bases are dominated.
-> ffxt_mask_scan(root, source, before, n, m, p, axis, scratch, words, out, meta, selection) (String i64[] i64 i64 i64 i64 i64 i64[] i64 i64[] i64[] i64[]) i64
  size = n ## i64
  if axis == 1
    size = m
  elsif axis == 2
    size = p
  if axis < 0 || axis > 2 || size < 2 || size > 32
    return 0
  stats = i64[6]
  best = before+1 ## i64
  selected = 0-1 ## i64
  winner = 0 ## i64
  a = 0 ## i64
  while a < size
    b = 0 ## i64
    while b < size
      if File.exists?(root + "/stop")
        return 0-1
      if a != b
        rank = ffxt_mask_rank(source, before, n, m, p, axis, a, 1 << b, scratch, words, out, stats, meta) ## i64
        if rank < 1
          return 0
        if rank < best
          best = rank
          selected = a
          winner = 1 << b
      b += 1
    a += 1
  a = selected
  rank = ffxt_mask_rank(source, before, n, m, p, axis, a, 0, scratch, words, out, stats, meta) ## i64
  if rank < 1
    return 0
  if rank < best
    best = rank
    winner = 0
  b = 0 ## i64
  while b < size
    if b != a
      c = b+1 ## i64
      while c < size
        if c != a
          mask = (1 << b) | (1 << c) ## i64
          rank = ffxt_mask_rank(source, before, n, m, p, axis, a, mask, scratch, words, out, stats, meta) ## i64
          if rank < 1
            return 0
          if rank < best
            best = rank
            winner = mask
          d = c+1 ## i64
          while d < size
            if File.exists?(root + "/stop")
              return 0-1
            if d != a
              mask = (1 << b) | (1 << c) | (1 << d) ## i64
              rank = ffxt_mask_rank(source, before, n, m, p, axis, a, mask, scratch, words, out, stats, meta) ## i64
              if rank < 1
                return 0
              if rank < best
                best = rank
                winner = mask
            d += 1
        c += 1
    b += 1
  if File.exists?(root + "/stop")
    return 0-1
  rank = ffxt_mask_rank(source, before, n, m, p, axis, a, winner, scratch, words, out, stats, meta) ## i64
  if rank != best
    return 0
  selection[0] = a
  selection[1] = winner
  rank

# Returns rank; result meta = n,m,p,charged work,work-limited. A basis task
# uses at most six axis calls plus cleanup, each capped at 20M algebra work.
-> ffxt_propose(root, source, out, before, n, m, p, mode, meta) (String i64[] i64[] i64 i64 i64 i64 i64 i64[]) i64
  stride = ffpk_stride(n, m, p) ## i64
  words = ffwm_scratch_words(before, stride) ## i64
  scratch = i64[words]
  stats = i64[6]
  meta[0] = n
  meta[1] = m
  meta[2] = p
  meta[3] = 0
  meta[4] = 0
  rank = before ## i64
  if mode >= 3126 && mode <= 3128
    axis = 1 ## i64
    if mode == 3127
      axis = 0
    if mode == 3128
      axis = 2
    chosen = i64[2]
    rank = ffxt_mask_scan(root, source, before, n, m, p, axis, scratch, words, out, meta, chosen)
    if rank > 0
      meta[axis] -= 1
    return rank
  basis_mode = mode ## i64
  if mode >= 3090
    basis_mode -= 3090
    if basis_mode >= 18
      basis_mode -= 18
  if basis_mode < 18
    i = 0 ## i64
    while i < 3*stride*before
      out[i] = source[i]
      i += 1
    passes = 1 ## i64
    axes = 1 ## i64
    permutation = 0 ## i64
    if basis_mode >= 6
      passes = 2
      axes = 3
      permutation = (basis_mode-6)/2
    orders = [0, 1, 2, 0, 2, 1, 1, 0, 2, 1, 2, 0, 2, 0, 1, 2, 1, 0]
    pass = 0 ## i64
    while pass < passes
      i = 0
      while i < axes
        if File.exists?(root + "/stop")
          return 0-1
        axis = basis_mode/2 ## i64
        if basis_mode >= 6
          axis = orders[3*permutation+i]
        rank = ffwm_refactor(out, 3*32*16384, rank, n, m, p, scratch, words, axis, basis_mode%2, 20000000, stats, 6)
        if rank < 1
          return 0
        meta[3] += stats[0]
        if stats[2] != 0
          meta[4] = 1
        i += 1
      pass += 1
      if rank == before && ffxt_same(source, out, 3*stride*rank) == 1
        break
  else
    coordinate = mode-18 ## i64
    axis = 0 ## i64
    while axis < 3
      size = meta[axis] ## i64
      if size > 1
        if coordinate < size
          break
        coordinate -= size
      axis += 1
    if axis >= 3
      return 0
    rank = ffwp_project(source, 3*32*16384, before, n, m, p, axis, coordinate, out, 3*32*16384)
    if rank < 1
      return 0
    meta[axis] -= 1
  if File.exists?(root + "/stop")
    return 0-1
  rank = ffwm_reduce(out, 3*32*16384, rank, meta[0], meta[1], meta[2], scratch, words, 20000000, stats, 6)
  meta[3] += stats[0]
  if stats[2] != 0
    meta[4] = 1
  rank

-> ffxt_walk(root, source, out, before, n, m, p, mode, sequence, meta) (String i64[] i64[] i64 i64 i64 i64 i64 i64 i64[]) i64
  if ffxt_walkable(n, m, p, before) != 1 || (mode != 3129 && mode != 3130)
    return 0
  stride = ffpk_stride(n, m, p) ## i64
  cap = before+64 ## i64
  state = i64[ffws_words_rect(n, m, p, cap)]
  nonce = 25000000+sequence%1000000000 ## i64
  if ffws_init_rect(state, n, m, p, cap, source, before, nonce) != 1
    return 0
  control = i64[ffwd_words(state, 4096)]
  if ffwd_init(state, control, 2, 4096) != 1
    return 0
  scratch = i64[12*stride]
  stop = i64[1]
  remaining = 1000000 ## i64
  if mode == 3130
    remaining = 10000000
  while remaining > 0
    if File.exists?(root + "/stop")
      return 0-1
    batch = remaining ## i64
    if batch > 100000
      batch = 100000
    if ffwd_work(state, scratch, control, batch, stop, 8) < 0
      return 0
    remaining -= batch
  rank = ffws_export(state, out, 1) ## i64
  if rank < 1 || rank > before || ffpk_canonicalize(out, out.size(), rank, stride) != rank
    return 0
  meta[0] = n
  meta[1] = m
  meta[2] = p
  meta[3] = state[7]
  meta[4] = 0
  rank

-> ffxt_task(root, sequence) (String i64) i64
  queue = root + "/composition/transforms/"
  raw = ffbq_read(queue, "tasks", sequence)
  mode = ffxt_mode(raw) ## i64
  if mode < 0
    return 0
  fields = raw.strip().split(" ")
  identity = fields[1]
  blob = File.read_prefix(root + "/composition/objects/" + identity + ".tensor", 12632129)
  if blob == nil || Crypto:SHA256.hexdigest(blob) != identity
    return 0
  source = i64[3*32*16384]
  out = i64[3*32*16384]
  parity = i64[32768]
  info = i64[4]
  meta = i64[5]
  before = ffpk_parse(blob, source, 3*32*16384, info, 4) ## i64
  mask_axis = 1 ## i64
  if mode == 3127
    mask_axis = 0
  if mode == 3128
    mask_axis = 2
  if before < 1 || (mode >= 18 && mode < 3090 && mode >= 18+ffxt_coordinates(info[0], info[1], info[2])) || (mode >= 3126 && (info[mask_axis] < 2 || info[mask_axis] > 32))
    return 0
  checked = ffpk_exact(source, 3*32*16384, before, info[0], info[1], info[2], parity, 32768, 20000000) ## i64
  if checked != 1
    return 0
  rank = 0 ## i64
  if mode >= 3131
    rank = pair_compose(source,before,info[0],info[1],info[2],mode-3131,out,meta)
  elsif mode >= 3129
    rank = ffxt_walk(root, source, out, before, info[0], info[1], info[2], mode, sequence, meta)
  else
    rank = ffxt_propose(root, source, out, before, info[0], info[1], info[2], mode, meta)
  if rank <= 0
    return rank
  if rank > before && mode < 3131
    return 0
  checked = ffpk_exact(out, 3*32*16384, rank, meta[0], meta[1], meta[2], parity, 32768, 20000000)
  if checked != 1 && checked != 0-1
    return 0
  if File.exists?(root + "/stop")
    return 0-1
  status = 1+meta[4] ## i64
  result = "-"
  admitted = 0 ## i64
  new_best = 0 ## i64
  if checked == 0-1
    status = 3
  else
    output = ffpk_blob(out, rank, meta[0], meta[1], meta[2])
    result = Crypto:SHA256.hexdigest(output)
    shape = meta[0].to_s() + "x" + meta[1].to_s() + "x" + meta[2].to_s()
    previous = File.read_prefix(root + "/composition/best/" + shape, 100)
    prior_rank = 16385 ## i64
    if previous != nil
      parts = previous.strip().split(" ")
      if parts.size() != 2 || ffrf_hash_valid(parts[1]) != 1
        return 0
      prior_rank = ffpk_decimal(parts[0])
      if prior_rank < 1 || prior_rank > 16384 || previous != prior_rank.to_s() + " " + parts[1] + "\n"
        return 0
    if rank < prior_rank
      new_best = 1
    if ffwc_index_kind(root, result, output, rank, meta[0], meta[1], meta[2], identity, "MFW_TRANSFORM1") != 1
      return 0
    offered = ffwf_publish(root, result, output, rank, meta[0], meta[1], meta[2]) ## i64
    if offered != 1
      return offered
    if mode < 3129 && new_best == 1 && ffxt_walkable(meta[0], meta[1], meta[2], rank) == 1
      offered = ffxt_offer(root, result, 3129)
      if offered != 1
        return offered
    if new_best == 1 && ffxt_offer_pairs(root,result,meta[0],meta[1],meta[2],rank) != 1
      return 0
    admitted = rank
  # Offer bounded continuations. Paged per-source indexes make a replay
  # idempotent even if other producers append after an interrupted task.
  successor = 0 ## i64
  if mode < 17 || (mode >= 18 && mode < 3090 && mode+1 < 18+ffxt_coordinates(info[0], info[1], info[2])) || (mode >= 3090 && mode < 3107) || (mode >= 3108 && mode < 3125)
    successor = ffxt_offer(root, identity, mode+1)
    if successor != 1
      return successor
  if mode < 18 && admitted > 0 && result != identity && ffxt_coordinates(meta[0], meta[1], meta[2]) > 0
    successor = ffxt_offer(root, result, 18)
    if successor != 1
      return successor
  if mode == 3107 || mode == 3125
    shape = info[0].to_s() + "x" + info[1].to_s() + "x" + info[2].to_s()
    best = File.read_prefix(root + "/composition/best/" + shape, 100)
    if best != nil
      parts = best.strip().split(" ")
      if parts.size() != 2 || ffpk_decimal(parts[0]) < 1 || ffrf_hash_valid(parts[1]) != 1 || best != parts[0] + " " + parts[1] + "\n"
        return 0
      if mode == 3107
        # The best may have changed while this source's first sweep was
        # queued. Start its first family if its last context is not offered.
        next_mode = 3108 ## i64
        if ffbq_read(queue + "index/" + parts[1] + "/", "postbasis", 18) == nil
          next_mode = 3090
        successor = ffxt_offer(root, parts[1], next_mode)
        if successor != 1
          return successor
      if ffxt_reproject(mode, before, ffpk_decimal(parts[0]), ffxt_coordinates(meta[0], meta[1], meta[2])) == 1
        successor = ffxt_offer(root, parts[1], 18)
        if successor != 1
          return successor
      if mode == 3125
        successor = ffxt_offer_masks(root, parts[1], info[0], info[1], info[2])
        if successor != 1
          return successor
  if mode >= 3126 && mode <= 3128 && admitted > 0 && rank < before && ffxt_coordinates(meta[0], meta[1], meta[2]) > 0
    successor = ffxt_offer(root, result, 18)
    if successor != 1
      return successor
    # A masked child can still have removable shared-factor rows. The ordinary
    # postbasis sweep found certified strict drops after three axis masks;
    # one-dimensional tensors already meet their flattening rank bound.
    if meta[0] > 1 && meta[1] > 1 && meta[2] > 1
      successor = ffxt_offer(root, result, 3090)
      if successor != 1
        return successor
  if (mode == 3129 || mode == 3130) && admitted > 0 && result != identity
    successor = ffxt_offer(root, result, 18)
    if successor != 1
      return successor
    if mode == 3129 && rank < before
      successor = ffxt_offer(root, result, 3130)
      if successor != 1
        return successor
  if mode >= 3131 && admitted > 0 && new_best == 1
    successor = ffxt_offer(root,result,0)
    if successor != 1
      return successor
    successor = ffxt_offer(root,result,18)
    if successor != 1
      return successor
  if mode >= 18 && mode < 3090
    coordinate = mode-18 ## i64
    axis = 0 ## i64
    while axis < 3
      size = info[axis] ## i64
      if size > 1
        if coordinate < size
          if coordinate == size-1
            shape = meta[0].to_s() + "x" + meta[1].to_s() + "x" + meta[2].to_s()
            best = File.read_prefix(root + "/composition/best/" + shape, 100)
            if best != nil
              parts = best.strip().split(" ")
              if parts.size() != 2 || ffpk_decimal(parts[0]) < 1 || ffrf_hash_valid(parts[1]) != 1 || best != parts[0] + " " + parts[1] + "\n"
                return 0
              successor = ffxt_offer(root, parts[1], 3090)
              if successor != 1
                return successor
          break
        coordinate -= size
      axis += 1
    if mode == 17+ffxt_coordinates(info[0], info[1], info[2])
      shape = info[0].to_s() + "x" + info[1].to_s() + "x" + info[2].to_s()
      best = File.read_prefix(root + "/composition/best/" + shape, 100)
      if best != nil
        parts = best.strip().split(" ")
        if parts.size() != 2 || ffpk_decimal(parts[0]) < 1 || ffrf_hash_valid(parts[1]) != 1 || best != parts[0] + " " + parts[1] + "\n"
          return 0
        successor = ffxt_offer_masks(root, parts[1], info[0], info[1], info[2])
        if successor != 1
          return successor
  record = "MFT_RESULT1 " + Crypto:SHA256.hexdigest(raw) + " " + result + " " + meta[0].to_s() + " " + meta[1].to_s() + " " + meta[2].to_s() + " " + before.to_s() + " " + rank.to_s() + " " + admitted.to_s() + " " + status.to_s() + " " + meta[3].to_s() + "\n"
  if File.exists?(root + "/stop")
    return 0-1
  if ffbq_put(queue, "results", sequence, record) != 1
    return 0
  delta = 0 ## i64
  if admitted > 0 && admitted < before
    delta = before-admitted
  ffrf_atomic(queue + "last", status.to_s() + " " + delta.to_s() + "\n", "wide-transform")

-> ffxt_failure(queue, sequence) (String i64) i64
  count = ffbc_counter(queue + "failures") + 1 ## i64
  z = ffrf_atomic(queue + "failures", count.to_s() + "\n", "wide-transform") ## i64
  z = ffrf_atomic(queue + "error", "task=" + sequence.to_s() + "\n", "wide-transform")
  << "METAFLIP_WIDE_TRANSFORM_FAILED task=" + sequence.to_s()
  1

-> ffxt_drain(root, limit) (String i64) i64
  if limit < 1 || limit > 4
    return 2
  if File.exists?(root + "/stop") || env("METAFLIP_WIDE_TRANSFORMS") == "0"
    return 0
  queue = root + "/composition/transforms/"
  consumed = ffmd_count(queue + "consumed") ## i64
  if ffxt_recover(queue) != 1
    return ffxt_failure(queue, consumed+1)
  count = 0 ## i64
  while count < limit && consumed < ffmd_count(queue + "submitted")
    if File.exists?(root + "/stop")
      return 0
    result = ffxt_task(root, consumed+1) ## i64
    if result == 0-1
      return 0
    if result != 1
      return ffxt_failure(queue, consumed+1)
    consumed += 1
    if ffrf_atomic(queue + "consumed", consumed.to_s() + "\n", "wide-transform") != 1
      return ffxt_failure(queue, consumed)
    ccall("__w_unlink", queue + "error")
    count += 1
  << "METAFLIP_WIDE_TRANSFORM_COMPLETED done=" + consumed.to_s() + " pending=" + (ffmd_count(queue + "submitted")-consumed).to_s()
  0
