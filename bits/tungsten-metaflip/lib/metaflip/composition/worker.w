# Incremental, certificate-backed composition. One native low-priority
# process owns this queue. All work is durable; a price is never verification.
use ../fleet/refinement_artifacts
use ../compose
use pairs
use pages
use leaf_walk
use schedule
use group_bank
use deferred

-> ffbc_failure(queue, ticket, ordinal, code) (String i64 i64 i64) i64
  failures = ffbc_counter(queue + "failures") + 1 ## i64
  z = ffrf_atomic(queue + "failures", failures.to_s() + "\n", "composition") ## i64
  z = ffrf_atomic(queue + "error", "task=" + ticket.to_s() + " ordinal=" + ordinal.to_s() + " code=" + code.to_s() + "\n", "composition")
  << "METAFLIP_COMPOSE_FAILED task=" + ticket.to_s() + " code=" + code.to_s()
  1

-> ffbc_leaf(root, runtime, scale, work, source, parity) (String String i64 i64[] i64[] i64[])
  cap = ffrf_capacity() ## i64
  meta = i64[4]
  marker = root + "/composition/leaves/" + scale.to_s()
  old = File.read_prefix(marker, 66)
  if old != nil
    identity = old.strip()
    if ffrf_load(root, identity, work, cap, meta, parity) != 1 || meta[0] != 2 || meta[1] != scale || meta[2] != scale
      return ""
    if scale != 4 || meta[3] <= 26
      return identity
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
  if scale == 4
    path = runtime + "/seeds/gf2/matmul_2x4x5_rank33_catalog_gf2.txt"
    m = 4
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
    rank = ffmp_project(source, 3*cap, cap, rank, 2, 4, 5, 2, 2, work, ffmc_scratch_words(cap), cap)
    rank = ffpc_reduce(work, ffmc_scratch_words(cap), cap, rank, 0, 1, 2)
    rank = ffmc_reduce(work, ffmc_scratch_words(cap), cap, rank)
    rank = ffbc_walk_leaf4(root, work, cap, rank, parity)
  else
    z = ffrf_copy(work, source, cap, rank) ## i64
  if ffrf_exact(work, cap, rank, 2, scale, scale, parity) != 1
    return ""
  identity = ffrf_store(root, work, cap, rank, 2, scale, scale, "composition")
  if identity == "" || ffrf_atomic(marker, identity + "\n", "composition") != 1
    return ""
  identity

-> ffbc_submit_parent(root, identity, leaves, ranks, banks, prices, work, meta, parity, mates) i64
  if ffrf_hash_valid(identity) != 1
    return 0
  marker = root + "/composition/parents/" + identity
  # Nine recipe identities, not merely three leaf identities: this also
  # permits a pair-only axis to stay unchanged when a larger leaf changes.
  stamp = "MFC_PARENT3"
  previous_parent = File.read_prefix(marker, 1025)
  previous_leaves = []
  if previous_parent != nil
    tokens = previous_parent.strip().split(" ")
    if (tokens.size() == 4 && tokens[0] == "MFC_PARENT2") || (tokens.size() == 10 && tokens[0] == "MFC_PARENT3")
      previous_leaves = tokens
  cap = ffrf_capacity() ## i64
  if ffrf_load(root, identity, work, cap, meta, parity) != 1
    return 0
  costs = i64[7]
  sizes = i64[cap]
  plan = i64[4*(cap+1)]
  queue = root + "/composition/"
  sequence = ffbc_counter(queue + "submitted") ## i64
  # Recover a task committed just before its counter/dedup index.
  recovery = 0 ## i64
  while ffbq_read(queue, "tasks", sequence+1) != nil
    if ffbq_read(queue, "tasks", sequence+1) == "" || recovery >= 9
      return 0
    sequence += 1
    recovery += 1
  # One bounded suffix read per parent, not nine page scans per recipe.
  # Newly appended records join this local list (at most 18 records total).
  recent_records = []
  recent = sequence-8 ## i64
  if recent < 1
    recent = 1
  while recent <= sequence
    saved = ffbq_read(queue, "tasks", recent)
    if saved == nil || saved == ""
      return 0
    recent_records.push(saved)
    recent += 1
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
      kind = "MFC1"
      dependency = leaves[scale-2]
      if banks[scale-2] != ""
        k = 1 ## i64
        while k <= 6
          costs[k] = prices[(scale-2)*7+k]
          k += 1
        grouped = ffbg_plan(work, 3*cap, cap, meta[3], axis, costs, 7, mates, cap, sizes, cap, plan, 4*(cap+1)) ## i64
        if grouped < 1 || grouped > predicted
          return 0
        if ffbg_large(sizes, meta[3]) != 0
          predicted = grouped
          kind = "MCG1"
          dependency = banks[scale-2]
      # Scheduling family: only recipes better than this parent's naive
      # Kronecker expansion. This is not an exhaustive-search lower bound.
      if predicted < meta[3]*scale*scale && predicted <= 16384 && ffpk_stride(n, m, p) > 0
        body = kind + " " + identity + " " + dependency + " " + axis.to_s() + " " + scale.to_s() + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + predicted.to_s() + "\n"
        task_id = Crypto:SHA256.hexdigest(body)
        stamp = stamp + " " + task_id
        previous = File.read_prefix(queue + "by-id/" + task_id, 32)
        duplicate = 0 ## i64
        if previous_leaves.size() == 10 && previous_leaves[1+axis*3+scale-2] == task_id
          duplicate = 1
        if previous_leaves.size() == 4 && kind == "MFC1" && previous_leaves[scale-1] == dependency
          duplicate = 1
        if previous != nil
          stored = ffbq_read(queue, "tasks", ffw_parse_decimal_i64(previous.strip()))
          if stored != body
            return 0
          duplicate = 1
        # At most nine recipes belong to the single in-flight parent. Recover
        # its unacknowledged suffix by full bytes; no per-recipe index file.
        r = 0 ## i64
        while duplicate == 0 && r < recent_records.size()
          if recent_records[r] == body
            duplicate = 1
          r += 1
        if duplicate == 0
          sequence += 1
          if ffbq_put(queue, "tasks", sequence, body) != 1
            return 0
          recent_records.push(body)
      else
        stamp = stamp + " -"
      scale += 1
    axis += 1
  if ffrf_atomic(queue + "submitted", sequence.to_s() + "\n", "composition") != 1
    return 0
  ffrf_atomic(marker, stamp + "\n", "composition")

