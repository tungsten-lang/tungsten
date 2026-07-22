# Bounded "Rubik word" audit for the autonomous fixed-rank pocket move.
#
# One autonomous ticket is useful on the C013 7x7 composition, but a real
# tunnel can require several individually unremarkable tickets.  This bench
# therefore chains two and three ticket endpoints while keeping the same
# strict local limits used by the intake test:
#
#   pocket terms <= 5, local depth <= 5, states <= 512, edge debt <= 12.
#
# Each beam expansion retains (a) the best endpoint found by the complete
# bounded autonomous ticket search and (b) the ticket's legal one-flip
# endpoint.  The latter is important: it admits a neutral/uphill first word
# whose child can pay the debt on a later word.  Every whole-scheme endpoint
# is independently exact-gated.  The archive is canonical-term-set
# de-duplicated; hashes are only a prefilter for authoritative equality.

use flipfleet_fixed_rank_pocket
use flipfleet_bank_policy

+ FFFRPWordNode
  -> new(scheme, parent, ticket, kind, density, local_delta, barrier, states, proposals, has_nonimproving, root_distance, trace)
    @scheme = scheme
    @parent = parent
    @meta = i64[10]
    @meta[0] = ticket
    @meta[1] = kind
    @meta[2] = density
    @meta[3] = local_delta
    @meta[4] = barrier
    @meta[5] = states
    @meta[6] = proposals
    @meta[7] = has_nonimproving
    @meta[8] = root_distance
    @meta[9] = 0
    if parent != nil
      @meta[9] = parent.depth() + 1
    @trace = trace

  -> scheme()
    @scheme
  -> parent()
    @parent
  -> ticket()
    @meta[0]
  -> kind()
    @meta[1]
  -> density()
    @meta[2]
  -> local_delta()
    @meta[3]
  -> barrier()
    @meta[4]
  -> states()
    @meta[5]
  -> proposals()
    @meta[6]
  -> has_nonimproving()
    @meta[7]
  -> root_distance()
    @meta[8]
  -> depth()
    @meta[9]
  -> trace()
    @trace

+ FFFRPWordArchive
  -> new()
    @nodes = []
    @hashes = []

  -> size()
    @nodes.size()
  -> node(index)
    @nodes[index]
  -> find(scheme, hash)
    i = 0 ## i64
    while i < @nodes.size()
      if @hashes[i] == hash && fffrpw_equal(@nodes[i].scheme(), scheme) == 1
        return i
      i += 1
    0 - 1
  -> add(node, hash)
    @nodes.push(node)
    @hashes.push(hash)
    @nodes.size() - 1

-> fffrpw_expect(label, condition) (String bool) i64
  if !condition
    << "FIXED_RANK_POCKET_WORD_FAIL " + label
    exit(1)
  1

-> fffrpw_density(scheme) (FFBCScheme) i64
  if scheme == nil
    return 0 - 1
  total = 0 ## i64
  term = i64[3]
  i = 0 ## i64
  while i < scheme.rank()
    if fffrp_scalar_term(scheme, i, term) != 1
      return 0 - 1
    total += fffrp_popcount(term[0]) + fffrp_popcount(term[1]) + fffrp_popcount(term[2])
    i += 1
  total

# Authoritative canonical term-set equality.  Schemes are parity-compacted,
# so a zero symmetric difference is exact equality.
-> fffrpw_equal(left, right) (FFBCScheme FFBCScheme) i64
  if left == nil || right == nil || left.rank() != right.rank()
    return 0
  common = 0 ## i64
  term = i64[3]
  i = 0 ## i64
  while i < left.rank()
    if fffrp_scalar_term(left, i, term) != 1
      return 0
    common += fffrp_scheme_has_scalar(right, term[0], term[1], term[2])
    i += 1
  if common == left.rank()
    return 1
  0

-> fffrpw_distance(left, right) (FFBCScheme FFBCScheme) i64
  if left == nil || right == nil
    return 0 - 1
  common = 0 ## i64
  term = i64[3]
  i = 0 ## i64
  while i < left.rank()
    if fffrp_scalar_term(left, i, term) != 1
      return 0 - 1
    common += fffrp_scheme_has_scalar(right, term[0], term[1], term[2])
    i += 1
  left.rank() + right.rank() - common - common

