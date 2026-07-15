# Bounded real-frontier audit for exact Fano-plane quadrilateral refactors.
#
# Usage:
#   flipfleet_projective_plane_bench [max_cells] [anchor_values] [max_groups]
#
# For each factor axis, the audit forms every independent triple among the
# first `anchor_values` distinct live factors, canonicalizes its seven-point
# plane exactly, and captures the maximal live subtotal in that plane.  At
# most `max_groups` qualifying (k>=5) groups per tensor are optimized.
# `cells<=max_cells` receives exhaustive D search; larger factor ranks use the
# documented structured candidate family. The bounds are printed explicitly;
# this is not an assertion that every plane in a frontier was scanned.

use flipfleet_projective_plane

-> ffppb_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTIVE_PLANE_BENCH_FAIL " + label
    exit(1)
  1

-> ffppb_unique_axis(us, vs, ws, count, axis, values) (i64[] i64[] i64[] i64 i64 i64[]) i64
  made = 0 ## i64
  position = 0 ## i64
  while position < count
    value = ffmp_axis_get(us,vs,ws,position,axis) ## i64
    seen = 0 ## i64
    i = 0 ## i64
    while i < made
      if values[i] == value
        seen = 1
      i += 1
    if seen == 0
      values[made] = value
      made += 1
    position += 1
  made

-> ffppb_plane_seen(stored, count, points) (i64[] i64 i64[]) i64
  plane = 0 ## i64
  while plane < count
    same = 1 ## i64
    point = 0 ## i64
    while point < 7
      if stored[plane*7+point] != points[point]
        same = 0
      point += 1
    if same == 1
      return 1
    plane += 1
  0

-> ffppb_store_plane(stored, position, points) (i64[] i64 i64[]) i64
  point = 0 ## i64
  while point < 7
    stored[position*7+point] = points[point]
    point += 1
  1

