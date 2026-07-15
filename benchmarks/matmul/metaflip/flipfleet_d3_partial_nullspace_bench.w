# Exhaustive frontier audit for genuine D3 partial-automorphism tunnels.
#
# Each nonidentity map is one of the tensor-axis factor maps implemented by
# ffbi_transform_term, not a coordinate-index permutation.  For every tracked
# 4x4..7x7 frontier seed we solve the exact term-delta kernel, quotient fixed
# terms, exhaust the effective kernel when small, and otherwise enumerate a
# reproducible bounded closure of basis combinations.  Every materialized
# endpoint is rebuilt and independently passed through the full n^6 gate.
#
# Usage:
#   flipfleet_d3_partial_nullspace_bench [only_n=0] [combo_cap=4096]
#                                        [exhaustive_dim=12] [output_prefix=""]
#                                        [dense_milli=0]

use flipfleet_d3_partial_nullspace
use flipfleet_profiles

-> ffd3nsb_add(target, source) (i64[] i64[]) i64
  i = 0 ## i64
  while i < target.size() && i < source.size()
    target[i] = target[i] + source[i]
    i += 1
  1

-> ffd3nsb_map_label(code, reverse) (i64 i64)
  name = "id" ## String
  if code == 1
    name = "rho"
  if code == 2
    name = "rho2"
  if code == 3
    name = "tau"
  if code == 4
    name = "rho-tau"
  if code == 5
    name = "rho2-tau"
  if reverse != 0
    name += "+reverse"
  name

# The additive fields are kept separate from minima/maxima so summaries cannot
# silently turn a per-map dimension into an aggregate dimension.
# totals: maps, attempts, set-stable, materialized, exact, source, global,
# canonical-source, genuine, D3-novel, canonical-unique, rank-drop,
# density-improve, parity-drop, failures, relation-failures, elimination-ms,
# admission-ms, capped-maps, exhaustive-maps.
-> ffd3nsb_accumulate(totals, meta) (i64[] i64[]) i64
  totals[0] += 1
  totals[1] += meta[4]
  totals[2] += meta[6]
  totals[3] += meta[8]
  totals[4] += meta[9]
  totals[5] += meta[10]
  totals[6] += meta[11]
  totals[7] += meta[12]
  totals[8] += meta[13]
  totals[9] += meta[14]
  totals[10] += meta[15]
  totals[11] += meta[16]
  totals[12] += meta[17]
  totals[13] += meta[26]
  totals[14] += meta[27]
  totals[15] += meta[7]
  totals[16] += meta[24]
  totals[17] += meta[25]
  totals[18] += meta[23]
  totals[19] += meta[5]
  1

