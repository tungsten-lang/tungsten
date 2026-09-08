# Pure-Tungsten, file-spooled cold refinement. One bounded native child owns
# these slabs; no live CPU/GPU state is shared with it. Artifacts identify the
# complete sorted term multiset AND ordered shape, never a bucket signature.
use core/crypto/sha256
use core/file
use pair_cleanup
use projection
use ../paths

-> ffrf_capacity() i64
  4096

-> ffrf_hash_valid(value) (String) i64
  if value.size() != 64
    return 0
  i = 0 ## i64
  while i < 64
    byte = value.byte_at(i) ## i64
    if !((byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102))
      return 0
    i += 1
  1

-> ffrf_atomic(path, body, writer) (String String String) i64
  tmp = path + ".tmp." + writer
  if !write_file(tmp, body)
    return 0
  if !ccall("__w_rename", tmp, path)
    return 0
  1

-> ffrf_sort(work, capacity, rank) (i64[] i64 i64) i64
  i = 1 ## i64
  while i < rank
    u = work[i] ## i64
    v = work[capacity+i] ## i64
    w = work[2*capacity+i] ## i64
    j = i ## i64
    while j > 0 && (work[j-1] > u || (work[j-1] == u && work[capacity+j-1] > v) || (work[j-1] == u && work[capacity+j-1] == v && work[2*capacity+j-1] > w))
      work[j] = work[j-1]
      work[capacity+j] = work[capacity+j-1]
      work[2*capacity+j] = work[2*capacity+j-1]
      j -= 1
    work[j] = u
    work[capacity+j] = v
    work[2*capacity+j] = w
    i += 1
  rank