-> ffppb_density(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < count
    density += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  density

-> ffppb_state_density(state) (i64[]) i64
  capacity = state[4] ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_current(state,us,vs,ws) ## i64
  ffppb_density(us,vs,ws,rank)

-> ffppb_run(label, path, n, max_cells, anchor_values, max_groups) (String String i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  source = i64[ffw_state_size(capacity)]
  source_rank = ffw_load_scheme_cap(source,path,n,capacity,982001+n,0,1,1,1) ## i64
  ffppb_expect(label + " source exact",source_rank > 0 && ffw_verify_current_exact(source,n) == 1)
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  ffppb_expect(label + " export",ffw_export_current(source,us,vs,ws) == source_rank)
  source_density = ffppb_density(us,vs,ws,source_rank) ## i64
  selected = i64[capacity]
  su = i64[capacity]
  sv = i64[capacity]
  sw = i64[capacity]
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  plane_capacity = anchor_values * anchor_values * anchor_values ## i64
  if plane_capacity < 1
    plane_capacity = 1
  stored = i64[plane_capacity*7]
  total_planes = 0 ## i64
  ge5 = 0 ## i64
  over_cells = 0 ## i64
  structured = 0 ## i64
  optimized = 0 ## i64
  enumerated = 0 ## i64
  ordinary_reducible = 0 ## i64
  circuit_drops = 0 ## i64
  circuit_neutral = 0 ## i64
  full_exact = 0 ## i64
  failures = 0 ## i64
  global_drops = 0 ## i64
  density_wins = 0 ## i64
  max_group = 0 ## i64
  max_distance = 0 ## i64
  best_rank = source_rank ## i64
  best_density = source_density ## i64
  started = ccall("__w_clock_ms") ## i64
  axis = 0 ## i64
  while axis < 3
    axis_seen = 0 ## i64
    unique = i64[capacity]
    unique_count = ffppb_unique_axis(us,vs,ws,source_rank,axis,unique) ## i64
    anchor_count = unique_count ## i64
    if anchor_count > anchor_values
      anchor_count = anchor_values
    first = 0 ## i64
    while first < anchor_count - 2
      second = first + 1 ## i64
      while second < anchor_count - 1
        third = second + 1 ## i64
        while third < anchor_count
          points = i64[7]
          if ffpp_plane_from(unique[first],unique[second],unique[third],points) == 7
            if ffppb_plane_seen(stored,axis_seen,points) == 0
              if axis_seen < plane_capacity
                z = ffppb_store_plane(stored,axis_seen,points) ## i64
                axis_seen += 1
                total_planes += 1
                group_count = ffpp_capture_plane(us,vs,ws,source_rank,axis,points,selected,su,sv,sw) ## i64
                if group_count > max_group
                  max_group = group_count
                if group_count >= 5
                  ge5 += 1
                  if optimized < max_groups
                    meta = i64[16]
                    made = ffpp_optimize_group(su,sv,sw,group_count,axis,points,max_cells,out_u,out_v,out_w,meta) ## i64
                    if made < 1
                      if meta[3] > max_cells
                        over_cells += 1
                    if made > 0
                      optimized += 1
                      if meta[13] == 2
                        structured += 1
                      enumerated += meta[4]
                      if meta[5] < group_count
                        ordinary_reducible += 1
                      if meta[7] != 0 && meta[12] > 0
                        if meta[6] < meta[5]
                          circuit_drops += 1
                        if meta[6] == meta[5]
                          circuit_neutral += 1
                          << "PROJECTIVE_PLANE_HIT tensor=" + label + " axis=" + axis.to_s() + " anchors=" + first.to_s() + "," + second.to_s() + "," + third.to_s() + " group=" + group_count.to_s() + " cells=" + meta[3].to_s() + " mode=" + meta[13].to_s() + " circuit=" + meta[7].to_s() + " d=" + meta[8].to_s() + " distance=" + meta[12].to_s() + " plane=" + points[0].to_s() + "," + points[1].to_s() + "," + points[2].to_s() + "," + points[3].to_s() + "," + points[4].to_s() + "," + points[5].to_s() + "," + points[6].to_s()
                        if meta[12] > max_distance
                          max_distance = meta[12]
                        candidate = i64[ffw_state_size(capacity)]
                        candidate_rank = ffmp_splice_state(source,selected,group_count,out_u,out_v,out_w,made,candidate,983001 + axis*100003 + first*1009 + second*101 + third) ## i64
                        if candidate_rank > 0 && ffw_verify_current_exact(candidate,n) == 1
                          full_exact += 1
                          candidate_density = ffppb_state_density(candidate) ## i64
                          if candidate_rank < source_rank
                            global_drops += 1
                          if candidate_rank == source_rank && candidate_density < source_density
                            density_wins += 1
                          if candidate_rank < best_rank || (candidate_rank == best_rank && candidate_density < best_density)
                            best_rank = candidate_rank
                            best_density = candidate_density
                        else
                          failures += 1
          third += 1
        second += 1
      first += 1
    axis += 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  << "PROJECTIVE_PLANE_BENCH tensor=" + label + " rank=" + source_rank.to_s() + " density=" + source_density.to_s() + " anchors=" + anchor_values.to_s() + " max_groups=" + max_groups.to_s() + " planes=" + total_planes.to_s() + " ge5=" + ge5.to_s() + " max_group=" + max_group.to_s() + " optimized=" + optimized.to_s() + " structured=" + structured.to_s() + " unsupported=" + over_cells.to_s() + " enumerated=" + enumerated.to_s() + " ordinary_reducible=" + ordinary_reducible.to_s() + " circuit_drop=" + circuit_drops.to_s() + " circuit_neutral=" + circuit_neutral.to_s() + " full_exact=" + full_exact.to_s() + " failures=" + failures.to_s() + " global_drops=" + global_drops.to_s() + " density_wins=" + density_wins.to_s() + " max_distance=" + max_distance.to_s() + " best=r" + best_rank.to_s() + "/d" + best_density.to_s() + " ms=" + elapsed.to_s()
  failures

args = argv()
max_cells = 16 ## i64
anchor_values = 14 ## i64
max_groups = 16 ## i64
if args.size() > 0
  max_cells = args[0].to_i()
if args.size() > 1
  anchor_values = args[1].to_i()
if args.size() > 2
  max_groups = args[2].to_i()
if max_cells < 1 || max_cells > 20 || anchor_values < 3 || anchor_values > 32 || max_groups < 1 || max_groups > 2048
  << "usage: flipfleet_projective_plane_bench [max_cells:1..20] [anchor_values:3..32] [max_groups:1..2048]"
  exit(2)

failures = 0 ## i64
failures += ffppb_run("4x4-r49","benchmarks/matmul/metaflip/matmul_4x4_rank49_d432_signed_4x4x4_m49_zt_gf2.txt",4,max_cells,anchor_values,max_groups)
failures += ffppb_run("4x4-r47","benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt",4,max_cells,anchor_values,max_groups)
failures += ffppb_run("5x5-d1155","benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt",5,max_cells,anchor_values,max_groups)
failures += ffppb_run("5x5-d968","benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt",5,max_cells,anchor_values,max_groups)
failures += ffppb_run("6x6-d2508","benchmarks/matmul/metaflip/matmul_6x6_rank153_d2508_gf2.txt",6,max_cells,anchor_values,max_groups)
failures += ffppb_run("6x6-d1860","benchmarks/matmul/metaflip/matmul_6x6_rank153_d1860_global_isotropy_gf2.txt",6,max_cells,anchor_values,max_groups)
failures += ffppb_run("7x7-r250","benchmarks/matmul/metaflip/matmul_7x7_rank250_d2966_gf2.txt",7,max_cells,anchor_values,max_groups)
failures += ffppb_run("7x7-r247","benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_partial_auto_min_density_gf2.txt",7,max_cells,anchor_values,max_groups)
ffppb_expect("all full gates",failures == 0)
<< "flipfleet_projective_plane_bench: pass max_cells=" + max_cells.to_s() + " anchors=" + anchor_values.to_s() + " max_groups=" + max_groups.to_s()