-> fffrpw_hash(scheme) (FFBCScheme) i64
  if scheme == nil
    return 0
  rank = scheme.rank() ## i64
  us = i64[rank]
  vs = i64[rank]
  ws = i64[rank]
  if fffrp_scalar_scheme(scheme, us, vs, ws) != rank
    return 0
  fffrp_sort_terms(us, vs, ws, rank)
  hash = fffrp_hash_mix(1469598103934665603, rank) ## i64
  i = 0 ## i64
  while i < rank
    hash = fffrp_hash_mix(hash, us[i])
    hash = fffrp_hash_mix(hash, vs[i])
    hash = fffrp_hash_mix(hash, ws[i])
    i += 1
  hash

-> fffrpw_add(archive, candidates, root, parent, candidate, ticket, kind, local_delta, barrier, states, proposals, trace) (FFFRPWordArchive Array FFBCScheme FFFRPWordNode FFBCScheme i64 i64 i64 i64 i64 i64 String) i64
  if candidate == nil || ffbc_verify_exact(candidate) != 1 || candidate.rank() != root.rank()
    return 0
  hash = fffrpw_hash(candidate) ## i64
  if archive.find(candidate, hash) >= 0
    return 0
  density = fffrpw_density(candidate) ## i64
  nonimproving = parent.has_nonimproving() ## i64
  if density >= parent.density()
    nonimproving = 1
  distance = fffrpw_distance(root, candidate) ## i64
  node = FFFRPWordNode.new(candidate, parent, ticket, kind, density, local_delta, barrier, states, proposals, nonimproving, distance, trace)
  archive.add(node, hash)
  candidates.push(node)
  1

# The literal ticket edge is a useful tunnel seed even when it is not the
# density-best state in that ticket's local closure.
-> fffrpw_direct(source, source_u, source_v, source_w, count, ticket, edge_limit) (FFBCScheme i64[] i64[] i64[] i64 i64 i64)
  info = i64[3]
  if fffrp_ticket(source_u, source_v, source_w, count, ticket, info) != 1
    return nil
  input_u = i64[2]
  input_v = i64[2]
  input_w = i64[2]
  input_u[0] = source_u[info[0]]
  input_v[0] = source_v[info[0]]
  input_w[0] = source_w[info[0]]
  input_u[1] = source_u[info[1]]
  input_v[1] = source_v[info[1]]
  input_w[1] = source_w[info[1]]
  endpoint_u = i64[2]
  endpoint_v = i64[2]
  endpoint_w = i64[2]
  if fffrp_flip_neighbor(input_u, input_v, input_w, 0, 2, 0, 1, info[2], endpoint_u, endpoint_v, endpoint_w) != 2
    return nil
  before = fffrp_density(input_u, input_v, input_w, 0, 2) ## i64
  after = fffrp_density(endpoint_u, endpoint_v, endpoint_w, 0, 2) ## i64
  if after - before > edge_limit
    return nil
  origins = i64[2]
  origins[0] = info[0]
  origins[1] = info[1]
  fffrp_sort_origins(origins, 2)
  fffrp_materialize_selected(source, origins, endpoint_u, endpoint_v, endpoint_w, 2)

