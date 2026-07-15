# Exhaustive length-two physical-index word audit.  Every candidate is applied
# and exactly inverted before the next candidate.  Only final-strict endpoints
# whose first elementary intermediate is illegal count as atomic tunnels.

use flipfleet_ternary_index_word2

-> fftiw2a_run(label,path,n) (String String i64) i64
  capacity = fft_default_capacity(n) ## i64
  state = i64[fft_state_size(capacity)]
  rank = fft_load_seed(state,path,n,capacity,2026071800+n,4) ## i64
  if rank < 1
    << "WORD2_FAIL load " + label
    return 0 - 1
  if fft_current_exact_error(state) != 0
    return 0 - 1
  start_density = state[20] ## i64
  probes = 0 ## i64
  legal = 0 ## i64
  atomic = 0 ## i64
  bidirectional = 0 ## i64
  changed = 0 ## i64
  neutral_atomic = 0 ## i64
  descent_atomic = 0 ## i64
  uphill_atomic = 0 ## i64
  best_delta = 1000000000 ## i64
  best_physical = 0 ## i64
  best_d1 = 0 ## i64
  best_s1 = 1 ## i64
  best_c1 = 1 ## i64
  best_d2 = 0 ## i64
  best_s2 = 1 ## i64
  best_c2 = 1 ## i64
  meta = i64[6]
  physical = 0 ## i64
  while physical < 3
    d1 = 0 ## i64
    while d1 < n
      s1 = 0 ## i64
      while s1 < n
        if d1 != s1
          c1 = 0 - 1 ## i64
          while c1 <= 1
            d2 = 0 ## i64
            while d2 < n
              s2 = 0 ## i64
              while s2 < n
                if d2 != s2
                  c2 = 0 - 1 ## i64
                  while c2 <= 1
                    result = fftiw2_probe(state,physical,d1,s1,c1,d2,s2,c2,meta) ## i64
                    probes += 1
                    if result < 0
                      return 0 - 1
                    if result > 0
                      legal += 1
                    if result == 2 && meta[3] != 0
                      atomic += 1
                      if meta[5] != 0
                        bidirectional += 1
                      delta = meta[2] ## i64
                      if delta < 0
                        descent_atomic += 1
                      if delta == 0
                        neutral_atomic += 1
                      if delta > 0
                        uphill_atomic += 1
                      if delta < best_delta
                        best_delta = delta
                        best_physical = physical
                        best_d1 = d1
                        best_s1 = s1
                        best_c1 = c1
                        best_d2 = d2
                        best_s2 = s2
                        best_c2 = c2
                    if result > 0 && meta[3] != 0
                      changed += 1
                    c2 += 2
                s2 += 1
              d2 += 1
            c1 += 2
        s1 += 1
      d1 += 1
    physical += 1

  exact = 1 ## i64
  if atomic > 0
    result = fftiw2_raw(state,best_physical,best_d1,best_s1,best_c1,best_d2,best_s2,best_c2) ## i64
    if result != 2 || fft_current_exact_error(state) != 0
      exact = 0
    inverse = fftiw2_inverse_raw(state,best_physical,best_d1,best_s1,best_c1,best_d2,best_s2,best_c2) ## i64
    if inverse <= 0 || state[20] != start_density || fft_current_exact_error(state) != 0
      exact = 0
  if best_delta == 1000000000
    best_delta = 0
  << "WORD2 tensor=" + label + " rank=" + rank.to_s() + " density=" + start_density.to_s() + " probes=" + probes.to_s() + " legal=" + legal.to_s() + " changed=" + changed.to_s() + " atomic=" + atomic.to_s() + " bidirectional=" + bidirectional.to_s() + " delta=" + descent_atomic.to_s() + "/" + neutral_atomic.to_s() + "/" + uphill_atomic.to_s() + " best_delta=" + best_delta.to_s() + " best=" + best_physical.to_s() + ":" + best_d1.to_s() + "," + best_s1.to_s() + "," + best_c1.to_s() + ":" + best_d2.to_s() + "," + best_s2.to_s() + "," + best_c2.to_s() + " exact=" + exact.to_s()
  if exact == 0
    return 0 - 1
  atomic

root = "benchmarks/matmul/metaflip/"
z = fftiw2a_run("4x4-r49-d432",root+"matmul_4x4_rank49_dronperminov_ternary.txt",4) ## i64
if z >= 0
  z = fftiw2a_run("5x5-r93-d967",root+"matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt",5)
if z >= 0
  z = fftiw2a_run("6x6-r153-d1931",root+"matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt",6)
if z < 0
  << "FAIL ternary index word2 audit"
  exit(1)
<< "PASS ternary index word2 audit"
