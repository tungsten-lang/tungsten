# Full MFW objects cross this boundary, never a narrowed u64 factor. The
# producer owns submitted/index; the consumer owns consumed. Admission still
# requires a full tensor check, not merely a matching hash or queue record.
use packed
use pages
use counters

-> ffpf_valid(raw) (String) i64
  if raw == nil || raw == ""
    return 0
  f = raw.strip().split(" ")
  if f.size() != 6 || f[0] != "MFW_PACKED1" || ffrf_hash_valid(f[1]) != 1
    return 0
  n = ffpk_decimal(f[2]) ## i64
  m = ffpk_decimal(f[3]) ## i64
  p = ffpk_decimal(f[4]) ## i64
  rank = ffpk_decimal(f[5]) ## i64
  if ffpk_stride(n,m,p) < 1 || rank < 1 || rank > 16384
    return 0
  if raw != "MFW_PACKED1 " + f[1] + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + rank.to_s() + "\n"
    return 0
  1

-> ffpf_bind(queue, raw, ticket) (String String i64) i64
  if ffpf_valid(raw) != 1
    return 0
  f = raw.strip().split(" ")
  path = queue + "by-id/" + f[1]
  old = File.read_prefix(path,32)
  value = ticket.to_s() + "\n"
  if old != nil && old != value
    return 0
  if old == nil
    return ffrf_atomic(path,value,"packed-feed")
  1

-> ffpf_recover(queue) (String) i64
  submitted = ffmd_count(queue + "submitted") ## i64
  consumed = ffmd_count(queue + "consumed") ## i64
  if submitted < 0 || consumed < 0 || consumed > submitted || submitted >= 1000000000000
    return 0
  raw = ffbq_read(queue,"tasks",submitted+1)
  if raw != nil
    if ffpf_valid(raw) != 1 || ffbq_read(queue,"tasks",submitted+2) != nil || ffpf_bind(queue,raw,submitted+1) != 1
      return 0
    submitted += 1
    if ffrf_atomic(queue + "submitted",submitted.to_s() + "\n","packed-feed") != 1
      return 0
  if submitted > 0 && ffpf_bind(queue,ffbq_read(queue,"tasks",submitted),submitted) != 1
    return 0
  1

-> ffpf_offer(root, kind, identity, blob, rank, n, m, p) (String String String String i64 i64 i64 i64) i64
  if File.exists?(root + "/stop")
    return 0-1
  raw = "MFW_PACKED1 " + identity + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + rank.to_s() + "\n"
  if (kind != "packed-intake" && kind != "packed-feedback") || ffpf_valid(raw) != 1 || Crypto:SHA256.hexdigest(blob) != identity
    return 0
  queue = root + "/composition/" + kind + "/"
  if !File.mkdir_p(root + "/composition/objects") || !File.mkdir_p(queue + "tasks-pages") || !File.mkdir_p(queue + "by-id") || ffpf_recover(queue) != 1
    return 0
  path = root + "/composition/objects/" + identity + ".tensor"
  old = File.read_prefix(path,12632129)
  if old != nil && old != blob
    return 0
  if old == nil && ffrf_atomic(path,blob,"packed-feed") != 1
    return 0
  submitted = ffmd_count(queue + "submitted") ## i64
  old = File.read_prefix(queue + "by-id/" + identity,32)
  if old != nil
    ticket = ffpk_decimal(old.strip()) ## i64
    if ticket < 1 || ticket > submitted || old != ticket.to_s() + "\n" || ffbq_read(queue,"tasks",ticket) != raw
      return 0
    return 1
  if submitted >= 999999999999 || ffbq_put(queue,"tasks",submitted+1,raw) != 1 || ffpf_bind(queue,raw,submitted+1) != 1
    return 0
  ffrf_atomic(queue + "submitted",(submitted+1).to_s() + "\n","packed-feed")

# Checks immutable bytes and dimensions, not tensor correctness. The caller
# must cross ffpk_exact before using an output as a seed or a claimed result.
-> ffpf_load(root, raw, out, words, meta) (String String i64[] i64 i64[]) i64
  if ffpf_valid(raw) != 1
    return 0
  f = raw.strip().split(" ")
  blob = File.read_prefix(root + "/composition/objects/" + f[1] + ".tensor",12632129)
  if blob == nil || Crypto:SHA256.hexdigest(blob) != f[1]
    return 0
  rank = ffpk_parse(blob,out,words,meta,4) ## i64
  if rank < 1 || meta[0].to_s() != f[2] || meta[1].to_s() != f[3] || meta[2].to_s() != f[4] || rank.to_s() != f[5]
    return 0
  rank