-> fffrpw_expand(archive, root, parent, candidates, max_states, edge_limit, work) (FFFRPWordArchive FFBCScheme FFFRPWordNode Array i64 i64 i64[]) i64
  scheme = parent.scheme()
  rank = scheme.rank() ## i64
  source_u = i64[rank]
  source_v = i64[rank]
  source_w = i64[rank]
  if fffrp_scalar_scheme(scheme, source_u, source_v, source_w) != rank
    return 0
  tickets = fffrp_ticket_count(source_u, source_v, source_w, rank) ## i64
  if work.size() >= 4
    work[0] = work[0] + tickets
  endpoint_u = i64[5]
  endpoint_v = i64[5]
  endpoint_w = i64[5]
  origins = i64[5]
  stats = i64[32]
  added = 0 ## i64
  ticket = 0 ## i64
  while ticket < tickets
    gain = fffrp_autonomous_ticket(source_u, source_v, source_w, rank, ticket, 5, 5, max_states, edge_limit, endpoint_u, endpoint_v, endpoint_w, origins, stats) ## i64
    if work.size() >= 4
      work[1] = work[1] + stats[0]
      work[2] = work[2] + stats[1]
    if gain > 0
      candidate = fffrp_materialize_selected(scheme, origins, endpoint_u, endpoint_v, endpoint_w, stats[7])
      trace = "A" + ticket.to_s() + ":g" + gain.to_s() + ":d" + stats[6].to_s() + ":b" + stats[8].to_s() + ":s" + stats[0].to_s() + ":p" + stats[1].to_s()
      accepted = fffrpw_add(archive, candidates, root, parent, candidate, ticket, 1, 0 - gain, stats[8], stats[0], stats[1], trace) ## i64
      added += accepted
      if work.size() >= 4
        work[3] = work[3] + accepted

    direct = fffrpw_direct(scheme, source_u, source_v, source_w, rank, ticket, edge_limit)
    if direct != nil
      delta = fffrpw_density(direct) - parent.density() ## i64
      info = i64[3]
      fffrp_ticket(source_u, source_v, source_w, rank, ticket, info)
      trace = "D" + ticket.to_s() + ":a" + info[2].to_s() + ":delta" + delta.to_s()
      accepted = fffrpw_add(archive, candidates, root, parent, direct, ticket, 0, delta, delta, 1, 1, trace) ## i64
      added += accepted
      if work.size() >= 4
        work[3] = work[3] + accepted
    ticket += 1
  added

-> fffrpw_select(candidates, root, width) (Array FFBCScheme i64)
  selected = []
  if candidates.size() <= width
    i = 0 ## i64
    while i < candidates.size()
      selected.push(candidates[i])
      i += 1
    return selected
  used = i64[candidates.size()]

  # Half density-first.
  density_slots = width / 2 ## i64
  slot = 0 ## i64
  while slot < density_slots
    best = 0 - 1 ## i64
    i = 0 ## i64
    while i < candidates.size()
      if used[i] == 0
        if best < 0 || candidates[i].density() < candidates[best].density() || (candidates[i].density() == candidates[best].density() && candidates[i].root_distance() > candidates[best].root_distance())
          best = i
      i += 1
    if best >= 0
      used[best] = 1
      selected.push(candidates[best])
    slot += 1

  # One quarter explicitly preserves debt-bearing tunnel prefixes.
  tunnel_slots = width / 4 ## i64
  slot = 0
  while slot < tunnel_slots
    best = 0 - 1
    i = 0
    while i < candidates.size()
      if used[i] == 0 && candidates[i].has_nonimproving() == 1
        if best < 0 || candidates[i].density() < candidates[best].density() || (candidates[i].density() == candidates[best].density() && candidates[i].root_distance() > candidates[best].root_distance())
          best = i
      i += 1
    if best >= 0
      used[best] = 1
      selected.push(candidates[best])
    slot += 1

  # Fill by support novelty, then density.
  while selected.size() < width
    best = 0 - 1
    i = 0
    while i < candidates.size()
      if used[i] == 0
        if best < 0 || candidates[i].root_distance() > candidates[best].root_distance() || (candidates[i].root_distance() == candidates[best].root_distance() && candidates[i].density() < candidates[best].density())
          best = i
      i += 1
    if best < 0
      return selected
    used[best] = 1
    selected.push(candidates[best])
  selected

-> fffrpw_print_path(label, node) (String FFFRPWordNode) i64
  path = []
  cursor = node
  while cursor != nil && cursor.depth() > 0
    path.push(cursor)
    cursor = cursor.parent()
  text = ""
  i = path.size() - 1 ## i64
  while i >= 0
    if text != ""
      text = text + " | "
    text = text + path[i].trace()
    i -= 1
  << "FIXED_RANK_POCKET_WORD_PATH shape=" + label + " depth=" + node.depth().to_s() + " density=" + node.density().to_s() + " distance=" + node.root_distance().to_s() + " tunnel=" + node.has_nonimproving().to_s() + " path=" + text
  1

-> fffrpw_state(scheme, n, seed, steps) (FFBCScheme i64 i64 i64)
  if scheme == nil
    return nil
  capacity = ffw_default_capacity(n) ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if fffrp_scalar_scheme(scheme, us, vs, ws) != scheme.rank()
    return nil
  state = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(state, us, vs, ws, scheme.rank(), n, capacity, seed, 4, 1, steps, steps / 4) ## i64
  if loaded != scheme.rank() || ffw_verify_best_exact(state, n) != 1
    return nil
  state

