# Bounded immutable-prefix pages for composition records. New writes use at
# most 64 records/page, with atomic replacement and a payload digest. Legacy
# per-record files remain readable; no old evidence is deleted implicitly.
use ../fleet/refinement_artifacts

-> ffbq_path(queue, kind, sequence) (String String i64)
  queue + kind + "-pages/" + ((sequence-1)/64).to_s()

# nil = missing; empty string = malformed; otherwise verified page payload.
# meta contains first sequence and record count. Hashes protect serialization,
# not tensor correctness: the composition admission gate still expands inputs.
-> ffbq_page(queue, kind, sequence, meta) (String String i64 i64[])
  raw = File.read_prefix(ffbq_path(queue, kind, sequence), 16641)
  if raw == nil
    return nil
  if raw.size() > 16640 || !raw.ends_with?("\n")
    return ""
  split = 0 ## i64
  while split < raw.size() && raw.byte_at(split) != 10 && split < 128
    split += 1
  if split >= 128 || split >= raw.size()
    return ""
  header = raw.slice(0, split).split(" ")
  if header.size() != 4 || header[0] != "MFCP1"
    return ""
  first = ffw_parse_decimal_i64(header[1]) ## i64
  count = ffw_parse_decimal_i64(header[2]) ## i64
  if first < 1 || first > 1000000000000 || count < 1 || count > 64 || (first-1)/64 != (sequence-1)/64 || (first+count-2)/64 != (sequence-1)/64
    return ""
  body = raw.slice(split+1, raw.size()-split-1)
  if raw.slice(0, split) != "MFCP1 " + first.to_s() + " " + count.to_s() + " " + Crypto:SHA256.hexdigest(body)
    return ""
  lines = 0 ## i64
  length = 0 ## i64
  i = 0 ## i64
  while i < body.size()
    length += 1
    if length > 256
      return ""
    if body.byte_at(i) == 10
      if length == 1
        return ""
      lines += 1
      length = 0
    i += 1
  if lines != count || length != 0
    return ""
  meta[0] = first
  meta[1] = count
  body

-> ffbq_line(body, index) (String i64)
  first = 0 ## i64
  i = 0 ## i64
  line = 0 ## i64
  while i < body.size()
    if body.byte_at(i) == 10
      if line == index
        return body.slice(first, i-first+1)
      line += 1
      first = i+1
    i += 1
  nil

-> ffbq_read(queue, kind, sequence) (String String i64)
  if sequence < 1 || sequence > 1000000000000
    return ""
  old = File.read_prefix(queue + kind + "/" + sequence.to_s(), 257)
  if old != nil
    if old.size() > 256 || old.size() < 2 || !old.ends_with?("\n")
      return ""
    i = 0 ## i64
    while i < old.size()-1
      if old.byte_at(i) == 10
        return ""
      i += 1
    return old
  meta = i64[2]
  body = ffbq_page(queue, kind, sequence, meta)
  if body == nil || body == ""
    return body
  if sequence < meta[0] || sequence >= meta[0]+meta[1]
    return nil
  ffbq_line(body, sequence-meta[0])

-> ffbq_put(queue, kind, sequence, record) (String String i64 String) i64
  if sequence < 1 || sequence > 1000000000000 || record.size() < 2 || record.size() > 256 || !record.ends_with?("\n")
    return 0
  i = 0 ## i64
  while i < record.size()-1
    if record.byte_at(i) == 10
      return 0
    i += 1
  # Read a page only once per append. The legacy path remains uncommon and
  # uses the same strict reader as replay; it never shadows a malformed file.
  legacy = File.read_prefix(queue + kind + "/" + sequence.to_s(), 257)
  if legacy != nil
    if ffbq_read(queue, kind, sequence) == record
      return 1
    return 0
  meta = i64[2]
  body = ffbq_page(queue, kind, sequence, meta)
  if body == ""
    return 0
  if body == nil
    if sequence > 1
      previous = ffbq_read(queue, kind, sequence-1)
      if previous == nil || previous == ""
        return 0
    body = ""
    meta[0] = sequence
    meta[1] = 0
  elsif sequence >= meta[0] && sequence < meta[0]+meta[1]
    if ffbq_line(body, sequence-meta[0]) == record
      return 1
    return 0
  if sequence != meta[0]+meta[1] || meta[1] >= 64
    return 0
  body = body + record
  raw = "MFCP1 " + meta[0].to_s() + " " + (meta[1]+1).to_s() + " " + Crypto:SHA256.hexdigest(body) + "\n" + body
  ffrf_atomic(ffbq_path(queue, kind, sequence), raw, "composition")
