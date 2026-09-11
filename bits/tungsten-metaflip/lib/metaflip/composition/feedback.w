# Child-owned outbox, coordinator-owned consumed cursor. Only full-checked
# <=63-bit descendants enter the existing narrow refinement/seed boundary.
# Hashes bind representations; neither an index nor a recipe is a tensor gate.
use packed
use pages
use counters

-> ffwf_valid_record(raw) (String) i64
  if raw == nil || raw == ""
    return 0
  f = raw.strip().split(" ")
  if f.size() != 7 || f[0] != "MFW_FEED1" || ffrf_hash_valid(f[1]) != 1 || ffrf_hash_valid(f[2]) != 1
    return 0
  n = ffpk_decimal(f[3]) ## i64
  m = ffpk_decimal(f[4]) ## i64
  p = ffpk_decimal(f[5]) ## i64
  rank = ffpk_decimal(f[6]) ## i64
  if ffrf_shape_valid(n, m, p) != 1 || rank < 1 || rank > ffrf_capacity()
    return 0
  if raw != "MFW_FEED1 " + f[1] + " " + f[2] + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + rank.to_s() + "\n"
    return 0
  1

-> ffwf_bind(queue, raw, sequence) (String String i64) i64
  if ffwf_valid_record(raw) != 1
    return 0
  fields = raw.strip().split(" ")
  path = queue + "by-id/" + fields[1]
  old = File.read_prefix(path, 32)
  record = sequence.to_s() + "\n"
  if old != nil && old != record
    return 0
  if old == nil
    return ffrf_atomic(path, record, "feedback")
  1

-> ffwf_recover(queue) (String) i64
  submitted = ffmd_count(queue + "submitted") ## i64
  consumed = ffmd_count(queue + "consumed") ## i64
  if submitted < 0 || consumed < 0 || submitted >= 1000000000000
    return 0
  raw = ffbq_read(queue, "tasks", submitted+1)
  if raw != nil
    if ffwf_valid_record(raw) != 1 || ffbq_read(queue, "tasks", submitted+2) != nil || ffwf_bind(queue, raw, submitted+1) != 1
      return 0
    submitted += 1
    if ffrf_atomic(queue + "submitted", submitted.to_s() + "\n", "feedback") != 1
      return 0
  if consumed > submitted
    return 0
  if submitted > 0 && ffwf_bind(queue, ffbq_read(queue, "tasks", submitted), submitted) != 1
    return 0
  1

# Format conversion only. The caller must still cross the complete tensor
# check. Both layouts retain the full factors; labels are never factor masks.
-> ffwf_unpack(source, words, rank, n, m, p, out, out_words, cap) (i64[] i64 i64 i64 i64 i64 i64[] i64 i64) i64
  if cap < 1 || cap > 4096 || rank > cap || out_words < 3*cap || ffrf_shape_valid(n, m, p) != 1 || ffpk_valid(source, words, rank, n, m, p) != 1
    return 0
  stride = ffpk_stride(n, m, p) ## i64
  t = 0 ## i64
  while t < rank
    axis = 0 ## i64
    while axis < 3
      value = source[(3*t+axis)*stride] ## i64
      if stride == 2
        value = value | (source[(3*t+axis)*stride+1] << 32)
      out[axis*cap+t] = value
      axis += 1
    t += 1
  1

