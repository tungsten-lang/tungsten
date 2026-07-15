# Reproducible real-frontier audit for the bounded strict-ternary signed-span
# refactor.  Each seed receives deterministic independent three-/four-term
# windows.  All three-term windows get the complete 3->2 search; the smallest
# catalogue additionally gets a fully-changed 3<->3 tunnel and an
# external-cancellation search.  The smallest four-term catalogue gets a
# complete 4->3 search when it fits the explicit 20,000-candidate cap.
#
# Usage: flipfleet_ternary_span_refactor_bench [windows-per-seed]

use flipfleet_ternary_span_refactor

-> fftsrbench_select(rank, k, nonce, selected) (i64 i64 i64 i64[]) i64
  value = (nonce + 1) * 1442695040888963407 + 6364136223846793005 ## i64
  i = 0 ## i64
  while i < k
    value = (value * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
    candidate = value % rank ## i64
    unique = 0 ## i64
    while unique == 0
      unique = 1
      j = 0 ## i64
      while j < i
        if selected[j] == candidate
          unique = 0
        j += 1
      if unique == 0
        candidate = (candidate + 1) % rank
    selected[i] = candidate
    i += 1
  1

-> fftsrbench_local_density(st, selected, count) (i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < count
    density += fft_slot_density(st,selected[i])
    i += 1
  density

-> fftsrbench_output_density(up,un,vp,vn,wp,wn,count) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < count
    density += fft_popcount(up[i] | un[i]) + fft_popcount(vp[i] | vn[i]) + fft_popcount(wp[i] | wn[i])
    i += 1
  density

-> fftsrbench_run(label,path,n,windows,seed) (String String i64 i64 i64) i64
  capacity = fft_default_capacity(n) ## i64
  state_size = fft_state_size(capacity) ## i64
  state = i64[state_size]
  rank = fft_load_seed(state,path,n,capacity,seed,3) ## i64
  if rank < 4 || fft_verify_current_exact(state) == 0
    << "TERNARY_SPAN tensor=" + label + " error=load"
    return 0 - 1

  three_workspace = FFTSRWorkspace.new(5000)
  four_workspace = FFTSRWorkspace.new(20000)
  scout = FFTSRWorkspace.new(16)
  out_up = i64[4]
  out_un = i64[4]
  out_vp = i64[4]
  out_vn = i64[4]
  out_wp = i64[4]
  out_wn = i64[4]
  sup = i64[4]
  sun = i64[4]
  svp = i64[4]
  svn = i64[4]
  swp = i64[4]
  swn = i64[4]
  meta = i64[20]
  selected3 = i64[3]
  selected4 = i64[4]
  best3 = i64[3]
  best4 = i64[4]
  best3_count = 1000000000 ## i64
  best4_count = 1000000000 ## i64
  direct_hits = 0 ## i64
  direct_exact = 0 ## i64
  direct_candidates = 0 ## i64
  direct_probes = 0 ## i64
  direct_gates = 0 ## i64
  direct_overcap = 0 ## i64
  collision_windows = 0 ## i64
  collision_hits = 0 ## i64
  collision_exact = 0 ## i64
  collision_representable = 0 ## i64
  disjoint_windows = 0 ## i64
  disjoint_hits = 0 ## i64
  disjoint_exact = 0 ## i64
  disjoint_best_delta = 1000000000 ## i64
  started = ccall("__w_clock_ms") ## i64

  sample = 0 ## i64
  while sample < windows
    z = fftsrbench_select(rank,3,seed + sample * 17,selected3) ## i64
    found = fftsr_find_current_ws(state,selected3,3,2,three_workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta) ## i64
    direct_candidates += meta[3]
    direct_probes += meta[4]
    direct_gates += meta[6]
    direct_overcap += meta[8]
    if meta[3] < best3_count
      best3_count = meta[3]
      i = 0 ## i64
      while i < 3
        best3[i] = selected3[i]
        i += 1
    if found == 2
      direct_hits += 1
      endpoint = i64[state_size]
      cloned = fft_clone_gated_seed(endpoint,state,seed + 5000 + sample,3) ## i64
      spliced = fftsr_splice_current(endpoint,selected3,3,out_up,out_un,out_vp,out_vn,out_wp,out_wn,2,0) ## i64
      if cloned == rank && spliced == rank - 1 && fft_verify_current_exact(endpoint) == 1
        direct_exact += 1
        z = fft_dump_current(endpoint,"/tmp/ternary_span_" + label + "_rank" + spliced.to_s() + ".txt") ## i64

    # External representability is much rarer than a generic local window.
    # Audit the first sixteen windows rather than only the smallest catalogue.
    if sample < 16
      collision_windows += 1
      collision = fftsr_find_collision_current_ws(state,selected3,three_workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta) ## i64
      collision_representable += meta[14]
      if collision == 3
        collision_hits += 1
        endpoint = i64[state_size]
        cloned = fft_clone_gated_seed(endpoint,state,seed + 7000 + sample,3)
        spliced = fftsr_splice_current(endpoint,selected3,3,out_up,out_un,out_vp,out_vn,out_wp,out_wn,3,1)
        if cloned == rank && spliced <= rank - 2 && fft_verify_current_exact(endpoint) == 1
          collision_exact += 1
          z = fft_dump_current(endpoint,"/tmp/ternary_span_collision_" + label + "_rank" + spliced.to_s() + ".txt")

      disjoint_windows += 1
      z = fftsr_extract_current(state,selected3,3,sup,sun,svp,svn,swp,swn) ## i64
      disjoint = fftsr_find_terms_disjoint_ws(sup,sun,svp,svn,swp,swn,n,3,3,three_workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta) ## i64
      if disjoint == 3
        disjoint_hits += 1
        source_local_density = fftsrbench_local_density(state,selected3,3) ## i64
        output_local_density = fftsrbench_output_density(out_up,out_un,out_vp,out_vn,out_wp,out_wn,3) ## i64
        delta = output_local_density - source_local_density ## i64
        if delta < disjoint_best_delta
          disjoint_best_delta = delta
        endpoint = i64[state_size]
        cloned = fft_clone_gated_seed(endpoint,state,seed + 9000 + sample,3)
        spliced = fftsr_splice_current(endpoint,selected3,3,out_up,out_un,out_vp,out_vn,out_wp,out_wn,3,0)
        if cloned == rank && spliced == rank && fft_verify_current_exact(endpoint) == 1
          disjoint_exact += 1
          if delta < 0
            z = fft_dump_current(endpoint,"/tmp/ternary_span_disjoint_" + label + "_r" + rank.to_s() + "_d" + endpoint[20].to_s() + ".txt")

    z = fftsrbench_select(rank,4,seed + sample * 29 + 7,selected4)
    ignored = fftsr_find_current_ws(state,selected4,4,3,scout,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta) ## i64
    if meta[3] < best4_count
      best4_count = meta[3]
      i = 0
      while i < 4
        best4[i] = selected4[i]
        i += 1
    sample += 1

  if disjoint_hits == 0
    disjoint_best_delta = 0

  four_searched = 0 ## i64
  four_found = 0 ## i64
  four_exact = 0 ## i64
  four_pairs = 0 ## i64
  if best4_count <= four_workspace.max_candidates()
    four_searched = 1
    four_found = fftsr_find_current_ws(state,best4,4,3,four_workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta)
    four_pairs = meta[4]
    if four_found == 3
      endpoint = i64[state_size]
      cloned = fft_clone_gated_seed(endpoint,state,seed + 8000,3)
      spliced = fftsr_splice_current(endpoint,best4,4,out_up,out_un,out_vp,out_vn,out_wp,out_wn,3,0)
      if cloned == rank && spliced == rank - 1 && fft_verify_current_exact(endpoint) == 1
        four_exact = 1
        z = fft_dump_current(endpoint,"/tmp/ternary_span4_" + label + "_rank" + spliced.to_s() + ".txt")

  elapsed = ccall("__w_clock_ms") - started ## i64
  average_candidates = direct_candidates / windows ## i64
  << "TERNARY_SPAN tensor=" + label + " rank=" + rank.to_s() + " density=" + state[21].to_s() + " windows=" + windows.to_s() + " 3cand_avg=" + average_candidates.to_s() + " 3cand_min=" + best3_count.to_s() + " 3to2=" + direct_hits.to_s() + " full=" + direct_exact.to_s() + " overcap=" + direct_overcap.to_s() + " probes=" + direct_probes.to_s() + " gates=" + direct_gates.to_s() + " disjoint_windows=" + disjoint_windows.to_s() + " disjoint3=" + disjoint_hits.to_s() + " disjoint_exact=" + disjoint_exact.to_s() + " disjoint_delta=" + disjoint_best_delta.to_s() + " collision_windows=" + collision_windows.to_s() + " collision3=" + collision_hits.to_s() + " collision_exact=" + collision_exact.to_s() + " collision_repr=" + collision_representable.to_s() + " 4cand_min=" + best4_count.to_s() + " 4searched=" + four_searched.to_s() + " 4to3=" + four_found.to_s() + " 4exact=" + four_exact.to_s() + " 4pairs=" + four_pairs.to_s() + " ms=" + elapsed.to_s()
  1

args = argv()
windows = 32 ## i64
if args.size() > 0
  windows = args[0].to_i()
if windows < 1
  windows = 1

root = "benchmarks/matmul/metaflip/"
labels = ["4x4-r49-d432","5x5-r93-d967","6x6-r153-d1931-index","6x6-r153-d1931-symmetry","7x7-r250-d2966","7x7-r250-d3069"]
paths = [
  root + "matmul_4x4_rank49_dronperminov_ternary.txt",
  root + "matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d1931_symmetry_escape_ternary.txt",
  root + "matmul_7x7_rank250_dronperminov_ternary.txt",
  root + "matmul_7x7_rank250_d3069_ternary_door.txt"
]
dimensions = [4,5,6,6,7,7]
i = 0 ## i64
while i < paths.size()
  ok = fftsrbench_run(labels[i],paths[i],dimensions[i],windows,2026071510 + i * 1000) ## i64
  if ok != 1
    exit(1)
  i += 1
