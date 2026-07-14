# Bounded deterministic frontier search for atomic three-flip tunnels and
# labeled R+2 catalysts.  This is evaluation/reference code, not a pool lane.
# It records duplication by an ordinary one-flip edge and by the complete
# span-3 refactor family before recommending an operator for scheduling.

use flipfleet_tunnel_catalyst

-> fftcs_capture3(us, vs, ws, a, b, c, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  out_u[0] = us[a]
  out_v[0] = vs[a]
  out_w[0] = ws[a]
  out_u[1] = us[b]
  out_v[1] = vs[b]
  out_w[1] = ws[b]
  out_u[2] = us[c]
  out_v[2] = vs[c]
  out_w[2] = ws[c]
  3

-> fftcs_unique3(us, vs, ws) (i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 3
    if us[i] == 0 || vs[i] == 0 || ws[i] == 0
      return 0
    j = i + 1 ## i64
    while j < 3
      if fftc_same_term(us[i], vs[i], ws[i], us[j], vs[j], ws[j]) == 1
        return 0
      j += 1
    i += 1
  1

-> fftcs_one_flip(source_u, source_v, source_w, out_u, out_v, out_w) (i64[] i64[] i64[] i64[] i64[] i64[]) i64
  trial_u = i64[3]
  trial_v = i64[3]
  trial_w = i64[3]
  code = 0 ## i64
  while code < fftc_code_count(3)
    z = fftc_copy_terms(source_u, source_v, source_w, 3, trial_u, trial_v, trial_w) ## i64
    if fftc_apply_code(trial_u, trial_v, trial_w, 3, code, 0 - 1) == 1
      if fftc_terms_same_set(trial_u, trial_v, trial_w, 3, out_u, out_v, out_w, 3) == 1
        return 1
    code += 1
  0

-> fftcs_in_span3(source, value) (i64[] i64) i64
  combo = 0 ## i64
  while combo < 8
    made = 0 ## i64
    bit = 0 ## i64
    while bit < 3
      if ((combo >> bit) & 1) != 0
        made = made ^ source[bit]
      bit += 1
    if made == value
      return 1
    combo += 1
  0

# Exact local equality plus factor membership in the original three spans is
# precisely membership in the complete span-3 search family.
-> fftcs_span3_duplicate(source_u, source_v, source_w, out_u, out_v, out_w) (i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if fftc_local_exact(source_u, source_v, source_w, 3, out_u, out_v, out_w, 3) != 1
    return 0
  i = 0 ## i64
  while i < 3
    if fftcs_in_span3(source_u, out_u[i]) == 0 || fftcs_in_span3(source_v, out_v[i]) == 0 || fftcs_in_span3(source_w, out_w[i]) == 0
      return 0
    i += 1
  1

-> fftcs_selected(index, a, b, c) (i64 i64 i64 i64) i64
  selected = 0 ## i64
  if index == a || index == b || index == c
    selected = 1
  selected

-> fftcs_global_splice_ok(us, vs, ws, rank, a, b, c, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[]) i64
  if fftcs_unique3(out_u, out_v, out_w) != 1
    return 0
  position = 0 ## i64
  while position < rank
    if fftcs_selected(position, a, b, c) == 0
      i = 0 ## i64
      while i < 3
        if fftc_same_term(us[position], vs[position], ws[position], out_u[i], out_v[i], out_w[i]) == 1
          return 0
        i += 1
    position += 1
  1

-> fftcs_connected3(us, vs, ws, a, b, c) (i64[] i64[] i64[] i64 i64 i64) i64
  pairs = i64[6]
  pairs[0] = a
  pairs[1] = b
  pairs[2] = a
  pairs[3] = c
  pairs[4] = b
  pairs[5] = c
  p = 0 ## i64
  while p < 3
    left = pairs[p * 2] ## i64
    right = pairs[p * 2 + 1] ## i64
    if us[left] == us[right] || vs[left] == vs[right] || ws[left] == ws[right]
      return 1
    p += 1
  0

# Scan at most `triple_cap` triples containing a live compatible pair and at
# most `path_cap` final-code attempts.  Meta:
# [0] all triples visited, [1] connected triples scanned, [2] final attempts,
# [3] changed exact path endpoints, [4] one-flip duplicates,
# [5] span-3 duplicates, [6] globally spliceable endpoints,
# [7] best local density delta.  Returns the best collision-free endpoint that
# is not itself one ordinary flip.
-> fftcs_search_tunnels(us, vs, ws, rank, triple_cap, path_cap, selected, out_u, out_v, out_w, path, meta) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if rank < 3 || triple_cap < 1 || path_cap < 1
    return 0
  best_delta = 999999999 ## i64
  found = 0 ## i64
  stop = 0 ## i64
  a = 0 ## i64
  while a < rank - 2 && stop == 0
    b = a + 1 ## i64
    while b < rank - 1 && stop == 0
      c = b + 1 ## i64
      while c < rank && stop == 0
        meta[0] = meta[0] + 1
        if fftcs_connected3(us, vs, ws, a, b, c) == 1
          if meta[1] >= triple_cap
            stop = 1
          if stop == 0
            meta[1] = meta[1] + 1
            source_u = i64[3]
            source_v = i64[3]
            source_w = i64[3]
            z = fftcs_capture3(us, vs, ws, a, b, c, source_u, source_v, source_w) ## i64
            state1_u = i64[3]
            state1_v = i64[3]
            state1_w = i64[3]
            state2_u = i64[3]
            state2_v = i64[3]
            state2_w = i64[3]
            state3_u = i64[3]
            state3_v = i64[3]
            state3_w = i64[3]
            code_count = fftc_code_count(3) ## i64
            code0 = 0 ## i64
            while code0 < code_count && stop == 0
              z = fftc_copy_terms(source_u, source_v, source_w, 3, state1_u, state1_v, state1_w)
              if fftc_apply_code(state1_u, state1_v, state1_w, 3, code0, 0 - 1) == 1
                code1 = 0 ## i64
                while code1 < code_count && stop == 0
                  z = fftc_copy_terms(state1_u, state1_v, state1_w, 3, state2_u, state2_v, state2_w)
                  if fftc_apply_code(state2_u, state2_v, state2_w, 3, code1, 0 - 1) == 1
                    code2 = 0 ## i64
                    while code2 < code_count && stop == 0
                      if meta[2] >= path_cap
                        stop = 1
                      if stop == 0
                        meta[2] = meta[2] + 1
                        z = fftc_copy_terms(state2_u, state2_v, state2_w, 3, state3_u, state3_v, state3_w)
                        if fftc_apply_code(state3_u, state3_v, state3_w, 3, code2, 0 - 1) == 1
                          if fftcs_unique3(state3_u, state3_v, state3_w) == 1
                            if fftc_terms_same_set(source_u, source_v, source_w, 3, state3_u, state3_v, state3_w, 3) == 0
                              if fftc_local_exact(source_u, source_v, source_w, 3, state3_u, state3_v, state3_w, 3) == 1
                                meta[3] = meta[3] + 1
                                one_flip = fftcs_one_flip(source_u, source_v, source_w, state3_u, state3_v, state3_w) ## i64
                                if one_flip == 1
                                  meta[4] = meta[4] + 1
                                span3 = fftcs_span3_duplicate(source_u, source_v, source_w, state3_u, state3_v, state3_w) ## i64
                                if span3 == 1
                                  meta[5] = meta[5] + 1
                                global_ok = fftcs_global_splice_ok(us, vs, ws, rank, a, b, c, state3_u, state3_v, state3_w) ## i64
                                if global_ok == 1
                                  meta[6] = meta[6] + 1
                                  delta = fftc_density(state3_u, state3_v, state3_w, 3) - fftc_density(source_u, source_v, source_w, 3) ## i64
                                  if one_flip == 0 && delta < best_delta
                                    best_delta = delta
                                    selected[0] = a
                                    selected[1] = b
                                    selected[2] = c
                                    z = fftc_copy_terms(state3_u, state3_v, state3_w, 3, out_u, out_v, out_w)
                                    path[0] = code0
                                    path[1] = code1
                                    path[2] = code2
                                    found = 3
                      code2 += 1
                  code1 += 1
              code0 += 1
        c += 1
      b += 1
    a += 1
  if found == 3
    meta[7] = best_delta
  found

# Bounded exhaustive depth-four search for one fixed source triple/catalyst.
# meta: final-code attempts, equal-label endpoints, changed exact endpoints,
# one-flip duplicates.  The first non-one-flip endpoint is returned.
-> fftcs_find_catalyst_endpoint4(source_u, source_v, source_w, catalyst_u, catalyst_v, catalyst_w, node_cap, out_u, out_v, out_w, path, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if catalyst_u == 0 || catalyst_v == 0 || catalyst_w == 0 || node_cap < 1
    return 0
  initial_u = i64[5]
  initial_v = i64[5]
  initial_w = i64[5]
  z = fftc_copy_terms(source_u, source_v, source_w, 3, initial_u, initial_v, initial_w) ## i64
  initial_u[3] = catalyst_u
  initial_v[3] = catalyst_v
  initial_w[3] = catalyst_w
  initial_u[4] = catalyst_u
  initial_v[4] = catalyst_v
  initial_w[4] = catalyst_w
  state1_u = i64[5]
  state1_v = i64[5]
  state1_w = i64[5]
  state2_u = i64[5]
  state2_v = i64[5]
  state2_w = i64[5]
  state3_u = i64[5]
  state3_v = i64[5]
  state3_w = i64[5]
  state4_u = i64[5]
  state4_v = i64[5]
  state4_w = i64[5]
  count = fftc_code_count(5) ## i64
  code0 = 0 ## i64
  while code0 < count && meta[0] < node_cap
    z = fftc_copy_terms(initial_u, initial_v, initial_w, 5, state1_u, state1_v, state1_w)
    if fftc_apply_code(state1_u, state1_v, state1_w, 5, code0, 3) == 1
      code1 = 0 ## i64
      while code1 < count && meta[0] < node_cap
        z = fftc_copy_terms(state1_u, state1_v, state1_w, 5, state2_u, state2_v, state2_w)
        if fftc_apply_code(state2_u, state2_v, state2_w, 5, code1, 3) == 1
          code2 = 0 ## i64
          while code2 < count && meta[0] < node_cap
            z = fftc_copy_terms(state2_u, state2_v, state2_w, 5, state3_u, state3_v, state3_w)
            if fftc_apply_code(state3_u, state3_v, state3_w, 5, code2, 3) == 1
              code3 = 0 ## i64
              while code3 < count && meta[0] < node_cap
                meta[0] = meta[0] + 1
                z = fftc_copy_terms(state3_u, state3_v, state3_w, 5, state4_u, state4_v, state4_w)
                if fftc_apply_code(state4_u, state4_v, state4_w, 5, code3, 3) == 1
                  if fftc_pair_equal(state4_u, state4_v, state4_w, 3, 4) == 1
                    meta[1] = meta[1] + 1
                    if fftcs_unique3(state4_u, state4_v, state4_w) == 1
                      if fftc_terms_same_set(source_u, source_v, source_w, 3, state4_u, state4_v, state4_w, 3) == 0
                        if fftc_local_exact(source_u, source_v, source_w, 3, state4_u, state4_v, state4_w, 3) == 1
                          meta[2] = meta[2] + 1
                          if fftcs_one_flip(source_u, source_v, source_w, state4_u, state4_v, state4_w) == 0
                            z = fftc_copy_terms(state4_u, state4_v, state4_w, 3, out_u, out_v, out_w)
                            path[0] = code0
                            path[1] = code1
                            path[2] = code2
                            path[3] = code3
                            return 3
                          meta[3] = meta[3] + 1
                code3 += 1
            code2 += 1
        code1 += 1
    code0 += 1
  0

# Search catalysts formed from the 3x3x3 Cartesian product of each source
# triple's live factors.  This ensures every label can knock on actual motif
# doors without pretending arbitrary random factors are evidence.  Meta:
# triples tried, catalyst terms tried, final attempts, equal-label endpoints,
# changed exact endpoints, one-flip duplicates, global collisions, span3 dup.
-> fftcs_search_catalysts(us, vs, ws, rank, triple_cap, node_cap, selected, catalyst, out_u, out_v, out_w, path, meta) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if rank < 3 || triple_cap < 1 || node_cap < 1
    return 0
  a = 0 ## i64
  while a < rank - 2 && meta[0] < triple_cap && meta[2] < node_cap
    b = a + 1 ## i64
    while b < rank - 1 && meta[0] < triple_cap && meta[2] < node_cap
      c = b + 1 ## i64
      while c < rank && meta[0] < triple_cap && meta[2] < node_cap
        meta[0] = meta[0] + 1
        source_u = i64[3]
        source_v = i64[3]
        source_w = i64[3]
        z = fftcs_capture3(us, vs, ws, a, b, c, source_u, source_v, source_w) ## i64
        code = 0 ## i64
        prior_u = i64[27]
        prior_v = i64[27]
        prior_w = i64[27]
        prior_count = 0 ## i64
        while code < 27 && meta[2] < node_cap
          ui = code / 9 ## i64
          vi = (code / 3) % 3 ## i64
          wi = code % 3 ## i64
          cat_u = source_u[ui] ## i64
          cat_v = source_v[vi] ## i64
          cat_w = source_w[wi] ## i64
          duplicate = 0 ## i64
          q = 0 ## i64
          while q < prior_count
            if fftc_same_term(prior_u[q], prior_v[q], prior_w[q], cat_u, cat_v, cat_w) == 1
              duplicate = 1
            q += 1
          if duplicate == 0
            prior_u[prior_count] = cat_u
            prior_v[prior_count] = cat_v
            prior_w[prior_count] = cat_w
            prior_count += 1
            meta[1] = meta[1] + 1
            local_meta = i64[4]
            remaining = node_cap - meta[2] ## i64
            hit = fftcs_find_catalyst_endpoint4(source_u, source_v, source_w, cat_u, cat_v, cat_w, remaining, out_u, out_v, out_w, path, local_meta) ## i64
            meta[2] = meta[2] + local_meta[0]
            meta[3] = meta[3] + local_meta[1]
            meta[4] = meta[4] + local_meta[2]
            meta[5] = meta[5] + local_meta[3]
            if hit == 3
              if fftcs_global_splice_ok(us, vs, ws, rank, a, b, c, out_u, out_v, out_w) == 1
                selected[0] = a
                selected[1] = b
                selected[2] = c
                catalyst[0] = cat_u
                catalyst[1] = cat_v
                catalyst[2] = cat_w
                if fftcs_span3_duplicate(source_u, source_v, source_w, out_u, out_v, out_w) == 1
                  meta[7] = meta[7] + 1
                return 3
              meta[6] = meta[6] + 1
          code += 1
        c += 1
      b += 1
    a += 1
  0

-> fftcs_flat_state_equal(left_u, left_v, left_w, left_offset, right_u, right_v, right_w, right_offset) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < 5
    if left_u[left_offset + i] != right_u[right_offset + i] || left_v[left_offset + i] != right_v[right_offset + i] || left_w[left_offset + i] != right_w[right_offset + i]
      return 0
    i += 1
  1

-> fftcs_copy_flat5(source_u, source_v, source_w, source_offset, dest_u, dest_v, dest_w, dest_offset) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < 5
    dest_u[dest_offset + i] = source_u[source_offset + i]
    dest_v[dest_offset + i] = source_v[source_offset + i]
    dest_w[dest_offset + i] = source_w[source_offset + i]
    i += 1
  5

-> fftcs_flat_first3_same_source(state_u, state_v, state_w, offset, source_u, source_v, source_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  local_u = i64[3]
  local_v = i64[3]
  local_w = i64[3]
  i = 0 ## i64
  while i < 3
    local_u[i] = state_u[offset + i]
    local_v[i] = state_v[offset + i]
    local_w[i] = state_w[offset + i]
    i += 1
  fftc_terms_same_set(local_u, local_v, local_w, 3, source_u, source_v, source_w, 3)

-> fftcs_flat_score(state_u, state_v, state_w, offset, source_u, source_v, source_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  equal_axes = 0 ## i64
  if state_u[offset + 3] == state_u[offset + 4]
    equal_axes += 1
  if state_v[offset + 3] == state_v[offset + 4]
    equal_axes += 1
  if state_w[offset + 3] == state_w[offset + 4]
    equal_axes += 1
  changed = 1 - fftcs_flat_first3_same_source(state_u, state_v, state_w, offset, source_u, source_v, source_w) ## i64
  density = 0 ## i64
  i = 0 ## i64
  while i < 5
    density += ffw_popcount(state_u[offset + i]) + ffw_popcount(state_v[offset + i]) + ffw_popcount(state_w[offset + i])
    i += 1
  changed * 100000 + equal_axes * 1000 - density

# Deterministic bounded beam through labeled catalyst state space.  Unlike the
# depth-four exhaustive checker, this can audit depths five and six without a
# 60^depth explosion.  Every returned endpoint is still exact: all edges are
# pair identities and the two labeled terms are required to agree before they
# cancel.  meta: attempted edges, valid edges, states admitted, equal-label
# endpoints, changed exact endpoints, one-flip duplicates, deepest level.
-> fftcs_find_catalyst_beam(source_u, source_v, source_w, catalyst_u, catalyst_v, catalyst_w, max_depth, beam_width, node_cap, out_u, out_v, out_w, path, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if catalyst_u == 0 || catalyst_v == 0 || catalyst_w == 0 || max_depth < 1 || max_depth > 8 || beam_width < 1 || node_cap < 1
    return 0
  beam_u = i64[beam_width * 5]
  beam_v = i64[beam_width * 5]
  beam_w = i64[beam_width * 5]
  beam_paths = i64[beam_width * max_depth]
  i = 0 ## i64
  while i < 3
    beam_u[i] = source_u[i]
    beam_v[i] = source_v[i]
    beam_w[i] = source_w[i]
    i += 1
  beam_u[3] = catalyst_u
  beam_v[3] = catalyst_v
  beam_w[3] = catalyst_w
  beam_u[4] = catalyst_u
  beam_v[4] = catalyst_v
  beam_w[4] = catalyst_w
  beam_count = 1 ## i64
  depth = 0 ## i64
  code_count = fftc_code_count(5) ## i64
  trial_u = i64[5]
  trial_v = i64[5]
  trial_w = i64[5]
  while depth < max_depth && beam_count > 0 && meta[0] < node_cap
    next_u = i64[beam_width * 5]
    next_v = i64[beam_width * 5]
    next_w = i64[beam_width * 5]
    next_paths = i64[beam_width * max_depth]
    next_scores = i64[beam_width]
    next_count = 0 ## i64
    parent = 0 ## i64
    while parent < beam_count && meta[0] < node_cap
      code = 0 ## i64
      while code < code_count && meta[0] < node_cap
        meta[0] = meta[0] + 1
        z = fftcs_copy_flat5(beam_u, beam_v, beam_w, parent * 5, trial_u, trial_v, trial_w, 0) ## i64
        if fftc_apply_code(trial_u, trial_v, trial_w, 5, code, 3) == 1
          meta[1] = meta[1] + 1
          labels_equal = fftc_pair_equal(trial_u, trial_v, trial_w, 3, 4) ## i64
          if labels_equal == 1
            meta[3] = meta[3] + 1
            if fftcs_unique3(trial_u, trial_v, trial_w) == 1
              if fftc_terms_same_set(source_u, source_v, source_w, 3, trial_u, trial_v, trial_w, 3) == 0
                if fftc_local_exact(source_u, source_v, source_w, 3, trial_u, trial_v, trial_w, 3) == 1
                  meta[4] = meta[4] + 1
                  if fftcs_one_flip(source_u, source_v, source_w, trial_u, trial_v, trial_w) == 0
                    z = fftc_copy_terms(trial_u, trial_v, trial_w, 3, out_u, out_v, out_w)
                    r = 0 ## i64
                    while r < depth
                      path[r] = beam_paths[parent * max_depth + r]
                      r += 1
                    path[depth] = code
                    meta[6] = depth + 1
                    return 3
                  meta[5] = meta[5] + 1
          duplicate = 0 ## i64
          slot = 0 ## i64
          while slot < next_count && duplicate == 0
            duplicate = fftcs_flat_state_equal(trial_u, trial_v, trial_w, 0, next_u, next_v, next_w, slot * 5)
            slot += 1
          if duplicate == 0
            score = fftcs_flat_score(trial_u, trial_v, trial_w, 0, source_u, source_v, source_w) ## i64
            target = next_count ## i64
            if next_count < beam_width
              next_count += 1
            if target >= beam_width
              target = 0
              slot = 1
              while slot < beam_width
                if next_scores[slot] < next_scores[target]
                  target = slot
                slot += 1
              if score <= next_scores[target]
                target = 0 - 1
            if target >= 0
              z = fftcs_copy_flat5(trial_u, trial_v, trial_w, 0, next_u, next_v, next_w, target * 5)
              next_scores[target] = score
              r = 0
              while r < depth
                next_paths[target * max_depth + r] = beam_paths[parent * max_depth + r]
                r += 1
              next_paths[target * max_depth + depth] = code
              meta[2] = meta[2] + 1
        code += 1
      parent += 1
    beam_u = next_u
    beam_v = next_v
    beam_w = next_w
    beam_paths = next_paths
    beam_count = next_count
    depth += 1
    meta[6] = depth
  0

# Frontier wrapper for the depth-5/6 beam, using the same live-factor
# Cartesian catalyst motifs as the exhaustive depth-four scan.
-> fftcs_search_catalysts_beam(us, vs, ws, rank, triple_cap, max_depth, beam_width, node_cap, selected, catalyst, out_u, out_v, out_w, path, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if rank < 3 || triple_cap < 1 || node_cap < 1
    return 0
  a = 0 ## i64
  while a < rank - 2 && meta[0] < triple_cap && meta[2] < node_cap
    b = a + 1 ## i64
    while b < rank - 1 && meta[0] < triple_cap && meta[2] < node_cap
      c = b + 1 ## i64
      while c < rank && meta[0] < triple_cap && meta[2] < node_cap
        meta[0] = meta[0] + 1
        source_u = i64[3]
        source_v = i64[3]
        source_w = i64[3]
        z = fftcs_capture3(us, vs, ws, a, b, c, source_u, source_v, source_w) ## i64
        seen_u = i64[27]
        seen_v = i64[27]
        seen_w = i64[27]
        seen = 0 ## i64
        code = 0 ## i64
        while code < 27 && meta[2] < node_cap
          ui = code / 9 ## i64
          vi = (code / 3) % 3 ## i64
          wi = code % 3 ## i64
          cat_u = source_u[ui] ## i64
          cat_v = source_v[vi] ## i64
          cat_w = source_w[wi] ## i64
          duplicate = 0 ## i64
          q = 0 ## i64
          while q < seen
            if fftc_same_term(seen_u[q], seen_v[q], seen_w[q], cat_u, cat_v, cat_w) == 1
              duplicate = 1
            q += 1
          if duplicate == 0
            seen_u[seen] = cat_u
            seen_v[seen] = cat_v
            seen_w[seen] = cat_w
            seen += 1
            meta[1] = meta[1] + 1
            local_meta = i64[7]
            remaining = node_cap - meta[2] ## i64
            hit = fftcs_find_catalyst_beam(source_u, source_v, source_w, cat_u, cat_v, cat_w, max_depth, beam_width, remaining, out_u, out_v, out_w, path, local_meta) ## i64
            meta[2] = meta[2] + local_meta[0]
            meta[3] = meta[3] + local_meta[1]
            meta[4] = meta[4] + local_meta[2]
            meta[5] = meta[5] + local_meta[3]
            meta[6] = meta[6] + local_meta[4]
            meta[7] = meta[7] + local_meta[5]
            if hit == 3
              if fftcs_global_splice_ok(us, vs, ws, rank, a, b, c, out_u, out_v, out_w) == 1
                selected[0] = a
                selected[1] = b
                selected[2] = c
                catalyst[0] = cat_u
                catalyst[1] = cat_v
                catalyst[2] = cat_w
                return 3
          code += 1
        c += 1
      b += 1
    a += 1
  0
