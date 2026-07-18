# Production pooled move: dynamic exact circuit mining over a live window plus nearby terms.
# A kernel on the live columns alone would be an immediate deletion.  The
# useful extension is to add bounded one-factor XOR neighbors, compute the
# exact ambient-tensor kernel, and toggle a relation containing new terms.
# `nonce` offsets the affinity-window stream so repeated pool launches do not
# replay the same fundamental circuits.

use pooled_exact

-> ffds_add_candidate(cu, cv, cw, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return count
  i = 0 ## i64
  while i < count
    if cu[i] == u && cv[i] == v && cw[i] == w
      return count
    i += 1
  if count < capacity
    cu[count] = u
    cv[count] = v
    cw[count] = w
    count += 1
  count

-> ffds_expand(u, v, w, uw, vw, ww, row, offset, limbs) (i64 i64 i64 i64 i64 i64 i64[] i64 i64) i64
  limb = 0 ## i64
  while limb < limbs
    row[offset + limb] = 0
    limb += 1
  a = 0 ## i64
  while a < uw
    if ((u >> a) & 1) == 1
      b = 0 ## i64
      while b < vw
        if ((v >> b) & 1) == 1
          c = 0 ## i64
          while c < ww
            if ((w >> c) & 1) == 1
              coordinate = (a * vw + b) * ww + c ## i64
              li = coordinate / 64 ## i64
              bit = coordinate % 64 ## i64
              row[offset + li] = row[offset + li] ^ (1 << bit)
            c += 1
        b += 1
    a += 1
  1

-> ffds_first_bit(row, offset, limbs, ambient) (i64[] i64 i64 i64) i64
  coordinate = 0 ## i64
  while coordinate < ambient
    limb = coordinate / 64 ## i64
    bit = coordinate % 64 ## i64
    if ((row[offset + limb] >> bit) & 1) == 1
      return coordinate
    coordinate += 1
  0 - 1

-> ffds_xor_row(target, target_offset, source, source_offset, limbs) (i64[] i64 i64[] i64 i64) i64
  limb = 0 ## i64
  while limb < limbs
    target[target_offset + limb] = target[target_offset + limb] ^ source[source_offset + limb]
    limb += 1
  1

-> ffds_window(us, vs, ws, rank, count, nonce, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  selected[0] = nonce % rank
  made = 1 ## i64
  while made < count
    best = 0 - 1 ## i64
    best_score = 0 - 1 ## i64
    candidate = 0 ## i64
    while candidate < rank
      used = 0 ## i64
      j = 0 ## i64
      while j < made
        if selected[j] == candidate
          used = 1
        j += 1
      if used == 0
        score = 0 ## i64
        j = 0
        while j < made
          score += ffw_popcount(us[selected[j]] & us[candidate])
          score += ffw_popcount(vs[selected[j]] & vs[candidate])
          score += ffw_popcount(ws[selected[j]] & ws[candidate])
          if us[selected[j]] == us[candidate]
            score += 8
          if vs[selected[j]] == vs[candidate]
            score += 8
          if ws[selected[j]] == ws[candidate]
            score += 8
          j += 1
        if score > best_score
          best_score = score
          best = candidate
      candidate += 1
    if best < 0
      return 0
    selected[made] = best
    made += 1
  made

-> ffds_search(us, vs, ws, rank, n, m, p, budget, nonce, out_u, out_v, out_w, stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  z = ffpe_clear(stats) ## i64
  if rank < 3 || budget < 1
    return 0
  uw = n * m ## i64
  vw = m * p ## i64
  ww = n * p ## i64
  ambient = uw * vw * ww ## i64
  limbs = (ambient + 63) / 64 ## i64
  best_rank = rank + 100 ## i64
  best_density = 0x7fffffff ## i64
  live_count = 8 ## i64
  if live_count > rank
    live_count = rank
  cap = 60 ## i64
  # Tungsten campaign allocations live for the worker's lifetime. Keep the
  # O(cap * n^6/64) elimination arena flat across attempts instead of
  # retaining another ~2.7 MB at every 7x7 window.
  selected = i64[live_count]
  cu = i64[cap]
  cv = i64[cap]
  cw = i64[cap]
  vectors = i64[cap * limbs]
  basis = i64[cap * limbs]
  basis_combo = i64[cap]
  pivot_owner = i64[ambient]
  candidate_u = i64[rank + cap]
  candidate_v = i64[rank + cap]
  candidate_w = i64[rank + cap]
  attempt = 0 ## i64
  while attempt < budget
    logical_attempt = nonce + attempt ## i64
    stats[0] += 1
    if ffds_window(us, vs, ws, rank, live_count, logical_attempt * 19 + 1, selected) == live_count
      candidate_count = 0 ## i64
      i = 0 ## i64
      while i < live_count
        candidate_count = ffds_add_candidate(cu, cv, cw, candidate_count, cap, us[selected[i]], vs[selected[i]], ws[selected[i]])
        i += 1
      i = 0
      while i < live_count && candidate_count < cap
        j = 0 ## i64
        while j < live_count && candidate_count < cap
          if i != j
            axis = 0 ## i64
            while axis < 3 && candidate_count < cap
              u = us[selected[i]] ## i64
              v = vs[selected[i]] ## i64
              w = ws[selected[i]] ## i64
              if axis == 0
                u = u ^ us[selected[j]]
              if axis == 1
                v = v ^ vs[selected[j]]
              if axis == 2
                w = w ^ ws[selected[j]]
              candidate_count = ffds_add_candidate(cu, cv, cw, candidate_count, cap, u, v, w)
              axis += 1
          j += 1
        i += 1
      coordinate = 0 ## i64
      while coordinate < ambient
        pivot_owner[coordinate] = 0 - 1
        coordinate += 1
      basis_count = 0 ## i64
      cidx = 0 ## i64
      while cidx < candidate_count
        z = ffds_expand(cu[cidx], cv[cidx], cw[cidx], uw, vw, ww, vectors, cidx * limbs, limbs)
        combo = 1 << cidx ## i64
        reducing = 1 ## i64
        while reducing == 1
          pivot = ffds_first_bit(vectors, cidx * limbs, limbs, ambient) ## i64
          if pivot < 0
            reducing = 0
            live_bits = 0 ## i64
            new_bits = 0 ## i64
            bit_index = 0 ## i64
            while bit_index < candidate_count
              if ((combo >> bit_index) & 1) == 1
                if bit_index < live_count
                  live_bits += 1
                else
                  new_bits += 1
              bit_index += 1
            # A one-live-term split relation is merely a way to manufacture
            # rank debt.  Require a circuit to touch at least two live terms;
            # live-only dependencies remain admissible because they expose an
            # immediate deletion in a nonminimal input scheme.
            if live_bits > 1
              count = ffpe_copy(us, vs, ws, rank, candidate_u, candidate_v, candidate_w) ## i64
              bit_index = 0
              while bit_index < candidate_count
                if ((combo >> bit_index) & 1) == 1
                  candidate_u[count] = cu[bit_index]
                  candidate_v[count] = cv[bit_index]
                  candidate_w[count] = cw[bit_index]
                  count += 1
                bit_index += 1
              candidate_rank = ffpe_compact(candidate_u, candidate_v, candidate_w, count) ## i64
              # Atomic tunnels should be rank-neutral or closing.  Higher-rank
              # fundamental circuits are valid algebraically, but belong in a
              # separately budgeted debt/shoulder strategy rather than being
              # silently returned by this move.
              if candidate_rank <= rank && ffpe_note(us, vs, ws, rank, candidate_u, candidate_v, candidate_w, candidate_rank, n, m, p, stats) == 1
                candidate_density = ffpe_density(candidate_u, candidate_v, candidate_w, candidate_rank) ## i64
                if candidate_rank < best_rank || (candidate_rank == best_rank && candidate_density < best_density)
                  best_rank = candidate_rank
                  best_density = candidate_density
                  z = ffpe_copy(candidate_u, candidate_v, candidate_w, candidate_rank, out_u, out_v, out_w)
                  if candidate_rank < rank
                    return candidate_rank
          if pivot >= 0
            owner = pivot_owner[pivot] ## i64
            if owner >= 0
              z = ffds_xor_row(vectors, cidx * limbs, basis, owner * limbs, limbs)
              combo = combo ^ basis_combo[owner]
            if owner < 0
              limb = 0 ## i64
              while limb < limbs
                basis[basis_count * limbs + limb] = vectors[cidx * limbs + limb]
                limb += 1
              basis_combo[basis_count] = combo
              pivot_owner[pivot] = basis_count
              basis_count += 1
              reducing = 0
        cidx += 1
    attempt += 1
  if best_rank <= rank + 50
    return best_rank
  0
