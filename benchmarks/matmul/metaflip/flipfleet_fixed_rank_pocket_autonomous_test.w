use flipfleet_fixed_rank_pocket

-> fffrpat_expect(label, condition) (String bool) i64
  if !condition
    << "FIXED_RANK_POCKET_AUTONOMOUS_FAIL " + label
    exit(1)
  1

-> fffrpat_scheme_density(scheme) (FFBCScheme) i64
  total = 0 ## i64
  term = i64[3]
  i = 0 ## i64
  while i < scheme.rank()
    if fffrp_scalar_term(scheme, i, term) == 1
      total += fffrp_popcount(term[0]) + fffrp_popcount(term[1]) + fffrp_popcount(term[2])
    i += 1
  total

-> fffrpat_distance(left, right) (FFBCScheme FFBCScheme) i64
  if left == nil || right == nil
    return 0 - 1
  common = 0 ## i64
  term = i64[3]
  i = 0 ## i64
  while i < left.rank()
    if fffrp_scalar_term(left, i, term) == 1
      common += fffrp_scheme_has_scalar(right, term[0], term[1], term[2])
    i += 1
  left.rank() + right.rank() - common - common

root = "bits/tungsten-metaflip/lib/metaflip/seeds/gf2/"

# Lookup and count have deliberately distinct contracts.  A one-ticket source
# used to make an out-of-range lookup return the count (1), which was
# indistinguishable from success and exposed uninitialized ticket metadata.
one_u = [1, 1, 2]
one_v = [2, 4, 8]
one_w = [16, 32, 64]
one_ticket = i64[3]
fffrpat_expect("one-ticket count", fffrp_ticket_count(one_u, one_v, one_w, 3) == 1)
fffrpat_expect("one-ticket lookup", fffrp_ticket(one_u, one_v, one_w, 3, 0, one_ticket) == 1 && one_ticket[0] == 0 && one_ticket[1] == 1 && one_ticket[2] == 0)
fffrpat_expect("one-ticket out of range", fffrp_ticket(one_u, one_v, one_w, 3, 1, one_ticket) == 0)

c013 = ffbc_load_exact(root + "matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt", 7, 7, 7, 260)
fffrpat_expect("load C013", c013 != nil && c013.rank() == 247 && fffrpat_scheme_density(c013) == 3554)

source_u = i64[260]
source_v = i64[260]
source_w = i64[260]
fffrpat_expect("scalarize C013", fffrp_scalar_scheme(c013, source_u, source_v, source_w) == 247)
ticket_count = fffrp_ticket_count(source_u, source_v, source_w, 247) ## i64
fffrpat_expect("C013 ticket count", ticket_count == 43)

endpoint_u = i64[8]
endpoint_v = i64[8]
endpoint_w = i64[8]
origins = i64[8]
stats = i64[32]

best_gain = 0 ## i64
best_ticket = 0 - 1 ## i64
best_rise = 0 ## i64
best_terms = 0 ## i64
best_endpoint_u = i64[8]
best_endpoint_v = i64[8]
best_endpoint_w = i64[8]
best_origins = i64[8]
ticket = 8 ## i64
while ticket < 9
  gain = fffrp_autonomous_ticket(source_u, source_v, source_w, 247, ticket, 5, 5, 4096, -1, endpoint_u, endpoint_v, endpoint_w, origins, stats) ## i64
  << "AUTONOMOUS_C013_TICKET ticket=" + ticket.to_s() + " gain=" + gain.to_s() + " states=" + stats[0].to_s() + " cap=" + stats[9].to_s()
  if gain > best_gain
    best_gain = gain
    best_ticket = ticket
    best_rise = stats[8]
    best_terms = stats[7]
    fffrp_copy_terms(endpoint_u, endpoint_v, endpoint_w, 0, best_endpoint_u, best_endpoint_v, best_endpoint_w, 0, best_terms)
    i = 0 ## i64
    while i < best_terms
      best_origins[i] = origins[i]
      i += 1
    << "AUTONOMOUS_C013 ticket=" + ticket.to_s() + " gain=" + gain.to_s() + " depth=" + stats[6].to_s() + " terms=" + stats[7].to_s() + " states=" + stats[0].to_s() + " proposals=" + stats[1].to_s() + " max-rise=" + stats[8].to_s() + " cap=" + stats[9].to_s()
  ticket += 1