-> fffrpw_continuation(label, root, endpoint, n, trials, steps) (String FFBCScheme FFBCScheme i64 i64 i64) i64
  if root == nil || endpoint == nil || fffrpw_equal(root, endpoint) == 1
    return 0
  root_wins = 0 ## i64
  endpoint_wins = 0 ## i64
  ties = 0 ## i64
  root_sum = 0 ## i64
  endpoint_sum = 0 ## i64
  root_min = 999999999 ## i64
  endpoint_min = 999999999 ## i64
  trial = 0 ## i64
  while trial < trials
    seed = 91001 + n * 1009 + trial * 104729 ## i64
    left = fffrpw_state(root, n, seed, steps)
    right = fffrpw_state(endpoint, n, seed, steps)
    fffrpw_expect("continuation states " + label, left != nil && right != nil)
    ffw_walk(left, steps)
    ffw_walk(right, steps)
    fffrpw_expect("continuation exact " + label, ffw_verify_best_exact(left, n) == 1 && ffw_verify_best_exact(right, n) == 1)
    lb = ffw_best_bits(left) ## i64
    rb = ffw_best_bits(right) ## i64
    root_sum += lb
    endpoint_sum += rb
    if lb < root_min
      root_min = lb
    if rb < endpoint_min
      endpoint_min = rb
    if ffw_best_rank(left) < ffw_best_rank(right) || (ffw_best_rank(left) == ffw_best_rank(right) && lb < rb)
      root_wins += 1
    elsif ffw_best_rank(right) < ffw_best_rank(left) || (ffw_best_rank(left) == ffw_best_rank(right) && rb < lb)
      endpoint_wins += 1
    else
      ties += 1
    trial += 1
  root_state = fffrpw_state(root, n, 99001 + n, steps)
  endpoint_state = fffrpw_state(endpoint, n, 99003 + n, steps)
  << "FIXED_RANK_POCKET_WORD_CONTINUATION shape=" + label + " trials=" + trials.to_s() + " steps=" + steps.to_s() + " wins-root/word/tie=" + root_wins.to_s() + "/" + endpoint_wins.to_s() + "/" + ties.to_s() + " min=" + root_min.to_s() + "/" + endpoint_min.to_s() + " avg=" + (root_sum / trials).to_s() + "/" + (endpoint_sum / trials).to_s() + " basin=" + ffbi_best_id(root_state).to_s() + "/" + ffbi_best_id(endpoint_state).to_s() + " signature=" + ffbp_structural_signature(root_state).to_s() + "/" + ffbp_structural_signature(endpoint_state).to_s() + " distance=" + ffbp_distance(root_state, endpoint_state).to_s()
  endpoint_wins - root_wins

