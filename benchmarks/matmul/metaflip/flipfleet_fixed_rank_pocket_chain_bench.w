# Extend productive autonomous-ticket words to convergence.  Two policies are
# audited independently from each root:
#
#   ordinal1: replay current ticket ordinal 1 at every exact endpoint;
#   greedy:   enumerate every current ticket and adopt the largest strict
#             density gain (lowest ordinal wins a tie).
#
# Both stop on no strict gain, a canonical cycle, or 32 tickets.  Every local
# search uses k<=5, depth<=5, <=512 states, and edge debt<=12; every adopted
# whole scheme is independently exact-gated.

use flipfleet_fixed_rank_pocket
use flipfleet_bank_policy

-> fffrpc_expect(label, condition) (String bool) i64
  if !condition
    << "FIXED_RANK_POCKET_CHAIN_FAIL " + label
    exit(1)
  1

-> fffrpc_density(scheme) (FFBCScheme) i64
  total = 0 ## i64
  term = i64[3]
  i = 0 ## i64
  while i < scheme.rank()
    if fffrp_scalar_term(scheme, i, term) != 1
      return 0 - 1
    total += fffrp_popcount(term[0]) + fffrp_popcount(term[1]) + fffrp_popcount(term[2])
    i += 1
  total

-> fffrpc_equal(left, right) (FFBCScheme FFBCScheme) i64
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

-> fffrpc_distance(left, right) (FFBCScheme FFBCScheme) i64
  common = 0 ## i64
  term = i64[3]
  i = 0 ## i64
  while i < left.rank()
    if fffrp_scalar_term(left, i, term) != 1
      return 0 - 1
    common += fffrp_scheme_has_scalar(right, term[0], term[1], term[2])
    i += 1
  left.rank() + right.rank() - common - common

-> fffrpc_seen(seen, candidate) (Array FFBCScheme) i64
  i = 0 ## i64
  while i < seen.size()
    if fffrpc_equal(seen[i], candidate) == 1
      return 1
    i += 1
  0

-> fffrpc_state(scheme, seed) (FFBCScheme i64)
  capacity = ffw_default_capacity(7) ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if scheme == nil || fffrp_scalar_scheme(scheme, us, vs, ws) != scheme.rank()
    return nil
  state = i64[ffw_state_size(capacity)]
  if ffw_init_terms_cap(state, us, vs, ws, scheme.rank(), 7, capacity, seed, 4, 1, 25000000, 6250000) != scheme.rank()
    return nil
  if ffw_verify_best_exact(state, 7) != 1
    return nil
  state

# Pressure is the extra work-mode gate absent from a density-only pocket
# closure.  For a depth-one two-term ticket, measure the exact old/new values
# on their respective whole-scheme states.  out=[old,new,gap,partner-count].
-> fffrpc_pressure(source, candidate, ticket, local_depth, pocket_terms, out) (FFBCScheme FFBCScheme i64 i64 i64 i64[]) i64
  if out.size() < 4
    return 0
  i = 0 ## i64
  while i < 4
    out[i] = 0 - 1
    i += 1
  if local_depth != 1 || pocket_terms != 2
    return 0
  rank = source.rank() ## i64
  us = i64[rank]
  vs = i64[rank]
  ws = i64[rank]
  if fffrp_scalar_scheme(source, us, vs, ws) != rank
    return 0
  info = i64[3]
  if fffrp_ticket(us, vs, ws, rank, ticket, info) != 1
    return 0
  key = us[info[0]] ## i64
  if info[2] == 1
    key = vs[info[0]]
  if info[2] == 2
    key = ws[info[0]]
  partners = 0 ## i64
  slot = 0 ## i64
  while slot < rank
    value = us[slot] ## i64
    if info[2] == 1
      value = vs[slot]
    if info[2] == 2
      value = ws[slot]
    if slot != info[0] && value == key
      partners += 1
    slot += 1

  source_pu = i64[5]
  source_pv = i64[5]
  source_pw = i64[5]
  target_pu = i64[5]
  target_pv = i64[5]
  target_pw = i64[5]
  count = fffrp_extract_pocket(source, candidate, source_pu, source_pv, source_pw, target_pu, target_pv, target_pw) ## i64
  if count != 2
    return 0
  source_state = fffrpc_state(source, 120001)
  target_state = fffrpc_state(candidate, 120003)
  if source_state == nil || target_state == nil
    return 0
  old_pressure = 0 ## i64
  new_pressure = 0 ## i64
  i = 0
  while i < 2
    old_pressure += ffw_pressure(source_state, source_pu[i], source_pv[i], source_pw[i])
    new_pressure += ffw_pressure(target_state, target_pu[i], target_pv[i], target_pw[i])
    i += 1
  out[0] = old_pressure
  out[1] = new_pressure
  out[2] = old_pressure - new_pressure
  out[3] = partners
  1

