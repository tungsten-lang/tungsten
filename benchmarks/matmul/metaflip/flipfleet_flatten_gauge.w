# Exact flattening-gauge repartition moves for FlipFleet.
#
# For a selected k-term window and one flattening axis, write
#
#     T = U K^T,
#
# where the columns of U are factors on the flattening axis and each column of
# K is the outer product of the other two factors.  Every G in GL(k,2) gives
#
#     T = (U G) (K G^{-T})^T.
#
# We represent both transforms by coefficient masks over the original terms.
# A sparse transvection G=I+E_ab updates
#
#     U_column[b] ^= U_column[a]
#     K_column[a] ^= K_column[b]
#
# and is its own inverse.  Each reshaped K column is then factored at exact
# minimal GF(2) matrix rank.  Duplicate output terms cancel in pairs before an
# exact local-tensor gate.  This exposes ordinary flips at depth one and
# coordinated multi-term repartitions at larger depth.
#
# The bounded beam engine supports 2 <= k <= 16, depth <= 4, beam <= 32.
# Packed terms are [u0,v0,w0,u1,v1,w1,...].  Search config is
# [k, flatten_axis, max_depth, beam_width].

use flipfleet_circuit_images
use flipfleet_shear_moves

-> ffgr_valid_window(k, flatten_axis) (i64 i64) i64
  ok = 0 ## i64
  if k >= 2 && k <= 16 && flatten_axis >= 0 && flatten_axis < 3
    ok = 1
  ok

-> ffgr_identity(k, u_combos, k_combos) (i64 i64[] i64[]) i64
  result = 0 ## i64
  if k >= 1 && k <= 16 && u_combos.size() >= k && k_combos.size() >= k
    i = 0 ## i64
    while i < k
      u_combos[i] = 1 << i
      k_combos[i] = 1 << i
      i += 1
    result = k
  result

-> ffgr_transvection(u_combos, k_combos, k, source, destination) (i64[] i64[] i64 i64 i64) i64
  ok = 0 ## i64
  if k >= 2 && k <= 16 && source >= 0 && source < k && destination >= 0 && destination < k && source != destination
    if u_combos.size() >= k && k_combos.size() >= k
      u_combos[destination] = u_combos[destination] ^ u_combos[source]
      k_combos[source] = k_combos[source] ^ k_combos[destination]
      ok = 1
  ok

-> ffgr_axis_get(us, vs, ws, term, axis) (i64[] i64[] i64[] i64 i64) i64
  value = 0 ## i64
  if axis == 0
    value = us[term]
  if axis == 1
    value = vs[term]
  if axis == 2
    value = ws[term]
  value

-> ffgr_axis_set(us, vs, ws, term, axis, value) (i64[] i64[] i64[] i64 i64 i64) i64
  if axis == 0
    us[term] = value
  if axis == 1
    vs[term] = value
  if axis == 2
    ws[term] = value
  value

-> ffgr_other_axes(flatten_axis, axes) (i64 i64[]) i64
  ok = 0 ## i64
  if axes.size() >= 2
    if flatten_axis == 0
      axes[0] = 1
      axes[1] = 2
      ok = 1
    if flatten_axis == 1
      axes[0] = 0
      axes[1] = 2
      ok = 1
    if flatten_axis == 2
      axes[0] = 0
      axes[1] = 1
      ok = 1
  ok

-> ffgr_unpack(packed, count, us, vs, ws) (i64[] i64 i64[] i64[] i64[]) i64
  result = 0 ## i64
  if count >= 0 && packed.size() >= count*3 && us.size() >= count && vs.size() >= count && ws.size() >= count
    i = 0 ## i64
    while i < count
      us[i] = packed[i*3]
      vs[i] = packed[i*3+1]
      ws[i] = packed[i*3+2]
      i += 1
    result = count
  result

