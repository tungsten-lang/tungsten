# Bounded CPU audit for exact projective-line / matrix-pencil refactors.
#
# Usage:
#   flipfleet_matrix_pencil_bench [max_cells]
#
# max_cells=20 (default) exhausts every 4x5/5x4 pencil in the selected
# archives.  max_cells=25 additionally builds one 128 MiB 5x5 matrix-rank
# table and exhausts the 2^25 choices for every 5x5 pencil.  No GPU work or
# production/TUI state is touched.

use flipfleet_matrix_pencil

-> ffmpb_expect(label, condition) (String bool) i64
  if !condition
    << "MATRIX_PENCIL_BENCH_FAIL " + label
    exit(1)
  1

-> ffmpb_density(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < count
    density += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  density

-> ffmpb_state_density(state) (i64[]) i64
  capacity = state[4] ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_current(state,us,vs,ws) ## i64
  ffmpb_density(us,vs,ws,rank)

-> ffmpb_run(label, path, n, max_cells, rank_table) (String String i64 i64 i32[]) i64
  capacity = ffw_default_capacity(n) ## i64
  source = i64[ffw_state_size(capacity)]
  source_rank = ffw_load_scheme_cap(source,path,n,capacity,812001+n,0,1,1,1) ## i64
  ffmpb_expect(label + " source exact",source_rank > 0 && ffw_verify_current_exact(source,n) == 1)
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  ffmpb_expect(label + " export",ffw_export_current(source,us,vs,ws) == source_rank)
  source_density = ffmpb_density(us,vs,ws,source_rank) ## i64
  pair_capacity = source_rank * (source_rank - 1) / 2 ## i64
  lines_a = i64[pair_capacity]
  lines_b = i64[pair_capacity]
  lines_c = i64[pair_capacity]
  selected = i64[capacity]
  su = i64[capacity]
  sv = i64[capacity]
  sw = i64[capacity]
  out_u = i64[96]
  out_v = i64[96]
  out_w = i64[96]
  total_lines = 0 ## i64
  ge5 = 0 ## i64
  max_group = 0 ## i64
  cells20 = 0 ## i64
  cells25 = 0 ## i64
  other_cells = 0 ## i64
  searched = 0 ## i64
  skipped = 0 ## i64
  enumerated = 0 ## i64
  ordinary_reducible = 0 ## i64
  cross_drops = 0 ## i64
  cross_neutral = 0 ## i64
  changed = 0 ## i64
  full_exact = 0 ## i64
  global_drops = 0 ## i64
  density_wins = 0 ## i64
  failures = 0 ## i64
  max_distance = 0 ## i64
  best_rank = source_rank ## i64
  best_density = source_density ## i64
  started = ccall("__w_clock_ms") ## i64
  axis = 0 ## i64
  while axis < 3
    seen = 0 ## i64
    first = 0 ## i64
    while first < source_rank - 1
      second = first + 1 ## i64
      while second < source_rank
        left = ffmp_axis_get(us,vs,ws,first,axis) ## i64
        right = ffmp_axis_get(us,vs,ws,second,axis) ## i64
        if left != right
          line = i64[3]
          if ffmp_line_sort(left,right,left ^ right,line) == 1
            if ffmp_line_seen(lines_a,lines_b,lines_c,seen,line) == 0
              lines_a[seen] = line[0]
              lines_b[seen] = line[1]
              lines_c[seen] = line[2]
              seen += 1
              total_lines += 1
              group_count = ffmp_capture_line(us,vs,ws,source_rank,axis,line,selected,su,sv,sw) ## i64
              if group_count > max_group
                max_group = group_count
              if group_count >= 5
                ge5 += 1
                meta = i64[14]
                made = ffmp_optimize_group(su,sv,sw,group_count,axis,line,max_cells,rank_table,out_u,out_v,out_w,meta) ## i64
                if meta[3] == 20
                  cells20 += 1
                if meta[3] == 25
                  cells25 += 1
                if meta[3] != 20 && meta[3] != 25
                  other_cells += 1
                if made < 1
                  skipped += 1
                if made > 0
                  searched += 1
                  enumerated += meta[4]
                  if meta[5] < group_count
                    ordinary_reducible += 1
                  cross = 0 ## i64
                  if meta[8] != meta[7] && meta[12] > 0
                    cross = 1
                  if cross == 1 && meta[6] < meta[5]
                    cross_drops += 1
                  if cross == 1 && meta[6] == meta[5]
                    cross_neutral += 1
                  if cross == 1
                    changed += 1
                    if meta[12] > max_distance
                      max_distance = meta[12]
                    candidate = i64[ffw_state_size(capacity)]
                    candidate_rank = ffmp_splice_state(source,selected,group_count,out_u,out_v,out_w,made,candidate,813001 + axis*10007 + first*101 + second) ## i64
                    if candidate_rank > 0 && ffw_verify_current_exact(candidate,n) == 1
                      full_exact += 1
                      candidate_density = ffmpb_state_density(candidate) ## i64
                      if candidate_rank < source_rank
                        global_drops += 1
                      if candidate_rank == source_rank && candidate_density < source_density
                        density_wins += 1
                      if candidate_rank < best_rank || (candidate_rank == best_rank && candidate_density < best_density)
                        best_rank = candidate_rank
                        best_density = candidate_density
                    else
                      failures += 1
        second += 1
      first += 1
    axis += 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  << "MATRIX_PENCIL_BENCH tensor=" + label + " rank=" + source_rank.to_s() + " density=" + source_density.to_s() + " lines=" + total_lines.to_s() + " max_group=" + max_group.to_s() + " ge5=" + ge5.to_s() + " cells20=" + cells20.to_s() + " cells25=" + cells25.to_s() + " other_cells=" + other_cells.to_s() + " searched=" + searched.to_s() + " skipped=" + skipped.to_s() + " enumerated=" + enumerated.to_s() + " ordinary_reducible=" + ordinary_reducible.to_s() + " cross_drop=" + cross_drops.to_s() + " cross_neutral=" + cross_neutral.to_s() + " changed=" + changed.to_s() + " full_exact=" + full_exact.to_s() + " failures=" + failures.to_s() + " global_drops=" + global_drops.to_s() + " density_wins=" + density_wins.to_s() + " max_distance=" + max_distance.to_s() + " best=r" + best_rank.to_s() + "/d" + best_density.to_s() + " ms=" + elapsed.to_s()
  failures

args = argv()
max_cells = 20 ## i64
if args.size() > 0
  max_cells = args[0].to_i()
if max_cells < 4 || max_cells > 25
  << "usage: flipfleet_matrix_pencil_bench [max_cells:4..25]"
  exit(2)

rank_table = i32[1]
if max_cells == 25
  rank_table = i32[33554432]
  started_table = ccall("__w_clock_ms") ## i64
  ffmpb_expect("5x5 rank table",ffmp_fill_rank_table(5,5,rank_table) == 33554432)
  << "MATRIX_PENCIL_TABLE shape=5x5 entries=33554432 bytes=134217728 ms=" + (ccall("__w_clock_ms") - started_table).to_s()

failures = 0 ## i64
failures += ffmpb_run("4x4-r49","benchmarks/matmul/metaflip/matmul_4x4_rank49_d432_signed_4x4x4_m49_zt_gf2.txt",4,max_cells,rank_table)
failures += ffmpb_run("4x4-r47","benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt",4,max_cells,rank_table)
failures += ffmpb_run("5x5-d1155","benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt",5,max_cells,rank_table)
failures += ffmpb_run("5x5-d968","benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt",5,max_cells,rank_table)
failures += ffmpb_run("6x6-d2508","benchmarks/matmul/metaflip/matmul_6x6_rank153_d2508_gf2.txt",6,max_cells,rank_table)
failures += ffmpb_run("6x6-d1860","benchmarks/matmul/metaflip/matmul_6x6_rank153_d1860_global_isotropy_gf2.txt",6,max_cells,rank_table)
ffmpb_expect("all full gates",failures == 0)
<< "flipfleet_matrix_pencil_bench: pass max_cells=" + max_cells.to_s()