-> fffrpw_run(label, path, n, capacity, width, compare_density) (String String i64 i64 i64 i64) i64
  root = ffbc_load_exact(path, n, n, n, capacity)
  fffrpw_expect("load " + label, root != nil && ffbc_verify_exact(root) == 1)
  root_density = fffrpw_density(root) ## i64
  archive = FFFRPWordArchive.new()
  root_node = FFFRPWordNode.new(root, nil, 0 - 1, 0 - 1, root_density, 0, 0, 0, 0, 0, 0, "root")
  archive.add(root_node, fffrpw_hash(root))
  beam = []
  beam.push(root_node)
  best = root_node
  best_chained = nil
  best_tunnel = nil
  work = i64[4]
  started = ccall("__w_clock_ms") ## i64
  rung = 1 ## i64
  while rung <= 3 && beam.size() > 0
    candidates = []
    i = 0 ## i64
    while i < beam.size()
      fffrpw_expand(archive, root, beam[i], candidates, 512, 12, work)
      i += 1
    i = 0
    rung_best = nil
    rung_tunnel = 0 ## i64
    while i < candidates.size()
      if rung_best == nil || candidates[i].density() < rung_best.density()
        rung_best = candidates[i]
      if candidates[i].density() < best.density()
        best = candidates[i]
      if candidates[i].depth() >= 2
        if best_chained == nil || candidates[i].density() < best_chained.density()
          best_chained = candidates[i]
        if candidates[i].has_nonimproving() == 1 && candidates[i].density() < root_density
          rung_tunnel += 1
          if best_tunnel == nil || candidates[i].density() < best_tunnel.density()
            best_tunnel = candidates[i]
      i += 1
    if rung_best != nil
      << "FIXED_RANK_POCKET_WORD_RUNG shape=" + label + " rung=" + rung.to_s() + " parents=" + beam.size().to_s() + " unique=" + candidates.size().to_s() + " archive=" + archive.size().to_s() + " best=" + rung_best.density().to_s() + " distance=" + rung_best.root_distance().to_s() + " tunnel-wins=" + rung_tunnel.to_s()
    beam = fffrpw_select(candidates, root, width)
    rung += 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  << "FIXED_RANK_POCKET_WORD_SUMMARY shape=" + label + " root=" + root_density.to_s() + " best=" + best.density().to_s() + " gain=" + (root_density - best.density()).to_s() + " depth=" + best.depth().to_s() + " archive=" + archive.size().to_s() + " tickets=" + work[0].to_s() + " states=" + work[1].to_s() + " proposals=" + work[2].to_s() + " accepted=" + work[3].to_s() + " elapsed-ms=" + elapsed.to_s()
  fffrpw_print_path(label, best)
  if best_chained != nil
    fffrpw_print_path(label + "-best-chained", best_chained)
  if best_tunnel != nil
    fffrpw_print_path(label + "-best-tunnel", best_tunnel)

  # Preserve the strongest exact chained door even when it is a density tie;
  # this makes negative continuation evidence reproducible.
  saved = best_chained
  if saved == nil
    saved = best
  if saved != nil && saved.depth() >= 2
    output = "/tmp/matmul_" + label + "_rank" + saved.scheme().rank().to_s() + "_d" + saved.density().to_s() + "_fixed_rank_pocket_word_gf2.txt"
    fffrpw_expect("write " + label, ffbc_write(output, saved.scheme()) == saved.scheme().rank())
    reloaded = ffbc_load_exact(output, n, n, n, capacity)
    fffrpw_expect("reload " + label, reloaded != nil && fffrpw_equal(reloaded, saved.scheme()) == 1)
    << "FIXED_RANK_POCKET_WORD_CERT shape=" + label + " output=" + output
    fffrpw_continuation(label, root, saved.scheme(), n, 6, 250000)

  if compare_density > 0
    if best.density() < compare_density
      << "FIXED_RANK_POCKET_WORD_BEATS_CONTROL shape=" + label + " control=" + compare_density.to_s() + " best=" + best.density().to_s()
      return 1
    << "FIXED_RANK_POCKET_WORD_NO_BEAT shape=" + label + " control=" + compare_density.to_s() + " best=" + best.density().to_s()
  0

root = "bits/tungsten-metaflip/lib/metaflip/seeds/gf2/"
beats = 0 ## i64
wide = 0 ## i64
av = argv()
if av.size() > 1 || (av.size() == 1 && av[0] != "wide")
  << "usage: fixed-rank-pocket-word [wide]"
  exit(1)
if av.size() == 1
  wide = 1
c013_width = 24 ## i64
control_width = 12 ## i64
leader_width = 16 ## i64
if wide == 1
  c013_width = 64
  control_width = 24
  leader_width = 32
# The C013 rung gets a wider beam because it is the one demonstrated source
# of barrier-crossing autonomous tickets.  The other leaders are controls.
beats += fffrpw_run("7x7-c013", root + "matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt", 7, 260, c013_width, 3546)
beats += fffrpw_run("7x7-c013-child", root + "matmul_7x7_rank247_d3546_autonomous_flip_pocket_gf2.txt", 7, 260, c013_width, 3546)
beats += fffrpw_run("3x3", root + "matmul_3x3_rank23_d139_gf2.txt", 3, 32, control_width, 0)
beats += fffrpw_run("4x4", root + "matmul_4x4_rank47_d450_gf2.txt", 4, 64, control_width, 0)
beats += fffrpw_run("5x5", root + "matmul_5x5_rank93_d967_four_split_control_gf2.txt", 5, 112, control_width, 0)
beats += fffrpw_run("6x6", root + "matmul_6x6_rank153_d1860_global_isotropy_gf2.txt", 6, 176, control_width, 0)
beats += fffrpw_run("7x7-leader", root + "matmul_7x7_rank247_d3094_three_flip_density_gf2.txt", 7, 260, leader_width, 0)
<< "FIXED_RANK_POCKET_WORD_FINAL controls-beaten=" + beats.to_s()
