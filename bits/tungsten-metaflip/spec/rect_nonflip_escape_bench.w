# Rectangular audit for exact algebraic escape operators whose state-mutating
# convenience wrappers were originally written for square schemes.
#
# Every retained endpoint is spliced as a GF(2) set, rebuilt through the
# rectangular initializer, and exhaustively verified against the full
# matrix-multiplication tensor.  This file is intentionally a decision
# benchmark, not scheduler integration.

use ../lib/metaflip/rect
use ../lib/metaflip/strategies/shear
use ../lib/metaflip/strategies/low_rank_shear
use ../lib/metaflip/strategies/span_refactor
use ../lib/metaflip/strategies/flatten_gauge

-> ffreb_init_stats(stats) (i64[]) i64
  i = 0 ## i64
  while i < stats.size()
    stats[i] = 0
    i += 1
  stats[7] = 0 - 1
  stats[8] = 9223372036854775807
  1

-> ffreb_selected(selected, count, value) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if selected[i] == value
      return 1
    i += 1
  0

-> ffreb_same_term(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  if u0 == u1 && v0 == v1 && w0 == w1
    return 1
  0

-> ffreb_toggle(us, vs, ws, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return 0 - count - 1
  i = 0 ## i64
  while i < count
    if ffreb_same_term(us[i],vs[i],ws[i],u,v,w) == 1
      last = count - 1 ## i64
      us[i] = us[last]
      vs[i] = vs[last]
      ws[i] = ws[last]
      return count - 1
    i += 1
  if count >= capacity
    return 0 - count - 1
  us[count] = u
  vs[count] = v
  ws[count] = w
  count + 1

-> ffreb_splice(us, vs, ws, rank, selected, selected_count, out_u, out_v, out_w, out_count, candidate_u, candidate_v, candidate_w, capacity) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  count = 0 ## i64
  position = 0 ## i64
  while position < rank
    if ffreb_selected(selected,selected_count,position) == 0
      count = ffreb_toggle(candidate_u,candidate_v,candidate_w,count,capacity,us[position],vs[position],ws[position])
      if count < 0
        return 0
    position += 1
  i = 0 ## i64
  while i < out_count
    count = ffreb_toggle(candidate_u,candidate_v,candidate_w,count,capacity,out_u[i],out_v[i],out_w[i])
    if count < 0
      return 0
    i += 1
  count

-> ffreb_density(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < count
    density += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  density

-> ffreb_term_in(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if ffreb_same_term(us[i],vs[i],ws[i],u,v,w) == 1
      return 1
    i += 1
  0

-> ffreb_distance(lu, lv, lw, lcount, ru, rv, right_w, rcount) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  distance = 0 ## i64
  i = 0 ## i64
  while i < lcount
    if ffreb_term_in(ru,rv,right_w,rcount,lu[i],lv[i],lw[i]) == 0
      distance += 1
    i += 1
  i = 0
  while i < rcount
    if ffreb_term_in(lu,lv,lw,lcount,ru[i],rv[i],right_w[i]) == 0
      distance += 1
    i += 1
  distance

-> ffreb_fingerprint(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  fingerprint = 0 ## i64
  i = 0 ## i64
  while i < count
    fingerprint = fingerprint ^ ffw_term_zobrist(us[i],vs[i],ws[i])
    i += 1
  fingerprint

-> ffreb_copy_terms(source_u, source_v, source_w, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    out_u[i] = source_u[i]
    out_v[i] = source_v[i]
    out_w[i] = source_w[i]
    i += 1
  count

# stats: local hits, full gates, exact, changed, rank wins, density wins,
# failures, best rank, best density, max distance, unique count.
-> ffreb_consider(source_u, source_v, source_w, source_rank, source_density, candidate_u, candidate_v, candidate_w, candidate_rank, n, m, p, capacity, seed, fingerprints, stats, best_u, best_v, best_w) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  stats[1] = stats[1] + 1
  state = i64[ffr_state_size(capacity)]
  loaded = ffr_init_terms_cap(state,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,seed,4,4,250000,50000) ## i64
  if loaded != candidate_rank || ffr_verify_best_exact(state,n,m,p) != 1
    stats[6] = stats[6] + 1
    return 0
  stats[2] = stats[2] + 1
  distance = ffreb_distance(source_u,source_v,source_w,source_rank,candidate_u,candidate_v,candidate_w,candidate_rank) ## i64
  if distance == 0
    return 0
  stats[3] = stats[3] + 1
  if distance > stats[9]
    stats[9] = distance
  density = ffreb_density(candidate_u,candidate_v,candidate_w,candidate_rank) ## i64
  if candidate_rank < source_rank
    stats[4] = stats[4] + 1
  if candidate_rank == source_rank && density < source_density
    stats[5] = stats[5] + 1
  fingerprint = ffreb_fingerprint(candidate_u,candidate_v,candidate_w,candidate_rank) ## i64
  unique = 1 ## i64
  i = 0 ## i64
  while i < stats[10]
    if fingerprints[i] == fingerprint
      unique = 0
    i += 1
  if unique == 1 && stats[10] < fingerprints.size()
    fingerprints[stats[10]] = fingerprint
    stats[10] = stats[10] + 1
  if stats[7] < 0 || candidate_rank < stats[7] || (candidate_rank == stats[7] && density < stats[8])
    stats[7] = candidate_rank
    stats[8] = density
    z = ffreb_copy_terms(candidate_u,candidate_v,candidate_w,candidate_rank,best_u,best_v,best_w) ## i64
  1

-> ffreb_make_uniform(rank, nonce, count, selected) (i64 i64 i64 i64[]) i64
  if count < 1 || count > rank || selected.size() < count
    return 0
  state = (nonce + 1) * 6364136223846793005 + 1442695040888963407 ## i64
  made = 0 ## i64
  while made < count
    state = state * 6364136223846793005 + 1442695040888963407
    candidate = (state ^ (state >> 29)) & 9223372036854775807 ## i64
    candidate = candidate % rank
    if ffreb_selected(selected,made,candidate) == 0
      selected[made] = candidate
      made += 1
  made

# Greedily grows a window through shared-factor and XOR-factor adjacency.
-> ffreb_make_connected(us, vs, ws, rank, nonce, count, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  if (nonce & 1) == 0
    return ffreb_make_uniform(rank,nonce,count,selected)
  if count < 1 || count > rank || selected.size() < count
    return 0
  selected[0] = (nonce*97+13) % rank
  made = 1 ## i64
  while made < count
    best = 0 - 1 ## i64
    best_score = 0 - 1 ## i64
    offset = (nonce*53+made*17) % rank ## i64
    ci = 0 ## i64
    while ci < rank
      candidate = (offset+ci) % rank ## i64
      if ffreb_selected(selected,made,candidate) == 0
        score = 0 ## i64
        si = 0 ## i64
        while si < made
          axis = 0 ## i64
          while axis < 3
            factor = ffsm_axis_get(us,vs,ws,candidate,axis) ## i64
            if factor == ffsm_axis_get(us,vs,ws,selected[si],axis)
              score += 8
            sj = si + 1 ## i64
            while sj < made
              if factor == (ffsm_axis_get(us,vs,ws,selected[si],axis) ^ ffsm_axis_get(us,vs,ws,selected[sj],axis))
                score += 2
              sj += 1
            axis += 1
          si += 1
        if score > best_score
          best_score = score
          best = candidate
      ci += 1
    if best < 0
      return 0
    selected[made] = best
    made += 1
  made

-> ffreb_capture(us, vs, ws, selected, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    out_u[i] = us[selected[i]]
    out_v[i] = vs[selected[i]]
    out_w[i] = ws[selected[i]]
    i += 1
  count

-> ffreb_dump(path, us, vs, ws, rank) (String i64[] i64[] i64[] i64) i64
  if rank < 1
    return 0
  body = rank.to_s() + "\n"
  i = 0 ## i64
  while i < rank
    body = body + us[i].to_s() + " " + vs[i].to_s() + " " + ws[i].to_s() + "\n"
    i += 1
  z = write_file(path,body)
  rank

-> ffreb_continue(label, source_u, source_v, source_w, source_rank, door_u, door_v, door_w, door_rank, n, m, p, capacity, trials, moves) (String i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  if door_rank != source_rank
    << "RECT_ESCAPE_CONT tensor="+label+" skipped=nonneutral door-r"+door_rank.to_s()
    return 0
  control_wins = 0 ## i64
  door_wins = 0 ## i64
  ties = 0 ## i64
  control_drops = 0 ## i64
  door_drops = 0 ## i64
  trial = 0 ## i64
  while trial < trials
    seed = 700001 + trial*104729 + n*1009 + m*1013 + p*1019 ## i64
    control = i64[ffr_state_size(capacity)]
    door = i64[ffr_state_size(capacity)]
    cr = ffr_init_terms_cap(control,source_u,source_v,source_w,source_rank,n,m,p,capacity,seed,4,4,250000,50000) ## i64
    dr = ffr_init_terms_cap(door,door_u,door_v,door_w,door_rank,n,m,p,capacity,seed,4,4,250000,50000) ## i64
    if cr == source_rank && dr == door_rank
      z = ffr_walk(control,moves) ## i64
      z = ffr_walk(door,moves) ## i64
      cb = ffr_best_rank(control) ## i64
      db = ffr_best_rank(door) ## i64
      cd = ffr_best_bits(control) ## i64
      dd = ffr_best_bits(door) ## i64
      if cb < source_rank
        control_drops += 1
      if db < source_rank
        door_drops += 1
      if db < cb || (db == cb && dd < cd)
        door_wins += 1
      else
        if cb < db || (cb == db && cd < dd)
          control_wins += 1
        else
          ties += 1
    trial += 1
  << "RECT_ESCAPE_CONT tensor="+label+" trials="+trials.to_s()+" moves="+moves.to_s()+" door_wins="+door_wins.to_s()+" control_wins="+control_wins.to_s()+" ties="+ties.to_s()+" door_drops="+door_drops.to_s()+" control_drops="+control_drops.to_s()
  door_wins - control_wins

-> ffreb_print(label, family, source_rank, source_density, stats, elapsed_ms) (String String i64 i64 i64[] i64) i64
  << "RECT_ESCAPE tensor="+label+" family="+family+" local="+stats[0].to_s()+" gates="+stats[1].to_s()+" exact="+stats[2].to_s()+" changed="+stats[3].to_s()+" unique="+stats[10].to_s()+" drops="+stats[4].to_s()+" density_wins="+stats[5].to_s()+" gate_fail="+stats[6].to_s()+" source=r"+source_rank.to_s()+"/d"+source_density.to_s()+" best=r"+stats[7].to_s()+"/d"+stats[8].to_s()+" max_distance="+stats[9].to_s()+" ms="+elapsed_ms.to_s()
  1

-> ffreb_run(label, path, n, m, p) (String String i64 i64 i64) i64
  capacity = ffr_default_capacity(n,m,p) ## i64
  state = i64[ffr_state_size(capacity)]
  rank = ffr_load_scheme_cap(state,path,n,m,p,capacity,610001+n*100+m*10+p,4,4,250000,50000) ## i64
  if rank < 1 || ffr_verify_best_exact(state,n,m,p) != 1
    << "RECT_ESCAPE tensor="+label+" error=load path="+path
    return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  z = ffw_export_best(state,us,vs,ws) ## i64
  source_density = ffreb_density(us,vs,ws,rank) ## i64

  # Exhaustive triangle-shear motif audit.  Full gates are bounded because
  # local exactness is already deterministic; gates validate the adapter path.
  shear_stats = i64[11]
  z = ffreb_init_stats(shear_stats) ## i64
  shear_fingerprints = i64[32]
  shear_best_u = i64[capacity]
  shear_best_v = i64[capacity]
  shear_best_w = i64[capacity]
  start = ccall("__w_clock_ms") ## i64
  a = 0 ## i64
  while a < rank-2
    b = a+1 ## i64
    while b < rank-1
      c = b+1 ## i64
      while c < rank
        su = i64[3]
        sv = i64[3]
        sw = i64[3]
        su[0] = us[a]
        sv[0] = vs[a]
        sw[0] = ws[a]
        su[1] = us[b]
        sv[1] = vs[b]
        sw[1] = ws[b]
        su[2] = us[c]
        sv[2] = vs[c]
        sw[2] = ws[c]
        out_u = i64[3]
        out_v = i64[3]
        out_w = i64[3]
        meta = i64[2]
        made = ffsm_find_triangle_shear(su,sv,sw,out_u,out_v,out_w,meta) ## i64
        if made == 3
          shear_stats[0] = shear_stats[0] + 1
          if shear_stats[1] < 24
            selected = i64[3]
            selected[0] = a
            selected[1] = b
            selected[2] = c
            candidate_u = i64[capacity]
            candidate_v = i64[capacity]
            candidate_w = i64[capacity]
            candidate_rank = ffreb_splice(us,vs,ws,rank,selected,3,out_u,out_v,out_w,3,candidate_u,candidate_v,candidate_w,capacity) ## i64
            if candidate_rank > 0
              z = ffreb_consider(us,vs,ws,rank,source_density,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,620001+shear_stats[1],shear_fingerprints,shear_stats,shear_best_u,shear_best_v,shear_best_w)
        c += 1
      b += 1
    a += 1
  elapsed = ccall("__w_clock_ms") - start ## i64
  z = ffreb_print(label,"triangle-shear",rank,source_density,shear_stats,elapsed)
  if shear_stats[7] > 0
    dump_path = "/tmp/metaflip_rect_escape_"+label+"_triangle-shear.txt"
    z = ffreb_dump(dump_path,shear_best_u,shear_best_v,shear_best_w,shear_stats[7])
    z = ffreb_continue(label+"/triangle-shear",us,vs,ws,rank,shear_best_u,shear_best_v,shear_best_w,shear_stats[7],n,m,p,capacity,3,2000000)

  # Global low-rank shear enumerator, with pair-order offsets spread across
  # the complete pair range instead of repeatedly accepting the first door.
  low_stats = i64[11]
  z = ffreb_init_stats(low_stats)
  low_fingerprints = i64[32]
  low_best_u = i64[capacity]
  low_best_v = i64[capacity]
  low_best_w = i64[capacity]
  start = ccall("__w_clock_ms")
  pair_total = (rank*(rank-1))/2 ## i64
  pair_stride = pair_total / 16 ## i64
  pair_stride += 1
  probe = 0 ## i64
  while probe < 16
    selected = i64[4]
    out_u = i64[4]
    out_v = i64[4]
    out_w = i64[4]
    meta = i64[8]
    # The enumerator increments its one-flip skip counter before writing any
    # winning metadata.  Initialize that read-before-write slot explicitly;
    # native dynamic-array lowering does not promise zeroed boxed elements.
    mi = 0 ## i64
    while mi < meta.size()
      meta[mi] = 0
      mi += 1
    nonce = probe*pair_stride ## i64
    made = fflrs_find_pair_absorb(us,vs,ws,rank,nonce,selected,out_u,out_v,out_w,meta) ## i64
    if made == 3 || made == 4
      low_stats[0] = low_stats[0] + 1
      candidate_u = i64[capacity]
      candidate_v = i64[capacity]
      candidate_w = i64[capacity]
      candidate_rank = ffreb_splice(us,vs,ws,rank,selected,made,out_u,out_v,out_w,made,candidate_u,candidate_v,candidate_w,capacity) ## i64
      if candidate_rank > 0
        z = ffreb_consider(us,vs,ws,rank,source_density,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,630001+probe,low_fingerprints,low_stats,low_best_u,low_best_v,low_best_w)
    probe += 1
  elapsed = ccall("__w_clock_ms") - start
  z = ffreb_print(label,"low-rank-shear",rank,source_density,low_stats,elapsed)
  if low_stats[7] > 0
    dump_path = "/tmp/metaflip_rect_escape_"+label+"_low-rank-shear.txt"
    z = ffreb_dump(dump_path,low_best_u,low_best_v,low_best_w,low_stats[7])
    z = ffreb_continue(label+"/low-rank-shear",us,vs,ws,rank,low_best_u,low_best_v,low_best_w,low_stats[7],n,m,p,capacity,3,2000000)

  # Complete span refactors on matched structured/uniform samples.  The
  # rank-drop directions are always tried first; rank-neutral 3->3 follows.
  span_stats = i64[11]
  z = ffreb_init_stats(span_stats)
  span_fingerprints = i64[64]
  span_best_u = i64[capacity]
  span_best_v = i64[capacity]
  span_best_w = i64[capacity]
  start = ccall("__w_clock_ms")
  sample = 0 ## i64
  while sample < 96
    selected = i64[4]
    z = ffreb_make_connected(us,vs,ws,rank,sample,3,selected) ## i64
    su = i64[4]
    sv = i64[4]
    sw = i64[4]
    z = ffreb_capture(us,vs,ws,selected,3,su,sv,sw)
    want_index = 0 ## i64
    while want_index < 2
      want = 2 + want_index ## i64
      out_u = i64[4]
      out_v = i64[4]
      out_w = i64[4]
      meta = i64[12]
      made = ffsr_find_terms(su,sv,sw,3,want,out_u,out_v,out_w,meta) ## i64
      if made == want
        span_stats[0] = span_stats[0] + 1
        if span_stats[1] < 48
          candidate_u = i64[capacity]
          candidate_v = i64[capacity]
          candidate_w = i64[capacity]
          candidate_rank = ffreb_splice(us,vs,ws,rank,selected,3,out_u,out_v,out_w,made,candidate_u,candidate_v,candidate_w,capacity) ## i64
          if candidate_rank > 0
            z = ffreb_consider(us,vs,ws,rank,source_density,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,640001+sample*2+want_index,span_fingerprints,span_stats,span_best_u,span_best_v,span_best_w)
      want_index += 1
    sample += 1
  sample = 0
  while sample < 24
    selected = i64[4]
    z = ffreb_make_connected(us,vs,ws,rank,1000+sample,4,selected)
    su = i64[4]
    sv = i64[4]
    sw = i64[4]
    z = ffreb_capture(us,vs,ws,selected,4,su,sv,sw)
    out_u = i64[4]
    out_v = i64[4]
    out_w = i64[4]
    meta = i64[12]
    made = ffsr_find_terms(su,sv,sw,4,3,out_u,out_v,out_w,meta) ## i64
    if made == 3
      span_stats[0] = span_stats[0] + 1
      if span_stats[1] < 48
        candidate_u = i64[capacity]
        candidate_v = i64[capacity]
        candidate_w = i64[capacity]
        candidate_rank = ffreb_splice(us,vs,ws,rank,selected,4,out_u,out_v,out_w,made,candidate_u,candidate_v,candidate_w,capacity) ## i64
        if candidate_rank > 0
          z = ffreb_consider(us,vs,ws,rank,source_density,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,650001+sample,span_fingerprints,span_stats,span_best_u,span_best_v,span_best_w)
    sample += 1
  elapsed = ccall("__w_clock_ms") - start
  z = ffreb_print(label,"span-refactor",rank,source_density,span_stats,elapsed)
  if span_stats[7] > 0
    dump_path = "/tmp/metaflip_rect_escape_"+label+"_span-refactor.txt"
    z = ffreb_dump(dump_path,span_best_u,span_best_v,span_best_w,span_stats[7])
    continuation_trials = 3 ## i64
    continuation_moves = 2000000 ## i64
    if label == "4x5x7" && span_stats[7] == rank && span_stats[8] == source_density
      continuation_trials = 8
      continuation_moves = 10000000
    z = ffreb_continue(label+"/span-refactor",us,vs,ws,rank,span_best_u,span_best_v,span_best_w,span_stats[7],n,m,p,capacity,continuation_trials,continuation_moves)

  # Flattening gauge: sixteen k=6 windows, three axes, depth four.  Its beam
  # is scored with external XOR-set collisions, so locally +1/global -1 doors
  # are admitted and independently full-gated here.
  gauge_stats = i64[11]
  z = ffreb_init_stats(gauge_stats)
  gauge_fingerprints = i64[64]
  gauge_best_u = i64[capacity]
  gauge_best_v = i64[capacity]
  gauge_best_w = i64[capacity]
  start = ccall("__w_clock_ms")
  sample = 0
  while sample < 16
    selected = i64[6]
    z = ffreb_make_connected(us,vs,ws,rank,2000+sample,6,selected)
    source = i64[48]
    i = 0 ## i64
    while i < 6
      source[i*3] = us[selected[i]]
      source[i*3+1] = vs[selected[i]]
      source[i*3+2] = ws[selected[i]]
      i += 1
    external_u = i64[capacity]
    external_v = i64[capacity]
    external_w = i64[capacity]
    external_count = 0 ## i64
    position = 0 ## i64
    while position < rank
      if ffreb_selected(selected,6,position) == 0
        external_u[external_count] = us[position]
        external_v[external_count] = vs[position]
        external_w[external_count] = ws[position]
        external_count += 1
      position += 1
    axis = 0 ## i64
    while axis < 3
      config = i64[4]
      config[0] = 6
      config[1] = axis
      config[2] = 4
      config[3] = 24
      replacement = i64[768]
      meta = i64[8]
      made = ffgr_search_compact_packed(source,config,external_u,external_v,external_w,external_count,replacement,meta) ## i64
      if made > 0
        gauge_stats[0] = gauge_stats[0] + 1
        if gauge_stats[1] < 48
          out_u = i64[256]
          out_v = i64[256]
          out_w = i64[256]
          z = ffgr_unpack(replacement,made,out_u,out_v,out_w) ## i64
          candidate_u = i64[capacity]
          candidate_v = i64[capacity]
          candidate_w = i64[capacity]
          candidate_rank = ffreb_splice(us,vs,ws,rank,selected,6,out_u,out_v,out_w,made,candidate_u,candidate_v,candidate_w,capacity) ## i64
          if candidate_rank > 0
            z = ffreb_consider(us,vs,ws,rank,source_density,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,660001+sample*3+axis,gauge_fingerprints,gauge_stats,gauge_best_u,gauge_best_v,gauge_best_w)
      axis += 1
    sample += 1
  elapsed = ccall("__w_clock_ms") - start
  z = ffreb_print(label,"flatten-gauge",rank,source_density,gauge_stats,elapsed)
  if gauge_stats[7] > 0
    dump_path = "/tmp/metaflip_rect_escape_"+label+"_flatten-gauge.txt"
    z = ffreb_dump(dump_path,gauge_best_u,gauge_best_v,gauge_best_w,gauge_stats[7])
    continuation_trials = 3
    continuation_moves = 2000000
    if label == "4x5x7" && gauge_stats[7] == rank && gauge_stats[8] == source_density
      continuation_trials = 8
      continuation_moves = 10000000
    z = ffreb_continue(label+"/flatten-gauge",us,vs,ws,rank,gauge_best_u,gauge_best_v,gauge_best_w,gauge_stats[7],n,m,p,capacity,continuation_trials,continuation_moves)
  1

root = "bits/tungsten-metaflip/lib/metaflip/seeds/gf2/"
z = ffreb_run("2x5x6",root+"matmul_2x5x6_rank47_d438_orbit_door_gf2.txt",2,5,6)
z = ffreb_run("3x4x6",root+"matmul_3x4x6_rank54_d488_gl_frontier_gf2.txt",3,4,6)
z = ffreb_run("4x4x5",root+"matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt",4,4,5)
z = ffreb_run("4x5x7",root+"matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt",4,5,7)
