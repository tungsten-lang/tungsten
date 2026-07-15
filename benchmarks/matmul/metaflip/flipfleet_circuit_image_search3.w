# Three-anchor fitting for the three-dimensional primitive circuit bank.
#
# The older circuit-image worker deliberately stops at templates 0..4: those
# relations live in two-dimensional factor spaces and two anchors determine
# their linear image.  Templates 5..7 have 10, 11, and 12 terms and genuinely
# need three independent anchors on every factor axis.  This worker enumerates
# exactly those anchor triples, fits injective maps, and scores the complete
# zero relation against a live scheme.  Toggling the relation is an atomic
# 10--12-term tunnel, beyond the complete span-3/span-4 workers.
#
# A fingerprint is used only for live-term lookup.  Every retained circuit is
# rechecked as a primitive tensor-zero relation, and callers must reconstruct
# the complete matrix-multiplication tensor after applying it.

use flipfleet_circuit_image_search

-> ffcis3_independent(a, b, c) (i64 i64 i64) i64
  if a == 0 || b == 0 || c == 0
    return 0
  if a == b || a == c || b == c
    return 0
  if (a ^ b ^ c) == 0
    return 0
  1

# Solve a full-rank three-equation GF(2) map.  The source masks are elements
# of F_2^3.  Brute force over their seven nonzero combinations is smaller and
# less error-prone than carrying a separate 3x3 inverse representation.
-> ffcis3_fit_axis(source0, source1, source2, destination0, destination1, destination2, maps, offset) (i64 i64 i64 i64 i64 i64 i64[] i64) i64
  if source0 < 1 || source0 > 7 || source1 < 1 || source1 > 7 || source2 < 1 || source2 > 7
    return 0
  if ffcis3_independent(source0, source1, source2) == 0
    return 0
  if ffcis3_independent(destination0, destination1, destination2) == 0
    return 0
  basis = 0 ## i64
  while basis < 3
    target = 1 << basis ## i64
    subset = 1 ## i64
    found = 0 ## i64
    image = 0 ## i64
    while subset < 8
      value = 0 ## i64
      candidate = 0 ## i64
      if (subset & 1) != 0
        value = value ^ source0
        candidate = candidate ^ destination0
      if (subset & 2) != 0
        value = value ^ source1
        candidate = candidate ^ destination1
      if (subset & 4) != 0
        value = value ^ source2
        candidate = candidate ^ destination2
      if value == target
        found += 1
        image = candidate
      subset += 1
    if found != 1 || image == 0
      return 0
    maps[offset + basis] = image
    basis += 1
  if ffcis3_independent(maps[offset], maps[offset + 1], maps[offset + 2]) == 0
    return 0
  if ffc_apply_linear_map(source0, maps, offset, 3) != destination0
    return 0
  if ffc_apply_linear_map(source1, maps, offset, 3) != destination1
    return 0
  if ffc_apply_linear_map(source2, maps, offset, 3) != destination2
    return 0
  1

-> ffcis3_permute(which, slot, a, b, c) (i64 i64 i64 i64 i64) i64
  result = a ## i64
  if which == 0
    if slot == 1
      result = b
    if slot == 2
      result = c
  if which == 1
    if slot == 1
      result = c
    if slot == 2
      result = b
  if which == 2
    if slot == 0
      result = b
    if slot == 1
      result = a
    if slot == 2
      result = c
  if which == 3
    if slot == 0
      result = b
    if slot == 1
      result = c
    if slot == 2
      result = a
  if which == 4
    if slot == 0
      result = c
    if slot == 1
      result = a
    if slot == 2
      result = b
  if which == 5
    if slot == 0
      result = c
    if slot == 1
      result = b
    if slot == 2
      result = a
  result

