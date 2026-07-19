# Coupled-nullspace repaint through the missing (3,2,2) primitive 9-circuit.
#
# Let a,b,c be independent factors and let y0,y1 and z0,z1 be independent
# pairs.  Over GF(2), the following five terms equal the following four:
#
#   a       y0       (z0+z1)        b       (y0+y1) z1
#   b       y1       (z0+z1)        c       y0       z0
#   c       y1       z0             (a+b)   y1       (z0+z1)
#   (a+b)   (y0+y1)  z1             (a+c)   (y0+y1) z1
#   (a+c)   (y0+y1)  (z0+z1)
#
# The nine-term symmetric difference is a primitive tensor-zero circuit with
# factor-span signature (3,2,2).  The checked-in cardinality-nine circuit has
# signature (2,2,2), so no injective image of that template covers this move.
#
# There is also a useful nullspace interpretation.  Bucket the tensor by the
# first factor.  The two overlapping factor dependencies
#
#   a + b + (a+b) = 0,       a + c + (a+c) = 0
#
# may be repainted by two independent complementary matrices at once.  Every
# one-dependency/single-D repaint can be rank-neutral while their coupled
# choice drops a term.  This is therefore not the existing one-D dependency
# median.
#
# The scanner recognizes both the live five-term side (a direct rank drop) and
# the live four-term side (a structured +1 escape).  All six axis permutations
# are covered.  Hash lookup is only a filter; the retained relation is checked
# as an exact primitive circuit by the caller before it is applied.

use flipfleet_circuit_image_search3
use flipfleet_flatten_gauge

-> ffcdr_permutation_axis(permutation, local_axis) (i64 i64) i64
  axis = 0 ## i64
  if permutation == 0
    axis = local_axis
  if permutation == 1
    if local_axis == 0
      axis = 0
    if local_axis == 1
      axis = 2
    if local_axis == 2
      axis = 1
  if permutation == 2
    if local_axis == 0
      axis = 1
    if local_axis == 1
      axis = 0
    if local_axis == 2
      axis = 2
  if permutation == 3
    if local_axis == 0
      axis = 1
    if local_axis == 1
      axis = 2
    if local_axis == 2
      axis = 0
  if permutation == 4
    if local_axis == 0
      axis = 2
    if local_axis == 1
      axis = 0
    if local_axis == 2
      axis = 1
  if permutation == 5
    if local_axis == 0
      axis = 2
    if local_axis == 1
      axis = 1
    if local_axis == 2
      axis = 0
  axis

-> ffcdr_axis_value(us, vs, ws, position, axis) (i64[] i64[] i64[] i64 i64) i64
  value = us[position] ## i64
  if axis == 1
    value = vs[position]
  if axis == 2
    value = ws[position]
  value

-> ffcdr_local_value(us, vs, ws, position, permutation, local_axis) (i64[] i64[] i64[] i64 i64 i64) i64
  ffcdr_axis_value(us,vs,ws,position,ffcdr_permutation_axis(permutation,local_axis))

-> ffcdr_set_axis(us, vs, ws, position, axis, value) (i64[] i64[] i64[] i64 i64 i64) i64
  if axis == 0
    us[position] = value
  if axis == 1
    vs[position] = value
  if axis == 2
    ws[position] = value
  1

-> ffcdr_set_local(us, vs, ws, position, permutation, x, y, z) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  us[position] = 0
  vs[position] = 0
  ws[position] = 0
  q = ffcdr_set_axis(us,vs,ws,position,ffcdr_permutation_axis(permutation,0),x) ## i64
  q = ffcdr_set_axis(us,vs,ws,position,ffcdr_permutation_axis(permutation,1),y)
  q = ffcdr_set_axis(us,vs,ws,position,ffcdr_permutation_axis(permutation,2),z)
  q

