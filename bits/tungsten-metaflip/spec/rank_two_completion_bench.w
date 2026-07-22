# Bounded real-record screen for exact rank-at-most-two completion.  The two
# candidate policies match rank_one_completion_bench: deterministic live-term
# pools and algebraically generated exact-flip pools.

use ../lib/metaflip/strategies/rank_two_completion

-> ffroc2b_has(values, count, value) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if values[i] == value
      return 1
    i += 1
  0

-> ffroc2b_fill_positions(rank, count, start, stride, positions) (i64 i64 i64 i64 i64[]) i64
  chosen = 0 ## i64
  cursor = start % rank ## i64
  if cursor < 0
    cursor += rank
  while chosen < count
    while ffroc2b_has(positions,chosen,cursor) != 0
      cursor = (cursor + 1) % rank
    positions[chosen] = cursor
    chosen += 1
    cursor = (cursor + stride) % rank
  chosen

-> ffroc2b_choose(n, k) (i64 i64) i64
  if k < 0 || k > n
    return 0
  kk = k ## i64
  if kk > n - kk
    kk = n - kk
  result = 1 ## i64
  i = 1 ## i64
  while i <= kk
    result = (result * (n-kk+i)) / i
    i += 1
  result

-> ffroc2b_add(pool_u, pool_v, pool_w, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if u <= 0 || v <= 0 || w <= 0
    return count
  i = 0 ## i64
  while i < count
    if pool_u[i] == u && pool_v[i] == v && pool_w[i] == w
      return count
    i += 1
  if count < capacity
    pool_u[count] = u
    pool_v[count] = v
    pool_w[count] = w
    return count + 1
  count

-> ffroc2b_flip_pool(us, vs, ws, rank, selected, k, pool_count, nonce, pool_u, pool_v, pool_w) (i64[] i64[] i64[] i64 i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  count = 0 ## i64
  anchor_index = 0 ## i64
  while anchor_index < k && count < pool_count
    left = selected[anchor_index] ## i64
    step = 0 ## i64
    while step < rank && count < pool_count
      right = (nonce*17 + step*11 + anchor_index*5) % rank ## i64
      if right != left
        if us[left] == us[right]
          count = ffroc2b_add(pool_u,pool_v,pool_w,count,pool_count,us[left],vs[left],ws[left]^ws[right])
          count = ffroc2b_add(pool_u,pool_v,pool_w,count,pool_count,us[left],vs[left]^vs[right],ws[right])
        if vs[left] == vs[right]
          count = ffroc2b_add(pool_u,pool_v,pool_w,count,pool_count,us[left],vs[left],ws[left]^ws[right])
          count = ffroc2b_add(pool_u,pool_v,pool_w,count,pool_count,us[left]^us[right],vs[left],ws[right])
        if ws[left] == ws[right]
          count = ffroc2b_add(pool_u,pool_v,pool_w,count,pool_count,us[left],vs[left]^vs[right],ws[left])
          count = ffroc2b_add(pool_u,pool_v,pool_w,count,pool_count,us[left]^us[right],vs[right],ws[left])
      step += 1
    anchor_index += 1
  step = 0
  while count < pool_count && step < rank
    position = (nonce*29 + step*11 + 5) % rank ## i64
    count = ffroc2b_add(pool_u,pool_v,pool_w,count,pool_count,us[position],vs[position],ws[position])
    step += 1
  count

-> ffroc2b_case(label, path, n, k, pool_count, windows, mode) (String String i64 i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  st = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(st,path,n,capacity,92000+n,0,1,1,1) ## i64
  if rank < 1 || ffw_verify_current_exact(st,n) == 0
    << "FAIL rank-two completion bench load " + label
    exit(1)
  all_u = i64[capacity]
  all_v = i64[capacity]
  all_w = i64[capacity]
  z = ffw_export_current(st,all_u,all_v,all_w) ## i64
  positions = i64[pool_count]
  selected = i64[k]
  pool_u = i64[pool_count]
  pool_v = i64[pool_count]
  pool_w = i64[pool_count]
  out = i64[ffw_state_size(capacity)]
  meta = i64[19]
  total_tuples = 0 ## i64
  total_decompositions = 0 ## i64
  total_zero = 0 ## i64
  total_rankone = 0 ## i64
  total_ranktwo = 0 ## i64
  total_rebuilds = 0 ## i64
  total_gates = 0 ## i64
  total_hits = 0 ## i64
  expected = ffroc2b_choose(pool_count,k-3) ## i64
  started = ccall("__w_clock_ms") ## i64
  window = 0 ## i64
  while window < windows && total_hits == 0
    z = ffroc2b_fill_positions(rank,k,window*17+3,7,selected) ## i64
    if mode == 0
      z = ffroc2b_fill_positions(rank,pool_count,window*29+5,11,positions)
      i = 0 ## i64
      while i < pool_count
        pool_u[i] = all_u[positions[i]]
        pool_v[i] = all_v[positions[i]]
        pool_w[i] = all_w[positions[i]]
        i += 1
    else
      z = ffroc2b_flip_pool(all_u,all_v,all_w,rank,selected,k,pool_count,window+1,pool_u,pool_v,pool_w)
      if z != pool_count
        << "FAIL rank-two completion flip pool " + label
        exit(1)
    hit = ffroc2_search(st,selected,k,pool_u,pool_v,pool_w,pool_count,expected,out,capacity,93000+n*100+window,meta) ## i64
    total_tuples += meta[0]
    total_decompositions += meta[1]
    total_zero += meta[2]
    total_rankone += meta[3]
    total_ranktwo += meta[4]
    total_rebuilds += meta[6]
    total_gates += meta[7]
    if hit > 0
      total_hits += 1
    window += 1
  elapsed_ms = ccall("__w_clock_ms") - started ## i64
  slice_cells = total_decompositions * n*n*n*n ## i64
  << label + " rank=" + rank.to_s() + " windows=" + window.to_s() + " k=" + k.to_s() + " pool=" + pool_count.to_s() + " tuples=" + total_tuples.to_s() + " decompositions=" + total_decompositions.to_s() + " slice_cells=" + slice_cells.to_s() + " zero=" + total_zero.to_s() + " rank1=" + total_rankone.to_s() + " rank2=" + total_ranktwo.to_s() + " rebuilds=" + total_rebuilds.to_s() + " gates=" + total_gates.to_s() + " hits=" + total_hits.to_s() + " ms=" + elapsed_ms.to_s()
  total_hits

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
hits = 0 ## i64
hits += ffroc2b_case("3x3/live",root+"matmul_3x3_rank23_d139_gf2.txt",3,5,12,64,0)
hits += ffroc2b_case("4x4/live",root+"matmul_4x4_rank47_d450_gf2.txt",4,6,13,64,0)
hits += ffroc2b_case("5x5/live",root+"matmul_5x5_rank93_d1155_gf2.txt",5,7,14,64,0)
hits += ffroc2b_case("6x6/live",root+"matmul_6x6_rank153_d2502_gf2.txt",6,8,15,64,0)
hits += ffroc2b_case("7x7/live",root+"matmul_7x7_rank247_d3094_three_flip_density_gf2.txt",7,9,16,64,0)
hits += ffroc2b_case("3x3/flip",root+"matmul_3x3_rank23_d139_gf2.txt",3,5,12,64,1)
hits += ffroc2b_case("4x4/flip",root+"matmul_4x4_rank47_d450_gf2.txt",4,6,13,64,1)
hits += ffroc2b_case("5x5/flip",root+"matmul_5x5_rank93_d1155_gf2.txt",5,7,14,64,1)
hits += ffroc2b_case("6x6/flip",root+"matmul_6x6_rank153_d2502_gf2.txt",6,8,15,64,1)
hits += ffroc2b_case("7x7/flip",root+"matmul_7x7_rank247_d3094_three_flip_density_gf2.txt",7,9,16,64,1)
<< "DONE rank-two completion bounded-record-screen hits=" + hits.to_s()
