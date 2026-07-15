# Exact affine-cube polarization circuits over GF(2).
#
# Let U(x)=u0+x1*u1+x2*u2+x3*u3, and define V(x), W(x) in
# the same way.  Summing U(x) tensor V(x) tensor W(x) over the eight
# points x in GF(2)^3 extracts the x1*x2*x3 coefficient.  Consequently
# the eight affine Segre corners equal the six direction permutations:
#
#   XOR_x U(x) tensor V(x) tensor W(x)
#     = XOR_{permutation (i,j,k)} ui tensor vj tensor wk.
#
# Their union is a fourteen-term tensor-zero circuit when the four factor
# images on every axis are independent.  Neither side contains a compatible
# pair, so the planted 8->6 exchange cannot start with an ordinary flip.  The
# search below has two bounded closures:
#
#   * discover a complete live affine cube from repeated componentwise pair
#     differences, which exposes a direct 8->6 reduction; and
#   * fit one of the two three-term permutation matchings plus a live corner,
#     which exposes +6-or-better exact shoulders even without a complete cube.
#
# This is unrelated to the C3 cubic-polarization escape and to the fixed-axis
# Fano four-bucket move.  It is deliberately move-lab only until continuation
# evidence earns a production lane.

use flipfleet_circuit_image_search3

-> ffacp_in_span3(value, a, b, c) (i64 i64 i64 i64) i64
  subset = 0 ## i64
  while subset < 8
    made = 0 ## i64
    if (subset & 1) != 0
      made = made ^ a
    if (subset & 2) != 0
      made = made ^ b
    if (subset & 4) != 0
      made = made ^ c
    if made == value
      return 1
    subset += 1
  0

-> ffacp_axis_embedding(origin, d0, d1, d2) (i64 i64 i64 i64) i64
  if ffcis3_independent(d0,d1,d2) == 0
    return 0
  if origin == 0 || ffacp_in_span3(origin,d0,d1,d2) == 1
    return 0
  1

