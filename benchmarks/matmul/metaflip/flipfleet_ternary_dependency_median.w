# Exact signed five-factor dependency medians over Z.
#
# Let five selected terms be written along one tensor axis as
#
#     f_i tensor M_i,
#
# and suppose their actual signed axis factors obey the primitive relation
#
#     sum_i s_i f_i = 0,                 s_i in {-1,+1}.
#
# Then, for either delta in {-1,+1} and any rank-one complementary matrix
# D = y tensor z,
#
#     M_i -> M_i + delta*s_i*D
#
# preserves the complete integer tensor.  This file deliberately does not
# infer the relation modulo two: signed pair sums are hash-matched against
# signed triple sums, every collision is compared coefficient by coefficient,
# and every admitted five-set is checked again over Z and required to have no
# zero proper subsum with those same signed coefficients.  Hashes are selectors
# only and chained buckets retain collisions.
#
# The endpoint builder keeps two terms when a sum cannot be merged inside the
# strict {-1,0,1} alphabet.  It emits one term only when a complementary
# projective factor is shared and the other factor sum is strict, and it
# removes exact opposite terms globally.  Callers must still initialize the
# returned masks through fft_init_terms, which performs the full n^6 integer
# matrix-multiplication gate before an endpoint is durable.

use flipfleet_ternary_worker

-> fftdm_mod(value, prime) (i64 i64) i64
  out = value % prime ## i64
  if out < 0
    out += prime
  out

-> fftdm_axis_p(st, term, axis) (i64[] i64 i64) i64
  st[st[32 + 2 * axis] + term]

-> fftdm_axis_n(st, term, axis) (i64[] i64 i64) i64
  st[st[33 + 2 * axis] + term]

-> fftdm_left_axis(axis) (i64) i64
  if axis == 0
    return 1
  0

-> fftdm_right_axis(axis) (i64) i64
  if axis == 2
    return 1
  2

-> fftdm_factor_hash(positive, negative, dim, prime, which) (i64 i64 i64 i64 i64) i64
  value = 0 ## i64
  coordinate = 0 ## i64
  while coordinate < dim
    coefficient = ((positive >> coordinate) & 1) - ((negative >> coordinate) & 1) ## i64
    if coefficient != 0
      x = coordinate + 1 ## i64
      weight = 1 + x * (which * 104729 + 1009) + x * x * (which * 8191 + 97) ## i64
      value += coefficient * (weight % prime)
      value %= prime
    coordinate += 1
  fftdm_mod(value,prime)

# First sign of a two-vector signed sum.  With two strict vectors a coordinate
# is zero precisely when one contribution is +1 and the other is -1.
-> fftdm_pair_first_sign(ap, an, bp0, bn0, sign) (i64 i64 i64 i64 i64) i64
  bp = bp0 ## i64
  bn = bn0 ## i64
  if sign < 0
    bp = bn0
    bn = bp0
  positive = ap | bp ## i64
  negative = an | bn ## i64
  nonzero = positive ^ negative ## i64
  if nonzero == 0
    return 0
  low = nonzero & (0 - nonzero) ## i64
  if (positive & low) != 0
    return 1
  0 - 1

# First sign of a three-vector signed sum.  A mixed coordinate with all three
# contributors is nonzero and takes the majority sign; a mixed coordinate
# with exactly two contributors cancels.
-> fftdm_triple_first_sign(ap, an, bp0, bn0, bsign, cp0, cn0, csign) (i64 i64 i64 i64 i64 i64 i64 i64) i64
  bp = bp0 ## i64
  bn = bn0 ## i64
  cp = cp0 ## i64
  cn = cn0 ## i64
  if bsign < 0
    bp = bn0
    bn = bp0
  if csign < 0
    cp = cn0
    cn = cp0
  positive = ap | bp | cp ## i64
  negative = an | bn | cn ## i64
  all_three = (ap | an) & (bp | bn) & (cp | cn) ## i64
  nonzero = (positive ^ negative) | all_three ## i64
  if nonzero == 0
    return 0
  low = nonzero & (0 - nonzero) ## i64
  if ((positive ^ negative) & low) != 0
    if (positive & low) != 0
      return 1
    return 0 - 1
  positive_majority = (ap & bp) | (ap & cp) | (bp & cp) ## i64
  if (positive_majority & low) != 0
    return 1
  0 - 1

