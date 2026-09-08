use refinement_artifacts
use ../composition/worker

# Six bounded one-axis basis proposals, each exact-compressed. Project every
# coordinate of the source and the best grouping endpoint (if different).
# This deliberately bounded family is not an exhaustive basis search.
-> ffrf_job(root, sequence, source, work, selected, meta, parity, runtime) (String i64 i64[] i64[] i64[] i64[] i64[] String) i64
  ticket = File.read_prefix(root + "/tasks/" + sequence.to_s(), 66)
  if ticket == nil
    return 0
  identity = ticket.strip()
  capacity = ffrf_capacity() ## i64
  words = ffmc_scratch_words(capacity) ## i64
  if ffrf_load(root, identity, source, capacity, meta, parity) != 1
    return 0
  n = meta[0] ## i64
  m = meta[1] ## i64
  p = meta[2] ## i64
  rank = meta[3] ## i64
  z = ffrf_copy(work, source, capacity, rank) ## i64
  clean_rank = ffpc_reduce(work, words, capacity, rank, 0, 1, 2) ## i64
  clean_rank = ffmc_reduce(work, words, capacity, clean_rank)
  writer = "worker-" + sequence.to_s()
  ids = []
  records = []
  if ffrf_emit(root, work, capacity, clean_rank, n, m, p, writer, identity, "matrix", ids, records, parity) != 1
    return 0
  z = ffrf_copy(source, work, capacity, clean_rank)
  z = ffrf_copy(selected, work, capacity, clean_rank)
  best_rank = clean_rank ## i64
  best_pairs = ffrf_pairs(selected, capacity, best_rank) ## i64
  mode = 0 ## i64
  while mode < 6
    if File.exists?(root + "/stop")
      return 0-1
    z = ffrf_copy(work, source, capacity, clean_rank)
    proposed = ffmc_refactor(work, words, capacity, clean_rank, mode/2, mode%2) ## i64
    proposed = ffmc_reduce(work, words, capacity, proposed)
    kind = "basis-" + mode.to_s()
    if ffrf_emit(root, work, capacity, proposed, n, m, p, writer, identity, kind, ids, records, parity) != 1
      return 0
    pairs = ffrf_pairs(work, capacity, proposed) ## i64
    if proposed < best_rank || (proposed == best_rank && pairs > best_pairs)
      best_rank = proposed
      best_pairs = pairs
      z = ffrf_copy(selected, work, capacity, proposed)
    mode += 1
  bases = 1 ## i64
  if best_rank != clean_rank || ffrf_same(selected, source, capacity, clean_rank) == 0
    bases = 2
  base = 0 ## i64
  while base < bases
    original = source
    original_rank = clean_rank ## i64
    if base == 1
      original = selected
      original_rank = best_rank
    axis = 0 ## i64
    while axis < 3
      size = n ## i64
      if axis == 1
        size = m
      if axis == 2
        size = p
      removed = 0 ## i64
      while size > 1 && removed < size
        if File.exists?(root + "/stop")
          return 0-1
        projected = ffmp_project(original, 3*capacity, capacity, original_rank, n, m, p, axis, removed, work, words, capacity) ## i64
        projected = ffpc_reduce(work, words, capacity, projected, 0, 1, 2)
        projected = ffmc_reduce(work, words, capacity, projected)
        nn = n ## i64
        mm = m ## i64
        pp = p ## i64
        if axis == 0
          nn -= 1
        if axis == 1
          mm -= 1
        if axis == 2
          pp -= 1
        kind = "project-" + base.to_s() + "-" + axis.to_s() + "-" + removed.to_s()
        if ffrf_emit(root, work, capacity, projected, nn, mm, pp, writer, identity, kind, ids, records, parity) != 1
          return 0
        removed += 1
      axis += 1
    base += 1
  prepared = ffbc_prepare(root, runtime, identity, ids) ## i64
  if prepared != 1
    return prepared
  # Only the final atomic manifest marks a job complete. Partial objects are
  # immutable and can be reused after stop/retry without losing any input.
  body = "MFR_RESULT1 " + sequence.to_s() + " " + identity + " " + records.size().to_s() + "\n"
  i = 0 ## i64
  while i < records.size()
    body = body + records[i] + "\n"
    i += 1
  ffrf_atomic(root + "/results/" + sequence.to_s(), body, writer)

-> ffrf_batch_with_composition(root, first, last, runtime) (String i64 i64 String) i64
  if first < 1 || last < first || last-first >= 8
    return 2
  capacity = ffrf_capacity() ## i64
  source = i64[3*capacity]
  selected = i64[3*capacity]
  work = i64[ffmc_scratch_words(capacity)]
  parity = i64[4096]
  meta = i64[4]
  sequence = first ## i64
  while sequence <= last
    if File.exists?(root + "/stop")
      return 0
    result = ffrf_job(root, sequence, source, work, selected, meta, parity, runtime) ## i64
    if result == 0-1
      return 0
    if result != 1
      << "METAFLIP_REFINE_FAILED job=" + sequence.to_s()
      return 1
    << "METAFLIP_REFINE_COMPLETED job=" + sequence.to_s()
    if runtime != "" && !File.exists?(root + "/composition/error")
      # Refinement manifests and composition completion have separate cursors.
      # At most two expansions per input; overflow is served by idle batches.
      z = ffbc_drain(root, 2) ## i64
    sequence += 1
  0

-> ffrf_batch(root, first, last) (String i64 i64) i64
  ffrf_batch_with_composition(root, first, last, "")