-> ffgr_pack(us, vs, ws, count, packed) (i64[] i64[] i64[] i64 i64[]) i64
  result = 0 ## i64
  if count >= 0 && packed.size() >= count*3 && us.size() >= count && vs.size() >= count && ws.size() >= count
    i = 0 ## i64
    while i < count
      packed[i*3] = us[i]
      packed[i*3+1] = vs[i]
      packed[i*3+2] = ws[i]
      i += 1
    result = count
  result

-> ffgr_same_set(lu, lv, lw, lcount, ru, rv, right_w, rcount) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  same = 0 ## i64
  if lcount == rcount
    same = 1
    i = 0 ## i64
    while i < lcount && same == 1
      found = 0 ## i64
      j = 0 ## i64
      while j < rcount
        if ffc_same_term(lu[i],lv[i],lw[i],ru[j],rv[j],right_w[j]) == 1
          found = 1
        j += 1
      if found == 0
        same = 0
      i += 1
  same

-> ffgr_terms_well_formed(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  ok = 0 ## i64
  if count >= 1 && count <= 256 && us.size() >= count && vs.size() >= count && ws.size() >= count
    ok = 1
    i = 0 ## i64
    while i < count && ok == 1
      if us[i] <= 0 || vs[i] <= 0 || ws[i] <= 0
        ok = 0
      j = i + 1 ## i64
      while j < count && ok == 1
        if ffc_same_term(us[i],vs[i],ws[i],us[j],vs[j],ws[j]) == 1
          ok = 0
        j += 1
      i += 1
  ok

# Exact equality of two tensor sums, with no span-size or fingerprint limit.
-> ffgr_replacement_exact(lu, lv, lw, lcount, ru, rv, right_w, rcount) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  ok = 0 ## i64
  if lcount >= 0 && rcount >= 0 && lu.size() >= lcount && lv.size() >= lcount && lw.size() >= lcount && ru.size() >= rcount && rv.size() >= rcount && right_w.size() >= rcount
    ubits = ffc_max_width(lu,lcount) ## i64
    candidate = ffc_max_width(ru,rcount) ## i64
    if candidate > ubits
      ubits = candidate
    vbits = ffc_max_width(lv,lcount) ## i64
    candidate = ffc_max_width(rv,rcount)
    if candidate > vbits
      vbits = candidate
    wbits = ffc_max_width(lw,lcount) ## i64
    candidate = ffc_max_width(right_w,rcount)
    if candidate > wbits
      wbits = candidate
    ok = 1
    ui = 0 ## i64
    while ui < ubits && ok == 1
      vi = 0 ## i64
      while vi < vbits && ok == 1
        wi = 0 ## i64
        while wi < wbits && ok == 1
          parity = 0 ## i64
          i = 0 ## i64
          while i < lcount
            if ((lu[i] >> ui) & 1) != 0 && ((lv[i] >> vi) & 1) != 0 && ((lw[i] >> wi) & 1) != 0
              parity = parity ^ 1
            i += 1
          i = 0
          while i < rcount
            if ((ru[i] >> ui) & 1) != 0 && ((rv[i] >> vi) & 1) != 0 && ((right_w[i] >> wi) & 1) != 0
              parity = parity ^ 1
            i += 1
          if parity != 0
            ok = 0
          wi += 1
        vi += 1
      ui += 1
  ok

-> ffgr_toggle_output(out_u, out_v, out_w, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  result = 0 - 1 ## i64
  if u > 0 && v > 0 && w > 0
    found = 0 - 1 ## i64
    i = 0 ## i64
    while i < count && found < 0
      if ffc_same_term(out_u[i],out_v[i],out_w[i],u,v,w) == 1
        found = i
      i += 1
    if found >= 0
      out_u[found] = out_u[count-1]
      out_v[found] = out_v[count-1]
      out_w[found] = out_w[count-1]
      result = count - 1
    if found < 0 && count < capacity
      out_u[count] = u
      out_v[count] = v
      out_w[count] = w
      result = count + 1
  result

# Materialize one gauge transform.  meta layout:
# [0] output count [1] raw factored terms [2] canceled pairs [3] exact
# [4] same set [5] maximum K-column matrix rank [6] output density.
-> ffgr_materialize(su, sv, sw, k, flatten_axis, u_combos, k_combos, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  result = 0 ## i64
  valid = ffgr_valid_window(k,flatten_axis) ## i64
  capacity = k*k ## i64
  if su.size() < k || sv.size() < k || sw.size() < k || u_combos.size() < k || k_combos.size() < k
    valid = 0
  if out_u.size() < capacity || out_v.size() < capacity || out_w.size() < capacity || meta.size() < 7
    valid = 0
  if valid == 1 && ffgr_terms_well_formed(su,sv,sw,k) == 0
    valid = 0
  axes = i64[2]
  if valid == 1 && ffgr_other_axes(flatten_axis,axes) == 0
    valid = 0
  output_count = 0 ## i64
  raw_count = 0 ## i64
  max_matrix_rank = 0 ## i64
  if valid == 1
    column = 0 ## i64
    while column < k && valid == 1
      flat_factor = 0 ## i64
      i = 0 ## i64
      while i < k
        if ((u_combos[column] >> i) & 1) != 0
          flat_factor = flat_factor ^ ffgr_axis_get(su,sv,sw,i,flatten_axis)
        i += 1
      lefts = i64[16]
      rights = i64[16]
      matrix_terms = 0 ## i64
      i = 0
      while i < k
        if ((k_combos[column] >> i) & 1) != 0
          lefts[matrix_terms] = ffgr_axis_get(su,sv,sw,i,axes[0])
          rights[matrix_terms] = ffgr_axis_get(su,sv,sw,i,axes[1])
          matrix_terms += 1
        i += 1
      correction_left = i64[16]
      correction_right = i64[16]
      matrix_rank = ffsm_rank_factor_matrix(lefts,rights,matrix_terms,correction_left,correction_right) ## i64
      if matrix_rank < 0
        valid = 0
      if matrix_rank > max_matrix_rank
        max_matrix_rank = matrix_rank
      if valid == 1 && flat_factor != 0
        factor = 0 ## i64
        while factor < matrix_rank && valid == 1
          made_u = 0 ## i64
          made_v = 0 ## i64
          made_w = 0 ## i64
          holder_u = i64[1]
          holder_v = i64[1]
          holder_w = i64[1]
          z = ffgr_axis_set(holder_u,holder_v,holder_w,0,flatten_axis,flat_factor) ## i64
          z = ffgr_axis_set(holder_u,holder_v,holder_w,0,axes[0],correction_left[factor])
          z = ffgr_axis_set(holder_u,holder_v,holder_w,0,axes[1],correction_right[factor])
          made_u = holder_u[0]
          made_v = holder_v[0]
          made_w = holder_w[0]
          next_count = ffgr_toggle_output(out_u,out_v,out_w,output_count,capacity,made_u,made_v,made_w) ## i64
          if next_count < 0
            valid = 0
          if next_count >= 0
            output_count = next_count
            raw_count += 1
          factor += 1
      column += 1
  if valid == 1
    exact = ffgr_replacement_exact(su,sv,sw,k,out_u,out_v,out_w,output_count) ## i64
    same = ffgr_same_set(su,sv,sw,k,out_u,out_v,out_w,output_count) ## i64
    density = 0 ## i64
    i = 0 ## i64
    while i < output_count
      density += ffw_popcount(out_u[i]) + ffw_popcount(out_v[i]) + ffw_popcount(out_w[i])
      i += 1
    meta[0] = output_count
    meta[1] = raw_count
    meta[2] = (raw_count - output_count) / 2
    meta[3] = exact
    meta[4] = same
    meta[5] = max_matrix_rank
    meta[6] = density
    if exact == 1 && output_count > 0
      result = output_count
  result

# Six-argument packed wrapper for native admission tests.
-> ffgr_materialize_packed(source, config, u_combos, k_combos, replacement, meta) (i64[] i64[] i64[] i64[] i64[] i64[]) i64
  result = 0 ## i64
  if config.size() >= 2
    k = config[0] ## i64
    flatten_axis = config[1] ## i64
    if ffgr_valid_window(k,flatten_axis) == 1 && source.size() >= k*3 && replacement.size() >= k*k*3
      su = i64[16]
      sv = i64[16]
      sw = i64[16]
      z = ffgr_unpack(source,k,su,sv,sw) ## i64
      out_u = i64[256]
      out_v = i64[256]
      out_w = i64[256]
      made = ffgr_materialize(su,sv,sw,k,flatten_axis,u_combos,k_combos,out_u,out_v,out_w,meta) ## i64
      if made > 0
        z = ffgr_pack(out_u,out_v,out_w,made,replacement)
        result = made
  result

-> ffgr_transform_equal(states_u, states_k, state_index, candidate_u, candidate_k, k) (i64[] i64[] i64 i64[] i64[] i64) i64
  same = 1 ## i64
  i = 0 ## i64
  while i < k && same == 1
    if states_u[state_index*k+i] != candidate_u[i] || states_k[state_index*k+i] != candidate_k[i]
      same = 0
    i += 1
  same

-> ffgr_store_transform(states_u, states_k, state_index, candidate_u, candidate_k, k) (i64[] i64[] i64 i64[] i64[] i64) i64
  i = 0 ## i64
  while i < k
    states_u[state_index*k+i] = candidate_u[i]
    states_k[state_index*k+i] = candidate_k[i]
    i += 1
  k

# Insert a unique transform into a bounded unsorted best-score beam.  `header`
# is [current_count,width,k]; lower scores are better.
-> ffgr_beam_insert(states_u, states_k, scores, header, candidate_u, candidate_k, score) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  count = header[0] ## i64
  width = header[1] ## i64
  k = header[2] ## i64
  duplicate = 0 ## i64
  i = 0 ## i64
  while i < count
    if ffgr_transform_equal(states_u,states_k,i,candidate_u,candidate_k,k) == 1
      duplicate = 1
    i += 1
  if duplicate == 0
    target = 0 - 1 ## i64
    if count < width
      target = count
      count += 1
    if target < 0 && count > 0
      worst = 0 ## i64
      i = 1
      while i < count
        if scores[i] > scores[worst]
          worst = i
        i += 1
      if score < scores[worst]
        target = worst
    if target >= 0
      z = ffgr_store_transform(states_u,states_k,target,candidate_u,candidate_k,k) ## i64
      scores[target] = score
  header[0] = count
  count

# Bounded breadth/beam enumeration of sparse transvection words.  Rank is the
# primary score and factor density breaks ties.  meta layout:
# [0] output count [1] winning depth [2] expanded transforms
# [3] exact [4] same-set flag [5] output density [6] max K rank.
-> ffgr_search_packed(source, config, replacement, meta) (i64[] i64[] i64[] i64[]) i64
  result = 0 ## i64
  if config.size() >= 4 && meta.size() >= 7
    k = config[0] ## i64
    flatten_axis = config[1] ## i64
    max_depth = config[2] ## i64
    beam_width = config[3] ## i64
    valid = ffgr_valid_window(k,flatten_axis) ## i64
    if max_depth < 1 || max_depth > 4 || beam_width < 1 || beam_width > 32
      valid = 0
    if source.size() < k*3 || replacement.size() < k*k*3
      valid = 0
    if valid == 1
      current_u = i64[512]
      current_k = i64[512]
      next_u = i64[512]
      next_k = i64[512]
      current_scores = i64[32]
      next_scores = i64[32]
      identity_u = i64[16]
      identity_k = i64[16]
      z = ffgr_identity(k,identity_u,identity_k) ## i64
      z = ffgr_store_transform(current_u,current_k,0,identity_u,identity_k,k)
      current_count = 1 ## i64
      best_score = 9223372036854775807 ## i64
      best_count = 0 ## i64
      best_depth = 0 ## i64
      best_meta = i64[7]
      expanded = 0 ## i64
      depth = 1 ## i64
      while depth <= max_depth && current_count > 0
        header = i64[3]
        header[0] = 0
        header[1] = beam_width
        header[2] = k
        state_index = 0 ## i64
        while state_index < current_count
          source_index = 0 ## i64
          while source_index < k
            destination = 0 ## i64
            while destination < k
              if source_index != destination
                candidate_u = i64[16]
                candidate_k = i64[16]
                i = 0 ## i64
                while i < k
                  candidate_u[i] = current_u[state_index*k+i]
                  candidate_k[i] = current_k[state_index*k+i]
                  i += 1
                z = ffgr_transvection(candidate_u,candidate_k,k,source_index,destination)
                candidate_output = i64[768]
                candidate_meta = i64[7]
                made = ffgr_materialize_packed(source,config,candidate_u,candidate_k,candidate_output,candidate_meta) ## i64
                expanded += 1
                if made > 0
                  score = made * 1000000 + candidate_meta[6] ## i64
                  if candidate_meta[4] == 0 && score < best_score
                    best_score = score
                    best_count = made
                    best_depth = depth
                    i = 0
                    while i < made*3
                      replacement[i] = candidate_output[i]
                      i += 1
                    i = 0
                    while i < 7
                      best_meta[i] = candidate_meta[i]
                      i += 1
                  z = ffgr_beam_insert(next_u,next_k,next_scores,header,candidate_u,candidate_k,score)
              destination += 1
            source_index += 1
          state_index += 1
        current_count = header[0]
        state_index = 0
        while state_index < current_count
          i = 0
          while i < k
            current_u[state_index*k+i] = next_u[state_index*k+i]
            current_k[state_index*k+i] = next_k[state_index*k+i]
            i += 1
          current_scores[state_index] = next_scores[state_index]
          state_index += 1
        depth += 1
      if best_count > 0
        meta[0] = best_count
        meta[1] = best_depth
        meta[2] = expanded
        meta[3] = best_meta[3]
        meta[4] = best_meta[4]
        meta[5] = best_meta[6]
        meta[6] = best_meta[5]
        result = best_count
  result

# Score a packed replacement against the unselected live terms.  metrics are
# [external collisions, density of collided terms, effective output density].
-> ffgr_compact_metrics(replacement, count, external_u, external_v, external_w, external_count, metrics) (i64[] i64 i64[] i64[] i64[] i64 i64[]) i64
  ok = 0 ## i64
  if count >= 0 && replacement.size() >= count*3 && external_count >= 0 && external_u.size() >= external_count && external_v.size() >= external_count && external_w.size() >= external_count && metrics.size() >= 3
    collisions = 0 ## i64
    collision_density = 0 ## i64
    output_density = 0 ## i64
    i = 0 ## i64
    while i < count
      u = replacement[i*3] ## i64
      v = replacement[i*3+1] ## i64
      w = replacement[i*3+2] ## i64
      output_density += ffw_popcount(u) + ffw_popcount(v) + ffw_popcount(w)
      j = 0 ## i64
      while j < external_count
        if ffc_same_term(u,v,w,external_u[j],external_v[j],external_w[j]) == 1
          collisions += 1
          collision_density += ffw_popcount(external_u[j]) + ffw_popcount(external_v[j]) + ffw_popcount(external_w[j])
        j += 1
      i += 1
    metrics[0] = collisions
    metrics[1] = collision_density
    metrics[2] = output_density - 2*collision_density
    ok = 1
  ok

# Context-aware variant of the sparse flattening beam.  Unlike
# ffgr_search_packed, beam order includes parity cancellation against every
# unselected live term.  This is essential: a locally +1 transform with one
# external collision is a global -1 move and must outrank a locally neutral
# transform with no collision.  meta layout is [local count, depth, expanded,
# exact, same-set, local density, external collisions, effective density].
-> ffgr_search_compact_packed(source, config, external_u, external_v, external_w, external_count, replacement, meta) (i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[]) i64
  result = 0 ## i64
  if config.size() >= 4 && meta.size() >= 8
    k = config[0] ## i64
    flatten_axis = config[1] ## i64
    max_depth = config[2] ## i64
    beam_width = config[3] ## i64
    valid = ffgr_valid_window(k,flatten_axis) ## i64
    if max_depth < 1 || max_depth > 4 || beam_width < 1 || beam_width > 32
      valid = 0
    if source.size() < k*3 || replacement.size() < k*k*3
      valid = 0
    if external_count < 0 || external_u.size() < external_count || external_v.size() < external_count || external_w.size() < external_count
      valid = 0
    if valid == 1
      current_u = i64[512]
      current_k = i64[512]
      next_u = i64[512]
      next_k = i64[512]
      current_scores = i64[32]
      next_scores = i64[32]
      identity_u = i64[16]
      identity_k = i64[16]
      z = ffgr_identity(k,identity_u,identity_k) ## i64
      z = ffgr_store_transform(current_u,current_k,0,identity_u,identity_k,k)
      current_count = 1 ## i64
      best_score = 9223372036854775807 ## i64
      best_count = 0 ## i64
      best_depth = 0 ## i64
      best_meta = i64[7]
      best_metrics = i64[3]
      expanded = 0 ## i64
      depth = 1 ## i64
      while depth <= max_depth && current_count > 0
        header = i64[3]
        header[0] = 0
        header[1] = beam_width
        header[2] = k
        state_index = 0 ## i64
        while state_index < current_count
          source_index = 0 ## i64
          while source_index < k
            destination = 0 ## i64
            while destination < k
              if source_index != destination
                candidate_u = i64[16]
                candidate_k = i64[16]
                i = 0 ## i64
                while i < k
                  candidate_u[i] = current_u[state_index*k+i]
                  candidate_k[i] = current_k[state_index*k+i]
                  i += 1
                z = ffgr_transvection(candidate_u,candidate_k,k,source_index,destination)
                candidate_output = i64[768]
                candidate_meta = i64[7]
                made = ffgr_materialize_packed(source,config,candidate_u,candidate_k,candidate_output,candidate_meta) ## i64
                expanded += 1
                if made > 0
                  candidate_metrics = i64[3]
                  z = ffgr_compact_metrics(candidate_output,made,external_u,external_v,external_w,external_count,candidate_metrics)
                  effective_terms = made - 2*candidate_metrics[0] ## i64
                  score = (effective_terms + 512)*1000000 + candidate_metrics[2] ## i64
                  if candidate_meta[4] == 0 && score < best_score
                    best_score = score
                    best_count = made
                    best_depth = depth
                    i = 0
                    while i < made*3
                      replacement[i] = candidate_output[i]
                      i += 1
                    i = 0
                    while i < 7
                      best_meta[i] = candidate_meta[i]
                      i += 1
                    i = 0
                    while i < 3
                      best_metrics[i] = candidate_metrics[i]
                      i += 1
                  z = ffgr_beam_insert(next_u,next_k,next_scores,header,candidate_u,candidate_k,score)
              destination += 1
            source_index += 1
          state_index += 1
        current_count = header[0]
        state_index = 0
        while state_index < current_count
          i = 0
          while i < k
            current_u[state_index*k+i] = next_u[state_index*k+i]
            current_k[state_index*k+i] = next_k[state_index*k+i]
            i += 1
          current_scores[state_index] = next_scores[state_index]
          state_index += 1
        depth += 1
      if best_count > 0
        meta[0] = best_count
        meta[1] = best_depth
        meta[2] = expanded
        meta[3] = best_meta[3]
        meta[4] = best_meta[4]
        meta[5] = best_meta[6]
        meta[6] = best_metrics[0]
        meta[7] = best_metrics[2]
        result = best_count
  result

-> ffgr_selected_valid(selected, count, rank) (i64[] i64 i64) i64
  ok = 1 ## i64
  i = 0 ## i64
  while i < count
    if selected[i] < 0 || selected[i] >= rank
      ok = 0
    j = i + 1 ## i64
    while j < count
      if selected[i] == selected[j]
        ok = 0
      j += 1
    i += 1
  ok

# Generic exact packed splice for a materialized gauge replacement.
-> ffgr_apply_current_packed(st, selected, old_count, replacement, new_count) (i64[] i64[] i64 i64[] i64) i64
  result = 0 - 1 ## i64
  valid = ffw_valid(st) ## i64
  if old_count < 2 || old_count > 16 || new_count < 1 || new_count > old_count*old_count
    valid = 0
  if selected.size() < old_count || replacement.size() < new_count*3
    valid = 0
  old_rank = st[6] ## i64
  expected = old_rank - old_count + new_count ## i64
  if expected < 1 || expected > st[4]
    valid = 0
  if valid == 1 && ffgr_selected_valid(selected,old_count,old_rank) == 0
    valid = 0
  old_u = i64[16]
  old_v = i64[16]
  old_w = i64[16]
  if valid == 1
    i = 0 ## i64
    while i < old_count
      slot = st[st[50]+selected[i]] ## i64
      old_u[i] = st[st[44]+slot]
      old_v[i] = st[st[45]+slot]
      old_w[i] = st[st[46]+slot]
      i += 1
  new_u = i64[256]
  new_v = i64[256]
  new_w = i64[256]
  if valid == 1
    z = ffgr_unpack(replacement,new_count,new_u,new_v,new_w) ## i64
    if ffgr_terms_well_formed(new_u,new_v,new_w,new_count) == 0
      valid = 0
  if valid == 1 && ffgr_same_set(old_u,old_v,old_w,old_count,new_u,new_v,new_w,new_count) == 1
    valid = 0
  if valid == 1 && ffgr_replacement_exact(old_u,old_v,old_w,old_count,new_u,new_v,new_w,new_count) == 0
    valid = 0
  # No replacement may collide with an unselected live term.
  if valid == 1
    position = 0 ## i64
    while position < old_rank && valid == 1
      if ffc_position_in(selected,old_count,position) == 0
        slot = st[st[50]+position]
        j = 0 ## i64
        while j < new_count && valid == 1
          if ffc_same_term(st[st[44]+slot],st[st[45]+slot],st[st[46]+slot],new_u[j],new_v[j],new_w[j]) == 1
            valid = 0
          j += 1
      position += 1
  if valid == 1 && ffw_verify_current_exact(st,st[2]) == 0
    valid = 0
  if valid == 1
    rank = old_rank ## i64
    i = 0
    while i < old_count
      rank = ffw_toggle(st,old_u[i],old_v[i],old_w[i],rank)
      i += 1
    i = 0
    while i < new_count
      rank = ffw_toggle(st,new_u[i],new_v[i],new_w[i],rank)
      i += 1
    st[6] = rank
    if rank == expected && ffw_verify_current_exact(st,st[2]) == 1
      result = rank
    if result < 0
      i = 0
      while i < new_count
        rank = ffw_toggle(st,new_u[i],new_v[i],new_w[i],rank)
        i += 1
      i = 0
      while i < old_count
        rank = ffw_toggle(st,old_u[i],old_v[i],old_w[i],rank)
        i += 1
      st[6] = rank
      z = ffw_verify_current_exact(st,st[2])
  result

# Collision-aware exact splice.  A locally rank-neutral/+1 repartition can be
# globally rank-lowering when one of its output terms already lives outside
# the selected window: GF(2) parity then cancels that external term.  The
# original helper above intentionally rejects this case because it promises
# the nominal rank `old-old_count+new_count`; this variant instead toggles the
# complete symmetric difference, reports the actual compacted rank, and keeps
# the full tensor gate as the admission boundary.
-> ffgr_apply_current_packed_compact(st, selected, old_count, replacement, new_count) (i64[] i64[] i64 i64[] i64) i64
  result = 0 - 1 ## i64
  valid = ffw_valid(st) ## i64
  if old_count < 2 || old_count > 16 || new_count < 1 || new_count > old_count*old_count
    valid = 0
  if selected.size() < old_count || replacement.size() < new_count*3
    valid = 0
  old_rank = st[6] ## i64
  if valid == 1 && ffgr_selected_valid(selected,old_count,old_rank) == 0
    valid = 0

  old_u = i64[16]
  old_v = i64[16]
  old_w = i64[16]
  if valid == 1
    i = 0 ## i64
    while i < old_count
      slot = st[st[50]+selected[i]] ## i64
      old_u[i] = st[st[44]+slot]
      old_v[i] = st[st[45]+slot]
      old_w[i] = st[st[46]+slot]
      i += 1

  new_u = i64[256]
  new_v = i64[256]
  new_w = i64[256]
  if valid == 1
    z = ffgr_unpack(replacement,new_count,new_u,new_v,new_w) ## i64
    if ffgr_terms_well_formed(new_u,new_v,new_w,new_count) == 0
      valid = 0
  if valid == 1 && ffgr_same_set(old_u,old_v,old_w,old_count,new_u,new_v,new_w,new_count) == 1
    valid = 0
  if valid == 1 && ffgr_replacement_exact(old_u,old_v,old_w,old_count,new_u,new_v,new_w,new_count) == 0
    valid = 0
  if valid == 1 && ffw_verify_current_exact(st,st[2]) == 0
    valid = 0

  collision = i64[256]
  rank = old_rank ## i64
  if valid == 1
    i = 0
    while i < old_count
      next_rank = ffw_toggle(st,old_u[i],old_v[i],old_w[i],rank) ## i64
      if next_rank != rank - 1
        valid = 0
      rank = next_rank
      i += 1

  # Classify against the post-removal state before touching any output.  Live
  # outputs are removed first, which also makes capacity use minimal.
  collisions = 0 ## i64
  if valid == 1
    i = 0
    while i < new_count
      if ffw_find_term(st,new_u[i],new_v[i],new_w[i]) >= 0
        collision[i] = 1
        collisions += 1
      i += 1
    final_rank = rank + new_count - 2*collisions ## i64
    if final_rank < 1 || final_rank > st[4]
      valid = 0

  if valid == 1
    i = 0
    while i < new_count
      if collision[i] == 1
        next_rank = ffw_toggle(st,new_u[i],new_v[i],new_w[i],rank) ## i64
        if next_rank != rank - 1
          valid = 0
        rank = next_rank
      i += 1
    i = 0
    while i < new_count
      if collision[i] == 0
        next_rank = ffw_toggle(st,new_u[i],new_v[i],new_w[i],rank) ## i64
        if next_rank != rank + 1
          valid = 0
        rank = next_rank
      i += 1
    st[6] = rank
    if valid == 1 && rank == final_rank && ffw_verify_current_exact(st,st[2]) == 1
      result = rank

  if result < 0 && rank != old_rank
    # Involutive rollback.  Remove outputs that were newly inserted, restore
    # outputs that collided, and finally restore the selected source window.
    i = 0
    while i < new_count
      if collision[i] == 0 && ffw_find_term(st,new_u[i],new_v[i],new_w[i]) >= 0
        rank = ffw_toggle(st,new_u[i],new_v[i],new_w[i],rank)
      i += 1
    i = 0
    while i < new_count
      if collision[i] == 1 && ffw_find_term(st,new_u[i],new_v[i],new_w[i]) < 0
        rank = ffw_toggle(st,new_u[i],new_v[i],new_w[i],rank)
      i += 1
    i = 0
    while i < old_count
      if ffw_find_term(st,old_u[i],old_v[i],old_w[i]) < 0
        rank = ffw_toggle(st,old_u[i],old_v[i],old_w[i],rank)
      i += 1
    st[6] = rank
    z = ffw_verify_current_exact(st,st[2]) ## i64
  result
