# Usage:
#   flipfleet_ternary_dependency_median_bench seed n [circuit_cap] [max_debt]
#                                               [moves] [trials]
#
# circuit_cap=0 is complete over all proper-subsum-free signed unit
# five-factor relations.
# If a changed endpoint exists, every selected endpoint receives the complete
# n^6 integer gate.  Optional matched continuations compare it with an ordinary
# exact split shoulder at the same starting rank while retaining the original
# source as each arm's durable best.

use flipfleet_ternary_dependency_median

-> fftdmb_fail(label) (String) i64
  << "TERNARY_DEPENDENCY_MEDIAN_BENCH_FAIL " + label
  exit(1)
  0

-> fftdmb_install_current(st, baseline, up, un, vp, vn, wp, wn, rank, seed, max_debt) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64) i64
  if fft_clone_gated_seed(st,baseline,seed,max_debt) != baseline[6]
    return 0
  if rank < 1 || rank > st[4]
    return 0
  st[5] = rank
  i = 0 ## i64
  while i < rank
    st[st[32]+i] = up[i]
    st[st[33]+i] = un[i]
    st[st[34]+i] = vp[i]
    st[st[35]+i] = vn[i]
    st[st[36]+i] = wp[i]
    st[st[37]+i] = wn[i]
    if fft_canonicalize_slot(st,i) != 1
      return 0
    i += 1
  st[20] = fft_current_density(st)
  fft_verify_current_exact(st)

-> fftdmb_split_to_rank(st, target_rank, salt) (i64[] i64 i64) i64
  while st[5] < target_rank
    made = 0 ## i64
    attempt = 0 ## i64
    rank = st[5] ## i64
    while attempt < rank * rank * 3 && made == 0
      target = (salt * 17 + attempt * 7) % rank ## i64
      donor = (salt * 31 + attempt * 11 + 1) % rank ## i64
      axis = (salt + attempt) % 3 ## i64
      if target != donor
        made = fft_split_with_donor(st,target,donor,axis)
      attempt += 1
    if made == 0
      return 0
  fft_verify_current_exact(st)

-> fftdmb_term_equal(left, left_term, left_best, right, right_term, right_best) (i64[] i64 i64 i64[] i64 i64) i64
  left_base = 32 ## i64
  right_base = 32 ## i64
  if left_best != 0
    left_base = 38
  if right_best != 0
    right_base = 38
  axis = 0 ## i64
  while axis < 6
    if left[left[left_base + axis] + left_term] != right[right[right_base + axis] + right_term]
      return 0
    axis += 1
  1

-> fftdmb_term_distance(left, left_rank, left_best, right, right_rank, right_best) (i64[] i64 i64 i64[] i64 i64) i64
  used = i64[right_rank]
  common = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    j = 0 ## i64
    found = 0 - 1 ## i64
    while j < right_rank && found < 0
      if used[j] == 0 && fftdmb_term_equal(left,i,left_best,right,j,right_best) == 1
        found = j
      j += 1
    if found >= 0
      used[found] = 1
      common += 1
    i += 1
  left_rank + right_rank - 2 * common

args = argv()
if args.size() < 2
  << "usage: flipfleet_ternary_dependency_median_bench seed n [circuit_cap] [max_debt] [moves] [trials]"
  exit(2)
path = args[0]
n = args[1].to_i() ## i64
circuit_cap = 0 ## i64
max_debt = 2 ## i64
moves = 0 ## i64
trials = 0 ## i64
if args.size() > 2
  circuit_cap = args[2].to_i()
if args.size() > 3
  max_debt = args[3].to_i()
if args.size() > 4
  moves = args[4].to_i()
if args.size() > 5
  trials = args[5].to_i()
if n < 2 || n > 7 || circuit_cap < 0 || max_debt < 0 || max_debt > 8 || moves < 0 || trials < 0 || trials > 32 || (moves == 0 && trials != 0) || (moves != 0 && trials == 0)
  fftdmb_fail("arguments")

capacity = fft_default_capacity(n) ## i64
state_size = fft_state_size(capacity) ## i64
source = i64[state_size]
rank = fft_load_seed(source,path,n,capacity,97501,8) ## i64
if rank < 5 || fft_verify_current_exact(source) != 1
  fftdmb_fail("source gate")
out_up = i64[capacity]
out_un = i64[capacity]
out_vp = i64[capacity]
out_vn = i64[capacity]
out_wp = i64[capacity]
out_wn = i64[capacity]
meta = i64[16]
started = ccall("__w_clock_ms") ## i64
out_rank = fftdm_search(source,circuit_cap,max_debt,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta) ## i64
search_ms = ccall("__w_clock_ms") - started ## i64
if out_rank == 0
  << "TERNARY_DEPENDENCY_MEDIAN seed=" + path + " n=" + n.to_s() + " rank=" + rank.to_s() + " density=" + meta[15].to_s() + " pairs=" + meta[0].to_s() + " triple_probes=" + meta[1].to_s() + " hash_hits=" + meta[2].to_s() + " exact_hits=" + meta[3].to_s() + " circuits=" + meta[4].to_s() + " D=" + meta[5].to_s() + " qualified=" + meta[6].to_s() + " changed=0 capped=" + meta[14].to_s() + " ms=" + search_ms.to_s()
  exit(0)