# Called before the refinement completion manifest: a crash/stop cannot
# acknowledge the source job while losing its composition intake.
-> ffbc_prepare(root, runtime, identity, ids) i64
  if runtime == ""
    return 1
  if File.exists?(root + "/stop")
    return 0-1
  directories = ["tasks", "tasks-pages", "by-id", "parents", "objects", "results", "results-pages", "leaves", "best", "by-shape"]
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
  prices = i64[21]
  costs = i64[7]
  bank = i64[18*128]
  leaf_work = i64[3*128]
  leaves = []
  banks = []
  scale = 2 ## i64
  while scale <= 4
    leaf = ffbc_leaf(root, runtime, scale, work, source, parity)
    if leaf == "" || ffrf_load(root, leaf, work, cap, meta, parity) != 1
      if File.exists?(root + "/stop")
        return 0-1
      return 0
    ranks[scale-2] = meta[3]
    leaves.push(leaf)
    identity_bank = ""
    if scale > 2 && env("METAFLIP_COMPOSITION_GROUPS") != "0"
      identity_bank = ffbg_bank(root, runtime, scale, leaf, bank, 18*128, 128, costs, leaf_work, parity)
      if identity_bank == ""
        if File.exists?(root + "/stop")
          return 0-1
        return 0
      k = 1 ## i64
      while k <= 6
        prices[(scale-2)*7+k] = costs[k]
        k += 1
    banks.push(identity_bank)
    scale += 1
  if ffbc_submit_parent(root, identity, leaves, ranks, banks, prices, work, meta, parity, mates) != 1
    return 0
  mixed_bank = ""
  if env("METAFLIP_COMPOSITION_MIXED") != "0"
    mixed_leaves = i64[22*3*128]
    mixed_costs = i64[22]
    mixed_bank = ffmb_bank(root, runtime, leaves[1], leaves[2], mixed_leaves, 22*3*128, mixed_costs, 22, leaf_work, parity)
    if mixed_bank == "" || ffmd_offer(root, identity, mixed_bank) != 1
      if File.exists?(root + "/stop")
        return 0-1
      return 0
  i = 0
  while i < ids.size()
    if File.exists?(root + "/stop")
      return 0-1
    if ffbc_submit_parent(root, ids[i], leaves, ranks, banks, prices, work, meta, parity, mates) != 1
      return 0
    if mixed_bank != "" && ffmd_offer(root, ids[i], mixed_bank) != 1
      return 0
    i += 1
  1

