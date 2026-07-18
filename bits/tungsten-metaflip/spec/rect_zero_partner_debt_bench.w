# Bounded matched continuation screen for the 3x4x6 zero-partner plateau.
# This is a decision benchmark, not part of the default regression runtime.
# Optional argv: trials_per_door (1..64), focused_moves (1..10,000,000).

use ../lib/metaflip/rect

-> ffrzpb_load(path, capacity, seed) (String i64 i64)
  state = i64[ffr_state_size(capacity)]
  rank = ffr_load_scheme_cap(state, path, 3, 4, 6, capacity, seed, 4, 4, 10000, 2500) ## i64
  if rank != 54 || ffr_verify_best_exact(state,3,4,6) != 1
    return nil
  state

-> ffrzpb_current_digest(st, capacity) (i64[] i64) i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_current(st, us, vs, ws) ## i64
  digest = rank * 2862933555777941757 ## i64
  i = 0 ## i64
  while i < rank
    digest = digest ^ ffw_term_zobrist(us[i],vs[i],ws[i])
    i += 1
  digest

-> ffrzpb_add_digest(digests, offset, count, digest) (i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if digests[offset + i] == digest
      return count
    i += 1
  digests[offset + count] = digest
  count + 1

args = argv()
trials = 8 ## i64
moves = 100000 ## i64
if args.size() > 0
  trials = args[0].to_i()
if args.size() > 1
  moves = args[1].to_i()
if trials < 1
  trials = 1
if trials > 64
  trials = 64
if moves < 1
  moves = 1
if moves > 10000000
  moves = 10000000

root = __DIR__ + "/../lib/metaflip/seeds/gf2/" ## String
paths = [
  root + "matmul_3x4x6_rank54_d488_gl_frontier_gf2.txt",
  root + "matmul_3x4x6_rank54_catalog_gf2.txt"
]
names = ["control", "raw-split", "braid+1", "braid+2"]
capacity = ffr_default_capacity(3,4,6) ## i64
mode_count = 4 ## i64
stat_width = 9 ## i64
stats = i64[mode_count * stat_width]
digest_stride = paths.size() * trials ## i64
digests = i64[mode_count * digest_stride]

door = 0 ## i64
while door < paths.size()
  trial = 0 ## i64
  while trial < trials
    mode = 0 ## i64
    while mode < mode_count
      stat = mode * stat_width ## i64
      wall_start = ccall("__w_clock_ms") ## i64
      load_seed = 610001 + door * 1000003 + trial * 104729 ## i64
      state = ffrzpb_load(paths[door], capacity, load_seed)
      setup_ok = 1 ## i64
      source_bits = 0 ## i64
      if state == nil
        setup_ok = 0
      if setup_ok == 1
        source_bits = ffr_best_bits(state)
        if mode == 1
          split_result = ffr_try_split(state) ## i64
          if split_result < 1 || ffr_current_rank(state) != 55 || ffr_best_rank(state) != 54 || ffr_verify_current_exact(state,3,4,6) != 1
            setup_ok = 0
        if mode == 2
          if ffr_seed_braided_debt(state,1,710003 + door * 100003 + trial * 1009) != 55
            setup_ok = 0
        if mode == 3
          if ffr_seed_braided_debt(state,2,810007 + door * 100019 + trial * 1013) != 56
            setup_ok = 0
      if setup_ok == 0
        stats[stat + 8] += 1
      if setup_ok == 1
        # Setup families consume different amounts of entropy. Re-key every
        # state to the same continuation stream for a matched proposal audit.
        continuation_seed = 910009 + door * 1000033 + trial * 104759 ## i64
        z = ffw_seed_rng(state, continuation_seed) ## i64
        misses_before = ffw_partner_misses(state) ## i64
        accepted_before = ffw_accepted(state) ## i64
        z = ffr_work(state, moves)
        stats[stat] += 1
        stats[stat + 3] += ffw_partner_misses(state) - misses_before
        stats[stat + 4] += ffw_accepted(state) - accepted_before
        exact = 1 ## i64
        if ffr_verify_current_exact(state,3,4,6) != 1 || ffr_verify_best_exact(state,3,4,6) != 1
          exact = 0
          stats[stat + 6] += 1
        if exact == 1
          best_rank = ffr_best_rank(state) ## i64
          best_bits = ffr_best_bits(state) ## i64
          if best_rank < 54
            stats[stat + 1] += 1
          if best_rank == 54 && best_bits < source_bits
            stats[stat + 2] += 1
          digest = ffrzpb_current_digest(state,capacity) ## i64
          offset = mode * digest_stride ## i64
          stats[stat + 5] = ffrzpb_add_digest(digests,offset,stats[stat + 5],digest)
      stats[stat + 7] += ccall("__w_clock_ms") - wall_start
      mode += 1
    trial += 1
  door += 1

mode = 0
while mode < mode_count
  stat = mode * stat_width ## i64
  << "RECT_ZERO_PARTNER_BENCH mode=" + names[mode] + " doors=" + paths.size().to_s() + " trials=" + trials.to_s() + " moves=" + moves.to_s() + " runs=" + stats[stat].to_s() + " rank_wins=" + stats[stat+1].to_s() + " density_wins=" + stats[stat+2].to_s() + " partner_misses=" + stats[stat+3].to_s() + " accepted=" + stats[stat+4].to_s() + " unique_endpoints=" + stats[stat+5].to_s() + " exact_failures=" + stats[stat+6].to_s() + " setup_failures=" + stats[stat+8].to_s() + " wall_ms=" + stats[stat+7].to_s()
  mode += 1
