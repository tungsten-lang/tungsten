# Bounded out-of-order completion. The window is 128 tickets; one in four
# completions serves its oldest pending ticket. No price discards a candidate.
use pages
use packed

# state = [completion count, first unfinished ticket, four unsigned 32-bit
# completion masks]. Thus count = first-1 + popcount(masks), even on restart.
-> ffbs_blob(state) (i64[])
  raw = "MFCS1"
  i = 0 ## i64
  while i < 6
    raw = raw + " " + state[i].to_s()
    i += 1
  raw + " " + Crypto:SHA256.hexdigest(raw) + "\n"

-> ffbs_done(state, ticket) (i64[] i64) i64
  offset = ticket-state[1] ## i64
  if offset < 0
    return 1
  if offset >= 128
    return 0
  (state[2+offset/32] >> (offset%32)) & 1

-> ffbs_valid(state, submitted) (i64[] i64) i64
  if state[0] < 0 || state[0] > submitted || state[1] < 1 || state[1] > submitted+1 || (state[2] & 1) != 0
    return 0
  count = state[1]-1 ## i64
  i = 0 ## i64
  while i < 4
    if state[i+2] < 0 || state[i+2] > 4294967295
      return 0
    count += ffw_popcount(state[i+2])
    i += 1
  if count != state[0]
    return 0
  ticket = submitted+1 ## i64
  if ticket < state[1]
    ticket = state[1]
  while ticket < state[1]+128
    if ffbs_done(state, ticket) != 0
      return 0
    ticket += 1
  1

-> ffbs_mark(state, ticket, submitted) (i64[] i64 i64) i64
  offset = ticket-state[1] ## i64
  if ffbs_valid(state, submitted) != 1 || ticket > submitted || offset < 0 || offset >= 128 || ffbs_done(state, ticket) != 0
    return 0
  state[2+offset/32] = state[2+offset/32] | (1 << (offset%32))
  state[0] += 1
  while (state[2] & 1) != 0
    i = 0 ## i64
    while i < 3
      state[2+i] = (state[2+i] >> 1) | ((state[3+i] & 1) << 31)
      i += 1
    state[5] = state[5] >> 1
    state[1] += 1
  ffbs_valid(state, submitted)

-> ffbs_result_ticket(raw, ordinal) (String i64) i64
  if raw == nil || raw == "" || raw.size() > 256
    return 0
  fields = raw.strip().split(" ")
  if fields.size() == 5 && fields[0] == "MFC_RESULT1"
    return ordinal
  if fields.size() == 6 && fields[0] == "MFC_RESULT2"
    ticket = ffw_parse_decimal_i64(fields[1]) ## i64
    if ticket > 0 && ticket <= 1000000000000
      return ticket
  0

-> ffbs_load(queue, submitted, reported, state) (String i64 i64 i64[]) i64
  raw = File.read_prefix(queue + "schedule", 257)
  if raw == nil
    # A nonzero v2 cursor is not a v1 FIFO prefix. Starting from zero may
    # instead replay every committed result through the exact gate.
    last = ffbq_read(queue, "results", reported)
    if reported > 0 && (last == nil || !last.starts_with?("MFC_RESULT1 "))
      return 0
    state[0] = reported
    state[1] = reported+1
    i = 2 ## i64
    while i < 6
      state[i] = 0
      i += 1
    if ffbs_valid(state, submitted) != 1
      return 0
    return ffrf_atomic(queue + "schedule", ffbs_blob(state), "composition")
  fields = raw.strip().split(" ")
  if fields.size() != 8 || fields[0] != "MFCS1"
    return 0
  i = 0 ## i64
  while i < 6
    state[i] = ffw_parse_decimal_i64(fields[i+1])
    i += 1
  if ffbs_valid(state, submitted) != 1 || raw != ffbs_blob(state) || reported > state[0]
    return 0
  1

# Prices order work only. They are checked against the parent/leaf again at
# materialization, and the entire output must pass the tensor gate.
-> ffbs_choose_at(queue, archive, submitted, state, fifo) (String String i64 i64[] i64) i64
  if state[1] > submitted
    return 0
  if fifo != 0 || state[0]%4 == 0
    return state[1]
  best = state[1] ## i64
  best_num = 9223372036854775807 ## i64
  best_den = 1 ## i64
  cached_page = 0-1 ## i64
  payload = ""
  page_meta = i64[2]
  ticket = state[1] ## i64
  while ticket <= submitted && ticket < state[1]+128
    if ffbs_done(state, ticket) == 0
      raw = ""
      legacy = File.read_prefix(queue + "tasks/" + ticket.to_s(), 257)
      if legacy != nil
        raw = ffbq_read(queue, "tasks", ticket)
      else
        page = (ticket-1)/64 ## i64
        if page != cached_page
          payload = ffbq_page(queue, "tasks", ticket, page_meta)
          cached_page = page
        if payload == nil || payload == "" || ticket < page_meta[0] || ticket >= page_meta[0]+page_meta[1]
          return 0
        raw = ffbq_line(payload, ticket-page_meta[0])
      if raw == nil || raw == ""
        return 0
      fields = raw.strip().split(" ")
      if fields.size() != 9 || (fields[0] != "MFC1" && fields[0] != "MCG1" && fields[0] != "MFM1" && fields[0] != "MFM2" && fields[0] != "MFM3") || ffrf_hash_valid(fields[1]) != 1 || ffrf_hash_valid(fields[2]) != 1
        return 0
      n = ffw_parse_decimal_i64(fields[5]) ## i64
      m = ffw_parse_decimal_i64(fields[6]) ## i64
      p = ffw_parse_decimal_i64(fields[7]) ## i64
      rank = ffw_parse_decimal_i64(fields[8]) ## i64
      if rank < 1 || rank > 16384 || ffpk_stride(n, m, p) < 1
        return 0
      baseline = n*m*p ## i64
      shape = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
      prior = File.read_prefix(archive + "best/" + shape, 100)
      if prior != nil
        values = prior.strip().split(" ")
        if values.size() == 2 && ffrf_hash_valid(values[1]) == 1
          bound = ffw_parse_decimal_i64(values[0]) ## i64
          if bound > 0 && bound < baseline
            baseline = bound
      # Avoid the sentinel product; all later products are <= 16384*32768.
      better = 0 ## i64
      if best_num == 9223372036854775807
        better = 1
      elsif rank*best_den < best_num*baseline || (rank*best_den == best_num*baseline && rank < best_num)
        better = 1
      if better != 0
        best = ticket
        best_num = rank
        best_den = baseline
    ticket += 1
  best

-> ffbs_choose(queue, submitted, state, fifo) (String i64 i64[] i64) i64
  ffbs_choose_at(queue, queue, submitted, state, fifo)