# Inputs and leaves are rechecked. The full multiword result crosses the exact
# tensor gate BEFORE archive/best/result writes. Formula ranks are not gates.
-> ffbc_task_at(root, queue, sequence, ordinal, parent, leaf, mates, out, scratch, parity) (String String i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  raw = ffbq_read(queue, "tasks", sequence)
  if raw == nil || raw.size() > 256
    return 0
  fields = raw.strip().split(" ")
  if fields.size() == 9 && (fields[0] == "MFM1" || fields[0] == "MFM2") && queue == root + "/composition/mixed/"
    mixed_meta = i64[4]
    mixed_rank = ffmd_expand(root, raw, parent, mixed_meta, out, parity) ## i64
    return ffbc_finish_task(root, queue, sequence, ordinal, raw, mixed_rank, mixed_meta[3], mixed_meta[0], mixed_meta[1], mixed_meta[2], out, scratch)
  if queue != root + "/composition/"
    return 0
  if fields.size() != 9 || (fields[0] != "MFC1" && fields[0] != "MCG1") || ffrf_hash_valid(fields[1]) != 1 || ffrf_hash_valid(fields[2]) != 1
    return 0
  axis = ffw_parse_decimal_i64(fields[3]) ## i64
  scale = ffw_parse_decimal_i64(fields[4]) ## i64
  if axis < 0 || axis > 2 || scale < 2 || scale > 4
    return 0
  cap = ffrf_capacity() ## i64
  meta = i64[4]
  lm = i64[4]
  if ffrf_load(root, fields[1], parent, cap, meta, parity) != 1
    return 0
  n = meta[0]*ffbd_scale(axis, 0, scale) ## i64
  m = meta[1]*ffbd_scale(axis, 1, scale) ## i64
  p = meta[2]*ffbd_scale(axis, 2, scale) ## i64
  predicted = 0 ## i64
  bank = i64[18*128]
  bank_work = i64[3*128]
  costs = i64[7]
  sizes = i64[cap]
  plan = i64[4*(cap+1)]
  if fields[0] == "MCG1"
    if ffbg_load_bank(root, fields[2], scale, bank, 18*128, 128, costs, 7, bank_work, parity) != 1
      return 0
    predicted = ffbg_plan(parent, 3*cap, cap, meta[3], axis, costs, 7, mates, cap, sizes, cap, plan, 4*(cap+1))
  else
    if ffrf_load(root, fields[2], leaf, cap, lm, parity) != 1 || lm[0] != 2 || lm[1] != scale || lm[2] != scale
      return 0
    pairs = ffbd_pairs(parent, 3*cap, cap, meta[3], axis, mates, cap) ## i64
    predicted = (meta[3]-2*pairs)*scale*scale+pairs*lm[3]
  if predicted < 1 || predicted > 16384
    return 0
  canonical = fields[0] + " " + fields[1] + " " + fields[2] + " " + axis.to_s() + " " + scale.to_s() + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + predicted.to_s() + "\n"
  if raw != canonical
    return 0
  rank = 0 ## i64
  if fields[0] == "MCG1"
    rank = ffbg_compose(parent, 3*cap, cap, meta[3], meta[0], meta[1], meta[2], axis, scale, bank, 18*128, 128, costs, 7, mates, cap, sizes, cap, plan, 4*(cap+1), out, 3*32*16384)
  else
    rank = ffbd_compose(parent, 3*cap, cap, meta[3], meta[0], meta[1], meta[2], axis, scale, leaf, 3*cap, cap, lm[3], mates, cap, out, 3*32*16384)
  ffbc_finish_task(root, queue, sequence, ordinal, raw, rank, predicted, n, m, p, out, scratch)

-> ffbc_finish_task(root, queue, sequence, ordinal, raw, rank, predicted, n, m, p, out, scratch) (String String i64 i64 String i64 i64 i64 i64 i64 i64[] i64[]) i64
  if rank < 1 || rank > predicted || predicted > 16384
    return 0
  task_id = Crypto:SHA256.hexdigest(raw)
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
  archive = root + "/composition/"
  path = archive + "objects/" + identity + ".tensor"
  old = File.read_prefix(path, 13000000)
  if old != nil && old != blob
    return 0
  if old == nil && ffrf_atomic(path, blob, "composition") != 1
    return 0
  shape = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
  if !File.mkdir_p(archive + "by-shape/" + shape) || ffrf_atomic(archive + "by-shape/" + shape + "/" + identity, task_id + "\n", "composition") != 1
    return 0
  # Best is an advisory index of VERIFIED outputs, never a price cutoff.
  previous = File.read_prefix(archive + "best/" + shape, 100)
  best_rank = 16385 ## i64
  if previous != nil
    values = previous.strip().split(" ")
    if values.size() == 2 && ffrf_hash_valid(values[1]) == 1
      best_rank = ffw_parse_decimal_i64(values[0])
  if rank < best_rank && ffrf_atomic(archive + "best/" + shape, rank.to_s() + " " + identity + "\n", "composition") != 1
    return 0
  suffix = task_id + " " + identity + " " + shape + " " + rank.to_s() + "\n"
  result = "MFC_RESULT2 " + sequence.to_s() + " " + suffix
  # Old completion records are retained byte-for-byte, after full replay.
  old_result = ffbq_read(queue, "results", ordinal)
  if sequence == ordinal && old_result == "MFC_RESULT1 " + suffix
    return 1
  ffbq_put(queue, "results", ordinal, result)

-> ffbc_task(root, sequence, ordinal, parent, leaf, mates, out, scratch, parity) (String i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  ffbc_task_at(root, root + "/composition/", sequence, ordinal, parent, leaf, mates, out, scratch, parity)

-> ffbc_drain_queue(root, queue, limit) (String String i64) i64
  if limit < 1 || limit > 4
    return 2
  consumed = ffbc_counter(queue + "consumed") ## i64
  submitted = ffbc_counter(queue + "submitted") ## i64
  if File.exists?(root + "/stop")
    return 0
  state = i64[6]
  if ffbs_load(queue, submitted, consumed, state) != 1
    return ffbc_failure(queue, 0, consumed+1, 0-3)
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
    ordinal = consumed+1 ## i64
    ticket = 0 ## i64
    saved = ffbq_read(queue, "results", ordinal)
    if saved != nil
      ticket = ffbs_result_ticket(saved, ordinal)
    elsif consumed == state[0]
      fifo = 0 ## i64
      if env("METAFLIP_COMPOSITION_FIFO") == "1"
        fifo = 1
      ticket = ffbs_choose_at(queue, root + "/composition/", submitted, state, fifo)
    result = 0 ## i64
    recovering = consumed < state[0] ## bool
    if ticket > 0 && ticket <= submitted && ((recovering && ffbs_done(state, ticket) == 1) || (!recovering && ticket >= state[1] && ticket < state[1]+128 && ffbs_done(state, ticket) == 0))
      result = ffbc_task_at(root, queue, ticket, ordinal, parent, leaf, mates, out, scratch, parity)
    if result == 0-1
      return 0
    if result != 1
      return ffbc_failure(queue, ticket, ordinal, result)
    if !recovering
      if ffbs_mark(state, ticket, submitted) != 1 || ffrf_atomic(queue + "schedule", ffbs_blob(state), "composition") != 1
        return ffbc_failure(queue, ticket, ordinal, 0-4)
    ccall("__w_unlink", queue + "error")
    consumed += 1
    if ffrf_atomic(queue + "consumed", consumed.to_s() + "\n", "composition") != 1
      return ffbc_failure(queue, ticket, ordinal, 0-5)
    done += 1
  << "METAFLIP_COMPOSE_COMPLETED done=" + consumed.to_s() + " pending=" + (submitted-consumed).to_s()
  0

# Alternate lanes whenever both have work. Admission is bounded separately
# from the at-most-four exact expansions, and never changes old-lane tickets.
-> ffbc_drain(root, limit) (String i64) i64
  if limit < 1 || limit > 4
    return 2
  if File.exists?(root + "/stop")
    return 0
  queue = root + "/composition/"
  mixed = queue + "mixed/"
  if ffmd_admit(root, 27) != 1
    return ffbc_failure(mixed, 0, ffmd_count(mixed + "context"), 0-6)
  done = 0 ## i64
  while done < limit
    old_done = ffbc_counter(queue + "consumed") ## i64
    mixed_done = ffbc_counter(mixed + "consumed") ## i64
    old_pending = ffbc_counter(queue + "submitted")-old_done ## i64
    mixed_pending = ffbc_counter(mixed + "submitted")-mixed_done ## i64
    if old_pending <= 0 && mixed_pending <= 0
      if done == 0
        result = ffbc_drain_queue(root, queue, 1) ## i64
        if result != 0
          return result
        if File.exists?(mixed + "submitted")
          return ffbc_drain_queue(root, mixed, 1)
      return 0
    selected = queue
    if old_pending <= 0 || (mixed_pending > 0 && (old_done+mixed_done)%2 == 1)
      selected = mixed
    result = ffbc_drain_queue(root, selected, 1) ## i64
    if result != 0
      return result
    done += 1
  0
