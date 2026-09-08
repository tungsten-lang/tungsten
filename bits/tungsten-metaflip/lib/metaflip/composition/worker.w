# Incremental, certificate-backed pair composition. One native low-priority
# process owns this queue. FIFO work is durable; a price is never verification.
use ../fleet/refinement_artifacts
use ../compose
use pairs

-> ffbc_counter(path) (String) i64
  raw = File.read_prefix(path, 32)
  if raw == nil
    return 0
  value = ffw_parse_decimal_i64(raw.strip()) ## i64
  if value < 0 || value > 1000000000000
    return 0
  value

-> ffbc_leaf(root, runtime, scale, work, source, parity) (String String i64 i64[] i64[] i64[])
  cap = ffrf_capacity() ## i64
  meta = i64[4]
  marker = root + "/composition/leaves/" + scale.to_s()
  old = File.read_prefix(marker, 66)
  if old != nil
    identity = old.strip()
    if ffrf_load(root, identity, work, cap, meta, parity) == 1 && meta[0] == 2 && meta[1] == scale && meta[2] == scale
      return identity
    return ""
  us = i64[64]
  vs = i64[64]
  ws = i64[64]
  path = runtime + "/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt"
  n = 2 ## i64
  m = 2 ## i64
  p = 2 ## i64
  if scale == 3
    path = runtime + "/seeds/gf2/matmul_2x3x5_rank26_peterson_2026_block15_11_gf2.txt"
    m = 3
    p = 5
  rank = ffsc_load(path, us, vs, ws, 64) ## i64
  if rank < 1
    return ""
  i = 0 ## i64
  while i < rank
    source[i] = us[i]
    source[cap+i] = vs[i]
    source[2*cap+i] = ws[i]
    i += 1
  if ffrf_exact(source, cap, rank, n, m, p, parity) != 1
    return ""
  if scale == 3
    rank = ffmp_project(source, 3*cap, cap, rank, 2, 3, 5, 2, 4, work, ffmc_scratch_words(cap), cap)
    rank = ffmp_project(work, ffmc_scratch_words(cap), cap, rank, 2, 3, 4, 2, 3, source, 3*cap, cap)
    z = ffrf_copy(work, source, cap, rank) ## i64
    rank = ffpc_reduce(work, ffmc_scratch_words(cap), cap, rank, 0, 1, 2)
    rank = ffmc_reduce(work, ffmc_scratch_words(cap), cap, rank)
  elsif scale == 4
    # Four disjoint <2,2,2> blocks form an exact <2,4,4> leaf.
    block = 0 ## i64
    while block < 4
      i = 0
      while i < rank
        axis = 0 ## i64
        while axis < 3
          rowoff = 0 ## i64
          coloff = (block/2)*2 ## i64
          if axis == 1
            rowoff = (block/2)*2
            coloff = (block%2)*2
          if axis == 2
            coloff = (block%2)*2
          value = source[axis*cap+i] ## i64
          mapped = 0 ## i64
          bit = 0 ## i64
          while bit < 4
            if ((value >> bit) & 1) != 0
              mapped = mapped ^ (1 << ((bit/2+rowoff)*4+bit%2+coloff))
            bit += 1
          work[axis*cap+block*rank+i] = mapped
          axis += 1
        i += 1
      block += 1
    rank *= 4
  else
    z = ffrf_copy(work, source, cap, rank) ## i64
  if ffrf_exact(work, cap, rank, 2, scale, scale, parity) != 1
    return ""
  identity = ffrf_store(root, work, cap, rank, 2, scale, scale, "composition")
  if identity == "" || ffrf_atomic(marker, identity + "\n", "composition") != 1
    return ""
  identity

