# Matched decision benchmark for injecting exact braided rank debt at the
# focused-work/adaptive boundary. This is intentionally not a regression: it
# screens a scheduling choice on exact record walls with bounded move budgets.
#
# Optional argv: trials_per_seed (1..64), total_moves (10..100,000,000),
# exact seed index (-1 for all; the two 3x4x6 doors are 0 and 1).

use ../lib/metaflip/rect

-> ffrpf_load(path, n, m, p, rank, seed) (String i64 i64 i64 i64 i64)
  capacity = ffr_default_capacity(n,m,p) ## i64
  state = i64[ffr_state_size(capacity)]
  loaded = ffr_load_scheme_cap(state,path,n,m,p,capacity,seed,4,4,10000,2500) ## i64
  if loaded != rank || ffr_verify_best_exact(state,n,m,p) != 1 || ffr_verify_current_exact(state,n,m,p) != 1
    return nil
  state

-> ffrpf_current_digest(st, capacity) (i64[] i64) i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_current(st,us,vs,ws) ## i64
  digest = rank * 2862933555777941757 ## i64
  i = 0 ## i64
  while i < rank
    digest = digest ^ ffw_term_zobrist(us[i],vs[i],ws[i])
    i += 1
  digest

-> ffrpf_best_digest(st, capacity) (i64[] i64) i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_best(st,us,vs,ws) ## i64
  digest = rank * 3202034522624059733 ## i64
  i = 0 ## i64
  while i < rank
    digest = digest ^ ffw_term_zobrist(us[i],vs[i],ws[i])
    i += 1
  digest

