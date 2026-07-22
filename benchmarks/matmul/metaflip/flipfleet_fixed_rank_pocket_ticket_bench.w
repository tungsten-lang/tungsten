use flipfleet_fixed_rank_pocket

-> fffrptb_run(label, path, n, m, p, capacity, max_states) (String String i64 i64 i64 i64 i64) i64
  scheme = ffbc_load_exact(path, n, m, p, capacity)
  if scheme == nil
    << "FIXED_RANK_POCKET_TICKETS_FAIL load " + label
    return 0 - 1
  rank = scheme.rank() ## i64
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  if fffrp_scalar_scheme(scheme, source_u, source_v, source_w) != rank
    << "FIXED_RANK_POCKET_TICKETS_FAIL scalar " + label
    return 0 - 1
  tickets = fffrp_ticket_count(source_u, source_v, source_w, rank) ## i64
  endpoint_u = i64[8]
  endpoint_v = i64[8]
  endpoint_w = i64[8]
  origins = i64[8]
  stats = i64[32]
  gated_u = i64[8]
  gated_v = i64[8]
  gated_w = i64[8]
  gated_origins = i64[8]
  gated_stats = i64[32]

  productive = 0 ## i64
  gated_productive = 0 ## i64
  tunnel_advantage = 0 ## i64
  exact = 0 ## i64
  best_gain = 0 ## i64
  best_gated = 0 ## i64
  max_barrier = 0 ## i64
  states = 0 ## i64
  proposals = 0 ## i64
  started = ccall("__w_clock_ms") ## i64
  ticket = 0 ## i64
  while ticket < tickets
    gain = fffrp_autonomous_ticket(source_u, source_v, source_w, rank, ticket, 5, 5, max_states, -1, endpoint_u, endpoint_v, endpoint_w, origins, stats) ## i64
    states += stats[0]
    proposals += stats[1]
    if gain > 0
      productive += 1
      candidate = fffrp_materialize_selected(scheme, origins, endpoint_u, endpoint_v, endpoint_w, stats[7])
      if candidate != nil
        exact += 1
      if gain > best_gain
        best_gain = gain
      if stats[8] > max_barrier
        max_barrier = stats[8]
    gated_gain = fffrp_autonomous_ticket(source_u, source_v, source_w, rank, ticket, 5, 5, max_states, 4, gated_u, gated_v, gated_w, gated_origins, gated_stats) ## i64
    if gated_gain > 0
      gated_productive += 1
    if gated_gain > best_gated
      best_gated = gated_gain
    if gain > gated_gain
      tunnel_advantage += 1
    ticket += 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  if elapsed < 1
    elapsed = 1
  << "FIXED_RANK_POCKET_TICKETS shape=" + label + " rank=" + rank.to_s() + " tickets=" + tickets.to_s() + " productive=" + productive.to_s() + " gated=" + gated_productive.to_s() + " tunnel-advantage=" + tunnel_advantage.to_s() + " exact=" + exact.to_s() + " best-gain=" + best_gain.to_s() + "/" + best_gated.to_s() + " max-barrier=" + max_barrier.to_s() + " states=" + states.to_s() + " proposals=" + proposals.to_s() + " elapsed-ms=" + elapsed.to_s() + " tickets/s=" + (tickets * 1000 / elapsed).to_s() + " proposals/s=" + (proposals * 1000 / elapsed).to_s()
  if exact != productive
    return 0 - 1
  tunnel_advantage

root = "bits/tungsten-metaflip/lib/metaflip/seeds/gf2/"
total_tunnels = 0 ## i64
total_tunnels += fffrptb_run("2x2", root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16, 256)
total_tunnels += fffrptb_run("3x3", root + "matmul_3x3_rank23_d139_gf2.txt", 3, 3, 3, 32, 256)
total_tunnels += fffrptb_run("4x4", root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 64, 256)
total_tunnels += fffrptb_run("5x5", root + "matmul_5x5_rank93_d967_four_split_control_gf2.txt", 5, 5, 5, 112, 512)
total_tunnels += fffrptb_run("6x6", root + "matmul_6x6_rank153_d1860_global_isotropy_gf2.txt", 6, 6, 6, 176, 512)
total_tunnels += fffrptb_run("7x7-c013", root + "matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt", 7, 7, 7, 260, 512)
total_tunnels += fffrptb_run("7x7-leader", root + "matmul_7x7_rank247_d3094_three_flip_density_gf2.txt", 7, 7, 7, 260, 512)
total_tunnels += fffrptb_run("2x2x5-d92", root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt", 2, 2, 5, 24, 512)
if total_tunnels < 1
  << "FIXED_RANK_POCKET_TICKETS_FAIL no tunnel advantage"
  exit(1)
<< "FIXED_RANK_POCKET_TICKETS_SUMMARY tunnel-advantage=" + total_tunnels.to_s()