-> ffd3nsb_run_frontier(n, combo_cap, exhaustive_dim, output_prefix, dense_milli, grand) (i64 i64 i64 String i64 i64[]) i64
  paths = ffp_frontier_seed_paths(n)
  capacity = ffw_default_capacity(n) ## i64
  state_size = ffw_state_size(capacity) ## i64
  frontier_ids = i64[paths.size()]
  valid = i64[paths.size()]

  # First independently gate the complete archive and record its D3-canonical
  # identities.  These IDs are telemetry only; exactness never depends on a
  # digest comparison.
  source_index = 0 ## i64
  while source_index < paths.size()
    archive_state = i64[state_size]
    rank = ffw_load_scheme_cap(archive_state, paths[source_index], n, capacity, 970001 + n * 1000 + source_index, 0, 1, 1, 1) ## i64
    if rank > 0 && ffw_verify_best_exact(archive_state, n) == 1
      valid[source_index] = 1
      frontier_ids[source_index] = ffbi_best_id(archive_state)
    source_index += 1

  tensor = n.to_s() + "x" + n.to_s() ## String
  << "D3_PARTIAL_FRONTIER_BEGIN tensor=" + tensor + " sources=" + paths.size().to_s() + " cap=" + combo_cap.to_s() + " exhaustive_dim=" + exhaustive_dim.to_s() + " dense_milli=" + dense_milli.to_s()
  totals = i64[20]
  max_raw = 0 ## i64
  max_effective = 0 ## i64
  max_distance = 0 ## i64
  min_effective = 9223372036854775807 ## i64
  archive_novel_best = 0 ## i64
  source_index = 0
  while source_index < paths.size()
    if valid[source_index] == 0
      << "D3_PARTIAL_LOAD_FAIL tensor=" + tensor + " source=" + source_index.to_s() + " path=" + paths[source_index]
      totals[14] += 1
    else
      state = i64[state_size]
      rank = ffw_load_scheme_cap(state, paths[source_index], n, capacity, 971001 + n * 1000 + source_index, 0, 1, 1, 1)
      source_density = ffw_best_bits(state) ## i64
      workspace = FFD3NSWorkspace.new(rank, n, capacity, combo_cap)
      workspace.reset_best(rank, source_density)
      meta = i64[28]
      source_totals = i64[20]
      source_min_effective = rank + 1 ## i64
      source_max_effective = 0 ## i64
      reverse = 0 ## i64
      while reverse < 2
        code = 0 ## i64
        while code < 6
          if code != 0 || reverse != 0
            scanned = ffd3ns_scan_state_policy(state, code, reverse, exhaustive_dim, dense_milli, workspace, meta) ## i64
            if scanned < 0
              totals[14] += 1
              source_totals[14] += 1
            else
              ffd3nsb_accumulate(totals, meta)
              ffd3nsb_accumulate(source_totals, meta)
              if meta[0] > max_raw
                max_raw = meta[0]
              if meta[2] > max_effective
                max_effective = meta[2]
              if meta[2] < min_effective
                min_effective = meta[2]
              if meta[2] > source_max_effective
                source_max_effective = meta[2]
              if meta[2] < source_min_effective
                source_min_effective = meta[2]
              if meta[20] > max_distance
                max_distance = meta[20]
              << "D3_PARTIAL_MAP tensor=" + tensor + " source=" + source_index.to_s() + " map=" + ffd3nsb_map_label(code, reverse) + " raw=" + meta[0].to_s() + " fixed=" + meta[1].to_s() + " effective=" + meta[2].to_s() + " theory=" + meta[3].to_s() + " tried=" + meta[4].to_s() + " exhaustive=" + meta[5].to_s() + " stable=" + meta[6].to_s() + " exact=" + meta[9].to_s() + " source_q=" + meta[10].to_s() + " global_q=" + meta[11].to_s() + " canonical_q=" + meta[12].to_s() + " genuine=" + meta[13].to_s() + " d3_novel=" + meta[14].to_s() + " drop=" + meta[16].to_s() + " dense=" + meta[17].to_s() + " dist=" + meta[20].to_s() + " ms=" + meta[24].to_s() + "/" + meta[25].to_s() + " fail=" + (meta[7] + meta[27]).to_s()
          code += 1
        reverse += 1

      # Classify the best admitted endpoint against every tracked frontier,
      # not just its source.  This is the stronger archive-novel signal used
      # for deciding whether a generated scheme is worth publishing.
      best_meta = workspace.best_meta()
      archive_match = 0 ## i64
      best_id = 0 ## i64
      if best_meta[0] != 0
        best_id = ffbi_best_id(workspace.best())
        archive_index = 0 ## i64
        while archive_index < paths.size()
          if valid[archive_index] != 0 && frontier_ids[archive_index] == best_id
            archive_match = 1
          archive_index += 1
        if archive_match == 0
          archive_novel_best += 1
          if output_prefix.size() > 0
            output = output_prefix + "_" + tensor + "_rank" + best_meta[1].to_s() + "_d" + best_meta[2].to_s() + "_d3_partial_nullspace_mixed_s" + source_index.to_s() + "_gf2.txt" ## String
            dumped = ffw_dump_best(workspace.best(), output) ## i64
            reloaded = i64[state_size]
            reload_rank = ffw_load_scheme_cap(reloaded, output, n, capacity, 972001 + source_index, 0, 1, 1, 1) ## i64
            if dumped != best_meta[1] || reload_rank != best_meta[1] || ffw_verify_best_exact(reloaded, n) != 1
              << "D3_PARTIAL_PUBLISH_FAIL path=" + output
              totals[14] += 1
            else
              << "D3_PARTIAL_PUBLISH path=" + output + " rank=" + reload_rank.to_s() + " density=" + ffw_best_bits(reloaded).to_s() + " distance=" + best_meta[3].to_s()
      << "D3_PARTIAL_SOURCE tensor=" + tensor + " source=" + source_index.to_s() + " rank=" + rank.to_s() + " density=" + source_density.to_s() + " effective=" + source_min_effective.to_s() + ".." + source_max_effective.to_s() + " attempts=" + source_totals[1].to_s() + " stable=" + source_totals[2].to_s() + " exact=" + source_totals[4].to_s() + " genuine=" + source_totals[8].to_s() + " d3_novel=" + source_totals[9].to_s() + " best=" + best_meta[1].to_s() + "/" + best_meta[2].to_s() + " archive_match=" + archive_match.to_s() + " fail=" + (source_totals[14] + source_totals[15]).to_s() + " path=" + paths[source_index]
    source_index += 1

  if min_effective == 9223372036854775807
    min_effective = 0
  << "D3_PARTIAL_FRONTIER_SUMMARY tensor=" + tensor + " maps=" + totals[0].to_s() + " attempts=" + totals[1].to_s() + " stable=" + totals[2].to_s() + " materialized=" + totals[3].to_s() + " exact=" + totals[4].to_s() + " source_q=" + totals[5].to_s() + " global_q=" + totals[6].to_s() + " canonical_q=" + totals[7].to_s() + " genuine=" + totals[8].to_s() + " d3_novel=" + totals[9].to_s() + " unique=" + totals[10].to_s() + " drops=" + totals[11].to_s() + " dense=" + totals[12].to_s() + " archive_novel_best=" + archive_novel_best.to_s() + " raw_max=" + max_raw.to_s() + " effective=" + min_effective.to_s() + ".." + max_effective.to_s() + " distance=" + max_distance.to_s() + " exhaustive=" + totals[19].to_s() + " capped=" + totals[18].to_s() + " ms=" + totals[16].to_s() + "/" + totals[17].to_s() + " fail=" + (totals[14] + totals[15]).to_s()
  ffd3nsb_add(grand, totals)
  archive_novel_best

