# Mixed contexts have their own parent and recipe journals. A single cold
# child is the writer. Fixed-axis and mixed recipes share one occupancy cap.
use counters
use mixed_bank
use pages

-> ffmd_parent_valid(raw) (String) i64
  if raw == nil || raw == ""
    return 0
  fields = raw.strip().split(" ")
  if fields.size() != 3 || fields[0] != "MFMD1" || ffrf_hash_valid(fields[1]) != 1 || ffrf_hash_valid(fields[2]) != 1 || raw != "MFMD1 " + fields[1] + " " + fields[2] + "\n"
    return 0
  1

# A recipe binds its deferred parent ticket and context, so the last recipe
# also recovers a cursor update lost immediately after its append.
-> ffmd_task_code(queue, raw, parents) (String String i64) i64
  if raw == nil || raw == ""
    return 0-1
  fields = raw.strip().split(" ")
  if fields.size() != 9 || fields[0] != "MFM1" || ffrf_hash_valid(fields[1]) != 1 || ffrf_hash_valid(fields[2]) != 1
    return 0-1
  ticket = ffw_parse_decimal_i64(fields[3]) ## i64
  context = ffw_parse_decimal_i64(fields[4]) ## i64
  n = ffw_parse_decimal_i64(fields[5]) ## i64
  m = ffw_parse_decimal_i64(fields[6]) ## i64
  p = ffw_parse_decimal_i64(fields[7]) ## i64
  price = ffw_parse_decimal_i64(fields[8]) ## i64
  if ticket < 1 || ticket > parents || context < 0 || context >= 27 || price < 1 || price > 16384 || ffpk_stride(n, m, p) < 1
    return 0-1
  if ffbq_read(queue, "parents", ticket) != "MFMD1 " + fields[1] + " " + fields[2] + "\n"
    return 0-1
  if raw != "MFM1 " + fields[1] + " " + fields[2] + " " + ticket.to_s() + " " + context.to_s() + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + price.to_s() + "\n"
    return 0-1
  27*(ticket-1)+context

-> ffmd_recover(root) (String) i64
  queue = root + "/composition/mixed/"
  parents = ffmd_count(queue + "parent-submitted") ## i64
  submitted = ffmd_count(queue + "submitted") ## i64
  consumed = ffmd_count(queue + "consumed") ## i64
  cursor = ffmd_count(queue + "context") ## i64
  if parents < 0 || parents > 1000000000000 || submitted < 0 || submitted > 1000000000000 || consumed < 0 || cursor < 0
    return 0
  tail = nil
  if parents < 1000000000000
    tail = ffbq_read(queue, "parents", parents+1)
  if tail != nil
    if ffmd_parent_valid(tail) != 1 || (parents < 999999999999 && ffbq_read(queue, "parents", parents+2) != nil)
      return 0
    parents += 1
    if ffrf_atomic(queue + "parent-submitted", parents.to_s() + "\n", "mixed") != 1
      return 0
  if parents > 0
    tail = ffbq_read(queue, "parents", parents)
    if ffmd_parent_valid(tail) != 1
      return 0
    marker = queue + "by-parent/" + Crypto:SHA256.hexdigest(tail)
    prior = File.read_prefix(marker, 32)
    if prior != nil && prior != parents.to_s() + "\n"
      return 0
    if prior == nil && ffrf_atomic(marker, parents.to_s() + "\n", "mixed") != 1
      return 0
  tail = nil
  if submitted < 1000000000000
    tail = ffbq_read(queue, "tasks", submitted+1)
  if tail != nil
    if ffmd_task_code(queue, tail, parents) < 0 || (submitted < 999999999999 && ffbq_read(queue, "tasks", submitted+2) != nil)
      return 0
    submitted += 1
    if ffrf_atomic(queue + "submitted", submitted.to_s() + "\n", "mixed") != 1
      return 0
  if consumed > submitted || cursor > 27*parents
    return 0
  if submitted > 0
    code = ffmd_task_code(queue, ffbq_read(queue, "tasks", submitted), parents) ## i64
    if code < 0 || code > cursor
      return 0
    if code == cursor
      cursor += 1
      if ffrf_atomic(queue + "context", cursor.to_s() + "\n", "mixed") != 1
        return 0
  1