-> ffbc_submit_parent(root, identity, leaves, ranks, work, meta, parity, mates) i64
  if ffrf_hash_valid(identity) != 1
    return 0
  marker = root + "/composition/parents/" + identity
  if File.exists?(marker)
    return 1
  cap = ffrf_capacity() ## i64
  if ffrf_load(root, identity, work, cap, meta, parity) != 1
    return 0
  queue = root + "/composition/"
  sequence = ffbc_counter(queue + "submitted") ## i64
  # Recover a task committed just before its counter/dedup index.
  while File.exists?(queue + "tasks/" + (sequence+1).to_s())
    sequence += 1
  if sequence > 0
    tail = File.read_prefix(queue + "tasks/" + sequence.to_s(), 257)
    if tail == nil || tail.size() > 256
      return 0
    tail_id = Crypto:SHA256.hexdigest(tail)
    if ffrf_atomic(queue + "by-id/" + tail_id, sequence.to_s() + "\n", "composition") != 1
      return 0
  axis = 0 ## i64
  while axis < 3
    pairs = ffbd_pairs(work, 3*cap, cap, meta[3], axis, mates, cap) ## i64
    if pairs < 0
      return 0
    scale = 2 ## i64
    while scale <= 4
      n = meta[0]*ffbd_scale(axis, 0, scale) ## i64
      m = meta[1]*ffbd_scale(axis, 1, scale) ## i64
      p = meta[2]*ffbd_scale(axis, 2, scale) ## i64
      predicted = (meta[3]-2*pairs)*scale*scale+pairs*ranks[scale-2] ## i64
      # Scheduling family: only recipes better than this parent's naive
      # Kronecker expansion. This is not an exhaustive-search lower bound.
      if pairs > 0 && predicted < meta[3]*scale*scale && predicted <= 16384 && ffpk_stride(n, m, p) > 0
        body = "MFC1 " + identity + " " + leaves[scale-2] + " " + axis.to_s() + " " + scale.to_s() + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + predicted.to_s() + "\n"
        task_id = Crypto:SHA256.hexdigest(body)
        previous = File.read_prefix(queue + "by-id/" + task_id, 32)
        if previous == nil
          sequence += 1
          if ffrf_atomic(queue + "tasks/" + sequence.to_s(), body, "composition") != 1 || ffrf_atomic(queue + "by-id/" + task_id, sequence.to_s() + "\n", "composition") != 1
            return 0
        else
          stored = File.read_prefix(queue + "tasks/" + previous.strip(), 257)
          if stored != body
            return 0
      scale += 1
    axis += 1
  if ffrf_atomic(queue + "submitted", sequence.to_s() + "\n", "composition") != 1
    return 0
  ffrf_atomic(marker, "pair-scales-2-4-v1\n", "composition")

# Called before the refinement completion manifest: a crash/stop cannot
# acknowledge the source job while losing its composition intake.
-> ffbc_prepare(root, runtime, identity, ids) i64
  if runtime == ""
    return 1
  directories = ["tasks", "by-id", "parents", "objects", "results", "leaves", "best", "by-shape"]
  i = 0 ## i64
  while i < directories.size()
    if !File.mkdir_p(root + "/composition/" + directories[i])
      return 0
    i += 1
  cap = ffrf_capacity() ## i64
  work = i64[ffmc_scratch_words(cap)]
  source = i64[3*cap]
  meta = i64[4]
  parity = i64[4096]
  mates = i64[cap]
  ranks = i64[3]
  leaves = []
  scale = 2 ## i64
  while scale <= 4
    leaf = ffbc_leaf(root, runtime, scale, work, source, parity)
    if leaf == "" || ffrf_load(root, leaf, work, cap, meta, parity) != 1
      return 0
    ranks[scale-2] = meta[3]
    leaves.push(leaf)
    scale += 1
  if ffbc_submit_parent(root, identity, leaves, ranks, work, meta, parity, mates) != 1
    return 0
  i = 0
  while i < ids.size()
    if File.exists?(root + "/stop")
      return 0-1
    if ffbc_submit_parent(root, ids[i], leaves, ranks, work, meta, parity, mates) != 1
      return 0
    i += 1
  1

