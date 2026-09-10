# One native cold child owns this FIFO. A task is one bounded basis context
# or one coordinate projection, not an entire recursive tensor campaign.
# Successors go to the tail. Index pages bind full source identity + context;
# no rank-only filter and no individual task/index file per coordinate.
use counters
use pages
use projection
use refinement

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
  if mode < 0 || mode >= 3090 || raw != "MFT_TASK1 " + fields[1] + " " + mode.to_s() + "\n"
    return 0-1
  mode

-> ffxt_index_kind(mode) (i64)
  if mode < 18
    return "basis"
  "project"

-> ffxt_index_ordinal(mode) (i64) i64
  if mode < 18
    return mode+1
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
  if ffrf_hash_valid(identity) != 1 || mode < 0 || mode >= 3090
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

-> ffxt_coordinates(n, m, p) (i64 i64 i64) i64
  count = 0 ## i64
  if n > 1
    count += n
  if m > 1
    count += m
  if p > 1
    count += p
  count

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
  ffxt_offer(root, fields[2], 18)

-> ffxt_same(left, right, words) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < words
    if left[i] != right[i]
      return 0
    i += 1
  1

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
  if mode < 18
    i = 0 ## i64
    while i < 3*stride*before
      out[i] = source[i]
      i += 1
    passes = 1 ## i64
    axes = 1 ## i64
    permutation = 0 ## i64
    if mode >= 6
      passes = 2
      axes = 3
      permutation = (mode-6)/2
    orders = [0, 1, 2, 0, 2, 1, 1, 0, 2, 1, 2, 0, 2, 0, 1, 2, 1, 0]
    pass = 0 ## i64
    while pass < passes
      i = 0
      while i < axes
        if File.exists?(root + "/stop")
          return 0-1
        axis = mode/2 ## i64
        if mode >= 6
          axis = orders[3*permutation+i]
        rank = ffwm_refactor(out, 3*32*16384, rank, n, m, p, scratch, words, axis, mode%2, 20000000, stats, 6)
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
  if before < 1 || mode >= 18+ffxt_coordinates(info[0], info[1], info[2])
    return 0
  checked = ffpk_exact(source, 3*32*16384, before, info[0], info[1], info[2], parity, 32768, 20000000) ## i64
  if checked != 1
    return 0
  rank = ffxt_propose(root, source, out, before, info[0], info[1], info[2], mode, meta) ## i64
  if rank <= 0
    return rank
  if rank > before
    return 0
  checked = ffpk_exact(out, 3*32*16384, rank, meta[0], meta[1], meta[2], parity, 32768, 20000000)
  if checked != 1 && checked != 0-1
    return 0
  if File.exists?(root + "/stop")
    return 0-1
  status = 1+meta[4] ## i64
  result = "-"
  admitted = 0 ## i64
  if checked == 0-1
    status = 3
  else
    output = ffpk_blob(out, rank, meta[0], meta[1], meta[2])
    result = Crypto:SHA256.hexdigest(output)
    if ffwc_index_kind(root, result, output, rank, meta[0], meta[1], meta[2], identity, "MFW_TRANSFORM1") != 1
      return 0
    admitted = rank
  # Offer at most two continuations. Paged per-source indexes make a replay
  # idempotent even if other producers append after an interrupted task.
  successor = 0 ## i64
  if mode < 17 || (mode >= 18 && mode+1 < 18+ffxt_coordinates(info[0], info[1], info[2]))
    successor = ffxt_offer(root, identity, mode+1)
    if successor != 1
      return successor
  if mode < 18 && admitted > 0 && result != identity && ffxt_coordinates(meta[0], meta[1], meta[2]) > 0
    successor = ffxt_offer(root, result, 18)
    if successor != 1
      return successor
  record = "MFT_RESULT1 " + Crypto:SHA256.hexdigest(raw) + " " + result + " " + meta[0].to_s() + " " + meta[1].to_s() + " " + meta[2].to_s() + " " + before.to_s() + " " + rank.to_s() + " " + admitted.to_s() + " " + status.to_s() + " " + meta[3].to_s() + "\n"
  if File.exists?(root + "/stop")
    return 0-1
  if ffbq_put(queue, "results", sequence, record) != 1
    return 0
  delta = 0 ## i64
  if admitted > 0
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