-> ffrpf_add_digest(digests, offset, count, digest) (i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if digests[offset+i] == digest
      return count
    i += 1
  digests[offset+count] = digest
  count + 1

# The proposed gate: do not manufacture debt from a live shoulder, an
# inexact state, or a wall that already has an ordinary pair-flip edge.
-> ffrpf_eligible(st, n, m, p) (i64[] i64 i64 i64) i64
  if ffr_current_rank(st) != ffr_best_rank(st)
    return 0
  if ffr_partnerable_incidences(st) != 0
    return 0
  if ffr_verify_best_exact(st,n,m,p) != 1 || ffr_verify_current_exact(st,n,m,p) != 1
    return 0
  1

-> ffrpf_inject(st, n, m, p, depth, nonce) (i64[] i64 i64 i64 i64 i64) i64
  if ffrpf_eligible(st,n,m,p) != 1
    return 0
  before = ffr_best_rank(st) ## i64
  rank = ffr_seed_braided_debt(st,depth,nonce) ## i64
  if rank == before + depth && ffr_verify_current_exact(st,n,m,p) == 1
    return depth
  0

args = argv()
trials = 8 ## i64
total_moves = 1000000 ## i64
seed_filter = 0 - 1 ## i64
if args.size() > 0
  trials = args[0].to_i()
if args.size() > 1
  total_moves = args[1].to_i()
if args.size() > 2
  seed_filter = args[2].to_i()
if trials < 1
  trials = 1
if trials > 64
  trials = 64
if total_moves < 10
  total_moves = 10
if total_moves > 100000000
  total_moves = 100000000

root = __DIR__ + "/../lib/metaflip/seeds/gf2/" ## String
paths = [
  root + "matmul_3x4x6_rank54_d488_gl_frontier_gf2.txt",
  root + "matmul_3x4x6_rank54_catalog_gf2.txt",
  root + "matmul_3x3x4_rank29_gf2.txt",
  root + "matmul_3x4x4_rank38_d280_live_density_leader_gf2.txt",
  root + "matmul_3x4x4_rank38_gf2.txt",
  root + "matmul_2x3x5_rank25_d160_fleet_gf2.txt",
  root + "matmul_2x3x5_rank25_d170_fleet_gf2.txt",
  root + "matmul_2x3x5_rank25_d210_fleet_gf2.txt",
  root + "matmul_2x3x5_rank25_d278_fleet_gf2.txt",
  root + "matmul_3x4x5_rank47_d386_gf2.txt",
  root + "matmul_4x5x5_rank76_gf2.txt",
  root + "matmul_5x6x7_rank150_catalog_gf2.txt",
  root + "matmul_5x6x7_rank150_d1875_gl_frontier_gf2.txt"
]
labels = [
  "346-frontier", "346-catalog", "334-r29", "344-live", "344-catalog",
  "235-d160", "235-d170", "235-d210", "235-d278", "345-r47",
  "455-r76", "567-catalog", "567-frontier"
]
ns = [3,3,3,3,3,2,2,2,2,3,4,5,5]
ms = [4,4,3,4,4,3,3,3,3,4,5,6,6]
ps = [6,6,4,4,4,5,5,5,5,5,5,7,7]
ranks = [54,54,29,38,38,25,25,25,25,47,76,150,150]

# control: no debt; init+1/+2: current production residents; post+1/+2:
# defer the debt until after focused work; rearm12/rearm21: start as production
# does, then inject the other depth only if focused work returned to a zero-edge
# exact best/current wall.
names = ["control", "init+1", "init+2", "post+1", "post+2", "rearm12", "rearm21"]
mode_count = names.size() ## i64
stat_width = 16 ## i64
phase = i64[3]
z = ffrp_campaign_budgets(total_moves,phase) ## i64

seed_index = 0 ## i64
while seed_index < paths.size()
  n = ns[seed_index] ## i64
  m = ms[seed_index] ## i64
  p = ps[seed_index] ## i64
  source_rank = ranks[seed_index] ## i64
  capacity = ffr_default_capacity(n,m,p) ## i64
  profile = ffrpf_load(paths[seed_index],n,m,p,source_rank,510001+seed_index*1009)
  if profile == nil
    << "RECT_POST_FOCUS_PROFILE seed=" + labels[seed_index] + " load=FAIL"
  if profile != nil
    incidence = ffr_partnerable_incidences(profile) ## i64
    # In addition to truly edge-free doors, observe partner-starved live leaf
    # seeds (at most one partnerable incidence per six possible incidences).
    # The injection itself remains strictly zero-edge gated; these rows answer
    # whether focused work naturally reaches such a wall.
    benchmark_candidate = 0 ## i64
    if incidence * 6 <= source_rank * 3
      benchmark_candidate = 1
    << "RECT_POST_FOCUS_PROFILE seed=" + labels[seed_index] + " shape=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " rank=" + source_rank.to_s() + " bits=" + ffr_best_bits(profile).to_s() + " partnerable=" + incidence.to_s() + "/" + (source_rank*3).to_s() + " exact=1 benchmark=" + benchmark_candidate.to_s()
    if benchmark_candidate == 1 && (seed_filter < 0 || seed_filter == seed_index)
      stats = i64[mode_count*stat_width]
      current_digests = i64[mode_count*trials]
      best_digests = i64[mode_count*trials]
      trial = 0 ## i64
      while trial < trials
        mode = 0 ## i64
        while mode < mode_count
          stat = mode*stat_width ## i64
          wall_start = ccall("__w_clock_ms") ## i64
          state = ffrpf_load(paths[seed_index],n,m,p,source_rank,610001+seed_index*1000003+trial*104729)
          setup_ok = 1 ## i64
          if state == nil
            setup_ok = 0
          source_bits = 0 ## i64
          debt_nonce = 710003 + seed_index*100003 + trial*1009 ## i64
          if setup_ok == 1
            source_bits = ffr_best_bits(state)
            # Init shoulders are the current scheduling policy and the first
            # half of both conditional-rearm modes.
            if incidence == 0 && (mode == 1 || mode == 5)
              if ffr_seed_braided_debt(state,1,debt_nonce) != source_rank+1
                setup_ok = 0
            if incidence == 0 && (mode == 2 || mode == 6)
              if ffr_seed_braided_debt(state,2,debt_nonce) != source_rank+2
                setup_ok = 0
          if setup_ok == 0
            stats[stat+13] += 1
          if setup_ok == 1
            stats[stat] += 1
            # Re-key each phase so setup timing/attempt count cannot create an
            # accidental entropy advantage for one schedule.
            focus_seed = 810007 + seed_index*1000033 + trial*104759 ## i64
            q = ffw_seed_rng(state,focus_seed) ## i64
            misses_before = ffw_partner_misses(state) ## i64
            accepted_before = ffw_accepted(state) ## i64
            q = ffr_work(state,phase[0])
            stats[stat+5] += ffw_partner_misses(state)-misses_before
            stats[stat+6] += ffw_accepted(state)-accepted_before

            eligible = ffrpf_eligible(state,n,m,p) ## i64
            stats[stat+7] += eligible
            inject_depth = 0 ## i64
            if mode == 3
              inject_depth = 1
            if mode == 4
              inject_depth = 2
            if mode == 5
              inject_depth = 2
            if mode == 6
              inject_depth = 1
            injected = 0 ## i64
            if inject_depth > 0
              injected = ffrpf_inject(state,n,m,p,inject_depth,debt_nonce+32452843)
            if injected > 0
              stats[stat+8] += 1
              stats[stat+9] += injected

            adaptive_seed = 910009 + seed_index*1000037 + trial*104761 ## i64
            q = ffw_seed_rng(state,adaptive_seed)
            misses_before = ffw_partner_misses(state)
            accepted_before = ffw_accepted(state)
            q = ffr_walk(state,phase[1])
            stats[stat+5] += ffw_partner_misses(state)-misses_before
            stats[stat+6] += ffw_accepted(state)-accepted_before

            wander_seed = 1010017 + seed_index*1000039 + trial*104773 ## i64
            q = ffw_seed_rng(state,wander_seed)
            misses_before = ffw_partner_misses(state)
            accepted_before = ffw_accepted(state)
            q = ffr_wander(state,phase[2])
            stats[stat+5] += ffw_partner_misses(state)-misses_before
            stats[stat+6] += ffw_accepted(state)-accepted_before

            exact = 1 ## i64
            if ffr_verify_current_exact(state,n,m,p) != 1 || ffr_verify_best_exact(state,n,m,p) != 1
              exact = 0
              stats[stat+12] += 1
            if exact == 1
              best_rank = ffr_best_rank(state) ## i64
              best_bits = ffr_best_bits(state) ## i64
              if best_rank < source_rank
                stats[stat+1] += 1
              if best_rank == source_rank && best_bits < source_bits
                stats[stat+2] += 1
              coff = mode*trials ## i64
              stats[stat+3] = ffrpf_add_digest(current_digests,coff,stats[stat+3],ffrpf_current_digest(state,capacity))
              stats[stat+4] = ffrpf_add_digest(best_digests,coff,stats[stat+4],ffrpf_best_digest(state,capacity))
              debt = ffr_current_rank(state)-ffr_best_rank(state) ## i64
              if debt == 0
                stats[stat+10] += 1
              if debt > 0
                stats[stat+11] += 1
          stats[stat+14] += ccall("__w_clock_ms")-wall_start
          mode += 1
        trial += 1
      mode = 0
      while mode < mode_count
        stat = mode*stat_width
        << "RECT_POST_FOCUS_BENCH seed=" + labels[seed_index] + " mode=" + names[mode] + " trials=" + trials.to_s() + " total_moves=" + total_moves.to_s() + " phases=" + phase[0].to_s() + "/" + phase[1].to_s() + "/" + phase[2].to_s() + " runs=" + stats[stat].to_s() + " rank_wins=" + stats[stat+1].to_s() + " density_wins=" + stats[stat+2].to_s() + " unique_current=" + stats[stat+3].to_s() + " unique_best=" + stats[stat+4].to_s() + " partner_misses=" + stats[stat+5].to_s() + " accepted=" + stats[stat+6].to_s() + " boundary_eligible=" + stats[stat+7].to_s() + " injections=" + stats[stat+8].to_s() + " injected_debt=" + stats[stat+9].to_s() + " end_wall=" + stats[stat+10].to_s() + " end_debt=" + stats[stat+11].to_s() + " exact_failures=" + stats[stat+12].to_s() + " setup_failures=" + stats[stat+13].to_s() + " wall_ms=" + stats[stat+14].to_s()
        mode += 1
  seed_index += 1
