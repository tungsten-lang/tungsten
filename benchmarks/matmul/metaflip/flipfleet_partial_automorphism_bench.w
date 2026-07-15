use flipfleet_partial_automorphism

-> ffpab_run(label, path, n, window, windows) (String String i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state, path, n, capacity, 88117 + n, 0, 1, 1, 1) ## i64
  if rank < 1 || ffw_verify_current_exact(state, n) != 1
    << "PARTIAL_CYCLE_LOAD_FAIL tensor=" + label
    return 0 - 1
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  exported = ffw_export_current(state, us, vs, ws) ## i64
  total_attempts = 0 ## i64
  total_hit2 = 0 ## i64
  total_hit3 = 0 ## i64
  total_hit4 = 0 ## i64
  total_comparisons = 0 ## i64
  total_rejects = 0 ## i64
  applied_candidates = 0 ## i64
  epoch = 0 ## i64
  while epoch < windows
    offset = (epoch * rank) / windows ## i64
    stats = i64[8]
    attempts = ffpa_audit_cycle_terms(us, vs, ws, exported, n, window, offset, stats) ## i64
    total_attempts += attempts
    total_hit2 += stats[3]
    total_hit3 += stats[4]
    total_hit4 += stats[5]
    total_comparisons += stats[6]
    total_rejects += stats[7]
    << "PARTIAL_CYCLE_WINDOW tensor=" + label + " offset=" + offset.to_s() + " window=" + stats[0].to_s() + " autos=" + stats[2].to_s() + " hit2=" + stats[3].to_s() + " hit3=" + stats[4].to_s() + " hit4=" + stats[5].to_s() + " comparisons=" + stats[6].to_s()

    # Materialize and independently full-tensor-check the first relation from
    # a positive window.  The audit itself already compares complete n^6-bit
    # deltas; this additionally covers worker collision/rank semantics.
    wanted = 0 ## i64
    if stats[3] > 0
      wanted = 2
    else
      if stats[4] > 0
        wanted = 3
      else
        if stats[5] > 0
          wanted = 4
    if wanted > 0
      selected = i64[4]
      meta = i64[11]
      found = ffpa_enumerate_cycle_terms(us, vs, ws, exported, n, window, offset, wanted, selected, meta) ## i64
      candidate = i64[ffw_state_size(capacity)]
      loaded = ffw_init_terms_cap(candidate, us, vs, ws, exported, n, capacity, 99173 + epoch + n * 100, 0, 1, 1, 1) ## i64
      applied = 0 - 1 ## i64
      if found == wanted && loaded == exported
        applied = ffpa_apply_current_cycle(candidate, selected, found, meta[1], meta[2], meta[3], meta[4], meta[5])
      if applied > 0 && ffw_verify_current_exact(candidate, n) == 1
        applied_candidates += 1
        << "PARTIAL_CYCLE_APPLY tensor=" + label + " wanted=" + wanted.to_s() + " rank=" + applied.to_s() + " domain=" + meta[1].to_s() + " cycle=" + meta[2].to_s() + "," + meta[3].to_s() + "," + meta[4].to_s() + " orientation=" + meta[5].to_s()
      else
        << "PARTIAL_CYCLE_APPLY_FAIL tensor=" + label
        return 0 - 1
    epoch += 1
  << "PARTIAL_CYCLE_SUMMARY tensor=" + label + " rank=" + rank.to_s() + " windows=" + windows.to_s() + " window=" + window.to_s() + " autos=" + total_attempts.to_s() + " hit2=" + total_hit2.to_s() + " hit3=" + total_hit3.to_s() + " hit4=" + total_hit4.to_s() + " comparisons=" + total_comparisons.to_s() + " rejects=" + total_rejects.to_s() + " applied=" + applied_candidates.to_s()
  total_hit2 + total_hit3 + total_hit4

root = "benchmarks/matmul/metaflip/"
windows = 4 ## i64
arguments = argv()
if arguments.size() > 0
  windows = arguments[0].to_i()
if windows < 1
  windows = 1
if windows > 16
  windows = 16

hits5 = ffpab_run("5x5", root + "matmul_5x5_rank93_d1155_gf2.txt", 5, 32, windows) ## i64
hits7 = ffpab_run("7x7", root + "matmul_7x7_rank248_d2952_sedoglavic_gf2.txt", 7, 20, windows) ## i64
if hits5 < 0 || hits7 < 0
  exit(1)