-> ffmd_deferred(root) (String) i64
  queue = root + "/composition/mixed/"
  parents = ffmd_count(queue + "parent-submitted") ## i64
  cursor = ffmd_count(queue + "context") ## i64
  if parents < 0 || cursor < 0 || cursor > 27*parents
    return 0-1
  27*parents-cursor

-> ffmd_offer(root, parent, bank) (String String String) i64
  if ffrf_hash_valid(parent) != 1 || ffrf_hash_valid(bank) != 1
    return 0
  queue = root + "/composition/mixed/"
  dirs = ["parents", "parents-pages", "by-parent", "tasks", "tasks-pages", "results", "results-pages"]
  i = 0 ## i64
  while i < dirs.size()
    if !File.mkdir_p(queue + dirs[i])
      return 0
    i += 1
  if ffmd_recover(root) != 1
    return 0
  body = "MFMD1 " + parent + " " + bank + "\n"
  marker = queue + "by-parent/" + Crypto:SHA256.hexdigest(body)
  previous = File.read_prefix(marker, 32)
  submitted = ffmd_count(queue + "parent-submitted") ## i64
  if previous != nil
    ticket = ffw_parse_decimal_i64(previous.strip()) ## i64
    if ticket < 1 || ticket > submitted || previous != ticket.to_s() + "\n" || ffbq_read(queue, "parents", ticket) != body
      return 0
    return 1
  if submitted >= 1000000000000
    return 0
  submitted += 1
  if ffbq_put(queue, "parents", submitted, body) != 1 || ffrf_atomic(queue + "parent-submitted", submitted.to_s() + "\n", "mixed") != 1
    return 0
  ffrf_atomic(marker, submitted.to_s() + "\n", "mixed")

# Include the old lane's at-most-nine unacknowledged records, but never
# rewrite its counter or parent marker from the independent mixed writer.
-> ffmd_occupancy(root) (String) i64
  queue = root + "/composition/"
  submitted = ffmd_count(queue + "submitted") ## i64
  consumed = ffmd_count(queue + "consumed") ## i64
  mixed = ffmd_count(queue + "mixed/submitted") ## i64
  done = ffmd_count(queue + "mixed/consumed") ## i64
  if submitted < 0 || submitted > 1000000000000 || consumed < 0 || mixed < 0 || mixed > 1000000000000 || done < 0 || done > mixed
    return 0-1
  recovered = 0 ## i64
  while submitted < 1000000000000 && ffbq_read(queue, "tasks", submitted+1) != nil
    if recovered >= 9 || ffbq_read(queue, "tasks", submitted+1) == ""
      return 0-1
    submitted += 1
    recovered += 1
  if consumed > submitted
    return 0-1
  submitted-consumed+mixed-done

