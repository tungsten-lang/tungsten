use ../lib/metaflip/scheme

-> original_text(st, uo, vo, wo, liveo, rank) (i64[] i64 i64 i64 i64 i64)
  body = rank.to_s() + "\n"
  i = 0 ## i64
  while i < rank
    slot = i ## i64
    if liveo >= 0
      slot = st[liveo + i]
    body = body + st[uo + slot].to_s() + " " + st[vo + slot].to_s() + " " + st[wo + slot].to_s() + "\n"
    i += 1
  body

n = 2 ## i64
while n <= 7
  capacity = ffw_default_capacity(n) ## i64
  st = i64[ffw_state_size(capacity)]
  rank = ffw_init_naive_cap(st, n, capacity, 9719, 8, 100, 10000, 10000) ## i64
  turn = 0 ## i64
  while turn < 3
    old_best = original_text(st, st[47], st[48], st[49], 0 - 1, st[7])
    best = ffw_view_text(st, st[47], st[48], st[49], 0 - 1, st[7])
    old_current = original_text(st, st[44], st[45], st[46], st[50], st[6])
    current = ffw_view_text(st, st[44], st[45], st[46], st[50], st[6])
    if best != old_best || current != old_current || ffw_verify_best_exact(st, n) != 1 || ffw_verify_current_exact(st, n) != 1
      << "FAIL checkpoint bytes/exactness n=" + n.to_s() + " turn=" + turn.to_s()
      exit(1)
    z = ffw_walk(st, 10000)
    turn += 1
  n += 1
<< "PASS checkpoint text: byte-identical current/best views and exact tensors for 2x2 through 7x7"