fffrpat_expect("C013 autonomous density gain", best_gain >= 8 && best_terms >= 3)
fffrpat_expect("C013 crosses DSLACK4", best_rise > 4)
<< "AUTONOMOUS_C013_PATH density=" + (3554 + stats[14]).to_s() + "->" + (3554 + stats[15]).to_s() + "->" + (3554 + stats[16]).to_s() + "->" + (3554 + stats[17]).to_s() + "->" + (3554 + stats[18]).to_s() + " axes=" + stats[21].to_s() + "/" + stats[22].to_s() + "/" + stats[23].to_s() + "/" + stats[24].to_s() + " terms=" + stats[26].to_s() + "/" + stats[27].to_s() + "/" + stats[28].to_s() + "/" + stats[29].to_s() + "/" + stats[30].to_s()
c013_closed = fffrp_materialize_selected(c013, best_origins, best_endpoint_u, best_endpoint_v, best_endpoint_w, best_terms)
fffrpat_expect("C013 whole endpoint exact", c013_closed != nil && c013_closed.rank() == 247 && fffrpat_scheme_density(c013_closed) <= 3546)
saved = ffbc_load_exact("benchmarks/matmul/metaflip/matmul_7x7_rank247_d3546_autonomous_flip_pocket_gf2.txt", 7, 7, 7, 260)
d3094 = ffbc_load_exact(root + "matmul_7x7_rank247_d3094_three_flip_density_gf2.txt", 7, 7, 7, 260)
fffrpat_expect("saved C013 tunnel certificate", saved != nil && fffrpat_distance(c013_closed, saved) == 0)
fffrpat_expect("C013 tunnel support distance", fffrpat_distance(c013, saved) == 6)
fffrpat_expect("C013 tunnel outside d3094 support", d3094 != nil && fffrpat_distance(saved, d3094) == 494)

# A matched run with the ordinary per-edge density gate cannot retain the
# +10 middle edge of the same word.
gated_gain = fffrp_autonomous_ticket(source_u, source_v, source_w, 247, best_ticket, 5, 5, 4096, 4, endpoint_u, endpoint_v, endpoint_w, origins, stats) ## i64
<< "AUTONOMOUS_C013_GATED ticket=" + best_ticket.to_s() + " gain=" + gated_gain.to_s() + " states=" + stats[0].to_s() + " prunes=" + stats[10].to_s()
fffrpat_expect("C013 gate loses tunnel value", gated_gain < 8 && stats[10] > 0)

# The rectangular d92 door is a second, structurally unrelated real control.
# It is not blocked by DSLACK4; the autonomous selector should still recover
# the known d84 endpoint without being given that endpoint or its five terms.
d92 = ffbc_load_exact(root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt", 2, 2, 5, 24)
fffrpat_expect("load d92", d92 != nil && d92.rank() == 18 && fffrpat_scheme_density(d92) == 92)
d92_u = i64[24]
d92_v = i64[24]
d92_w = i64[24]
fffrpat_expect("scalarize d92", fffrp_scalar_scheme(d92, d92_u, d92_v, d92_w) == 18)
d92_tickets = fffrp_ticket_count(d92_u, d92_v, d92_w, 18) ## i64
d92_best = 0 ## i64
d92_hits = 0 ## i64
d92_ticket = 0 ## i64
while d92_ticket < d92_tickets
  d92_gain = fffrp_autonomous_ticket(d92_u, d92_v, d92_w, 18, d92_ticket, 5, 5, 512, -1, endpoint_u, endpoint_v, endpoint_w, origins, stats) ## i64
  if d92_gain > d92_best
    d92_best = d92_gain
  if d92_gain >= 8
    d92_closed = fffrp_materialize_selected(d92, origins, endpoint_u, endpoint_v, endpoint_w, stats[7])
    if d92_closed != nil && fffrpat_scheme_density(d92_closed) <= 84
      d92_hits += 1
  d92_ticket += 1
<< "AUTONOMOUS_D92 tickets=" + d92_tickets.to_s() + " hits=" + d92_hits.to_s() + " best-gain=" + d92_best.to_s()
fffrpat_expect("d92 selector miss is pinned", d92_tickets == 16 && d92_best == 6 && d92_hits == 0)

<< "flipfleet_fixed_rank_pocket_autonomous_test: pass"