# Inputs and leaves are rechecked. The full multiword result crosses the exact
# tensor gate BEFORE archive/best/result writes. Formula ranks are not gates.
-> ffbc_task(root, sequence, parent, leaf, mates, out, scratch, parity) (String i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  queue = root + "/composition/"
  raw = File.read_prefix(queue + "tasks/" + sequence.to_s(), 257)
  if raw == nil || raw.size() > 256
    return 0
  fields = raw.strip().split(" ")
  if fields.size() != 9 || fields[0] != "MFC1" || ffrf_hash_valid(fields[1]) != 1 || ffrf_hash_valid(fields[2]) != 1
    return 0
  axis = ffw_parse_decimal_i64(fields[3]) ## i64
  scale = ffw_parse_decimal_i64(fields[4]) ## i64
  if axis < 0 || axis > 2 || scale < 2 || scale > 4
    return 0
  cap = ffrf_capacity() ## i64
  meta = i64[4]
  lm = i64[4]
  if ffrf_load(root, fields[1], parent, cap, meta, parity) != 1 || ffrf_load(root, fields[2], leaf, cap, lm, parity) != 1 || lm[0] != 2 || lm[1] != scale || lm[2] != scale
    return 0
  n = meta[0]*ffbd_scale(axis, 0, scale) ## i64
  m = meta[1]*ffbd_scale(axis, 1, scale) ## i64
  p = meta[2]*ffbd_scale(axis, 2, scale) ## i64
  pairs = ffbd_pairs(parent, 3*cap, cap, meta[3], axis, mates, cap) ## i64
  predicted = (meta[3]-2*pairs)*scale*scale+pairs*lm[3] ## i64
  canonical = "MFC1 " + fields[1] + " " + fields[2] + " " + axis.to_s() + " " + scale.to_s() + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + predicted.to_s() + "\n"
  if raw != canonical
    return 0
  task_id = Crypto:SHA256.hexdigest(raw)
  rank = ffbd_compose(parent, 3*cap, cap, meta[3], meta[0], meta[1], meta[2], axis, scale, leaf, 3*cap, cap, lm[3], mates, cap, out, 3*32*16384) ## i64
  if rank < 1
    return 0
  checked = ffpk_exact(out, 3*32*16384, rank, n, m, p, scratch, 32768, 20000000) ## i64
  if checked == 0-1
    # Keep the recipe pending. A budget exhaustion cannot become an archive
    # entry; the failure/status makes an over-budget head task visible.
    return 0-2
  if checked != 1
    return 0
  if File.exists?(root + "/stop")
    return 0-1
  blob = ffpk_blob(out, rank, n, m, p)
  identity = Crypto:SHA256.hexdigest(blob)
  path = queue + "objects/" + identity + ".tensor"
  old = File.read_prefix(path, 13000000)
  if old != nil && old != blob
    return 0
  if old == nil && ffrf_atomic(path, blob, "composition") != 1
    return 0
  shape = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
  if !File.mkdir_p(queue + "by-shape/" + shape) || ffrf_atomic(queue + "by-shape/" + shape + "/" + identity, task_id + "\n", "composition") != 1
    return 0
  # Best is an advisory index of VERIFIED outputs, never a price cutoff.
  previous = File.read_prefix(queue + "best/" + shape, 100)
  best_rank = 16385 ## i64
  if previous != nil
    values = previous.strip().split(" ")
    if values.size() == 2 && ffrf_hash_valid(values[1]) == 1
      best_rank = ffw_parse_decimal_i64(values[0])
  if rank < best_rank && ffrf_atomic(queue + "best/" + shape, rank.to_s() + " " + identity + "\n", "composition") != 1
    return 0
  result = "MFC_RESULT1 " + task_id + " " + identity + " " + shape + " " + rank.to_s() + "\n"
  ffrf_atomic(queue + "results/" + sequence.to_s(), result, "composition")

-> ffbc_drain(root, limit) (String i64) i64
  if limit < 1 || limit > 4
    return 2
  queue = root + "/composition/"
  consumed = ffbc_counter(queue + "consumed") ## i64
  submitted = ffbc_counter(queue + "submitted") ## i64
  if consumed >= submitted
    return 0
  cap = ffrf_capacity() ## i64
  parent = i64[3*cap]
  leaf = i64[3*cap]
  mates = i64[cap]
  out = i64[3*32*16384]
  scratch = i64[32768]
  parity = i64[4096]
  done = 0 ## i64
  while consumed < submitted && done < limit
    if File.exists?(root + "/stop")
      return 0
    result = ffbc_task(root, consumed+1, parent, leaf, mates, out, scratch, parity) ## i64
    if result == 0-1
      return 0
    if result != 1
      failures = ffbc_counter(queue + "failures") + 1 ## i64
      z = ffrf_atomic(queue + "failures", failures.to_s() + "\n", "composition") ## i64
      z = ffrf_atomic(queue + "error", "task=" + (consumed+1).to_s() + " code=" + result.to_s() + "\n", "composition")
      << "METAFLIP_COMPOSE_FAILED task=" + (consumed+1).to_s() + " code=" + result.to_s()
      return 1
    ccall("__w_unlink", queue + "error")
    consumed += 1
    if ffrf_atomic(queue + "consumed", consumed.to_s() + "\n", "composition") != 1
      return 1
    done += 1
  << "METAFLIP_COMPOSE_COMPLETED done=" + consumed.to_s() + " pending=" + (submitted-consumed).to_s()
  0