# At most 27 contexts per call. Deferred references are not
# recipes and do not reserve unbounded batches. Every admitted recipe crosses
# the shared occupancy check; a blocked source gets first claim on freed room.
-> ffmd_admit(root, max_contexts) (String i64) i64
  if max_contexts < 1 || max_contexts > 27 || ffmd_recover(root) != 1
    return 0
  if File.exists?(root + "/stop") || File.exists?(root + "/backpressure")
    return 1
  queue = root + "/composition/mixed/"
  cursor = ffmd_count(queue + "context") ## i64
  parents = ffmd_count(queue + "parent-submitted") ## i64
  submitted = ffmd_count(queue + "submitted") ## i64
  if cursor >= 27*parents
    return 1
  limit = ffbc_composition_limit() ## i64
  cap = ffrf_capacity() ## i64
  parent = i64[3*cap]
  meta = i64[4]
  parity = i64[4096]
  bank = i64[22*3*128]
  costs = i64[22]
  work = i64[3*128]
  leaves = i64[12*128]
  prices = i64[4]
  mates = i64[512]
  axes = i64[512]
  plan = i64[6*512]
  memo = i64[65536]
  choice = i64[65536]
  status = i64[3]
  loaded = 0 ## i64
  fields = []
  done = 0 ## i64
  while cursor < 27*parents && done < max_contexts
    if File.exists?(root + "/stop")
      return 1
    occupied = ffmd_occupancy(root) ## i64
    if occupied < 0
      return 0
    if limit != 0 && occupied >= limit
      return 1
    ticket = cursor/27+1 ## i64
    context = cursor%27 ## i64
    if ticket != loaded
      raw = ffbq_read(queue, "parents", ticket)
      if ffmd_parent_valid(raw) != 1
        return 0
      fields = raw.strip().split(" ")
      if ffrf_load(root, fields[1], parent, cap, meta, parity) != 1 || ffmb_load_bank(root, fields[2], bank, 22*3*128, costs, 22, work, parity) != 1
        return 0
      loaded = ticket
    a = 2+context/9 ## i64
    b = 2+(context/3)%3 ## i64
    c = 2+context%3 ## i64
    n = meta[0]*a ## i64
    m = meta[1]*b ## i64
    p = meta[2]*c ## i64
    if meta[3] <= 512 && ffpk_stride(n, m, p) > 0
      if ffmb_context(bank, 22*3*128, costs, 22, a, b, c, leaves, 12*128, prices, 4) != 1
        return 0
      price = ffmm_plan(parent, 3*cap, cap, meta[3], prices, 4, mates, axes, 512, plan, 6*512, memo, choice, 65536, status, 3, 50000) ## i64
      if price < 1
        return 0
      if price <= 16384
        body = "MFM1 " + fields[1] + " " + fields[2] + " " + ticket.to_s() + " " + context.to_s() + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + price.to_s() + "\n"
        if submitted >= 1000000000000
          return 0
        submitted += 1
        if ffbq_put(queue, "tasks", submitted, body) != 1 || ffrf_atomic(queue + "submitted", submitted.to_s() + "\n", "mixed") != 1
          return 0
    cursor += 1
    if ffrf_atomic(queue + "context", cursor.to_s() + "\n", "mixed") != 1
      return 0
    done += 1
  1

# Reconstruct MFM1's fixed, versioned 50k-state algorithm. The later common
# task consumer still checks the full output tensor before writing archives.
-> ffmd_expand(root, raw, parent, meta, out, parity) (String String i64[] i64[] i64[] i64[]) i64
  queue = root + "/composition/mixed/"
  if ffmd_task_code(queue, raw, ffmd_count(queue + "parent-submitted")) < 0
    return 0-1
  fields = raw.strip().split(" ")
  cap = ffrf_capacity() ## i64
  if ffrf_load(root, fields[1], parent, cap, meta, parity) != 1 || meta[3] > 512
    return 0-1
  context = ffw_parse_decimal_i64(fields[4]) ## i64
  a = 2+context/9 ## i64
  b = 2+(context/3)%3 ## i64
  c = 2+context%3 ## i64
  n = meta[0]*a ## i64
  m = meta[1]*b ## i64
  p = meta[2]*c ## i64
  bank = i64[22*3*128]
  costs = i64[22]
  work = i64[3*128]
  leaves = i64[12*128]
  prices = i64[4]
  mates = i64[512]
  axes = i64[512]
  plan = i64[6*512]
  memo = i64[65536]
  choice = i64[65536]
  status = i64[3]
  if ffmb_load_bank(root, fields[2], bank, 22*3*128, costs, 22, work, parity) != 1 || ffmb_context(bank, 22*3*128, costs, 22, a, b, c, leaves, 12*128, prices, 4) != 1
    return 0-1
  price = ffmm_plan(parent, 3*cap, cap, meta[3], prices, 4, mates, axes, 512, plan, 6*512, memo, choice, 65536, status, 3, 50000) ## i64
  if price < 1 || price > 16384 || fields[5] != n.to_s() || fields[6] != m.to_s() || fields[7] != p.to_s() || fields[8] != price.to_s()
    return 0-1
  rank = ffmm_compose(parent, 3*cap, cap, meta[3], meta[0], meta[1], meta[2], a, b, c, leaves, 12*128, 128, prices, 4, mates, axes, 512, out, 3*32*16384) ## i64
  meta[0] = n
  meta[1] = m
  meta[2] = p
  meta[3] = price
  rank