endpoint = i64[state_size]
loaded = fft_init_terms(endpoint,out_up,out_un,out_vp,out_vn,out_wp,out_wn,out_rank,n,capacity,97601,8) ## i64
if loaded != out_rank || fft_verify_current_exact(endpoint) != 1
  fftdmb_fail("endpoint full integer gate")
endpoint_distance = fftdmb_term_distance(source,rank,0,endpoint,out_rank,0) ## i64
<< "TERNARY_DEPENDENCY_MEDIAN seed=" + path + " n=" + n.to_s() + " rank=" + rank.to_s() + " density=" + meta[15].to_s() + " pairs=" + meta[0].to_s() + " triple_probes=" + meta[1].to_s() + " hash_hits=" + meta[2].to_s() + " exact_hits=" + meta[3].to_s() + " circuits=" + meta[4].to_s() + " D=" + meta[5].to_s() + " qualified=" + meta[6].to_s() + " changed=" + meta[7].to_s() + " drops=" + meta[8].to_s() + " neutral=" + meta[9].to_s() + " best=r" + out_rank.to_s() + "/d" + meta[11].to_s() + " local_delta=" + meta[12].to_s() + " term_distance=" + endpoint_distance.to_s() + " axis=" + meta[13].to_s() + " exact=1 capped=" + meta[14].to_s() + " ms=" + search_ms.to_s()

if moves > 0
  if out_rank < rank
    << "TERNARY_DEPENDENCY_MEDIAN_MATCH skipped=record_endpoint"
    exit(0)
  median_beats = 0 ## i64
  split_beats = 0 ## i64
  ties = 0 ## i64
  median_rank_wins = 0 ## i64
  median_density_wins = 0 ## i64
  split_rank_wins = 0 ## i64
  split_density_wins = 0 ## i64
  median_distance_sum = 0 ## i64
  split_distance_sum = 0 ## i64
  match_started = ccall("__w_clock_ms") ## i64
  trial = 0 ## i64
  while trial < trials
    seed = 97701 + trial * 104729 ## i64
    median = i64[state_size]
    control = i64[state_size]
    if fftdmb_install_current(median,source,out_up,out_un,out_vp,out_vn,out_wp,out_wn,out_rank,seed,8) != 1
      fftdmb_fail("median arm install")
    if fft_clone_gated_seed(control,source,seed,8) != rank || fftdmb_split_to_rank(control,out_rank,trial + 1) != 1
      fftdmb_fail("split arm install")
    z = fft_walk(median,moves) ## i64
    z = fft_walk(control,moves)
    if fft_verify_best_exact(median) != 1 || fft_verify_best_exact(control) != 1
      fftdmb_fail("continuation gate")
    median_rank = median[6] ## i64
    median_density = median[21] ## i64
    split_rank = control[6] ## i64
    split_density = control[21] ## i64
    median_distance = fftdmb_term_distance(source,rank,0,median,median_rank,1) ## i64
    split_distance = fftdmb_term_distance(source,rank,0,control,split_rank,1) ## i64
    median_distance_sum += median_distance
    split_distance_sum += split_distance
    if median_rank < rank
      median_rank_wins += 1
    if median_rank == rank && median_density < source[21]
      median_density_wins += 1
    if split_rank < rank
      split_rank_wins += 1
    if split_rank == rank && split_density < source[21]
      split_density_wins += 1
    if median_rank < split_rank || (median_rank == split_rank && median_density < split_density)
      median_beats += 1
    else
      if split_rank < median_rank || (median_rank == split_rank && split_density < median_density)
        split_beats += 1
      else
        ties += 1
    << "TERNARY_DEPENDENCY_MEDIAN_MATCH trial=" + trial.to_s() + " median=r" + median_rank.to_s() + "/d" + median_density.to_s() + "/dist" + median_distance.to_s() + " split=r" + split_rank.to_s() + "/d" + split_density.to_s() + "/dist" + split_distance.to_s()
    trial += 1
  match_ms = ccall("__w_clock_ms") - match_started ## i64
  << "TERNARY_DEPENDENCY_MEDIAN_MATCH summary=" + median_beats.to_s() + "/" + split_beats.to_s() + " ties=" + ties.to_s() + " rank_wins=" + median_rank_wins.to_s() + "/" + split_rank_wins.to_s() + " density_wins=" + median_density_wins.to_s() + "/" + split_density_wins.to_s() + " distance_avg=" + (median_distance_sum / trials).to_s() + "/" + (split_distance_sum / trials).to_s() + " trials=" + trials.to_s() + " moves=" + moves.to_s() + " aggregate=" + (trials * moves * 2).to_s() + " ms=" + match_ms.to_s()