# Fill source terms 0..4 and target terms 5..8.
-> ffcdr_fill_relation(a, b, c, y0, y1, z0, z1, permutation, us, vs, ws) (i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  if permutation < 0 || permutation > 5 || us.size() < 9 || vs.size() < 9 || ws.size() < 9
    return 0
  if ffcis3_independent(a,b,c) == 0 || y0 == 0 || y1 == 0 || y0 == y1 || z0 == 0 || z1 == 0 || z0 == z1
    return 0
  ys = y0 ^ y1 ## i64
  zs = z0 ^ z1 ## i64
  q = ffcdr_set_local(us,vs,ws,0,permutation,a,y0,zs) ## i64
  q = ffcdr_set_local(us,vs,ws,1,permutation,b,y1,zs)
  q = ffcdr_set_local(us,vs,ws,2,permutation,c,y1,z0)
  q = ffcdr_set_local(us,vs,ws,3,permutation,a ^ b,ys,z1)
  q = ffcdr_set_local(us,vs,ws,4,permutation,a ^ c,ys,zs)
  q = ffcdr_set_local(us,vs,ws,5,permutation,b,ys,z1)
  q = ffcdr_set_local(us,vs,ws,6,permutation,c,y0,z0)
  q = ffcdr_set_local(us,vs,ws,7,permutation,a ^ b,y1,zs)
  q = ffcdr_set_local(us,vs,ws,8,permutation,a ^ c,ys,z1)
  9

-> ffcdr_relation_overlap(us, vs, ws, table, relation_u, relation_v, relation_w) (i64[] i64[] i64[] i32[] i64[] i64[] i64[]) i64
  overlap = 0 ## i64
  i = 0 ## i64
  while i < 9
    if ffcis_lookup(us,vs,ws,table,relation_u[i],relation_v[i],relation_w[i]) >= 0
      overlap += 1
    i += 1
  overlap

-> ffcdr_relation_density_delta(us, vs, ws, table, relation_u, relation_v, relation_w) (i64[] i64[] i64[] i32[] i64[] i64[] i64[]) i64
  delta = 0 ## i64
  i = 0 ## i64
  while i < 9
    term_density = ffw_popcount(relation_u[i]) + ffw_popcount(relation_v[i]) + ffw_popcount(relation_w[i]) ## i64
    if ffcis_lookup(us,vs,ws,table,relation_u[i],relation_v[i],relation_w[i]) >= 0
      delta -= term_density
    else
      delta += term_density
    i += 1
  delta

# Compare one relation against the current best.  stats:
#   0 candidates, 1 forward patterns, 2 reverse patterns, 3 best overlap,
#   4 best rank delta, 5 best density delta, 6 best permutation,
#   7 retained direction (0 forward, 1 reverse), 8 primitive exact gate.
-> ffcdr_consider(us, vs, ws, table, relation_u, relation_v, relation_w, permutation, direction, best_u, best_v, best_w, stats) (i64[] i64[] i64[] i32[] i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  stats[0] = stats[0] + 1
  if direction == 0
    stats[1] = stats[1] + 1
  else
    stats[2] = stats[2] + 1
  overlap = ffcdr_relation_overlap(us,vs,ws,table,relation_u,relation_v,relation_w) ## i64
  delta = 9 - 2 * overlap ## i64
  density_delta = ffcdr_relation_density_delta(us,vs,ws,table,relation_u,relation_v,relation_w) ## i64
  better = 0 ## i64
  if stats[3] < 0 || delta < stats[4] || (delta == stats[4] && density_delta < stats[5])
    better = 1
  if better == 1
    i = 0 ## i64
    while i < 9
      best_u[i] = relation_u[i]
      best_v[i] = relation_v[i]
      best_w[i] = relation_w[i]
      i += 1
    stats[3] = overlap
    stats[4] = delta
    stats[5] = density_delta
    stats[6] = permutation
    stats[7] = direction
  better

-> ffcdr_distinct5(a, b, c, d, e) (i64 i64 i64 i64 i64) i64
  if a == b || a == c || a == d || a == e || b == c || b == d || b == e || c == d || c == e || d == e
    return 0
  1

-> ffcdr_distinct4(a, b, c, d) (i64 i64 i64 i64) i64
  if a == b || a == c || a == d || b == c || b == d || c == d
    return 0
  1

# Enumerate the chain presentation of the five-term side.
-> ffcdr_scan_forward(us, vs, ws, rank, table, best_u, best_v, best_w, stats) (i64[] i64[] i64[] i64 i32[] i64[] i64[] i64[] i64[]) i64
  before = stats[1] ## i64
  relation_u = i64[9]
  relation_v = i64[9]
  relation_w = i64[9]
  permutation = 0 ## i64
  while permutation < 6
    i = 0 ## i64
    while i < rank
      a = ffcdr_local_value(us,vs,ws,i,permutation,0) ## i64
      y0 = ffcdr_local_value(us,vs,ws,i,permutation,1) ## i64
      zs = ffcdr_local_value(us,vs,ws,i,permutation,2) ## i64
      j = 0 ## i64
      while j < rank
        if j != i && ffcdr_local_value(us,vs,ws,j,permutation,2) == zs
          b = ffcdr_local_value(us,vs,ws,j,permutation,0) ## i64
          y1 = ffcdr_local_value(us,vs,ws,j,permutation,1) ## i64
          if y1 != y0
            k = 0 ## i64
            while k < rank
              if k != i && k != j && ffcdr_local_value(us,vs,ws,k,permutation,1) == y1
                c = ffcdr_local_value(us,vs,ws,k,permutation,0) ## i64
                z0 = ffcdr_local_value(us,vs,ws,k,permutation,2) ## i64
                z1 = zs ^ z0 ## i64
                if ffcdr_fill_relation(a,b,c,y0,y1,z0,z1,permutation,relation_u,relation_v,relation_w) == 9
                  p3 = ffcis_lookup(us,vs,ws,table,relation_u[3],relation_v[3],relation_w[3]) ## i64
                  p4 = ffcis_lookup(us,vs,ws,table,relation_u[4],relation_v[4],relation_w[4]) ## i64
                  if p3 >= 0 && p4 >= 0 && ffcdr_distinct5(i,j,k,p3,p4) == 1
                    q = ffcdr_consider(us,vs,ws,table,relation_u,relation_v,relation_w,permutation,0,best_u,best_v,best_w,stats) ## i64
              k += 1
        j += 1
      i += 1
    permutation += 1
  stats[1] - before

# Enumerate the four-term side.  q0 and q3 share their final two factors;
# q1 then determines q2 and all latent parameters.
-> ffcdr_scan_reverse(us, vs, ws, rank, table, best_u, best_v, best_w, stats) (i64[] i64[] i64[] i64 i32[] i64[] i64[] i64[] i64[]) i64
  before = stats[2] ## i64
  relation_u = i64[9]
  relation_v = i64[9]
  relation_w = i64[9]
  permutation = 0 ## i64
  while permutation < 6
    q0 = 0 ## i64
    while q0 < rank
      b = ffcdr_local_value(us,vs,ws,q0,permutation,0) ## i64
      ys = ffcdr_local_value(us,vs,ws,q0,permutation,1) ## i64
      z1 = ffcdr_local_value(us,vs,ws,q0,permutation,2) ## i64
      q3 = 0 ## i64
      while q3 < rank
        if q3 != q0 && ffcdr_local_value(us,vs,ws,q3,permutation,1) == ys && ffcdr_local_value(us,vs,ws,q3,permutation,2) == z1
          ac = ffcdr_local_value(us,vs,ws,q3,permutation,0) ## i64
          q1 = 0 ## i64
          while q1 < rank
            if q1 != q0 && q1 != q3
              c = ffcdr_local_value(us,vs,ws,q1,permutation,0) ## i64
              y0 = ffcdr_local_value(us,vs,ws,q1,permutation,1) ## i64
              z0 = ffcdr_local_value(us,vs,ws,q1,permutation,2) ## i64
              a = ac ^ c ## i64
              y1 = ys ^ y0 ## i64
              if ffcdr_fill_relation(a,b,c,y0,y1,z0,z1,permutation,relation_u,relation_v,relation_w) == 9
                q2 = ffcis_lookup(us,vs,ws,table,relation_u[7],relation_v[7],relation_w[7]) ## i64
                if q2 >= 0 && ffcdr_distinct4(q0,q1,q2,q3) == 1
                  q = ffcdr_consider(us,vs,ws,table,relation_u,relation_v,relation_w,permutation,1,best_u,best_v,best_w,stats) ## i64
            q1 += 1
        q3 += 1
      q0 += 1
    permutation += 1
  stats[2] - before

# Return the retained nine-term circuit, or zero when neither side occurs.
-> ffcdr_scan(us, vs, ws, rank, include_reverse, best_u, best_v, best_w, stats) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  if rank < 4 || include_reverse < 0 || include_reverse > 1 || best_u.size() < 9 || best_v.size() < 9 || best_w.size() < 9 || stats.size() < 9
    return 0
  i = 0 ## i64
  while i < 9
    stats[i] = 0
    i += 1
  stats[3] = 0 - 1
  stats[4] = 1 << 30
  stats[5] = 1 << 30
  capacity = ffcis_table_capacity(rank) ## i64
  table = i32[capacity]
  q = ffcis_build_table(us,vs,ws,rank,table) ## i64
  q = ffcdr_scan_forward(us,vs,ws,rank,table,best_u,best_v,best_w,stats)
  if include_reverse == 1
    q = ffcdr_scan_reverse(us,vs,ws,rank,table,best_u,best_v,best_w,stats)
  if stats[3] < 0
    return 0
  stats[8] = ffc_is_primitive_circuit(best_u,best_v,best_w,9)
  if stats[8] != 1
    return 0
  9

# Fit a two-dimensional source axis to three live destinations.  The anchor
# bank guarantees that the three source values span both coordinates.  Trying
# all three source pairs handles the case where the first pair is equal.
-> ffcdr_fit_axis2_three(s0, s1, s2, d0, d1, d2, maps, offset) (i64 i64 i64 i64 i64 i64 i64[] i64) i64
  if s0 < 1 || s0 > 3 || s1 < 1 || s1 > 3 || s2 < 1 || s2 > 3 || d0 == 0 || d1 == 0 || d2 == 0
    return 0
  attempt = 0 ## i64
  while attempt < 3
    ok = 0 ## i64
    if attempt == 0
      ok = ffcis_fit_axis2(s0,s1,d0,d1,maps,offset)
    if attempt == 1
      ok = ffcis_fit_axis2(s0,s2,d0,d2,maps,offset)
    if attempt == 2
      ok = ffcis_fit_axis2(s1,s2,d1,d2,maps,offset)
    if ok == 1
      if maps[offset] != 0 && maps[offset + 1] != 0 && maps[offset] != maps[offset + 1]
        if ffc_apply_linear_map(s0,maps,offset,2) == d0 && ffc_apply_linear_map(s1,maps,offset,2) == d1 && ffc_apply_linear_map(s2,maps,offset,2) == d2
          return 1
    attempt += 1
  0

-> ffcdr_axis2_spans(a, b, c) (i64 i64 i64) i64
  if a < 1 || a > 3 || b < 1 || b > 3 || c < 1 || c > 3
    return 0
  if a != b || a != c
    return 1
  0

-> ffcdr_build_anchor_bank(template_u, template_v, template_w, anchor0s, anchor1s, anchor2s) (i64[] i64[] i64[] i64[] i64[] i64[]) i64
  count = 0 ## i64
  a = 0 ## i64
  while a < 7
    b = a + 1 ## i64
    while b < 8
      c = b + 1 ## i64
      while c < 9
        if ffcis3_independent(template_u[a],template_u[b],template_u[c]) == 1
          if ffcdr_axis2_spans(template_v[a],template_v[b],template_v[c]) == 1 && ffcdr_axis2_spans(template_w[a],template_w[b],template_w[c]) == 1
            if count < anchor0s.size() && count < anchor1s.size() && count < anchor2s.size()
              anchor0s[count] = a
              anchor1s[count] = b
              anchor2s[count] = c
              count += 1
        c += 1
      b += 1
    a += 1
  count

# Bounded mixed-span image fitting.  Unlike the direct recognizer above, this
# needs only three live anchors.  A fitted circuit therefore starts at debt
# +3, but an incidental fourth overlap makes it a structured +1 escape and a
# fifth overlap is an immediate drop.
#
# meta: 0 anchors, 1 live triples, 2 fits, 3 consistent injective fits,
# 4 circuits scored, 5 overlap-three, 6 overlap-four, 7 overlap-five-or-more,
# 8 best overlap, 9 best rank delta, 10 best density delta,
# 11 best axis permutation, 12 cap reached, 13 primitive exact gate.
-> ffcdr_fit_search(us, vs, ws, rank, fit_cap, nonce, best_u, best_v, best_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if rank < 3 || fit_cap < 0 || nonce < 0 || best_u.size() < 9 || best_v.size() < 9 || best_w.size() < 9 || meta.size() < 14
    return 0
  i = 0 ## i64
  while i < 14
    meta[i] = 0
    i += 1
  meta[8] = 0 - 1
  meta[9] = 1 << 30
  meta[10] = 1 << 30
  template_u = i64[9]
  template_v = i64[9]
  template_w = i64[9]
  if ffcdr_fill_relation(1,2,4,1,2,1,2,0,template_u,template_v,template_w) != 9
    return 0
  anchor0s = i64[84]
  anchor1s = i64[84]
  anchor2s = i64[84]
  anchor_count = ffcdr_build_anchor_bank(template_u,template_v,template_w,anchor0s,anchor1s,anchor2s) ## i64
  meta[0] = anchor_count
  if anchor_count < 1
    return 0
  table_capacity = ffcis_table_capacity(rank) ## i64
  table = i32[table_capacity]
  q = ffcis_build_table(us,vs,ws,rank,table) ## i64
  maps = i64[9]
  candidate_u = i64[9]
  candidate_v = i64[9]
  candidate_w = i64[9]
  rotation = nonce % rank ## i64
  anchor_rotation = nonce % anchor_count ## i64
  stop = 0 ## i64
  raw0 = 0 ## i64
  while raw0 < rank - 2 && stop == 0
    raw1 = raw0 + 1 ## i64
    while raw1 < rank - 1 && stop == 0
      raw2 = raw1 + 1 ## i64
      while raw2 < rank && stop == 0
        live_a = (raw0 + rotation) % rank ## i64
        live_b = (raw1 + rotation) % rank ## i64
        live_c = (raw2 + rotation) % rank ## i64
        meta[1] = meta[1] + 1
        permutation = 0 ## i64
        while permutation < 6 && stop == 0
          if ffcis3_independent(ffcdr_local_value(us,vs,ws,live_a,permutation,0),ffcdr_local_value(us,vs,ws,live_b,permutation,0),ffcdr_local_value(us,vs,ws,live_c,permutation,0)) == 1
            anchor_raw = 0 ## i64
            while anchor_raw < anchor_count && stop == 0
              anchor = (anchor_raw + anchor_rotation) % anchor_count ## i64
              a0 = anchor0s[anchor] ## i64
              a1 = anchor1s[anchor] ## i64
              a2 = anchor2s[anchor] ## i64
              assignment = 0 ## i64
              while assignment < 6 && stop == 0
                if fit_cap > 0 && meta[2] >= fit_cap
                  meta[12] = 1
                  stop = 1
                if stop == 0
                  l0 = ffcis3_permute(assignment,0,live_a,live_b,live_c) ## i64
                  l1 = ffcis3_permute(assignment,1,live_a,live_b,live_c) ## i64
                  l2 = ffcis3_permute(assignment,2,live_a,live_b,live_c) ## i64
                  meta[2] = meta[2] + 1
                  ok = ffcis3_fit_axis(template_u[a0],template_u[a1],template_u[a2],ffcdr_local_value(us,vs,ws,l0,permutation,0),ffcdr_local_value(us,vs,ws,l1,permutation,0),ffcdr_local_value(us,vs,ws,l2,permutation,0),maps,0) ## i64
                  if ok == 1
                    ok = ffcdr_fit_axis2_three(template_v[a0],template_v[a1],template_v[a2],ffcdr_local_value(us,vs,ws,l0,permutation,1),ffcdr_local_value(us,vs,ws,l1,permutation,1),ffcdr_local_value(us,vs,ws,l2,permutation,1),maps,3)
                  if ok == 1
                    ok = ffcdr_fit_axis2_three(template_w[a0],template_w[a1],template_w[a2],ffcdr_local_value(us,vs,ws,l0,permutation,2),ffcdr_local_value(us,vs,ws,l1,permutation,2),ffcdr_local_value(us,vs,ws,l2,permutation,2),maps,6)
                  if ok == 1
                    meta[3] = meta[3] + 1
                    term = 0 ## i64
                    while term < 9
                      x = ffc_apply_linear_map(template_u[term],maps,0,3) ## i64
                      y = ffc_apply_linear_map(template_v[term],maps,3,2) ## i64
                      z = ffc_apply_linear_map(template_w[term],maps,6,2) ## i64
                      q = ffcdr_set_local(candidate_u,candidate_v,candidate_w,term,permutation,x,y,z)
                      term += 1
                    overlap = ffcdr_relation_overlap(us,vs,ws,table,candidate_u,candidate_v,candidate_w) ## i64
                    delta = 9 - 2 * overlap ## i64
                    density_delta = ffcdr_relation_density_delta(us,vs,ws,table,candidate_u,candidate_v,candidate_w) ## i64
                    meta[4] = meta[4] + 1
                    if overlap == 3
                      meta[5] = meta[5] + 1
                    if overlap == 4
                      meta[6] = meta[6] + 1
                    if overlap >= 5
                      meta[7] = meta[7] + 1
                    if meta[8] < 0 || delta < meta[9] || (delta == meta[9] && density_delta < meta[10])
                      term = 0
                      while term < 9
                        best_u[term] = candidate_u[term]
                        best_v[term] = candidate_v[term]
                        best_w[term] = candidate_w[term]
                        term += 1
                      meta[8] = overlap
                      meta[9] = delta
                      meta[10] = density_delta
                      meta[11] = permutation
                assignment += 1
              anchor_raw += 1
          permutation += 1
        raw2 += 1
      raw1 += 1
    raw0 += 1
  if meta[8] < 0
    return 0
  meta[13] = ffc_is_primitive_circuit(best_u,best_v,best_w,9)
  if meta[13] != 1
    return 0
  9