args = argv()
only_n = 0 ## i64
combo_cap = 4096 ## i64
exhaustive_dim = 12 ## i64
output_prefix = "" ## String
dense_milli = 0 ## i64
if args.size() > 0
  only_n = args[0].to_i()
if args.size() > 1
  combo_cap = args[1].to_i()
if args.size() > 2
  exhaustive_dim = args[2].to_i()
if args.size() > 3
  output_prefix = args[3]
if args.size() > 4
  dense_milli = args[4].to_i()
if only_n != 0 && (only_n < 4 || only_n > 7)
  << "invalid only_n"
  exit(2)
if combo_cap < 1 || combo_cap > 262144
  << "invalid combo_cap"
  exit(2)
if exhaustive_dim < 0 || exhaustive_dim > 20
  << "invalid exhaustive_dim"
  exit(2)
if dense_milli < 0 || dense_milli > 1000
  << "invalid dense_milli"
  exit(2)

grand = i64[20]
archive_novel_best = 0 ## i64
n = 4 ## i64
while n <= 7
  if only_n == 0 || only_n == n
    archive_novel_best += ffd3nsb_run_frontier(n, combo_cap, exhaustive_dim, output_prefix, dense_milli, grand)
  n += 1
<< "D3_PARTIAL_ALL_SUMMARY maps=" + grand[0].to_s() + " attempts=" + grand[1].to_s() + " stable=" + grand[2].to_s() + " materialized=" + grand[3].to_s() + " exact=" + grand[4].to_s() + " source_q=" + grand[5].to_s() + " global_q=" + grand[6].to_s() + " canonical_q=" + grand[7].to_s() + " genuine=" + grand[8].to_s() + " d3_novel=" + grand[9].to_s() + " unique=" + grand[10].to_s() + " drops=" + grand[11].to_s() + " dense=" + grand[12].to_s() + " archive_novel_best=" + archive_novel_best.to_s() + " exhaustive=" + grand[19].to_s() + " capped=" + grand[18].to_s() + " ms=" + grand[16].to_s() + "/" + grand[17].to_s() + " fail=" + (grand[14] + grand[15]).to_s()