-> ffrf_copy(dst, src, capacity, rank) (i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < rank
    dst[i] = src[i]
    dst[capacity+i] = src[capacity+i]
    dst[2*capacity+i] = src[2*capacity+i]
    i += 1
  rank

-> ffrf_same(a, b, capacity, rank) (i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < rank
    if a[i] != b[i] || a[capacity+i] != b[capacity+i] || a[2*capacity+i] != b[2*capacity+i]
      return 0
    i += 1
  1

-> ffrf_shape_valid(n, m, p) (i64 i64 i64) i64
  if n < 1 || m < 1 || p < 1 || n > 63 || m > 63 || p > 63 || n*m > 63 || m*p > 63 || n*p > 63
    return 0
  1

-> ffrf_exact(work, capacity, rank, n, m, p, parity) (i64[] i64 i64 i64 i64 i64 i64[]) i64
  if ffrf_shape_valid(n, m, p) != 1 || rank < 1 || rank > capacity
    return 0
  umask = ffr_factor_mask(n*m) ## i64
  vmask = ffr_factor_mask(m*p) ## i64
  wmask = ffr_factor_mask(n*p) ## i64
  i = 0 ## i64
  while i < rank
    u = work[i] ## i64
    v = work[capacity+i] ## i64
    w = work[2*capacity+i] ## i64
    if u <= 0 || v <= 0 || w <= 0 || (u & umask) != u || (v & vmask) != v || (w & wmask) != w
      return 0
    i += 1
  if ffw_support_tensor_error_scratch(work, 0, capacity, 2*capacity, 0-1, rank, n, m, p, parity, 4096) != 0
    return 0
  1

-> ffrf_blob(work, capacity, rank, n, m, p) (i64[] i64 i64 i64 i64 i64)
  body = StringBuffer(64 + 60 * rank) ## recycle
  body.append("MFR1 ")
  body.append(n.to_s())
  body.append(" ")
  body.append(m.to_s())
  body.append(" ")
  body.append(p.to_s())
  body.append(" ")
  body.append(rank.to_s())
  body.append("\n")
  i = 0 ## i64
  while i < rank
    body.append(work[i].to_s())
    body.append(" ")
    body.append(work[capacity+i].to_s())
    body.append(" ")
    body.append(work[2*capacity+i].to_s())
    body.append("\n")
    i += 1
  body.to_s()

# Bounded read; canonical serialization is checked, including ordering and
# duplicate multiplicity. A hash match does not replace the full tensor gate.
-> ffrf_unsigned(raw, cursor, delimiter) (String i64[] i64) i64
  position = cursor[0] ## i64
  if position < 0 || position >= raw.size()
    return 0-1
  first = position ## i64
  value = 0 ## i64
  while position < raw.size()
    byte = raw.byte_at(position) ## i64
    if byte == delimiter
      if position == first || (position > first+1 && raw.byte_at(first) == 48)
        break
      cursor[0] = position+1
      return value
    if byte < 48 || byte > 57 || value > 922337203685477580 || (value == 922337203685477580 && byte > 55)
      break
    value = value*10 + byte-48
    position += 1
  cursor[0] = 0-1
  0-1

-> ffrf_load(root, identity, work, capacity, meta, parity) (String String i64[] i64 i64[] i64[]) i64
  if ffrf_hash_valid(identity) != 1
    return 0
  raw = File.read_prefix(root + "/objects/" + identity + ".tensor", 262145)
  if raw == nil || raw.size() >= 262144 || Crypto:SHA256.hexdigest(raw) != identity
    return 0
  if !raw.starts_with?("MFR1 ")
    return 0
  # Parse directly into native integers, reusing meta[0] as the cursor. Split
  # arrays used to retain hundreds of decimal strings per consumed tensor.
  meta[0] = 5
  n = ffrf_unsigned(raw, meta, 32) ## i64
  m = ffrf_unsigned(raw, meta, 32) ## i64
  p = ffrf_unsigned(raw, meta, 32) ## i64
  rank = ffrf_unsigned(raw, meta, 10) ## i64
  if ffrf_shape_valid(n, m, p) != 1 || rank < 1 || rank > capacity
    return 0
  i = 0 ## i64
  while i < rank
    work[i] = ffrf_unsigned(raw, meta, 32)
    work[capacity+i] = ffrf_unsigned(raw, meta, 32)
    work[2*capacity+i] = ffrf_unsigned(raw, meta, 10)
    if meta[0] < 0
      return 0
    if i > 0 && (work[i-1] > work[i] || (work[i-1] == work[i] && work[capacity+i-1] > work[capacity+i]) || (work[i-1] == work[i] && work[capacity+i-1] == work[capacity+i] && work[2*capacity+i-1] > work[2*capacity+i]))
      return 0
    i += 1
  if meta[0] != raw.size()
    return 0
  if ffrf_exact(work, capacity, rank, n, m, p, parity) != 1
    return 0
  meta[0] = n
  meta[1] = m
  meta[2] = p
  meta[3] = rank
  1

-> ffrf_store(root, work, capacity, rank, n, m, p, writer) (String i64[] i64 i64 i64 i64 i64 String)
  z = ffrf_sort(work, capacity, rank) ## i64
  body = ffrf_blob(work, capacity, rank, n, m, p)
  identity = Crypto:SHA256.hexdigest(body)
  path = root + "/objects/" + identity + ".tensor"
  previous = File.read_prefix(path, 262145)
  if previous != nil
    if previous != body
      return ""
    return identity
  if ffrf_atomic(path, body, writer) != 1
    return ""
  identity

# Grouping is only a projection scheduling heuristic. Every distinct neutral
# representation is still emitted, regardless of rank/density or this score.
-> ffrf_pairs(work, capacity, rank) (i64[] i64 i64) i64
  pairs = 0 ## i64
  i = 0 ## i64
  while i < rank
    j = 0 ## i64
    while j < i
      if work[i] == work[j] || work[capacity+i] == work[capacity+j] || work[2*capacity+i] == work[2*capacity+j]
        pairs += 1
      j += 1
    i += 1
  pairs

-> ffrf_emit(root, work, capacity, rank, n, m, p, writer, source_id, kind, ids, records, parity) i64
  if ffrf_exact(work, capacity, rank, n, m, p, parity) != 1
    return 0
  identity = ffrf_store(root, work, capacity, rank, n, m, p, writer)
  if identity == ""
    return 0
  if identity != source_id && !ids.include?(identity)
    directory = root + "/by-shape/" + n.to_s() + "x" + m.to_s() + "x" + p.to_s()
    if !File.mkdir_p(directory)
      return 0
    if ffrf_atomic(directory + "/" + identity, identity + "\n", writer) != 1
      return 0
    ids.push(identity)
    records.push(identity + " " + kind)
  1

# Six bounded one-axis basis proposals, each exact-compressed. Project every
# coordinate of the source and the best grouping endpoint (if different).
# This deliberately bounded family is not an exhaustive basis search.
-> ffrf_job(root, sequence, source, work, selected, meta, parity) (String i64 i64[] i64[] i64[] i64[] i64[]) i64
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
  # Only the final atomic manifest marks a job complete. Partial objects are
  # immutable and can be reused after stop/retry without losing any input.
  body = "MFR_RESULT1 " + sequence.to_s() + " " + identity + " " + records.size().to_s() + "\n"
  i = 0 ## i64
  while i < records.size()
    body = body + records[i] + "\n"
    i += 1
  ffrf_atomic(root + "/results/" + sequence.to_s(), body, writer)

-> ffrf_batch(root, first, last) (String i64 i64) i64
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
    result = ffrf_job(root, sequence, source, work, selected, meta, parity) ## i64
    if result == 0-1
      return 0
    if result != 1
      << "METAFLIP_REFINE_FAILED job=" + sequence.to_s()
      return 1
    << "METAFLIP_REFINE_COMPLETED job=" + sequence.to_s()
    sequence += 1
  0
