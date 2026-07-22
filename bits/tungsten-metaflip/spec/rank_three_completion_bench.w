# Bounded real-record screen for exact rank-at-most-three completion.  Each
# packaged square leader receives deterministic live-term pools and
# algebraically generated exact-flip pools.  This is a decision benchmark,
# not a production fleet lane.

use ../lib/metaflip/strategies/rank_three_completion

-> ffroc3b_has(values, count, value) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if values[i] == value
      return 1
    i += 1
  0

-> ffroc3b_fill_positions(rank, count, start, stride, positions) (i64 i64 i64 i64 i64[]) i64
  chosen = 0 ## i64
  cursor = start % rank ## i64
  if cursor < 0
    cursor += rank
  while chosen < count
    while ffroc3b_has(positions,chosen,cursor) != 0
      cursor = (cursor + 1) % rank
    positions[chosen] = cursor
    chosen += 1
    cursor = (cursor + stride) % rank
  chosen

-> ffroc3b_choose(n, k) (i64 i64) i64
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

-> ffroc3b_add(pool_u, pool_v, pool_w, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
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

# Exact two-for-two flip children are preferred.  Packaged live terms fill
# any remaining bounded slots so every policy has exactly pool_count unique
# nonzero triples.
-> ffroc3b_flip_pool(us, vs, ws, rank, selected, k, pool_count, nonce, pool_u, pool_v, pool_w) (i64[] i64[] i64[] i64 i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  count = 0 ## i64
  anchor_index = 0 ## i64
  while anchor_index < k && count < pool_count
    left = selected[anchor_index] ## i64
    step = 0 ## i64
    while step < rank && count < pool_count
      right = (nonce*17 + step*11 + anchor_index*5) % rank ## i64
      if right != left
        if us[left] == us[right]
          count = ffroc3b_add(pool_u,pool_v,pool_w,count,pool_count,us[left],vs[left],ws[left]^ws[right])
          count = ffroc3b_add(pool_u,pool_v,pool_w,count,pool_count,us[left],vs[left]^vs[right],ws[right])
        if vs[left] == vs[right]
          count = ffroc3b_add(pool_u,pool_v,pool_w,count,pool_count,us[left],vs[left],ws[left]^ws[right])
          count = ffroc3b_add(pool_u,pool_v,pool_w,count,pool_count,us[left]^us[right],vs[left],ws[right])
        if ws[left] == ws[right]
          count = ffroc3b_add(pool_u,pool_v,pool_w,count,pool_count,us[left],vs[left]^vs[right],ws[left])
          count = ffroc3b_add(pool_u,pool_v,pool_w,count,pool_count,us[left]^us[right],vs[right],ws[left])
      step += 1
    anchor_index += 1
  step = 0
  while count < pool_count && step < rank
    position = (nonce*29 + step*11 + 5) % rank ## i64
    count = ffroc3b_add(pool_u,pool_v,pool_w,count,pool_count,us[position],vs[position],ws[position])
    step += 1
  count

-> ffroc3b_case(label, path, n, k, pool_count, windows, mode) (String String i64 i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  st = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(st,path,n,capacity,94000+n,0,1,1,1) ## i64
  if rank < 1 || ffw_verify_current_exact(st,n) == 0
    << "FAIL rank-three completion bench load " + label
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
  meta = i64[28]
  totals = i64[15]
  expected = ffroc3b_choose(pool_count,k-4) ## i64
  started = ccall("__w_clock_ms") ## i64
  window = 0 ## i64
  while window < windows && totals[14] == 0
    z = ffroc3b_fill_positions(rank,k,window*17+3,7,selected) ## i64
    if mode == 0
      z = ffroc3b_fill_positions(rank,pool_count,window*29+5,11,positions)
      i = 0 ## i64
      while i < pool_count
        pool_u[i] = all_u[positions[i]]
        pool_v[i] = all_v[positions[i]]
        pool_w[i] = all_w[positions[i]]
        i += 1
    else
      z = ffroc3b_flip_pool(all_u,all_v,all_w,rank,selected,k,pool_count,window+1,pool_u,pool_v,pool_w)
      if z != pool_count
        << "FAIL rank-three completion flip pool " + label
        exit(1)
    hit = ffroc3_search(st,selected,k,pool_u,pool_v,pool_w,pool_count,expected,out,capacity,95000+n*100+window,meta) ## i64
    totals[0] += meta[0]
    totals[1] += meta[1]
    totals[2] += meta[2]
    totals[3] += meta[3]
    totals[4] += meta[4]
    totals[5] += meta[5]
    totals[6] += meta[6]
    totals[7] += meta[7]
    totals[8] += meta[8]
    totals[9] += meta[23]
    totals[10] += meta[24]
    totals[11] += meta[25]
    totals[12] += meta[26]
    totals[13] += meta[27]
    if hit > 0
      totals[14] += 1
    window += 1
  elapsed_ms = ccall("__w_clock_ms") - started ## i64
  << label + " rank=" + rank.to_s() + " windows=" + window.to_s() + " k=" + k.to_s() + " pool=" + pool_count.to_s() + " tuples=" + totals[0].to_s() + " classes=" + totals[2].to_s() + "/" + totals[3].to_s() + "/" + totals[4].to_s() + "/" + totals[5].to_s() + "/>3:" + totals[6].to_s() + " udim=" + totals[9].to_s() + "/" + totals[10].to_s() + "/" + totals[11].to_s() + "/" + totals[12].to_s() + "/>3:" + totals[13].to_s() + " rebuilds=" + totals[7].to_s() + " gates=" + totals[8].to_s() + " hits=" + totals[14].to_s() + " ms=" + elapsed_ms.to_s()
  totals[14]

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
hits = 0 ## i64
hits += ffroc3b_case("3x3/live",root+"matmul_3x3_rank23_d139_gf2.txt",3,6,12,32,0)
hits += ffroc3b_case("4x4/live",root+"matmul_4x4_rank47_d450_gf2.txt",4,7,13,32,0)
hits += ffroc3b_case("5x5/live",root+"matmul_5x5_rank93_d1155_gf2.txt",5,8,14,32,0)
hits += ffroc3b_case("6x6/live",root+"matmul_6x6_rank153_d2502_gf2.txt",6,9,15,32,0)
hits += ffroc3b_case("7x7/live",root+"matmul_7x7_rank247_d3094_three_flip_density_gf2.txt",7,10,16,32,0)
hits += ffroc3b_case("3x3/flip",root+"matmul_3x3_rank23_d139_gf2.txt",3,6,12,32,1)
hits += ffroc3b_case("4x4/flip",root+"matmul_4x4_rank47_d450_gf2.txt",4,7,13,32,1)
hits += ffroc3b_case("5x5/flip",root+"matmul_5x5_rank93_d1155_gf2.txt",5,8,14,32,1)
hits += ffroc3b_case("6x6/flip",root+"matmul_6x6_rank153_d2502_gf2.txt",6,9,15,32,1)
hits += ffroc3b_case("7x7/flip",root+"matmul_7x7_rank247_d3094_three_flip_density_gf2.txt",7,10,16,32,1)
<< "DONE rank-three completion bounded-record-screen hits=" + hits.to_s()