-> ffacp_fill_circuit(u0, v0, w0, du, dv, dw, out_u, out_v, out_w) (i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if du.size() < 3 || dv.size() < 3 || dw.size() < 3 || out_u.size() < 14 || out_v.size() < 14 || out_w.size() < 14
    return 0
  if ffacp_axis_embedding(u0,du[0],du[1],du[2]) == 0
    return 0
  if ffacp_axis_embedding(v0,dv[0],dv[1],dv[2]) == 0
    return 0
  if ffacp_axis_embedding(w0,dw[0],dw[1],dw[2]) == 0
    return 0
  count = 0 ## i64
  subset = 0 ## i64
  while subset < 8
    u = u0 ## i64
    v = v0 ## i64
    w = w0 ## i64
    bit = 0 ## i64
    while bit < 3
      if ((subset >> bit) & 1) != 0
        u = u ^ du[bit]
        v = v ^ dv[bit]
        w = w ^ dw[bit]
      bit += 1
    out_u[count] = u
    out_v[count] = v
    out_w[count] = w
    count += 1
    subset += 1
  out_u[count] = du[0]
  out_v[count] = dv[1]
  out_w[count] = dw[2]
  count += 1
  out_u[count] = du[0]
  out_v[count] = dv[2]
  out_w[count] = dw[1]
  count += 1
  out_u[count] = du[1]
  out_v[count] = dv[0]
  out_w[count] = dw[2]
  count += 1
  out_u[count] = du[1]
  out_v[count] = dv[2]
  out_w[count] = dw[0]
  count += 1
  out_u[count] = du[2]
  out_v[count] = dv[0]
  out_w[count] = dw[1]
  count += 1
  out_u[count] = du[2]
  out_v[count] = dv[1]
  out_w[count] = dw[0]
  count += 1
  count

# Exact column-rank/zero-sum audit for the fourteen-term circuit.  The older
# primitive-template helper is intentionally capped at twelve columns.
# meta = [column rank, zero sum, well formed].
-> ffacp_relation_analyze(us, vs, ws, count, meta) (i64[] i64[] i64[] i64 i64[]) i64
  if meta.size() >= 3
    meta[0] = 0
    meta[1] = 0
    meta[2] = 0
  if count < 1 || count > 14 || us.size() < count || vs.size() < count || ws.size() < count
    return 0
  well = 1 ## i64
  i = 0 ## i64
  while i < count
    if us[i] == 0 || vs[i] == 0 || ws[i] == 0
      well = 0
    j = i + 1 ## i64
    while j < count
      if ffc_same_term(us[i],vs[i],ws[i],us[j],vs[j],ws[j]) == 1
        well = 0
      j += 1
    i += 1
  if well == 0
    return 0
  basis = i64[14]
  column_rank = 0 ## i64
  zero_sum = 1 ## i64
  ubits = ffc_max_width(us,count) ## i64
  vbits = ffc_max_width(vs,count) ## i64
  wbits = ffc_max_width(ws,count) ## i64
  ui = 0 ## i64
  while ui < ubits
    vi = 0 ## i64
    while vi < vbits
      wi = 0 ## i64
      while wi < wbits
        row = 0 ## i64
        term = 0 ## i64
        while term < count
          if ((us[term] >> ui) & 1) != 0 && ((vs[term] >> vi) & 1) != 0 && ((ws[term] >> wi) & 1) != 0
            row = row ^ (1 << term)
          term += 1
        if (ffw_popcount(row) & 1) != 0
          zero_sum = 0
        value = row ## i64
        pivot = count - 1 ## i64
        while pivot >= 0 && value != 0
          if ((value >> pivot) & 1) != 0
            if basis[pivot] != 0
              value = value ^ basis[pivot]
            else
              basis[pivot] = value
              column_rank += 1
              value = 0
          pivot -= 1
        wi += 1
      vi += 1
    ui += 1
  if meta.size() >= 3
    meta[0] = column_rank
    meta[1] = zero_sum
    meta[2] = well
  column_rank

-> ffacp_is_primitive(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  meta = i64[3]
  rank = ffacp_relation_analyze(us,vs,ws,count,meta) ## i64
  if count == 14 && meta[2] == 1 && meta[1] == 1 && rank == 13
    return 1
  0

# Score one analytically exact injective affine-cube image.  `best` layout:
# 0 delta, 1 density, 2 overlap, 3 source kind, 4 initialized.
-> ffacp_score(us, vs, ws, rank, table, u0, v0, w0, du, dv, dw, source_kind, source_density, out_u, out_v, out_w, best, meta) (i64[] i64[] i64[] i64 i32[] i64 i64 i64 i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  circuit_u = i64[14]
  circuit_v = i64[14]
  circuit_w = i64[14]
  count = ffacp_fill_circuit(u0,v0,w0,du,dv,dw,circuit_u,circuit_v,circuit_w) ## i64
  if count != 14
    return 0
  overlap = 0 ## i64
  density = source_density ## i64
  term = 0 ## i64
  while term < count
    bits = ffw_popcount(circuit_u[term]) + ffw_popcount(circuit_v[term]) + ffw_popcount(circuit_w[term]) ## i64
    if ffcis_lookup(us,vs,ws,table,circuit_u[term],circuit_v[term],circuit_w[term]) >= 0
      overlap += 1
      density -= bits
    else
      density += bits
    term += 1
  delta = 14 - 2 * overlap ## i64
  meta[5] = meta[5] + 1
  if delta < 0
    meta[6] = meta[6] + 1
  if delta == 0
    meta[7] = meta[7] + 1
  if delta <= 2
    meta[8] = meta[8] + 1
  if overlap > meta[12]
    meta[12] = overlap
  better = 0 ## i64
  if best[4] == 0 || delta < best[0]
    better = 1
  if best[4] == 1 && delta == best[0] && density < best[1]
    better = 1
  if best[4] == 1 && delta == best[0] && density == best[1] && overlap > best[2]
    better = 1
  if better == 1
    best[0] = delta
    best[1] = density
    best[2] = overlap
    best[3] = source_kind
    best[4] = 1
    term = 0
    while term < 14
      out_u[term] = circuit_u[term]
      out_v[term] = circuit_v[term]
      out_w[term] = circuit_w[term]
      term += 1
  1

# Bounded complete-cube and partial permutation-frame closure.
#
# frame_cap=0 visits every unordered live triple.  origin_samples controls
# deterministic live-corner samples for ordinary three-overlap frames; a
# frame with at least four live permutation terms scans every live origin.
# cube_cap=0 leaves the repeated-difference complete-cube closure unbounded.
# nonce rotates logical term labels and sampled origins.
#
# meta:
#   0 frames visited, 1 independent frames, 2 frames with correction overlap>3,
#   3 origin candidates, 4 complete-cube score calls, 5 circuits scored,
#   6 drops, 7 neutral, 8 debt<=2, 9 best delta, 10 best density,
#   11 best overlap, 12 maximum overlap, 13 pair edges,
#   14 parallel pair pairs, 15 cube layer trials, 16 complete live cubes,
#   17 retained primitive gate, 18 cap reached, 19 status,
#   20 best source kind (1 frame, 2 complete cube), 21 circuit size,
#   22 maximum correction overlap, 23 source density.
-> ffacp_search(us, vs, ws, rank, frame_cap, origin_samples, cube_cap, nonce, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if rank < 4 || us.size() < rank || vs.size() < rank || ws.size() < rank || out_u.size() < 14 || out_v.size() < 14 || out_w.size() < 14 || meta.size() < 24
    return 0
  i = 0 ## i64
  while i < 24
    meta[i] = 0
    i += 1
  if origin_samples < 1
    origin_samples = 1
  table_capacity = ffcis_table_capacity(rank) ## i64
  table = i32[table_capacity]
  ffcis_build_table(us,vs,ws,rank,table)
  source_density = ffcis_density(us,vs,ws,rank) ## i64
  meta[23] = source_density
  best = i64[5]

  # First find complete live cubes.  All unordered pairs are chained by their
  # componentwise factor difference; two parallel edges and one second-layer
  # origin determine the remaining three corners by hash lookup.
  pair_capacity = rank * (rank - 1) / 2 ## i64
  pair_table_capacity = 16 ## i64
  while pair_table_capacity < pair_capacity * 4
    pair_table_capacity *= 2
  pair_heads = i32[pair_table_capacity]
  pair_next = i32[pair_capacity]
  pair_left = i32[pair_capacity]
  pair_right = i32[pair_capacity]
  pair_du = i64[pair_capacity]
  pair_dv = i64[pair_capacity]
  pair_dw = i64[pair_capacity]
  i = 0
  while i < pair_table_capacity
    pair_heads[i] = 0
    i += 1
  pair_count = 0 ## i64
  cube_stop = 0 ## i64
  left = 0 ## i64
  while left < rank - 1 && cube_stop == 0
    right = left + 1 ## i64
    while right < rank && cube_stop == 0
      du0 = us[left] ^ us[right] ## i64
      dv0 = vs[left] ^ vs[right] ## i64
      dw0 = ws[left] ^ ws[right] ## i64
      slot = ffcis_hash(du0,dv0,dw0) & (pair_table_capacity - 1) ## i64
      entry = pair_heads[slot] ## i64
      while entry != 0 && cube_stop == 0
        previous = entry - 1 ## i64
        if pair_du[previous] == du0 && pair_dv[previous] == dv0 && pair_dw[previous] == dw0
          meta[14] = meta[14] + 1
          other = pair_left[previous] ## i64
          du1 = us[left] ^ us[other] ## i64
          dv1 = vs[left] ^ vs[other] ## i64
          dw1 = ws[left] ^ ws[other] ## i64
          if du1 != 0 && dv1 != 0 && dw1 != 0 && du1 != du0 && dv1 != dv0 && dw1 != dw0
            layer_offset = nonce % rank ## i64
            layer_step = 0 ## i64
            while layer_step < rank && cube_stop == 0
              layer = (layer_offset + layer_step) % rank ## i64
              meta[15] = meta[15] + 1
              if cube_cap > 0 && meta[15] > cube_cap
                meta[18] = 1
                cube_stop = 1
              if cube_stop == 0
                du2 = us[left] ^ us[layer] ## i64
                dv2 = vs[left] ^ vs[layer] ## i64
                dw2 = ws[left] ^ ws[layer] ## i64
                if ffcis3_independent(du0,du1,du2) == 1 && ffcis3_independent(dv0,dv1,dv2) == 1 && ffcis3_independent(dw0,dw1,dw2) == 1
                  p1 = ffcis_lookup(us,vs,ws,table,us[layer] ^ du0,vs[layer] ^ dv0,ws[layer] ^ dw0) ## i64
                  p2 = ffcis_lookup(us,vs,ws,table,us[layer] ^ du1,vs[layer] ^ dv1,ws[layer] ^ dw1) ## i64
                  p3 = ffcis_lookup(us,vs,ws,table,us[layer] ^ du0 ^ du1,vs[layer] ^ dv0 ^ dv1,ws[layer] ^ dw0 ^ dw1) ## i64
                  if p1 >= 0 && p2 >= 0 && p3 >= 0
                    dirs_u = i64[3]
                    dirs_v = i64[3]
                    dirs_w = i64[3]
                    dirs_u[0] = du0
                    dirs_u[1] = du1
                    dirs_u[2] = du2
                    dirs_v[0] = dv0
                    dirs_v[1] = dv1
                    dirs_v[2] = dv2
                    dirs_w[0] = dw0
                    dirs_w[1] = dw1
                    dirs_w[2] = dw2
                    if ffacp_axis_embedding(us[left],du0,du1,du2) == 1 && ffacp_axis_embedding(vs[left],dv0,dv1,dv2) == 1 && ffacp_axis_embedding(ws[left],dw0,dw1,dw2) == 1
                      meta[16] = meta[16] + 1
                      meta[4] = meta[4] + 1
                      z = ffacp_score(us,vs,ws,rank,table,us[left],vs[left],ws[left],dirs_u,dirs_v,dirs_w,2,source_density,out_u,out_v,out_w,best,meta) ## i64
              layer_step += 1
        entry = pair_next[previous]
      if pair_count < pair_capacity
        pair_left[pair_count] = left
        pair_right[pair_count] = right
        pair_du[pair_count] = du0
        pair_dv[pair_count] = dv0
        pair_dw[pair_count] = dw0
        pair_next[pair_count] = pair_heads[slot]
        pair_heads[slot] = pair_count + 1
        pair_count += 1
        meta[13] = pair_count
      right += 1
    left += 1

  # Fit a diagonal three-permutation matching.  Its complementary matching is
  # determined without algebra or SAT.  Structural frames with extra live
  # correction terms receive every live origin; generic frames receive a
  # deterministic bounded sample.
  frame_stop = 0 ## i64
  a = 0 ## i64
  while a < rank - 2 && frame_stop == 0
    b = a + 1 ## i64
    while b < rank - 1 && frame_stop == 0
      c = b + 1 ## i64
      while c < rank && frame_stop == 0
        meta[0] = meta[0] + 1
        if frame_cap > 0 && meta[0] > frame_cap
          meta[18] = 1
          frame_stop = 1
        if frame_stop == 0
          ia = (a + nonce) % rank ## i64
          ib = (b + nonce) % rank ## i64
          ic = (c + nonce) % rank ## i64
          if ffcis3_independent(us[ia],us[ib],us[ic]) == 1 && ffcis3_independent(vs[ia],vs[ib],vs[ic]) == 1 && ffcis3_independent(ws[ia],ws[ib],ws[ic]) == 1
            meta[1] = meta[1] + 1
            dirs_u = i64[3]
            dirs_v = i64[3]
            dirs_w = i64[3]
            dirs_u[0] = us[ia]
            dirs_u[1] = us[ib]
            dirs_u[2] = us[ic]
            dirs_v[0] = vs[ic]
            dirs_v[1] = vs[ia]
            dirs_v[2] = vs[ib]
            dirs_w[0] = ws[ib]
            dirs_w[1] = ws[ic]
            dirs_w[2] = ws[ia]
            correction_overlap = 3 ## i64
            if ffcis_lookup(us,vs,ws,table,dirs_u[0],dirs_v[2],dirs_w[1]) >= 0
              correction_overlap += 1
            if ffcis_lookup(us,vs,ws,table,dirs_u[1],dirs_v[0],dirs_w[2]) >= 0
              correction_overlap += 1
            if ffcis_lookup(us,vs,ws,table,dirs_u[2],dirs_v[1],dirs_w[0]) >= 0
              correction_overlap += 1
            if correction_overlap > meta[22]
              meta[22] = correction_overlap
            samples = origin_samples ## i64
            if correction_overlap > 3
              meta[2] = meta[2] + 1
              samples = rank
            sample = 0 ## i64
            while sample < samples
              origin = 0 ## i64
              if correction_overlap > 3
                origin = (sample + nonce) % rank
              else
                origin = (ia * 17 + ib * 31 + ic * 43 + nonce * 59 + sample * 71) % rank
              meta[3] = meta[3] + 1
              if ffacp_axis_embedding(us[origin],dirs_u[0],dirs_u[1],dirs_u[2]) == 1 && ffacp_axis_embedding(vs[origin],dirs_v[0],dirs_v[1],dirs_v[2]) == 1 && ffacp_axis_embedding(ws[origin],dirs_w[0],dirs_w[1],dirs_w[2]) == 1
                z = ffacp_score(us,vs,ws,rank,table,us[origin],vs[origin],ws[origin],dirs_u,dirs_v,dirs_w,1,source_density,out_u,out_v,out_w,best,meta)
              sample += 1
        c += 1
      b += 1
    a += 1

  if best[4] == 0
    meta[19] = 0
    return 0
  meta[9] = best[0]
  meta[10] = best[1]
  meta[11] = best[2]
  meta[20] = best[3]
  meta[21] = 14
  meta[17] = ffacp_is_primitive(out_u,out_v,out_w,14)
  if meta[17] == 0
    meta[19] = 0
    return 0
  meta[19] = 1
  14