-> fftdm_pair_triple_equal(fp, fneg, i, j, pair_sign, pair_orientation, k, l, m, lsign, msign, triple_orientation, dim) (i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  coordinate = 0 ## i64
  while coordinate < dim
    pair_value = fft_coefficient(fp[i],fneg[i],coordinate) + pair_sign * fft_coefficient(fp[j],fneg[j],coordinate) ## i64
    triple_value = fft_coefficient(fp[k],fneg[k],coordinate) + lsign * fft_coefficient(fp[l],fneg[l],coordinate) + msign * fft_coefficient(fp[m],fneg[m],coordinate) ## i64
    if pair_orientation * pair_value != triple_orientation * triple_value
      return 0
    coordinate += 1
  1

-> fftdm_relation_exact(st, selected, signs, axis) (i64[] i64[] i64[] i64) i64
  coordinate = 0 ## i64
  while coordinate < st[3]
    total = 0 ## i64
    i = 0 ## i64
    while i < 5
      total += signs[i] * fft_coefficient(fftdm_axis_p(st,selected[i],axis),fftdm_axis_n(st,selected[i],axis),coordinate)
      i += 1
    if total != 0
      return 0
    coordinate += 1
  1

# Exclude lower-order unit subrelations masquerading as five-term identities.
# This is minimality inside the discovered +/-1 relation, not a claim that all
# proper subsets are independent over Q with arbitrary coefficients.
-> fftdm_relation_minimal(st, selected, signs, axis) (i64[] i64[] i64[] i64) i64
  if fftdm_relation_exact(st,selected,signs,axis) == 0
    return 0
  subset = 1 ## i64
  while subset < 31
    all_zero = 1 ## i64
    coordinate = 0 ## i64
    while coordinate < st[3] && all_zero == 1
      total = 0 ## i64
      i = 0 ## i64
      while i < 5
        if ((subset >> i) & 1) != 0
          total += signs[i] * fft_coefficient(fftdm_axis_p(st,selected[i],axis),fftdm_axis_n(st,selected[i],axis),coordinate)
        i += 1
      if total != 0
        all_zero = 0
      coordinate += 1
    if all_zero == 1
      return 0
    subset += 1
  1

# Append one actual signed rank-one term after applying the worker's U/V gauge.
# One existing exact opposite is removed, implementing integer cancellation.
-> fftdm_append(up, un, vp, vn, wp, wn, count, capacity, aup0, aun0, avp0, avn0, awp0, awn0) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  if count < 0 || count > capacity
    return 0 - 1
  aup = aup0 ## i64
  aun = aun0 ## i64
  avp = avp0 ## i64
  avn = avn0 ## i64
  awp = awp0 ## i64
  awn = awn0 ## i64
  if (aup | aun) == 0 || (avp | avn) == 0 || (awp | awn) == 0
    return 0 - 1
  if (aup & aun) != 0 || (avp & avn) != 0 || (awp & awn) != 0
    return 0 - 1
  if fft_first_sign(aup,aun) < 0
    swap = aup
    aup = aun
    aun = swap
    swap = awp
    awp = awn
    awn = swap
  if fft_first_sign(avp,avn) < 0
    swap = avp
    avp = avn
    avn = swap
    swap = awp
    awp = awn
    awn = swap
  i = 0 ## i64
  while i < count
    if up[i] == aup && un[i] == aun && vp[i] == avp && vn[i] == avn && wp[i] == awn && wn[i] == awp
      last = count - 1 ## i64
      if i != last
        up[i] = up[last]
        un[i] = un[last]
        vp[i] = vp[last]
        vn[i] = vn[last]
        wp[i] = wp[last]
        wn[i] = wn[last]
      return last
    i += 1
  if count >= capacity
    return 0 - 1
  up[count] = aup
  un[count] = aun
  vp[count] = avp
  vn[count] = avn
  wp[count] = awp
  wn[count] = awn
  count + 1

-> fftdm_append_axis(up, un, vp, vn, wp, wn, count, capacity, axis, fp, fneg, lp, ln, rp, rn) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  if axis == 0
    return fftdm_append(up,un,vp,vn,wp,wn,count,capacity,fp,fneg,lp,ln,rp,rn)
  if axis == 1
    return fftdm_append(up,un,vp,vn,wp,wn,count,capacity,lp,ln,fp,fneg,rp,rn)
  if axis == 2
    return fftdm_append(up,un,vp,vn,wp,wn,count,capacity,lp,ln,rp,rn,fp,fneg)
  0 - 1

-> fftdm_selected_position(selected, term) (i64[] i64) i64
  i = 0 ## i64
  while i < 5
    if selected[i] == term
      return i
    i += 1
  0 - 1

# Cost of M_i + coefficient*(y tensor z) before cancellations against terms
# outside the selected five.  A legal shared-factor merge costs one, exact
# cancellation costs zero, and the always-valid two-term form costs two.
-> fftdm_slice_cost(st, term, axis, coefficient, yp, yn, zp, zn) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  left_axis = fftdm_left_axis(axis) ## i64
  right_axis = fftdm_right_axis(axis) ## i64
  lp = fftdm_axis_p(st,term,left_axis) ## i64
  ln = fftdm_axis_n(st,term,left_axis) ## i64
  rp = fftdm_axis_p(st,term,right_axis) ## i64
  rn = fftdm_axis_n(st,term,right_axis) ## i64
  relation = fft_vector_relation(lp,ln,yp,yn) ## i64
  if relation != 0
    if fft_vector_add(st,rp,rn,zp,zn,coefficient * relation) == 1
      if (st[44] | st[45]) == 0
        return 0
      return 1
  relation = fft_vector_relation(rp,rn,zp,zn)
  if relation != 0
    if fft_vector_add(st,lp,ln,yp,yn,coefficient * relation) == 1
      if (st[44] | st[45]) == 0
        return 0
      return 1
  2

-> fftdm_local_rank(st, selected, signs, axis, delta, yp, yn, zp, zn) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  cost = 0 ## i64
  i = 0 ## i64
  while i < 5
    cost += fftdm_slice_cost(st,selected[i],axis,delta * signs[i],yp,yn,zp,zn)
    i += 1
  st[5] - 5 + cost

# Build and globally opposite-compact one exact dependency-median endpoint.
-> fftdm_build_endpoint(st, selected, signs, axis, delta, yp, yn, zp, zn, up, un, vp, vn, wp, wn) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  capacity = up.size() ## i64
  if un.size() < capacity || vp.size() < capacity || vn.size() < capacity || wp.size() < capacity || wn.size() < capacity || capacity < st[5] + 5 || fftdm_relation_minimal(st,selected,signs,axis) == 0
    return 0 - 1
  count = 0 ## i64
  term = 0 ## i64
  while term < st[5]
    if fftdm_selected_position(selected,term) < 0
      count = fftdm_append(up,un,vp,vn,wp,wn,count,capacity,fftdm_axis_p(st,term,0),fftdm_axis_n(st,term,0),fftdm_axis_p(st,term,1),fftdm_axis_n(st,term,1),fftdm_axis_p(st,term,2),fftdm_axis_n(st,term,2))
      if count < 0
        return 0 - 1
    term += 1
  left_axis = fftdm_left_axis(axis) ## i64
  right_axis = fftdm_right_axis(axis) ## i64
  i = 0
  while i < 5
    term = selected[i]
    coefficient = delta * signs[i] ## i64
    fp = fftdm_axis_p(st,term,axis) ## i64
    fneg = fftdm_axis_n(st,term,axis) ## i64
    lp = fftdm_axis_p(st,term,left_axis) ## i64
    ln = fftdm_axis_n(st,term,left_axis) ## i64
    rp = fftdm_axis_p(st,term,right_axis) ## i64
    rn = fftdm_axis_n(st,term,right_axis) ## i64
    handled = 0 ## i64
    relation = fft_vector_relation(lp,ln,yp,yn) ## i64
    if relation != 0
      if fft_vector_add(st,rp,rn,zp,zn,coefficient * relation) == 1
        sum_p = st[44] ## i64
        sum_n = st[45] ## i64
        if (sum_p | sum_n) != 0
          count = fftdm_append_axis(up,un,vp,vn,wp,wn,count,capacity,axis,fp,fneg,lp,ln,sum_p,sum_n)
        handled = 1
    if handled == 0
      relation = fft_vector_relation(rp,rn,zp,zn)
      if relation != 0
        if fft_vector_add(st,lp,ln,yp,yn,coefficient * relation) == 1
          sum_p = st[44]
          sum_n = st[45]
          if (sum_p | sum_n) != 0
            count = fftdm_append_axis(up,un,vp,vn,wp,wn,count,capacity,axis,fp,fneg,sum_p,sum_n,rp,rn)
          handled = 1
    if handled == 0
      count = fftdm_append_axis(up,un,vp,vn,wp,wn,count,capacity,axis,fp,fneg,lp,ln,rp,rn)
      if count >= 0
        dp = zp ## i64
        dn = zn ## i64
        if coefficient < 0
          dp = zn
          dn = zp
        count = fftdm_append_axis(up,un,vp,vn,wp,wn,count,capacity,axis,fp,fneg,yp,yn,dp,dn)
    if count < 0
      return 0 - 1
    i += 1
  count

-> fftdm_density(up, un, vp, vn, wp, wn, rank) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < rank
    density += fft_popcount(up[i] | un[i]) + fft_popcount(vp[i] | vn[i]) + fft_popcount(wp[i] | wn[i])
    i += 1
  density

-> fftdm_same_terms(st, up, un, vp, vn, wp, wn, rank) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  if rank != st[5]
    return 0
  used = i64[rank]
  i = 0 ## i64
  while i < rank
    found = 0 - 1 ## i64
    j = 0 ## i64
    while j < rank && found < 0
      if used[j] == 0 && up[i] == fftdm_axis_p(st,j,0) && un[i] == fftdm_axis_n(st,j,0) && vp[i] == fftdm_axis_p(st,j,1) && vn[i] == fftdm_axis_n(st,j,1) && wp[i] == fftdm_axis_p(st,j,2) && wn[i] == fftdm_axis_n(st,j,2)
        found = j
      j += 1
    if found < 0
      return 0
    used[found] = 1
    i += 1
  1

# Complete over proper-subsum-free signed unit five-factor dependencies when
# circuit_cap is zero.  A positive cap bounds distinct relations across axes.
# max_debt bounds the local five-slice rank before global opposite compaction.
#
# meta:
#  0 pair entries, 1 signed triple probes, 2 dual-hash hits,
#  3 coefficientwise relation hits, 4 unit five-relations, 5 D candidates,
#  6 debt-qualified, 7 changed endpoints, 8 rank drops, 9 rank neutral,
# 10 best rank, 11 best density, 12 best local delta, 13 best axis,
# 14 circuit cap reached, 15 source density.
-> fftdm_search(st, circuit_cap, max_debt, out_up, out_un, out_vp, out_vn, out_wp, out_wn, meta) (i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if fft_valid(st) == 0 || st[5] < 5 || circuit_cap < 0 || max_debt < 0 || out_up.size() < st[5] + 5 || out_un.size() < st[5] + 5 || out_vp.size() < st[5] + 5 || out_vn.size() < st[5] + 5 || out_wp.size() < st[5] + 5 || out_wn.size() < st[5] + 5 || meta.size() < 16
    return 0
  q = 0 ## i64
  while q < 16
    meta[q] = 0
    q += 1
  meta[15] = fft_current_density(st)
  rank = st[5] ## i64
  dim = st[3] ## i64
  p1 = 1000003 ## i64
  p2 = 1000033 ## i64
  candidate_up = i64[out_up.size()]
  candidate_un = i64[out_up.size()]
  candidate_vp = i64[out_up.size()]
  candidate_vn = i64[out_up.size()]
  candidate_wp = i64[out_up.size()]
  candidate_wn = i64[out_up.size()]
  selected = i64[5]
  signs = i64[5]
  initialized = 0 ## i64
  stop = 0 ## i64
  axis = 0 ## i64
  while axis < 3 && stop == 0
    fp = i64[rank]
    fneg = i64[rank]
    hash1 = i64[rank]
    hash2 = i64[rank]
    i = 0 ## i64
    while i < rank
      fp[i] = fftdm_axis_p(st,i,axis)
      fneg[i] = fftdm_axis_n(st,i,axis)
      hash1[i] = fftdm_factor_hash(fp[i],fneg[i],dim,p1,0)
      hash2[i] = fftdm_factor_hash(fp[i],fneg[i],dim,p2,1)
      i += 1
    pair_capacity = rank * (rank - 1) ## i64
    table_capacity = 16 ## i64
    while table_capacity < pair_capacity * 4
      table_capacity *= 2
    table_mask = table_capacity - 1 ## i64
    heads = i32[table_capacity]
    links = i32[pair_capacity]
    pair_i = i32[pair_capacity]
    pair_j = i32[pair_capacity]
    pair_sign = i64[pair_capacity]
    pair_orientation = i64[pair_capacity]
    pair_hash1 = i64[pair_capacity]
    pair_hash2 = i64[pair_capacity]
    pair_count = 0 ## i64
    i = 0
    while i < rank - 1
      j = i + 1 ## i64
      while j < rank
        branch = 0 ## i64
        while branch < 2
          s = 1 ## i64
          if branch == 1
            s = 0 - 1
          orientation = fftdm_pair_first_sign(fp[i],fneg[i],fp[j],fneg[j],s) ## i64
          if orientation != 0
            h1 = fftdm_mod(hash1[i] + s * hash1[j],p1) ## i64
            h2 = fftdm_mod(hash2[i] + s * hash2[j],p2) ## i64
            if orientation < 0
              if h1 != 0
                h1 = p1 - h1
              if h2 != 0
                h2 = p2 - h2
            bucket = (h1 * 1000033 + h2) & table_mask ## i64
            pair_i[pair_count] = i
            pair_j[pair_count] = j
            pair_sign[pair_count] = s
            pair_orientation[pair_count] = orientation
            pair_hash1[pair_count] = h1
            pair_hash2[pair_count] = h2
            links[pair_count] = heads[bucket]
            heads[bucket] = pair_count + 1
            pair_count += 1
          branch += 1
        j += 1
      i += 1
    meta[0] += pair_count

    k = 0 ## i64
    while k < rank - 2 && stop == 0
      l = k + 1 ## i64
      while l < rank - 1 && stop == 0
        m = l + 1 ## i64
        while m < rank && stop == 0
          pattern = 0 ## i64
          while pattern < 4 && stop == 0
            lsign = 1 ## i64
            msign = 1 ## i64
            if (pattern & 1) != 0
              lsign = 0 - 1
            if (pattern & 2) != 0
              msign = 0 - 1
            meta[1] += 1
            triple_orientation = fftdm_triple_first_sign(fp[k],fneg[k],fp[l],fneg[l],lsign,fp[m],fneg[m],msign) ## i64
            if triple_orientation != 0
              h1 = fftdm_mod(hash1[k] + lsign * hash1[l] + msign * hash1[m],p1)
              h2 = fftdm_mod(hash2[k] + lsign * hash2[l] + msign * hash2[m],p2)
              if triple_orientation < 0
                if h1 != 0
                  h1 = p1 - h1
                if h2 != 0
                  h2 = p2 - h2
              bucket = (h1 * 1000033 + h2) & table_mask
              entry = heads[bucket] ## i64
              while entry != 0 && stop == 0
                pair = entry - 1 ## i64
                i = pair_i[pair] ## i64
                j = pair_j[pair] ## i64
                if j < k && pair_hash1[pair] == h1 && pair_hash2[pair] == h2
                  meta[2] += 1
                  if fftdm_pair_triple_equal(fp,fneg,i,j,pair_sign[pair],pair_orientation[pair],k,l,m,lsign,msign,triple_orientation,dim) == 1
                    meta[3] += 1
                    selected[0] = i
                    selected[1] = j
                    selected[2] = k
                    selected[3] = l
                    selected[4] = m
                    signs[0] = pair_orientation[pair]
                    signs[1] = pair_orientation[pair] * pair_sign[pair]
                    signs[2] = 0 - triple_orientation
                    signs[3] = (0 - triple_orientation) * lsign
                    signs[4] = (0 - triple_orientation) * msign
                    if signs[0] < 0
                      q = 0
                      while q < 5
                        signs[q] = 0 - signs[q]
                        q += 1
                    if fftdm_relation_minimal(st,selected,signs,axis) == 1
                      meta[4] += 1
                      left_axis = fftdm_left_axis(axis) ## i64
                      right_axis = fftdm_right_axis(axis) ## i64
                      yi = 0 ## i64
                      while yi < 5
                        yp = fftdm_axis_p(st,selected[yi],left_axis) ## i64
                        yn = fftdm_axis_n(st,selected[yi],left_axis) ## i64
                        zi = 0 ## i64
                        while zi < 5
                          zp = fftdm_axis_p(st,selected[zi],right_axis) ## i64
                          zn = fftdm_axis_n(st,selected[zi],right_axis) ## i64
                          delta_branch = 0 ## i64
                          while delta_branch < 2
                            delta = 1 ## i64
                            if delta_branch == 1
                              delta = 0 - 1
                            meta[5] += 1
                            local_rank = fftdm_local_rank(st,selected,signs,axis,delta,yp,yn,zp,zn) ## i64
                            if local_rank <= rank + max_debt
                              meta[6] += 1
                              candidate_rank = fftdm_build_endpoint(st,selected,signs,axis,delta,yp,yn,zp,zn,candidate_up,candidate_un,candidate_vp,candidate_vn,candidate_wp,candidate_wn) ## i64
                              if candidate_rank > 0 && fftdm_same_terms(st,candidate_up,candidate_un,candidate_vp,candidate_vn,candidate_wp,candidate_wn,candidate_rank) == 0
                                meta[7] += 1
                                if candidate_rank < rank
                                  meta[8] += 1
                                if candidate_rank == rank
                                  meta[9] += 1
                                density = fftdm_density(candidate_up,candidate_un,candidate_vp,candidate_vn,candidate_wp,candidate_wn,candidate_rank) ## i64
                                better = 0 ## i64
                                if initialized == 0 || candidate_rank < meta[10]
                                  better = 1
                                if initialized == 1 && candidate_rank == meta[10] && density < meta[11]
                                  better = 1
                                if better == 1
                                  initialized = 1
                                  meta[10] = candidate_rank
                                  meta[11] = density
                                  meta[12] = local_rank - rank
                                  meta[13] = axis
                                  q = 0
                                  while q < candidate_rank
                                    out_up[q] = candidate_up[q]
                                    out_un[q] = candidate_un[q]
                                    out_vp[q] = candidate_vp[q]
                                    out_vn[q] = candidate_vn[q]
                                    out_wp[q] = candidate_wp[q]
                                    out_wn[q] = candidate_wn[q]
                                    q += 1
                            delta_branch += 1
                          zi += 1
                        yi += 1
                      if circuit_cap > 0 && meta[4] >= circuit_cap
                        meta[14] = 1
                        stop = 1
                entry = links[pair]
            pattern += 1
          m += 1
        l += 1
      k += 1
    axis += 1
  if initialized == 1
    return meta[10]
  0