# 1 = queued/deduplicated or intentionally archive-only, -1 = stopped,
# 0 = failed. Ineligible wide shapes remain in their existing checked archive.
-> ffwf_publish(root, identity, blob, rank, n, m, p) (String String String i64 i64 i64 i64) i64
  if env("METAFLIP_WIDE_FEEDBACK") == "0"
    return 1
  if File.exists?(root + "/stop")
    return 0-1
  if rank < 1 || rank > 16384 || ffpk_stride(n, m, p) == 0
    return 0
  if rank > ffrf_capacity() || ffrf_shape_valid(n, m, p) != 1
    return 1
  if ffrf_hash_valid(identity) != 1 || Crypto:SHA256.hexdigest(blob) != identity
    return 0
  archived = File.read_prefix(root + "/composition/objects/" + identity + ".tensor", 12632129)
  if archived == nil || archived != blob
    return 0
  packed = i64[6*rank]
  narrow = i64[3*rank]
  meta = i64[4]
  parity = i64[4096]
  if ffpk_parse(blob, packed, 6*rank, meta, 4) != rank || meta[0] != n || meta[1] != m || meta[2] != p
    return 0
  if ffwf_unpack(packed, 6*rank, rank, n, m, p, narrow, 3*rank, rank) != 1 || ffrf_exact(narrow, rank, rank, n, m, p, parity) != 1
    return 0
  queue = root + "/composition/feedback/"
  if !File.mkdir_p(root + "/objects") || !File.mkdir_p(queue + "tasks-pages") || !File.mkdir_p(queue + "by-id") || ffwf_recover(queue) != 1
    return 0
  converted = ffrf_store(root, narrow, rank, rank, n, m, p, "feedback")
  if converted == ""
    return 0
  record = "MFW_FEED1 " + identity + " " + converted + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + rank.to_s() + "\n"
  old = File.read_prefix(queue + "by-id/" + identity, 32)
  submitted = ffmd_count(queue + "submitted") ## i64
  if old != nil
    ticket = ffpk_decimal(old.strip()) ## i64
    if ticket < 1 || ticket > submitted || old != ticket.to_s() + "\n" || ffbq_read(queue, "tasks", ticket) != record
      return 0
    return 1
  if File.exists?(root + "/stop")
    return 0-1
  if submitted >= 999999999999 || ffbq_put(queue, "tasks", submitted+1, record) != 1 || ffwf_bind(queue, record, submitted+1) != 1
    return 0
  ffrf_atomic(queue + "submitted", (submitted+1).to_s() + "\n", "feedback")

-> ffwf_cleanup(root, source, n, m, p) (String String i64 i64 i64) i64
  if env("METAFLIP_WIDE_FEEDBACK") == "0" || ffrf_shape_valid(n, m, p) != 1
    return 1
  raw = File.read_prefix(root + "/composition/cleanup/results/" + source, 320)
  if raw == nil
    return 0
  f = raw.strip().split(" ")
  if f.size() != 12 || f[0] != "MFW_CLEAN1" || f[1] != source || ffrf_hash_valid(f[2]) != 1
    return 0
  blob = File.read_prefix(root + "/composition/objects/" + f[2] + ".tensor", 12632129)
  if blob == nil
    return 0
  ffwf_publish(root, f[2], blob, ffpk_decimal(f[6]), n, m, p)

# Consumer validates both immutable objects and their exact cross-format map.
-> ffwf_load(root, raw, packed, work, cap, meta, parity) (String String i64[] i64[] i64 i64[] i64[]) i64
  if ffwf_valid_record(raw) != 1
    return 0
  f = raw.strip().split(" ")
  if ffrf_load(root, f[2], work, cap, meta, parity) != 1 || meta[0].to_s() != f[3] || meta[1].to_s() != f[4] || meta[2].to_s() != f[5] || meta[3].to_s() != f[6]
    return 0
  rank = meta[3] ## i64
  blob = File.read_prefix(root + "/composition/objects/" + f[1] + ".tensor", 12632129)
  if blob == nil || Crypto:SHA256.hexdigest(blob) != f[1]
    return 0
  info = i64[4]
  if ffpk_parse(blob, packed, 6*cap, info, 4) != rank || info[0] != meta[0] || info[1] != meta[1] || info[2] != meta[2]
    return 0
  stride = ffpk_stride(meta[0], meta[1], meta[2]) ## i64
  t = 0 ## i64
  while t < rank
    axis = 0 ## i64
    while axis < 3
      value = packed[(3*t+axis)*stride] ## i64
      if stride == 2
        value = value | (packed[(3*t+axis)*stride+1] << 32)
      if value != work[axis*cap+t]
        return 0
      axis += 1
    t += 1
  1
