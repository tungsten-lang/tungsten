# Exhaustive reduced length-three physical-index word audit.  Exact small
# integer matrices quotient duplicate group elements; a hash selects the
# probe chain, but every matching hash is resolved by full matrix comparison.
# Every selected tensor endpoint is additionally checked by complete integer
# reconstruction.

use flipfleet_ternary_index_word3

-> fftiw3a_decode(n,id,out) (i64 i64 i64[]) i64
  out[2] = 0 - 1
  if (id & 1) != 0
    out[2] = 1
  pair = id / 2 ## i64
  out[0] = pair / n
  out[1] = pair % n
  1

-> fftiw3a_matrix_same(matrix,store,offset,width) (i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < width
    if matrix[i] != store[offset+i]
      return 0
    i += 1
  1

-> fftiw3a_table_insert(table,index_table,mask,fingerprint,matrix,store,width,used) (i64[] i64[] i64 i64 i64[] i64[] i64 i64) i64
  key = fingerprint + 1 ## i64
  slot = fft_mix63(fingerprint) & mask ## i64
  probes = 0 ## i64
  while table[slot] != 0 && probes <= mask
    if table[slot] == key
      entry = index_table[slot] - 1 ## i64
      if fftiw3a_matrix_same(matrix,store,entry*width,width) != 0
        return 0
    slot = (slot + 1) & mask
    probes += 1
  if probes > mask
    return 0 - 1
  table[slot] = key
  index_table[slot] = used + 1
  i = 0 ## i64
  while i < width
    store[used*width+i] = matrix[i]
    i += 1
  1

-> fftiw3a_table_contains(table,index_table,mask,fingerprint,matrix,store,width) (i64[] i64[] i64 i64 i64[] i64[] i64) i64
  key = fingerprint + 1 ## i64
  slot = fft_mix63(fingerprint) & mask ## i64
  probes = 0 ## i64
  while table[slot] != 0 && probes <= mask
    if table[slot] == key
      entry = index_table[slot] - 1 ## i64
      if fftiw3a_matrix_same(matrix,store,entry*width,width) != 0
        return 1
    slot = (slot + 1) & mask
    probes += 1
  0

# Telemetry key for the exact small integer matrix P represented by a word.
# This only removes duplicate spellings before endpoint evaluation; exactness
# and promotion never rely on the key.
-> fftiw3a_matrix_key(n,d1,s1,c1,d2,s2,c2,d3,s3,c3,matrix) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  i = 0 ## i64
  while i < n*n
    matrix[i] = 0
    i += 1
  i = 0
  while i < n
    matrix[i*n+i] = 1
    i += 1
  if c1 >= 0
    c1 = 1
  else
    c1 = 0 - 1
  if c2 >= 0
    c2 = 1
  else
    c2 = 0 - 1
  if c3 >= 0
    c3 = 1
  else
    c3 = 0 - 1
  column = 0 ## i64
  while column < n
    matrix[d1*n+column] += c1 * matrix[s1*n+column]
    column += 1
  column = 0
  while column < n
    matrix[d2*n+column] += c2 * matrix[s2*n+column]
    column += 1
  column = 0
  while column < n
    matrix[d3*n+column] += c3 * matrix[s3*n+column]
    column += 1
  hash = 32416190071 ## i64
  i = 0
  while i < n*n
    hash = fft_mix63(hash ^ ((matrix[i] + 5) * (1099511628211 + 104729*i)))
    i += 1
  hash

-> fftiw3a_matrix_key2(n,d1,s1,c1,d2,s2,c2,matrix) (i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  i = 0 ## i64
  while i < n*n
    matrix[i] = 0
    i += 1
  i = 0
  while i < n
    matrix[i*n+i] = 1
    i += 1
  if c1 >= 0
    c1 = 1
  else
    c1 = 0 - 1
  if c2 >= 0
    c2 = 1
  else
    c2 = 0 - 1
  column = 0 ## i64
  while column < n
    matrix[d1*n+column] += c1 * matrix[s1*n+column]
    column += 1
  column = 0
  while column < n
    matrix[d2*n+column] += c2 * matrix[s2*n+column]
    column += 1
  hash = 32416190071 ## i64
  i = 0
  while i < n*n
    hash = fft_mix63(hash ^ ((matrix[i] + 5) * (1099511628211 + 104729*i)))
    i += 1
  hash

# Read-only final-strict/barrier evaluation.  This avoids committing,
# canonicalizing, and exactly inverting the entire state for every enumerated
# word.  meta: [0] legal final, [1] forward prefix barrier,
# [2] inverse prefix barrier, [3] exact density delta, [4] inverse mismatch.
-> fftiw3a_evaluate(st,physical,d1,s1,c1,d2,s2,c2,d3,s3,c3,meta) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  i = 0 ## i64
  while i < 5
    meta[i] = 0
    i += 1
  values = i64[7]
  side = 0 ## i64
  while side < 2
    z = fft_index_shear_spec(st,physical,side,d1,s1) ## i64
    factor = st[60] ## i64
    orientation = st[61] ## i64
    to1 = st[62] ## i64
    from1 = st[63] ## i64
    z = fft_index_shear_spec(st,physical,side,d2,s2)
    to2 = st[62]
    from2 = st[63]
    z = fft_index_shear_spec(st,physical,side,d3,s3)
    to3 = st[62]
    from3 = st[63]
    side_c1 = c1 ## i64
    side_c2 = c2 ## i64
    side_c3 = c3 ## i64
    if side == 1
      side_c1 = 0 - c1
      side_c2 = 0 - c2
      side_c3 = 0 - c3
    base = 32 + 2*factor ## i64
    slot = 0 ## i64
    while slot < st[5]
      positive = st[st[base]+slot] ## i64
      negative = st[st[base+1]+slot] ## i64
      ok = fftiw3_vector(st,positive,negative,orientation,to1,from1,side_c1,to2,from2,side_c2,to3,from3,side_c3,values) ## i64
      if ok == 0 || (st[44] | st[45]) == 0
        return 0
      if st[46] != 0
        meta[1] = 1
      output_positive = st[44] ## i64
      output_negative = st[45] ## i64
      meta[3] += fft_popcount(output_positive | output_negative) - fft_popcount(positive | negative)
      ok = fftiw3_vector(st,output_positive,output_negative,orientation,to3,from3,0-side_c3,to2,from2,0-side_c2,to1,from1,0-side_c1,values)
      if ok == 0 || st[44] != positive || st[45] != negative
        meta[4] = 1
        return 0 - 1
      if st[46] != 0
        meta[2] = 1
      slot += 1
    side += 1
  meta[0] = 1
  1

-> fftiw3a_pow3(n) (i64) i64
  value = 1 ## i64
  i = 0 ## i64
  while i < n
    value *= 3
    i += 1
  value

# Histogram the n-coordinate row/column lines occurring in one factor view.
# A base-three digit is coefficient+1, so all-zero lines have code (3^n-1)/2.
-> fftiw3a_build_hist(st,factor,orientation,hist) (i64[] i64 i64 i64[]) i64
  limit = fftiw3a_pow3(st[2]) ## i64
  i = 0 ## i64
  while i < limit
    hist[i] = 0
    i += 1
  base = 32 + 2*factor ## i64
  slot = 0 ## i64
  while slot < st[5]
    line = 0 ## i64
    while line < st[2]
      code = 0 ## i64
      place = 1 ## i64
      coordinate = 0 ## i64
      while coordinate < st[2]
        bit = line*st[2]+coordinate ## i64
        if orientation == 0
          bit = coordinate*st[2]+line
        coefficient = fft_coefficient(st[st[base]+slot],st[st[base+1]+slot],bit) ## i64
        code += (coefficient + 1) * place
        place *= 3
        coordinate += 1
      hist[code] += 1
      line += 1
    slot += 1
  limit

# Compile one coordinate word into complete maps for all 3^n strict input
# lines.  This moves coefficient arithmetic out of the per-scheme scan.
-> fftiw3a_build_map(n,d1,s1,c1,d2,s2,c2,d3,s3,c3,valid,density_delta,barrier,inverse_barrier,values,original) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if c1 >= 0
    c1 = 1
  else
    c1 = 0 - 1
  if c2 >= 0
    c2 = 1
  else
    c2 = 0 - 1
  if c3 >= 0
    c3 = 1
  else
    c3 = 0 - 1
  limit = fftiw3a_pow3(n) ## i64
  code = 0 ## i64
  while code < limit
    value_code = code ## i64
    input_density = 0 ## i64
    i = 0 ## i64
    while i < n
      values[i] = (value_code % 3) - 1
      original[i] = values[i]
      if values[i] != 0
        input_density += 1
      value_code /= 3
      i += 1
    prefix_bad = 0 ## i64
    values[d1] += c1 * values[s1]
    i = 0
    while i < n
      if values[i] < 0 - 1 || values[i] > 1
        prefix_bad = 1
      i += 1
    values[d2] += c2 * values[s2]
    i = 0
    while i < n
      if values[i] < 0 - 1 || values[i] > 1
        prefix_bad = 1
      i += 1
    values[d3] += c3 * values[s3]
    final_ok = 1 ## i64
    output_density = 0 ## i64
    i = 0
    while i < n
      if values[i] < 0 - 1 || values[i] > 1
        final_ok = 0
      if values[i] != 0
        output_density += 1
      i += 1
    valid[code] = final_ok
    barrier[code] = prefix_bad
    density_delta[code] = output_density - input_density
    inverse_barrier[code] = 0
    if final_ok == 1
      inverse_bad = 0 ## i64
      values[d3] -= c3 * values[s3]
      i = 0
      while i < n
        if values[i] < 0 - 1 || values[i] > 1
          inverse_bad = 1
        i += 1
      values[d2] -= c2 * values[s2]
      i = 0
      while i < n
        if values[i] < 0 - 1 || values[i] > 1
          inverse_bad = 1
        i += 1
      values[d1] -= c1 * values[s1]
      i = 0
      while i < n
        if values[i] != original[i]
          return 0 - 1
        i += 1
      inverse_barrier[code] = inverse_bad
    code += 1
  limit

# Evaluate the two incident factor histograms through the compiled side maps.
# meta has the same fields as fftiw3a_evaluate.
-> fftiw3a_evaluate_hist(left_hist,right_hist,limit,left_valid,left_delta,left_barrier,left_inverse,right_valid,right_delta,right_barrier,right_inverse,meta) (i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 5
    meta[i] = 0
    i += 1
  code = 0 ## i64
  while code < limit
    left_count = left_hist[code] ## i64
    if left_count > 0
      if left_valid[code] == 0
        return 0
      meta[3] += left_count * left_delta[code]
      if left_barrier[code] != 0
        meta[1] = 1
      if left_inverse[code] != 0
        meta[2] = 1
    right_count = right_hist[code] ## i64
    if right_count > 0
      if right_valid[code] == 0
        return 0
      meta[3] += right_count * right_delta[code]
      if right_barrier[code] != 0
        meta[1] = 1
      if right_inverse[code] != 0
        meta[2] = 1
    code += 1
  meta[0] = 1
  1

-> fftiw3a_run(label,path,n,word2_floor) (String String i64 i64) i64
  started = ccall("__w_clock_ms") ## i64
  capacity = fft_default_capacity(n) ## i64
  state = i64[fft_state_size(capacity)]
  rank = fft_load_seed(state,path,n,capacity,2026072000+n,4) ## i64
  if rank < 1 || fft_current_exact_error(state) != 0
    << "WORD3_FAIL load " + label
    return 0 - 1
  source_fp = fft_current_fingerprint(state) ## i64
  source_density = state[20] ## i64
  table_capacity = 65536 ## i64
  if n == 5
    table_capacity = 262144
  if n >= 6
    table_capacity = 1048576
  table_mask = table_capacity - 1 ## i64
  word2_seen = i64[table_capacity]
  word2_index = i64[table_capacity]
  transform_seen = i64[table_capacity]
  transform_index = i64[table_capacity]
  generator_limit = 2*n*n ## i64
  offdiag_limit = 2*n*(n-1) ## i64
  matrix_width = n*n ## i64
  word2_store = i64[offdiag_limit*offdiag_limit*matrix_width]
  transform_store = i64[offdiag_limit*offdiag_limit*offdiag_limit*matrix_width]
  matrix = i64[49]
  hist_u_row = i64[729]
  hist_u_column = i64[729]
  hist_v_row = i64[729]
  hist_v_column = i64[729]
  hist_w_row = i64[729]
  hist_w_column = i64[729]
  line_limit = fftiw3a_build_hist(state,0,0,hist_u_row) ## i64
  z = fftiw3a_build_hist(state,0,1,hist_u_column)
  z = fftiw3a_build_hist(state,1,0,hist_v_row)
  z = fftiw3a_build_hist(state,1,1,hist_v_column)
  z = fftiw3a_build_hist(state,2,0,hist_w_row)
  z = fftiw3a_build_hist(state,2,1,hist_w_column)
  left_valid = i64[729]
  left_delta = i64[729]
  left_barrier = i64[729]
  left_inverse = i64[729]
  right_valid = i64[729]
  right_delta = i64[729]
  right_barrier = i64[729]
  right_inverse = i64[729]
  map_values = i64[7]
  map_original = i64[7]

  # Preload every reduced length-two group matrix.  A length-three matrix in
  # this table is an algebraically longer spelling of an already audited
  # physical-index transform, regardless of the source presentation.
  word2_unique = 0 ## i64
  g1 = 0 ## i64
  while g1 < generator_limit
    pair1 = g1 / 2 ## i64
    d1 = pair1 / n ## i64
    s1 = pair1 % n ## i64
    c1 = 0 - 1 ## i64
    if (g1 & 1) != 0
      c1 = 1
    if d1 != s1
      g2 = 0 ## i64
      while g2 < generator_limit
        pair2 = g2 / 2 ## i64
        d2 = pair2 / n ## i64
        s2 = pair2 % n ## i64
        c2 = 0 - 1 ## i64
        if (g2 & 1) != 0
          c2 = 1
        if d2 != s2
          canceled = fftiw3_inverse_pair(d1,s1,c1,d2,s2,c2) ## i64
          ordered = 1 ## i64
          if fftiw3_commute(d1,s1,d2,s2) == 1 && g1 > g2
            ordered = 0
          if canceled == 0 && ordered == 1
            key2 = fftiw3a_matrix_key2(n,d1,s1,c1,d2,s2,c2,matrix) ## i64
            added = fftiw3a_table_insert(word2_seen,word2_index,table_mask,key2,matrix,word2_store,matrix_width,word2_unique) ## i64
            if added < 0
              return 0 - 1
            word2_unique += added
        g2 += 1
    g1 += 1
  total = 0 ## i64
  reduced = 0 ## i64
  cancellation_skips = 0 ## i64
  commute_skips = 0 ## i64
  relabel_skips = 0 ## i64
  legal = 0 ## i64
  atomic = 0 ## i64
  bidirectional = 0 ## i64
  new_vs_word2 = 0 ## i64
  descent = 0 ## i64
  neutral = 0 ## i64
  uphill = 0 ## i64
  best_delta = 1000000000 ## i64
  best_word = i64[10]
  equivalent_word_skips = 0 ## i64
  unique_transforms = 0 ## i64
  screened_words = 0 ## i64
  evaluated_endpoints = 0 ## i64
  evaluation = i64[5]
  g1 = 0
  while g1 < generator_limit
    pair1 = g1 / 2
    d1 = pair1 / n
    s1 = pair1 % n
    c1 = 0 - 1
    if (g1 & 1) != 0
      c1 = 1
    if d1 != s1
      g2 = 0
      while g2 < generator_limit
        pair2 = g2 / 2
        d2 = pair2 / n
        s2 = pair2 % n
        c2 = 0 - 1
        if (g2 & 1) != 0
          c2 = 1
        if d2 != s2
          g3 = 0 ## i64
          while g3 < generator_limit
            pair3 = g3 / 2 ## i64
            d3 = pair3 / n ## i64
            s3 = pair3 % n ## i64
            c3 = 0 - 1 ## i64
            if (g3 & 1) != 0
              c3 = 1
            if d3 != s3
              total += 1
              reason = fftiw3_reduction_reason(n,d1,s1,c1,d2,s2,c2,d3,s3,c3) ## i64
              if reason == 1
                cancellation_skips += 1
              if reason == 2
                commute_skips += 1
              if reason == 3
                relabel_skips += 1
              if reason == 0
                reduced += 1
              # Screen every reduced length-three word.  Exact matrix hashes
              # quotient duplicate spellings, while the word-two table marks
              # endpoints already represented by a shallower transform.
              if reason == 0
                screened_words += 1
                matrix_key = fftiw3a_matrix_key(n,d1,s1,c1,d2,s2,c2,d3,s3,c3,matrix) ## i64
                transform_added = fftiw3a_table_insert(transform_seen,transform_index,table_mask,matrix_key,matrix,transform_store,matrix_width,unique_transforms) ## i64
                if transform_added < 0
                  return 0 - 1
                if transform_added == 0
                  equivalent_word_skips += 1
                if transform_added == 1
                  unique_transforms += 1
                  old_transform = fftiw3a_table_contains(word2_seen,word2_index,table_mask,matrix_key,matrix,word2_store,matrix_width) ## i64
                  mapped = fftiw3a_build_map(n,d1,s1,c1,d2,s2,c2,d3,s3,c3,left_valid,left_delta,left_barrier,left_inverse,map_values,map_original) ## i64
                  if mapped < 0
                    return 0 - 1
                  mapped = fftiw3a_build_map(n,s1,d1,0-c1,s2,d2,0-c2,s3,d3,0-c3,right_valid,right_delta,right_barrier,right_inverse,map_values,map_original)
                  if mapped < 0
                    return 0 - 1
                  physical = 0 ## i64
                  while physical < 3
                    evaluated_endpoints += 1
                    result = 0 ## i64
                    if physical == 0
                      result = fftiw3a_evaluate_hist(hist_u_row,hist_w_row,line_limit,left_valid,left_delta,left_barrier,left_inverse,right_valid,right_delta,right_barrier,right_inverse,evaluation)
                    if physical == 1
                      result = fftiw3a_evaluate_hist(hist_u_column,hist_v_row,line_limit,left_valid,left_delta,left_barrier,left_inverse,right_valid,right_delta,right_barrier,right_inverse,evaluation)
                    if physical == 2
                      result = fftiw3a_evaluate_hist(hist_v_column,hist_w_column,line_limit,left_valid,left_delta,left_barrier,left_inverse,right_valid,right_delta,right_barrier,right_inverse,evaluation)
                    if result < 0
                      return 0 - 1
                    if result > 0
                      legal += 1
                      if evaluation[1] != 0
                        atomic += 1
                        if evaluation[2] != 0
                          bidirectional += 1
                        if old_transform == 0
                          new_vs_word2 += 1
                        delta = evaluation[3] ## i64
                        if delta < 0
                          descent += 1
                        if delta == 0
                          neutral += 1
                        if delta > 0
                          uphill += 1
                        if old_transform == 0 && evaluation[2] != 0 && delta < best_delta
                          best_delta = delta
                          best_word[0] = physical
                          best_word[1] = d1
                          best_word[2] = s1
                          best_word[3] = c1
                          best_word[4] = d2
                          best_word[5] = s2
                          best_word[6] = c2
                          best_word[7] = d3
                          best_word[8] = s3
                          best_word[9] = c3
                    physical += 1
            g3 += 1
        g2 += 1
    g1 += 1

  exact = 1 ## i64
  if best_delta < 1000000000
    result = fftiw3_raw(state,best_word[0],best_word[1],best_word[2],best_word[3],best_word[4],best_word[5],best_word[6],best_word[7],best_word[8],best_word[9]) ## i64
    if result != 2 || fft_current_exact_error(state) != 0
      exact = 0
    inverse = fftiw3_inverse_raw(state,best_word[0],best_word[1],best_word[2],best_word[3],best_word[4],best_word[5],best_word[6],best_word[7],best_word[8],best_word[9]) ## i64
    if inverse <= 0 || state[20] != source_density || fft_current_fingerprint(state) != source_fp || fft_current_exact_error(state) != 0
      exact = 0
  found_best = 0 ## i64
  if best_delta < 1000000000
    found_best = 1
  if found_best == 0
    best_delta = 0
  lower = 0 ## i64
  if found_best != 0 && best_delta < word2_floor
    lower = 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  << "WORD3 tensor=" + label + " total=" + total.to_s() + " reduced=" + reduced.to_s() + " screened=" + screened_words.to_s() + " transforms=" + unique_transforms.to_s() + " equiv_skip=" + equivalent_word_skips.to_s() + " skip=" + cancellation_skips.to_s() + "/" + commute_skips.to_s() + "/" + relabel_skips.to_s() + " w2_transforms=" + word2_unique.to_s() + " evaluated=" + evaluated_endpoints.to_s() + " legal=" + legal.to_s() + " atomic=" + atomic.to_s() + " bidirectional=" + bidirectional.to_s() + " new_vs_w2=" + new_vs_word2.to_s() + " delta=" + descent.to_s() + "/" + neutral.to_s() + "/" + uphill.to_s() + " best_delta=" + best_delta.to_s() + " lower_than_w2=" + lower.to_s() + " best=" + best_word[0].to_s() + ":" + best_word[1].to_s() + "," + best_word[2].to_s() + "," + best_word[3].to_s() + ":" + best_word[4].to_s() + "," + best_word[5].to_s() + "," + best_word[6].to_s() + ":" + best_word[7].to_s() + "," + best_word[8].to_s() + "," + best_word[9].to_s() + " exact=" + exact.to_s() + " ms=" + elapsed.to_s()
  if exact == 0
    return 0 - 1
  best_delta

only_n = 0 ## i64
if ARGV.size() > 0
  only_n = ARGV[0].to_i()
root = "benchmarks/matmul/metaflip/"
z = 0 ## i64
if only_n == 0 || only_n == 4
  z = fftiw3a_run("4x4-r49-d432",root+"matmul_4x4_rank49_dronperminov_ternary.txt",4,72)
if z >= 0 && (only_n == 0 || only_n == 5)
  z = fftiw3a_run("5x5-r93-d967",root+"matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt",5,24)
if z >= 0 && (only_n == 0 || only_n == 6)
  z = fftiw3a_run("6x6-r153-d1931",root+"matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt",6,69)
if z < 0
  << "FAIL ternary index word3 audit"
  exit(1)
<< "PASS ternary index word3 audit"
