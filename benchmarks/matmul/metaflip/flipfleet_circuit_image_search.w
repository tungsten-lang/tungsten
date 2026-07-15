# Exhaustive two-anchor fitting for linear images of primitive circuits.
#
# Templates 0..4 live in two-dimensional factor spaces.  Every ordered pair
# of live terms is fitted to every ordered template anchor pair.  When the
# induced maps are injective on the factor spans actually used by a template,
# its image is automatically the same primitive zero circuit.  Toggling all
# image terms therefore gives an exact endpoint.  Two fitted anchors make the
# five-term template a structured +1 escape; extra live overlap can make the
# same operation rank-neutral or rank-lowering.

use flipfleet_circuit_images

-> ffcis_hash(u, v, w) (i64 i64 i64) i64
  value = (u * 6364136223846793005 + v * 1442695040888963407 + w * 2862933555777941757) & 9223372036854775807 ## i64
  value = value ^ (value >> 29)
  value

-> ffcis_table_capacity(count) (i64) i64
  capacity = 16 ## i64
  while capacity < count * 4
    capacity *= 2
  capacity

-> ffcis_build_table(us, vs, ws, count, slots) (i64[] i64[] i64[] i64 i32[]) i64
  i = 0 ## i64
  while i < slots.size()
    slots[i] = 0
    i += 1
  i = 0
  while i < count
    slot = ffcis_hash(us[i], vs[i], ws[i]) & (slots.size() - 1) ## i64
    while slots[slot] != 0
      slot = (slot + 1) & (slots.size() - 1)
    slots[slot] = i + 1
    i += 1
  count

-> ffcis_lookup(us, vs, ws, slots, u, v, w) (i64[] i64[] i64[] i32[] i64 i64 i64) i64
  slot = ffcis_hash(u, v, w) & (slots.size() - 1) ## i64
  probes = 0 ## i64
  while probes < slots.size()
    entry = slots[slot] ## i64
    if entry == 0
      return 0 - 1
    index = entry - 1 ## i64
    if ffc_same_term(us[index], vs[index], ws[index], u, v, w) == 1
      return index
    slot = (slot + 1) & (slots.size() - 1)
    probes += 1
  0 - 1

# Solve two equations in the two column images of a GF(2) linear map.  Equal
# source masks require equal destinations and leave one column at the fixed
# deterministic zero gauge; distinct nonzero masks determine both columns.
-> ffcis_fit_axis2(source0, source1, destination0, destination1, maps, offset) (i64 i64 i64 i64 i64[] i64) i64
  if source0 < 1 || source0 > 3 || source1 < 1 || source1 > 3 || destination0 == 0 || destination1 == 0
    return 0
  maps[offset] = 0
  maps[offset + 1] = 0
  if source0 == source1
    if destination0 != destination1
      return 0
    if source0 == 1
      maps[offset] = destination0
    if source0 == 2
      maps[offset + 1] = destination0
    if source0 == 3
      maps[offset] = destination0
    return 1
  if source0 == 1
    maps[offset] = destination0
    if source1 == 2
      maps[offset + 1] = destination1
    if source1 == 3
      maps[offset + 1] = destination0 ^ destination1
  if source0 == 2
    maps[offset + 1] = destination0
    if source1 == 1
      maps[offset] = destination1
    if source1 == 3
      maps[offset] = destination0 ^ destination1
  if source0 == 3
    if source1 == 1
      maps[offset] = destination1
      maps[offset + 1] = destination0 ^ destination1
    if source1 == 2
      maps[offset + 1] = destination1
      maps[offset] = destination0 ^ destination1
  if ffc_apply_linear_map(source0, maps, offset, 2) != destination0
    return 0
  if ffc_apply_linear_map(source1, maps, offset, 2) != destination1
    return 0
  1

-> ffcis_template_axis_rank(values, count) (i64[] i64) i64
  first = values[0] ## i64
  rank = 1 ## i64
  i = 1 ## i64
  while i < count
    if values[i] != first
      rank = 2
    i += 1
  rank

-> ffcis_axis_injective(values, count, maps, offset) (i64[] i64 i64[] i64) i64
  rank = ffcis_template_axis_rank(values, count) ## i64
  if rank == 1
    if ffc_apply_linear_map(values[0], maps, offset, 2) != 0
      return 1
    return 0
  left = maps[offset] ## i64
  right = maps[offset + 1] ## i64
  if left != 0 && right != 0 && left != right
    return 1
  0