# Build the complete list of unordered template triples that are bases on all
# three axes.  There are 8, 8, and 16 for templates 5, 6, and 7.
-> ffcis3_build_anchor_bank(template_u, template_v, template_w, template_counts, anchor_templates, anchor0s, anchor1s, anchor2s) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  count = 0 ## i64
  template = 0 ## i64
  while template < 3
    base = template * 12 ## i64
    terms = template_counts[template] ## i64
    a = 0 ## i64
    while a < terms - 2
      b = a + 1 ## i64
      while b < terms - 1
        c = b + 1 ## i64
        while c < terms
          ok = ffcis3_independent(template_u[base + a], template_u[base + b], template_u[base + c]) ## i64
          if ok == 1
            ok = ffcis3_independent(template_v[base + a], template_v[base + b], template_v[base + c])
          if ok == 1
            ok = ffcis3_independent(template_w[base + a], template_w[base + b], template_w[base + c])
          if ok == 1 && count < anchor_templates.size()
            anchor_templates[count] = template
            anchor0s[count] = a
            anchor1s[count] = b
            anchor2s[count] = c
            count += 1
          c += 1
        b += 1
      a += 1
    template += 1
  count

-> ffcis3_toggle(out_u, out_v, out_w, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  position = 0 - 1 ## i64
  i = 0 ## i64
  while i < count && position < 0
    if ffc_same_term(out_u[i], out_v[i], out_w[i], u, v, w) == 1
      position = i
    i += 1
  if position >= 0
    out_u[position] = out_u[count - 1]
    out_v[position] = out_v[count - 1]
    out_w[position] = out_w[count - 1]
    return count - 1
  if count >= capacity || u == 0 || v == 0 || w == 0
    return 0 - 1
  out_u[count] = u
  out_v[count] = v
  out_w[count] = w
  count + 1

-> ffcis3_apply_circuit(us, vs, ws, rank, circuit_u, circuit_v, circuit_w, circuit_count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  if rank < 0 || circuit_count < 1 || out_u.size() < rank + circuit_count || out_v.size() < rank + circuit_count || out_w.size() < rank + circuit_count
    return 0 - 1
  count = 0 ## i64
  i = 0 ## i64
  while i < rank
    count = ffcis3_toggle(out_u, out_v, out_w, count, out_u.size(), us[i], vs[i], ws[i])
    if count < 0
      return 0 - 1
    i += 1
  i = 0
  while i < circuit_count
    count = ffcis3_toggle(out_u, out_v, out_w, count, out_u.size(), circuit_u[i], circuit_v[i], circuit_w[i])
    if count < 0
      return 0 - 1
    i += 1
  count

-> ffcis3_added_axis_values(candidate_u, candidate_v, candidate_w, candidate_live, count, axis) (i64[] i64[] i64[] i64[] i64 i64) i64
  distinct = 0 ## i64
  term = 0 ## i64
  while term < count
    if candidate_live[term] == 0
      value = candidate_u[term] ## i64
      if axis == 1
        value = candidate_v[term]
      if axis == 2
        value = candidate_w[term]
      seen = 0 ## i64
      earlier = 0 ## i64
      while earlier < term
        earlier_value = candidate_u[earlier] ## i64
        if axis == 1
          earlier_value = candidate_v[earlier]
        if axis == 2
          earlier_value = candidate_w[earlier]
        if candidate_live[earlier] == 0 && earlier_value == value
          seen = 1
        earlier += 1
      if seen == 0
        distinct += 1
    term += 1
  distinct

# Exhaustive when fit_cap is zero.  A positive cap bounds fitted anchor/live
# assignments; nonce cyclically rotates the live term labels so capped archive
# runs do not all examine the same lexicographic prefix.  With gauge_only=1,
# retain only exchanges whose added side has more than `overlap` distinct
# factors on every axis.  Such an exchange cannot be a direct k=overlap
# flattening-gauge step in any orientation.
#
# meta:
#   0 template anchor triples, 1 independent live triples, 2 fits attempted,
#   3 consistent injective fits, 4 circuits scored, 5 primitive exact gates,
#   6 rank drops, 7 rank-neutral, 8 debt at most two, 9 best rank delta,
#   10 best density, 11 best circuit size, 12 best overlap, 13 max overlap,
#   14 cap reached, 15 status, 16 rotated live triples visited,
#   17 templates represented in the anchor bank, 18 low-debt circuits whose
#   added side has more distinct factors than the removed side on every axis,
#   19 maximum minimum added-axis cardinality, 20 retained minimum added-axis
#   cardinality.  A 4->6 circuit with value >4 at slot 20 cannot be one direct
#   k=4 flattening-gauge step on any axis.
-> ffcis3_search_triples(us, vs, ws, rank, fit_cap, nonce, gauge_only, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if rank < 3 || fit_cap < 0 || nonce < 0 || gauge_only < 0 || gauge_only > 1 || out_u.size() < 12 || out_v.size() < 12 || out_w.size() < 12 || meta.size() < 21
    return 0
  i = 0 ## i64
  while i < 21
    meta[i] = 0
    i += 1

  template_u = i64[36]
  template_v = i64[36]
  template_w = i64[36]
  template_counts = i64[3]
  scratch_u = i64[12]
  scratch_v = i64[12]
  scratch_w = i64[12]
  template = 0 ## i64
  while template < 3
    count = ffc_template_fill(template + 5, scratch_u, scratch_v, scratch_w) ## i64
    template_counts[template] = count
    term = 0 ## i64
    while term < count
      template_u[template * 12 + term] = scratch_u[term]
      template_v[template * 12 + term] = scratch_v[term]
      template_w[template * 12 + term] = scratch_w[term]
      term += 1
    template += 1
  meta[17] = 3

  anchor_templates = i64[64]
  anchor0s = i64[64]
  anchor1s = i64[64]
  anchor2s = i64[64]
  anchor_count = ffcis3_build_anchor_bank(template_u, template_v, template_w, template_counts, anchor_templates, anchor0s, anchor1s, anchor2s) ## i64
  meta[0] = anchor_count
  if anchor_count != 32
    return 0

  table_capacity = ffcis_table_capacity(rank) ## i64
  table = i32[table_capacity]
  z = ffcis_build_table(us, vs, ws, rank, table) ## i64
  source_density = ffcis_density(us, vs, ws, rank) ## i64
  maps = i64[9]
  candidate_u = i64[12]
  candidate_v = i64[12]
  candidate_w = i64[12]
  candidate_live = i64[12]
  best_delta = 1 << 30 ## i64
  best_density = 9223372036854775807 ## i64
  best_count = 0 ## i64
  best_overlap = 0 ## i64
  best_min_added = 0 ## i64
  rotation = nonce % rank ## i64
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
        meta[16] = meta[16] + 1
        live_ok = ffcis3_independent(us[live_a], us[live_b], us[live_c]) ## i64
        if live_ok == 1
          live_ok = ffcis3_independent(vs[live_a], vs[live_b], vs[live_c])
        if live_ok == 1
          live_ok = ffcis3_independent(ws[live_a], ws[live_b], ws[live_c])
        if live_ok == 1
          meta[1] = meta[1] + 1
          anchor = 0 ## i64
          while anchor < anchor_count && stop == 0
            template = anchor_templates[anchor] ## i64
            base = template * 12 ## i64
            a0 = anchor0s[anchor] ## i64
            a1 = anchor1s[anchor] ## i64
            a2 = anchor2s[anchor] ## i64
            permutation = 0 ## i64
            while permutation < 6 && stop == 0
              if fit_cap > 0 && meta[2] >= fit_cap
                meta[14] = 1
                stop = 1
              if stop == 0
                live0 = ffcis3_permute(permutation, 0, live_a, live_b, live_c) ## i64
                live1 = ffcis3_permute(permutation, 1, live_a, live_b, live_c) ## i64
                live2 = ffcis3_permute(permutation, 2, live_a, live_b, live_c) ## i64
                meta[2] = meta[2] + 1
                ok = ffcis3_fit_axis(template_u[base + a0], template_u[base + a1], template_u[base + a2], us[live0], us[live1], us[live2], maps, 0) ## i64
                if ok == 1
                  ok = ffcis3_fit_axis(template_v[base + a0], template_v[base + a1], template_v[base + a2], vs[live0], vs[live1], vs[live2], maps, 3)
                if ok == 1
                  ok = ffcis3_fit_axis(template_w[base + a0], template_w[base + a1], template_w[base + a2], ws[live0], ws[live1], ws[live2], maps, 6)
                if ok == 1
                  meta[3] = meta[3] + 1
                  count = template_counts[template] ## i64
                  term = 0
                  while term < count
                    candidate_u[term] = ffc_apply_linear_map(template_u[base + term], maps, 0, 3)
                    candidate_v[term] = ffc_apply_linear_map(template_v[base + term], maps, 3, 3)
                    candidate_w[term] = ffc_apply_linear_map(template_w[base + term], maps, 6, 3)
                    term += 1
                  overlap = 0 ## i64
                  candidate_density = source_density ## i64
                  term = 0
                  while term < count
                    position = ffcis_lookup(us, vs, ws, table, candidate_u[term], candidate_v[term], candidate_w[term]) ## i64
                    term_density = ffw_popcount(candidate_u[term]) + ffw_popcount(candidate_v[term]) + ffw_popcount(candidate_w[term]) ## i64
                    if position >= 0
                      candidate_live[term] = 1
                      overlap += 1
                      candidate_density -= term_density
                    else
                      candidate_live[term] = 0
                      candidate_density += term_density
                    term += 1
                  meta[4] = meta[4] + 1
                  if overlap > meta[13]
                    meta[13] = overlap
                  delta = count - overlap * 2 ## i64
                  if delta < 0
                    meta[6] = meta[6] + 1
                  if delta == 0
                    meta[7] = meta[7] + 1
                  if delta <= 2
                    meta[8] = meta[8] + 1
                  min_added = 0 ## i64
                  if delta <= 4
                    added_u = ffcis3_added_axis_values(candidate_u, candidate_v, candidate_w, candidate_live, count, 0) ## i64
                    added_v = ffcis3_added_axis_values(candidate_u, candidate_v, candidate_w, candidate_live, count, 1) ## i64
                    added_w = ffcis3_added_axis_values(candidate_u, candidate_v, candidate_w, candidate_live, count, 2) ## i64
                    min_added = added_u
                    if added_v < min_added
                      min_added = added_v
                    if added_w < min_added
                      min_added = added_w
                    if min_added > meta[19]
                      meta[19] = min_added
                    if min_added > overlap
                      meta[18] = meta[18] + 1
                  eligible = 1 ## i64
                  if gauge_only == 1 && min_added <= overlap
                    eligible = 0
                  if eligible == 1 && (delta < best_delta || (delta == best_delta && min_added > best_min_added) || (delta == best_delta && min_added == best_min_added && candidate_density < best_density))
                    # This exact gate is intentionally inside the miner.  The
                    # injective-map argument is sufficient algebraically, but
                    # a retained endpoint never relies on that argument alone.
                    if ffc_is_primitive_circuit(candidate_u, candidate_v, candidate_w, count) == 1
                      meta[5] = meta[5] + 1
                      best_delta = delta
                      best_density = candidate_density
                      best_count = count
                      best_overlap = overlap
                      best_min_added = min_added
                      term = 0
                      while term < count
                        out_u[term] = candidate_u[term]
                        out_v[term] = candidate_v[term]
                        out_w[term] = candidate_w[term]
                        term += 1
              permutation += 1
            anchor += 1
        raw2 += 1
      raw1 += 1
    raw0 += 1

  if best_count > 0
    meta[9] = best_delta
    meta[10] = best_density
    meta[11] = best_count
    meta[12] = best_overlap
    meta[20] = best_min_added
    meta[15] = 1
    return best_count
  0
