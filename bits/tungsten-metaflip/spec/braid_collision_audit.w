# Exhaustive corpus audit for cyclic braid-output collisions.
#
# This is deliberately an offline decision benchmark, not a registered move.
# For every ordered pair S,D whose three factors differ, the three cyclic
# 2 -> 3 identities are generated exactly as in ffr_braided_debt_step.  A path
# with c generated outputs already in the live term set has endpoint rank
# R + 1 - 2c.  The first and last outputs expose an ordinary direct merge;
# the middle output is the separate neutral-flip-then-merge closure that this
# audit is meant to measure.  Every c>0 endpoint is reconstructed and passed
# through the complete square/rectangular tensor gate.

use ../lib/metaflip/rect
use ../lib/metaflip/seeds/catalog

-> ffbca_same(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  if u0 == u1 && v0 == v1 && w0 == w1
    return 1
  0

# Output layout is three consecutive (u,v,w) triples.  Path 0/1/2 is the
# corrected cyclic U/V/W orientation respectively.
-> ffbca_outputs(su, sv, sw, du, dv, dw, path, out) (i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  if out.size() < 9 || path < 0 || path > 2
    return 0
  if su == du || sv == dv || sw == dw
    return 0
  if path == 0
    out[0] = su ^ du
    out[1] = sv
    out[2] = sw
    out[3] = du
    out[4] = sv
    out[5] = sw ^ dw
    out[6] = du
    out[7] = sv ^ dv
    out[8] = dw
  if path == 1
    out[0] = su
    out[1] = sv ^ dv
    out[2] = sw
    out[3] = su ^ du
    out[4] = dv
    out[5] = sw
    out[6] = du
    out[7] = dv
    out[8] = sw ^ dw
  if path == 2
    out[0] = su
    out[1] = sv
    out[2] = sw ^ dw
    out[3] = su
    out[4] = sv ^ dv
    out[5] = dw
    out[6] = su ^ du
    out[7] = dv
    out[8] = dw
  i = 0 ## i64
  while i < 9
    if out[i] == 0
      return 0
    i += 1
  1

-> ffbca_toggle(us, vs, ws, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return 0 - count - 1
  i = 0 ## i64
  while i < count
    if ffbca_same(us[i],vs[i],ws[i],u,v,w) == 1
      last = count - 1 ## i64
      us[i] = us[last]
      vs[i] = vs[last]
      ws[i] = ws[last]
      return count - 1
    i += 1
  if count >= capacity
    return 0 - count - 1
  us[count] = u
  vs[count] = v
  ws[count] = w
  count + 1

# Toggle the five-term zero relation S,D,O0,O1,O2 into a copied source set.
-> ffbca_candidate(us, vs, ws, rank, capacity, su, sv, sw, du, dv, dw, outputs, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < rank
    out_u[i] = us[i]
    out_v[i] = vs[i]
    out_w[i] = ws[i]
    i += 1
  count = rank ## i64
  count = ffbca_toggle(out_u,out_v,out_w,count,capacity,su,sv,sw)
  if count < 0
    return 0
  count = ffbca_toggle(out_u,out_v,out_w,count,capacity,du,dv,dw)
  if count < 0
    return 0
  output = 0 ## i64
  while output < 3
    offset = output * 3 ## i64
    count = ffbca_toggle(out_u,out_v,out_w,count,capacity,outputs[offset],outputs[offset+1],outputs[offset+2])
    if count < 0
      return 0
    output += 1
  count

-> ffbca_basename(path) (String)
  parts = path.split("/")
  if parts.size() < 1
    return "unknown"
  parts[parts.size()-1]

# Complete coefficient gate for one constructed endpoint.  Return one on an
# exact rank-lowering endpoint and zero on any construction/gate failure.
-> ffbca_gate(label, rectangular, n, m, p, capacity, source_rank, candidate_u, candidate_v, candidate_w, candidate_rank, gate_index) (String i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64 i64) i64
  if candidate_rank < 1 || candidate_rank >= source_rank
    return 0
  child = i64[ffw_state_size(capacity)]
  loaded = 0 ## i64
  exact = 0 ## i64
  seed = 880001 + gate_index * 1009 + n * 101 + m * 17 + p ## i64
  if rectangular == 0
    loaded = ffw_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,capacity,seed,0,1,1,1)
    if loaded == candidate_rank
      exact = ffw_verify_best_exact(child,n)
  if rectangular != 0
    loaded = ffr_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,seed,0,1,1,1)
    if loaded == candidate_rank
      exact = ffr_verify_best_exact(child,n,m,p)
  if exact != 1
    return 0
  output = "/tmp/metaflip_braid_collision_" + label + "_r" + candidate_rank.to_s() + "_g" + gate_index.to_s() + ".txt" ## String
  dumped = 0 ## i64
  if rectangular == 0
    dumped = ffw_dump_best(child,output)
  if rectangular != 0
    dumped = ffr_dump_best(child,output)
  if dumped != 1
    return 0
  1

# Stats layout:
#  0 ordered pairs, 1 eligible pairs, 2 paths,
#  3..6 c=0..3 paths,
#  7/8/9 first/middle/last live-output occurrences,
# 10 c=1 direct-edge paths, 11 c=1 middle-only paths, 12 c>=2 paths,
# 13 full gates, 14 exact gates, 15 gate failures, 16 best endpoint rank.
-> ffbca_scan_state(label, kind, state, rank, n, m, p, rectangular, capacity, stats) (String String i64[] i64 i64 i64 i64 i64 i64 i64[]) i64
  if stats.size() < 17
    return 0
  i = 0 ## i64
  while i < 17
    stats[i] = 0
    i += 1
  stats[16] = rank
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_best(state,us,vs,ws) != rank
    return 0
  started = ccall("__w_clock_ms") ## i64
  source = 0 ## i64
  while source < rank
    donor = 0 ## i64
    while donor < rank
      if source != donor
        stats[0] += 1
        su = us[source] ## i64
        sv = vs[source] ## i64
        sw = ws[source] ## i64
        du = us[donor] ## i64
        dv = vs[donor] ## i64
        dw = ws[donor] ## i64
        if su != du && sv != dv && sw != dw
          stats[1] += 1
          path = 0 ## i64
          while path < 3
            outputs = i64[9]
            if ffbca_outputs(su,sv,sw,du,dv,dw,path,outputs) != 1
              return 0
            stats[2] += 1
            hit0 = 0 ## i64
            hit1 = 0 ## i64
            hit2 = 0 ## i64
            if ffw_find_term(state,outputs[0],outputs[1],outputs[2]) >= 0
              hit0 = 1
            if ffw_find_term(state,outputs[3],outputs[4],outputs[5]) >= 0
              hit1 = 1
            if ffw_find_term(state,outputs[6],outputs[7],outputs[8]) >= 0
              hit2 = 1
            c = hit0 + hit1 + hit2 ## i64
            stats[3+c] += 1
            stats[7] += hit0
            stats[8] += hit1
            stats[9] += hit2
            if c == 1
              if hit1 == 1
                stats[11] += 1
              else
                stats[10] += 1
            if c >= 2
              stats[12] += 1
            if c > 0
              candidate_u = i64[capacity]
              candidate_v = i64[capacity]
              candidate_w = i64[capacity]
              candidate_rank = ffbca_candidate(us,vs,ws,rank,capacity,su,sv,sw,du,dv,dw,outputs,candidate_u,candidate_v,candidate_w) ## i64
              expected_rank = rank + 1 - c - c ## i64
              stats[13] += 1
              if candidate_rank == expected_rank && candidate_rank < stats[16]
                stats[16] = candidate_rank
              gate_label = ffbca_basename(label) ## String
              if candidate_rank == expected_rank && ffbca_gate(gate_label,rectangular,n,m,p,capacity,rank,candidate_u,candidate_v,candidate_w,candidate_rank,stats[13]) == 1
                stats[14] += 1
              else
                stats[15] += 1
            path += 1
      donor += 1
    source += 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  direct_outputs = stats[7] + stats[9] ## i64
  << "BRAID_COLLISION_SEED kind=" + kind + " tensor=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " seed=" + ffbca_basename(label) + " rank=" + rank.to_s() + " ordered=" + stats[0].to_s() + " eligible=" + stats[1].to_s() + " paths=" + stats[2].to_s() + " c0=" + stats[3].to_s() + " c1=" + stats[4].to_s() + " c2=" + stats[5].to_s() + " c3=" + stats[6].to_s() + " direct_outputs=" + direct_outputs.to_s() + " middle_outputs=" + stats[8].to_s() + " c1_direct=" + stats[10].to_s() + " c1_middle=" + stats[11].to_s() + " multi=" + stats[12].to_s() + " gates=" + stats[13].to_s() + " exact=" + stats[14].to_s() + " gate_fail=" + stats[15].to_s() + " best=" + stats[16].to_s() + " ms=" + elapsed.to_s()
  elapsed

-> ffbca_add_stats(total, stats) (i64[] i64[]) i64
  i = 0 ## i64
  while i < 16
    total[i] += stats[i]
    i += 1
  if total[16] == 0 || stats[16] < total[16]
    total[16] = stats[16]
  1

# Positive control for the genuinely separate middle-output closure.  Given
# two live endpoint outputs O0,O2, invert one cyclic path to obtain S,D,O1.
# Replacing O0,O2 by S,D,O1 is an exact R+1 shoulder whose only generated
# collision for the planted S,D path is the middle output O1.  Closing it must
# recover the exact rank-R source.
-> ffbca_middle_control(root) (String) i64
  n = 3 ## i64
  rank = 23 ## i64
  capacity = ffw_default_capacity(n) ## i64
  base = i64[ffw_state_size(capacity)]
  path_name = root + "seeds/gf2/matmul_3x3_rank23_d139_gf2.txt" ## String
  if ffw_load_scheme_cap(base,path_name,n,capacity,870001,0,1,1,1) != rank || ffw_verify_best_exact(base,n) != 1
    return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_best(base,us,vs,ws) != rank
    return 0
  passed = 0 ## i64
  orientation = 0 ## i64
  while orientation < 3
    orientation_pass = 0 ## i64
    first = 0 ## i64
    while first < rank && orientation_pass == 0
      last = 0 ## i64
      while last < rank && orientation_pass == 0
        if first != last
          e0u = us[first] ## i64
          e0v = vs[first] ## i64
          e0w = ws[first] ## i64
          e2u = us[last] ## i64
          e2v = vs[last] ## i64
          e2w = ws[last] ## i64
          su = e0u ^ e2u ## i64
          sv = e0v ## i64
          sw = e0w ## i64
          du = e2u ## i64
          dv = e0v ^ e2v ## i64
          dw = e2w ## i64
          mu = e2u ## i64
          mv = e0v ## i64
          mw = e0w ^ e2w ## i64
          if orientation == 1
            su = e0u
            sv = e0v ^ e2v
            sw = e0w
            du = e2u
            dv = e2v
            dw = e0w ^ e2w
            mu = e0u ^ e2u
            mv = e2v
            mw = e0w
          if orientation == 2
            su = e0u
            sv = e0v
            sw = e0w ^ e2w
            du = e0u ^ e2u
            dv = e2v
            dw = e2w
            mu = e0u
            mv = e0v ^ e2v
            mw = e2w
          valid = 1 ## i64
          if su == 0 || sv == 0 || sw == 0 || du == 0 || dv == 0 || dw == 0 || mu == 0 || mv == 0 || mw == 0
            valid = 0
          if valid == 1 && (su == du || sv == dv || sw == dw)
            valid = 0
          if valid == 1 && (ffw_find_term(base,su,sv,sw) >= 0 || ffw_find_term(base,du,dv,dw) >= 0 || ffw_find_term(base,mu,mv,mw) >= 0)
            valid = 0
          if valid == 1
            outputs = i64[9]
            if ffbca_outputs(su,sv,sw,du,dv,dw,orientation,outputs) != 1
              valid = 0
            if valid == 1 && (ffbca_same(outputs[0],outputs[1],outputs[2],e0u,e0v,e0w) != 1 || ffbca_same(outputs[3],outputs[4],outputs[5],mu,mv,mw) != 1 || ffbca_same(outputs[6],outputs[7],outputs[8],e2u,e2v,e2w) != 1)
              valid = 0
          if valid == 1
            planted_u = i64[capacity]
            planted_v = i64[capacity]
            planted_w = i64[capacity]
            # Toggling endpoints E0,E2 out and S,D,M in is the same five-term
            # zero relation, written explicitly to make the planted rank clear.
            i = 0 ## i64
            while i < rank
              planted_u[i] = us[i]
              planted_v[i] = vs[i]
              planted_w[i] = ws[i]
              i += 1
            planted_rank = rank ## i64
            planted_rank = ffbca_toggle(planted_u,planted_v,planted_w,planted_rank,capacity,e0u,e0v,e0w)
            planted_rank = ffbca_toggle(planted_u,planted_v,planted_w,planted_rank,capacity,e2u,e2v,e2w)
            planted_rank = ffbca_toggle(planted_u,planted_v,planted_w,planted_rank,capacity,su,sv,sw)
            planted_rank = ffbca_toggle(planted_u,planted_v,planted_w,planted_rank,capacity,du,dv,dw)
            planted_rank = ffbca_toggle(planted_u,planted_v,planted_w,planted_rank,capacity,mu,mv,mw)
            planted = i64[ffw_state_size(capacity)]
            loaded = ffw_init_terms_cap(planted,planted_u,planted_v,planted_w,planted_rank,n,capacity,870003,0,1,1,1) ## i64
            if planted_rank == rank + 1 && loaded == planted_rank && ffw_verify_best_exact(planted,n) == 1
              hit0 = 0 ## i64
              hit1 = 0 ## i64
              hit2 = 0 ## i64
              if ffw_find_term(planted,outputs[0],outputs[1],outputs[2]) >= 0
                hit0 = 1
              if ffw_find_term(planted,outputs[3],outputs[4],outputs[5]) >= 0
                hit1 = 1
              if ffw_find_term(planted,outputs[6],outputs[7],outputs[8]) >= 0
                hit2 = 1
              close_u = i64[capacity]
              close_v = i64[capacity]
              close_w = i64[capacity]
              closed_rank = ffbca_candidate(planted_u,planted_v,planted_w,planted_rank,capacity,su,sv,sw,du,dv,dw,outputs,close_u,close_v,close_w) ## i64
              closed = i64[ffw_state_size(capacity)]
              closed_loaded = ffw_init_terms_cap(closed,close_u,close_v,close_w,closed_rank,n,capacity,870007,0,1,1,1) ## i64
              if hit0 == 0 && hit1 == 1 && hit2 == 0 && closed_rank == rank && closed_loaded == rank && ffw_verify_best_exact(closed,n) == 1
                << "BRAID_COLLISION_CONTROL result=pass tensor=3x3x3 planted=r24 closure=r23 orientation=" + orientation.to_s() + " first=" + first.to_s() + " last=" + last.to_s() + " c=1 position=middle exact=1"
                orientation_pass = 1
                passed += 1
        last += 1
      first += 1
    if orientation_pass != 1
      return 0
    orientation += 1
  if passed == 3
    return 1
  0

runtime_root = __DIR__ + "/../lib/metaflip/" ## String
if ffbca_middle_control(runtime_root) != 1
  << "BRAID_COLLISION_CONTROL result=fail"
  exit(1)

square_total = i64[17]
rect_total = i64[17]
square_seeds = 0 ## i64
rect_seeds = 0 ## i64
square_shapes = 0 ## i64
rect_shapes = 0 ## i64
skipped_shoulders = 0 ## i64
total_ms = 0 ## i64

n = 2 ## i64
while n <= 7
  paths = ffp_frontier_seed_paths(n)
  if paths.size() > 0
    square_shapes += 1
  i = 0 ## i64
  while i < paths.size()
    capacity = ffw_default_capacity(n) ## i64
    state = i64[ffw_state_size(capacity)]
    rank = ffw_load_scheme_cap(state,runtime_root+paths[i],n,capacity,890001+n*1009+i,0,1,1,1) ## i64
    if rank != ffp_record(n) || ffw_verify_best_exact(state,n) != 1
      << "BRAID_COLLISION_FAIL kind=square tensor=" + n.to_s() + " seed=" + paths[i] + " reason=load-or-exact rank=" + rank.to_s()
      exit(1)
    stats = i64[17]
    elapsed = ffbca_scan_state(paths[i],"square",state,rank,n,n,n,0,capacity,stats) ## i64
    if elapsed < 0
      << "BRAID_COLLISION_FAIL kind=square tensor=" + n.to_s() + " seed=" + paths[i] + " reason=scan"
      exit(1)
    total_ms += elapsed
    z = ffbca_add_stats(square_total,stats) ## i64
    square_seeds += 1
    i += 1
  n += 1

n = 2
while n <= 7
  m = n ## i64
  while m <= 9
    p = m ## i64
    while p <= 9
      if ffrp_supported(n,m,p) == 1
        rect_shapes += 1
        slots = ffrp_frontier_seed_count(n,m,p) ## i64
        slot = 0 ## i64
        while slot < slots
          rel = ffrp_frontier_seed_rel(n,m,p,slot) ## String
          capacity = ffr_default_capacity(n,m,p) ## i64
          state = i64[ffw_state_size(capacity)]
          rank = ffr_load_scheme_cap(state,runtime_root+rel,n,m,p,capacity,910001+n*10007+m*1009+p*101+slot,0,1,1,1) ## i64
          record = ffrp_record_rank(n,m,p) ## i64
          if rank != record
            if rank > record && ffr_verify_best_exact(state,n,m,p) == 1
              skipped_shoulders += 1
            else
              << "BRAID_COLLISION_FAIL kind=rect tensor=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " seed=" + rel + " reason=load-or-rank rank=" + rank.to_s() + " record=" + record.to_s()
              exit(1)
          else
            if ffr_verify_best_exact(state,n,m,p) != 1
              << "BRAID_COLLISION_FAIL kind=rect tensor=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " seed=" + rel + " reason=exact"
              exit(1)
            stats = i64[17]
            elapsed = ffbca_scan_state(rel,"rect",state,rank,n,m,p,1,capacity,stats) ## i64
            if elapsed < 0
              << "BRAID_COLLISION_FAIL kind=rect tensor=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " seed=" + rel + " reason=scan"
              exit(1)
            total_ms += elapsed
            z = ffbca_add_stats(rect_total,stats)
            rect_seeds += 1
          slot += 1
      p += 1
    m += 1
  n += 1

all_total = i64[17]
z = ffbca_add_stats(all_total,square_total) ## i64
z = ffbca_add_stats(all_total,rect_total)
direct_outputs = all_total[7] + all_total[9] ## i64
rate = 0 ## i64
if total_ms > 0
  rate = all_total[2] * 1000 / total_ms
<< "BRAID_COLLISION_SUMMARY square_shapes=" + square_shapes.to_s() + " square_seeds=" + square_seeds.to_s() + " rect_shapes=" + rect_shapes.to_s() + " rect_seeds=" + rect_seeds.to_s() + " skipped_shoulders=" + skipped_shoulders.to_s() + " ordered=" + all_total[0].to_s() + " eligible=" + all_total[1].to_s() + " paths=" + all_total[2].to_s() + " c0=" + all_total[3].to_s() + " c1=" + all_total[4].to_s() + " c2=" + all_total[5].to_s() + " c3=" + all_total[6].to_s() + " direct_outputs=" + direct_outputs.to_s() + " middle_outputs=" + all_total[8].to_s() + " c1_direct=" + all_total[10].to_s() + " c1_middle=" + all_total[11].to_s() + " multi=" + all_total[12].to_s() + " gates=" + all_total[13].to_s() + " exact=" + all_total[14].to_s() + " gate_fail=" + all_total[15].to_s() + " ms=" + total_ms.to_s() + " paths_per_s=" + rate.to_s()