-> ffcis_density(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < count
    density += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  density

# meta: fits attempted, consistent fits, injective images, circuits scored,
# rank drops, rank-neutral, +1, +2, best delta, best density, best count,
# best overlap, maximum overlap.
-> ffcis_search_pairs(us, vs, ws, rank, max_template, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  if rank < 2 || max_template < 0 || max_template > 4 || out_u.size() < 12 || out_v.size() < 12 || out_w.size() < 12 || meta.size() < 13
    return 0
  i = 0 ## i64
  while i < 13
    meta[i] = 0
    i += 1
  source_density = ffcis_density(us, vs, ws, rank) ## i64
  table_capacity = ffcis_table_capacity(rank) ## i64
  table = i32[table_capacity]
  ffcis_build_table(us, vs, ws, rank, table)
  template_u = i64[12]
  template_v = i64[12]
  template_w = i64[12]
  candidate_u = i64[12]
  candidate_v = i64[12]
  candidate_w = i64[12]
  maps = i64[9]
  best_delta = 1 << 30 ## i64
  best_density = 1 << 30 ## i64
  best_count = 0 ## i64
  best_overlap = 0 ## i64

  template_id = 0 ## i64
  while template_id <= max_template
    count = ffc_template_fill(template_id, template_u, template_v, template_w) ## i64
    anchor0 = 0 ## i64
    while anchor0 < count
      anchor1 = anchor0 + 1 ## i64
      while anchor1 < count
        live0 = 0 ## i64
        while live0 < rank
          live1 = 0 ## i64
          while live1 < rank
            if live0 != live1
              meta[0] = meta[0] + 1
              ok = ffcis_fit_axis2(template_u[anchor0], template_u[anchor1], us[live0], us[live1], maps, 0) ## i64
              if ok == 1
                ok = ffcis_fit_axis2(template_v[anchor0], template_v[anchor1], vs[live0], vs[live1], maps, 3)
              if ok == 1
                ok = ffcis_fit_axis2(template_w[anchor0], template_w[anchor1], ws[live0], ws[live1], maps, 6)
              if ok == 1
                meta[1] = meta[1] + 1
                if ffcis_axis_injective(template_u, count, maps, 0) == 0
                  ok = 0
                if ffcis_axis_injective(template_v, count, maps, 3) == 0
                  ok = 0
                if ffcis_axis_injective(template_w, count, maps, 6) == 0
                  ok = 0
              if ok == 1
                meta[2] = meta[2] + 1
                term = 0 ## i64
                while term < count
                  candidate_u[term] = ffc_apply_linear_map(template_u[term], maps, 0, 2)
                  candidate_v[term] = ffc_apply_linear_map(template_v[term], maps, 3, 2)
                  candidate_w[term] = ffc_apply_linear_map(template_w[term], maps, 6, 2)
                  term += 1
                overlap = 0 ## i64
                candidate_density = source_density ## i64
                term = 0
                while term < count
                  position = ffcis_lookup(us, vs, ws, table, candidate_u[term], candidate_v[term], candidate_w[term]) ## i64
                  term_density = ffw_popcount(candidate_u[term]) + ffw_popcount(candidate_v[term]) + ffw_popcount(candidate_w[term]) ## i64
                  if position >= 0
                    overlap += 1
                    candidate_density -= term_density
                  else
                    candidate_density += term_density
                  term += 1
                meta[3] = meta[3] + 1
                if overlap > meta[12]
                  meta[12] = overlap
                delta = count - overlap - overlap ## i64
                if delta < 0
                  meta[4] = meta[4] + 1
                if delta == 0
                  meta[5] = meta[5] + 1
                if delta == 1
                  meta[6] = meta[6] + 1
                if delta == 2
                  meta[7] = meta[7] + 1
                if delta < best_delta || (delta == best_delta && candidate_density < best_density) || (delta == best_delta && candidate_density == best_density && count > best_count)
                  best_delta = delta
                  best_density = candidate_density
                  best_count = count
                  best_overlap = overlap
                  term = 0
                  while term < count
                    out_u[term] = candidate_u[term]
                    out_v[term] = candidate_v[term]
                    out_w[term] = candidate_w[term]
                    term += 1
            live1 += 1
          live0 += 1
        anchor1 += 1
      anchor0 += 1
    template_id += 1

  if best_count == 0
    return 0
  meta[8] = best_delta
  meta[9] = best_density
  meta[10] = best_count
  meta[11] = best_overlap
  best_count