-> fffrpc_candidate(source, ticket, stats_out) (FFBCScheme i64 i64[])
  rank = source.rank() ## i64
  us = i64[rank]
  vs = i64[rank]
  ws = i64[rank]
  if fffrp_scalar_scheme(source, us, vs, ws) != rank
    return nil
  endpoint_u = i64[5]
  endpoint_v = i64[5]
  endpoint_w = i64[5]
  origins = i64[5]
  local_stats = i64[32]
  gain = fffrp_autonomous_ticket(us, vs, ws, rank, ticket, 5, 5, 512, 12, endpoint_u, endpoint_v, endpoint_w, origins, local_stats) ## i64
  i = 0 ## i64
  while i < stats_out.size() && i < local_stats.size()
    stats_out[i] = local_stats[i]
    i += 1
  if gain <= 0
    return nil
  candidate = fffrp_materialize_selected(source, origins, endpoint_u, endpoint_v, endpoint_w, local_stats[7])
  if candidate == nil || ffbc_verify_exact(candidate) != 1 || fffrpc_density(source) - fffrpc_density(candidate) != gain
    return nil
  candidate

-> fffrpc_run(label, root, policy, max_steps) (String FFBCScheme i64 i64)
  current = root
  seen = []
  seen.push(root)
  root_density = fffrpc_density(root) ## i64
  total_tickets = 0 ## i64
  total_states = 0 ## i64
  total_proposals = 0 ## i64
  sequence = root_density.to_s()
  stop = "limit"
  step = 0 ## i64
  while step < max_steps
    rank = current.rank() ## i64
    us = i64[rank]
    vs = i64[rank]
    ws = i64[rank]
    fffrpc_expect("scalar " + label, fffrp_scalar_scheme(current, us, vs, ws) == rank)
    tickets = fffrp_ticket_count(us, vs, ws, rank) ## i64
    chosen = nil
    chosen_ticket = 0 - 1 ## i64
    chosen_gain = 0 ## i64
    chosen_stats = i64[32]
    scanned_states = 0 ## i64
    scanned_proposals = 0 ## i64
    first = 0 ## i64
    last = tickets ## i64
    if policy == 0
      first = 1
      last = 2
      if tickets <= 1
        last = first
    ticket = first ## i64
    while ticket < last
      stats = i64[32]
      candidate = fffrpc_candidate(current, ticket, stats)
      total_tickets += 1
      scanned_states += stats[0]
      scanned_proposals += stats[1]
      gain = stats[5] ## i64
      if candidate != nil && gain > chosen_gain
        chosen = candidate
        chosen_ticket = ticket
        chosen_gain = gain
        i = 0 ## i64
        while i < 32
          chosen_stats[i] = stats[i]
          i += 1
      ticket += 1
    total_states += scanned_states
    total_proposals += scanned_proposals
    if chosen == nil || chosen_gain <= 0
      stop = "no-strict-gain"
      step = max_steps
    elsif fffrpc_seen(seen, chosen) == 1
      stop = "cycle"
      step = max_steps
    else
      pressure = i64[4]
      fffrpc_pressure(current, chosen, chosen_ticket, chosen_stats[6], chosen_stats[7], pressure)
      current = chosen
      seen.push(current)
      density = fffrpc_density(current) ## i64
      sequence = sequence + "->" + density.to_s()
      << "FIXED_RANK_POCKET_CHAIN_STEP shape=" + label + " policy=" + policy.to_s() + " step=" + (seen.size() - 1).to_s() + " density=" + density.to_s() + " ticket=" + chosen_ticket.to_s() + "/" + tickets.to_s() + " gain=" + chosen_gain.to_s() + " local-depth=" + chosen_stats[6].to_s() + " barrier=" + chosen_stats[8].to_s() + " local-states=" + chosen_stats[0].to_s() + " scan-states=" + scanned_states.to_s() + " scan-proposals=" + scanned_proposals.to_s() + " distance=" + fffrpc_distance(root, current).to_s() + " pressure-old/new/gap=" + pressure[0].to_s() + "/" + pressure[1].to_s() + "/" + pressure[2].to_s() + " partners=" + pressure[3].to_s()
      step += 1
  actual_steps = seen.size() - 1 ## i64
  if actual_steps >= max_steps
    stop = "limit"
  state = fffrpc_state(current, 130001 + policy)
  << "FIXED_RANK_POCKET_CHAIN_SUMMARY shape=" + label + " policy=" + policy.to_s() + " steps=" + actual_steps.to_s() + " stop=" + stop + " root/best=" + root_density.to_s() + "/" + fffrpc_density(current).to_s() + " gain=" + (root_density - fffrpc_density(current)).to_s() + " tickets=" + total_tickets.to_s() + " states=" + total_states.to_s() + " proposals=" + total_proposals.to_s() + " distance=" + fffrpc_distance(root, current).to_s() + " basin=" + ffbi_best_id(state).to_s() + " signature=" + ffbp_structural_signature(state).to_s() + " sequence=" + sequence
  policy_name = "ordinal1"
  if policy == 1
    policy_name = "greedy"
  output = "/tmp/matmul_7x7_rank247_d" + fffrpc_density(current).to_s() + "_fixed_rank_pocket_chain_" + label + "_" + policy_name + "_gf2.txt"
  fffrpc_expect("write " + label, ffbc_write(output, current) == current.rank())
  reloaded = ffbc_load_exact(output, 7, 7, 7, 260)
  fffrpc_expect("reload " + label, reloaded != nil && fffrpc_equal(reloaded, current) == 1)
  << "FIXED_RANK_POCKET_CHAIN_CERT shape=" + label + " policy=" + policy.to_s() + " output=" + output
  current

root = "bits/tungsten-metaflip/lib/metaflip/seeds/gf2/"
c013 = ffbc_load_exact(root + "matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt", 7, 7, 7, 260)
child = ffbc_load_exact(root + "matmul_7x7_rank247_d3546_autonomous_flip_pocket_gf2.txt", 7, 7, 7, 260)
fffrpc_expect("load roots", c013 != nil && child != nil)
c013_ordinal = fffrpc_run("c013", c013, 0, 32)
c013_greedy = fffrpc_run("c013", c013, 1, 32)
child_ordinal = fffrpc_run("c013-child", child, 0, 32)
child_greedy = fffrpc_run("c013-child", child, 1, 32)
best = c013_ordinal
if fffrpc_density(c013_greedy) < fffrpc_density(best)
  best = c013_greedy
if fffrpc_density(child_ordinal) < fffrpc_density(best)
  best = child_ordinal
if fffrpc_density(child_greedy) < fffrpc_density(best)
  best = child_greedy
<< "FIXED_RANK_POCKET_CHAIN_FINAL density=" + fffrpc_density(best).to_s()
