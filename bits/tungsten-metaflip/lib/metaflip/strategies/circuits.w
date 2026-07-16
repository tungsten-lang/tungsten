# Exact linear images of a bounded bank of primitive Segre circuits.
#
# A circuit is a minimal GF(2) dependency among nonzero rank-one tensors.
# The bank below contains one checked primitive circuit of every cardinality
# from five through twelve.  Templates 0..4 use two source coordinates;
# templates 5..7 use three.  Independent linear maps P,Q,R may embed a
# template into any factor space supported by Metaflip (at most 49 bits).
# The maps are deliberately allowed to be rank deficient: the exact primitive
# gate, rather than an injectivity assumption, decides whether their image is
# still a useful circuit.
#
# `maps` is packed as three groups of three column images:
#   P columns maps[0..2], Q columns maps[3..5], R columns maps[6..8].
# Unused columns are ignored for two-dimensional templates.
#
# Public bounded surface:
#   ffc_template_fill(id,u,v,w)                    -> 5..12, or 0
#   ffc_map_template_raw(id,maps,u,v,w,meta)       -> exact zero relation
#   ffc_map_template(id,maps,u,v,w,meta)           -> primitive image or 0
#   ffc_fit_anchors(id,slots,packed,count,maps,meta)-> recovered linear maps
#   ffc_apply_circuit_current(st,u,v,w,count,mask)  -> new rank or -1
#
# `packed` is [u0,v0,w0,u1,v1,w1,...].  Anchor slots name template terms.
# `mask` chooses the live side of a circuit; its complement is spliced in.

use ../scheme

-> ffc_template_count(template_id) (i64) i64
  count = 0 ## i64
  if template_id >= 0 && template_id < 8
    count = template_id + 5
  count

-> ffc_template_dimension(template_id) (i64) i64
  dimension = 0 ## i64
  if template_id >= 0 && template_id < 5
    dimension = 2
  if template_id >= 5 && template_id < 8
    dimension = 3
  dimension

-> ffc_set_term(us, vs, ws, index, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  us[index] = u
  vs[index] = v
  ws[index] = w
  index + 1

# These were selected by exact binary-matroid rank, not by a probabilistic
# fingerprint.  For each entry, the XOR of all outer products is zero and the
# tensor-column rank is exactly cardinality-1.
-> ffc_template_fill(template_id, us, vs, ws) (i64 i64[] i64[] i64[]) i64
  result = 0 ## i64
  count = ffc_template_count(template_id) ## i64
  if count > 0 && us.size() >= count && vs.size() >= count && ws.size() >= count
    if template_id == 0
      z = ffc_set_term(us,vs,ws,0,1,1,1) ## i64
      z = ffc_set_term(us,vs,ws,1,1,1,3)
      z = ffc_set_term(us,vs,ws,2,3,1,1)
      z = ffc_set_term(us,vs,ws,3,2,1,2)
      z = ffc_set_term(us,vs,ws,4,3,1,3)
    if template_id == 1
      z = ffc_set_term(us,vs,ws,0,3,2,2)
      z = ffc_set_term(us,vs,ws,1,2,1,3)
      z = ffc_set_term(us,vs,ws,2,3,3,1)
      z = ffc_set_term(us,vs,ws,3,1,1,3)
      z = ffc_set_term(us,vs,ws,4,3,1,1)
      z = ffc_set_term(us,vs,ws,5,3,3,3)
    if template_id == 2
      z = ffc_set_term(us,vs,ws,0,2,1,2)
      z = ffc_set_term(us,vs,ws,1,1,1,1)
      z = ffc_set_term(us,vs,ws,2,1,3,3)
      z = ffc_set_term(us,vs,ws,3,1,2,3)
      z = ffc_set_term(us,vs,ws,4,1,3,2)
      z = ffc_set_term(us,vs,ws,5,3,2,2)
      z = ffc_set_term(us,vs,ws,6,2,3,2)
    if template_id == 3
      z = ffc_set_term(us,vs,ws,0,2,3,1)
      z = ffc_set_term(us,vs,ws,1,1,3,2)
      z = ffc_set_term(us,vs,ws,2,3,1,2)
      z = ffc_set_term(us,vs,ws,3,3,1,3)
      z = ffc_set_term(us,vs,ws,4,1,1,2)
      z = ffc_set_term(us,vs,ws,5,3,3,1)
      z = ffc_set_term(us,vs,ws,6,1,2,3)
      z = ffc_set_term(us,vs,ws,7,2,1,1)
    if template_id == 4
      z = ffc_set_term(us,vs,ws,0,1,2,1)
      z = ffc_set_term(us,vs,ws,1,1,3,1)
      z = ffc_set_term(us,vs,ws,2,3,1,3)
      z = ffc_set_term(us,vs,ws,3,1,3,3)
      z = ffc_set_term(us,vs,ws,4,2,2,2)
      z = ffc_set_term(us,vs,ws,5,1,2,3)
      z = ffc_set_term(us,vs,ws,6,2,3,2)
      z = ffc_set_term(us,vs,ws,7,3,2,1)
      z = ffc_set_term(us,vs,ws,8,3,3,1)
    if template_id == 5
      z = ffc_set_term(us,vs,ws,0,2,3,5)
      z = ffc_set_term(us,vs,ws,1,5,4,6)
      z = ffc_set_term(us,vs,ws,2,2,7,6)
      z = ffc_set_term(us,vs,ws,3,7,4,5)
      z = ffc_set_term(us,vs,ws,4,7,7,4)
      z = ffc_set_term(us,vs,ws,5,7,7,7)
      z = ffc_set_term(us,vs,ws,6,1,2,6)
      z = ffc_set_term(us,vs,ws,7,5,2,5)
      z = ffc_set_term(us,vs,ws,8,5,1,3)
      z = ffc_set_term(us,vs,ws,9,4,2,6)
    if template_id == 6
      z = ffc_set_term(us,vs,ws,0,3,1,5)
      z = ffc_set_term(us,vs,ws,1,7,4,7)
      z = ffc_set_term(us,vs,ws,2,3,2,5)
      z = ffc_set_term(us,vs,ws,3,1,1,7)
      z = ffc_set_term(us,vs,ws,4,2,4,6)
      z = ffc_set_term(us,vs,ws,5,4,4,3)
      z = ffc_set_term(us,vs,ws,6,7,4,4)
      z = ffc_set_term(us,vs,ws,7,1,4,4)
      z = ffc_set_term(us,vs,ws,8,1,6,5)
      z = ffc_set_term(us,vs,ws,9,1,5,2)
      z = ffc_set_term(us,vs,ws,10,2,7,5)
    if template_id == 7
      z = ffc_set_term(us,vs,ws,0,7,2,1)
      z = ffc_set_term(us,vs,ws,1,7,2,2)
      z = ffc_set_term(us,vs,ws,2,3,4,3)
      z = ffc_set_term(us,vs,ws,3,3,6,2)
      z = ffc_set_term(us,vs,ws,4,6,2,5)
      z = ffc_set_term(us,vs,ws,5,6,5,3)
      z = ffc_set_term(us,vs,ws,6,2,4,1)
      z = ffc_set_term(us,vs,ws,7,6,3,7)
      z = ffc_set_term(us,vs,ws,8,7,6,1)
      z = ffc_set_term(us,vs,ws,9,6,6,6)
      z = ffc_set_term(us,vs,ws,10,4,2,2)
      z = ffc_set_term(us,vs,ws,11,6,7,4)
    result = count
  result

-> ffc_same_term(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  same = 0 ## i64
  if u0 == u1 && v0 == v1 && w0 == w1
    same = 1
  same

-> ffc_terms_well_formed(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  ok = 0 ## i64
  if count >= 1 && count <= 12 && us.size() >= count && vs.size() >= count && ws.size() >= count
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

-> ffc_mask_width(mask) (i64) i64
  width = 0 ## i64
  if mask > 0
    while width < 63 && (mask >> width) != 0
      width += 1
  width

-> ffc_max_width(values, count) (i64[] i64) i64
  width = 0 ## i64
  i = 0 ## i64
  while i < count
    candidate = ffc_mask_width(values[i]) ## i64
    if candidate > width
      width = candidate
    i += 1
  width

# Compute the exact column rank of the selected rank-one tensors from their
# tensor-cell rows.  Only a 12-word binary basis is retained; no tensor bitmap
# and no hash/fingerprint is required even when the ambient tensor has 49^3
# cells.  meta = [column rank, zero-sum flag, well-formed flag].
-> ffc_relation_analyze(us, vs, ws, count, meta) (i64[] i64[] i64[] i64 i64[]) i64
  rank = 0 ## i64
  zero_sum = 1 ## i64
  well_formed = ffc_terms_well_formed(us,vs,ws,count) ## i64
  if meta.size() >= 3
    meta[0] = 0
    meta[1] = 0
    meta[2] = well_formed
  if well_formed == 1
    ubits = ffc_max_width(us,count) ## i64
    vbits = ffc_max_width(vs,count) ## i64
    wbits = ffc_max_width(ws,count) ## i64
    basis = i64[12]
    ui = 0 ## i64
    while ui < ubits
      vi = 0 ## i64
      while vi < vbits
        wi = 0 ## i64
        while wi < wbits
          row_mask = 0 ## i64
          term = 0 ## i64
          while term < count
            if ((us[term] >> ui) & 1) != 0
              if ((vs[term] >> vi) & 1) != 0
                if ((ws[term] >> wi) & 1) != 0
                  row_mask = row_mask ^ (1 << term)
            term += 1
          if (ffw_popcount(row_mask) & 1) != 0
            zero_sum = 0
          value = row_mask ## i64
          pivot = count - 1 ## i64
          while pivot >= 0 && value != 0
            if ((value >> pivot) & 1) != 0
              if basis[pivot] != 0
                value = value ^ basis[pivot]
              else
                basis[pivot] = value
                rank += 1
                value = 0
            pivot -= 1
          wi += 1
        vi += 1
      ui += 1
  if meta.size() >= 3
    meta[0] = rank
    meta[1] = zero_sum
    meta[2] = well_formed
  rank

-> ffc_is_primitive_circuit(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  ok = 0 ## i64
  meta = i64[3]
  rank = ffc_relation_analyze(us,vs,ws,count,meta) ## i64
  if meta[2] == 1 && meta[1] == 1 && rank == count - 1
    ok = 1
  ok

-> ffc_apply_linear_map(value, maps, offset, dimension) (i64 i64[] i64 i64) i64
  mapped = 0 ## i64
  bit = 0 ## i64
  while bit < dimension
    if ((value >> bit) & 1) != 0
      mapped = mapped ^ maps[offset + bit]
    bit += 1
  mapped

-> ffc_map_rank(maps, offset, dimension) (i64[] i64 i64) i64
  basis = i64[3]
  rank = 0 ## i64
  i = 0 ## i64
  while i < dimension
    # Exact tiny-span test.
    dependent = 0 ## i64
    combo = 0 ## i64
    while combo < (1 << rank)
      made = 0 ## i64
      j = 0 ## i64
      while j < rank
        if ((combo >> j) & 1) != 0
          made = made ^ basis[j]
        j += 1
      if made == maps[offset + i]
        dependent = 1
      combo += 1
    if dependent == 0 && maps[offset + i] != 0
      basis[rank] = maps[offset + i]
      rank += 1
    i += 1
  rank

# Raw mapping preserves the zero relation algebraically, even when a map is
# singular and produces a non-primitive image.  meta layout:
# [0] dimension [1] count [2] relation rank [3] zero [4] well formed
# [5] primitive [6..8] P/Q/R map ranks.
-> ffc_map_template_raw(template_id, maps, out_u, out_v, out_w, meta) (i64 i64[] i64[] i64[] i64[] i64[]) i64
  result = 0 ## i64
  count = ffc_template_count(template_id) ## i64
  dimension = ffc_template_dimension(template_id) ## i64
  if maps.size() >= 9 && out_u.size() >= count && out_v.size() >= count && out_w.size() >= count && meta.size() >= 9
    tu = i64[12]
    tv = i64[12]
    tw = i64[12]
    made = ffc_template_fill(template_id,tu,tv,tw) ## i64
    if made == count
      i = 0 ## i64
      while i < count
        out_u[i] = ffc_apply_linear_map(tu[i],maps,0,dimension)
        out_v[i] = ffc_apply_linear_map(tv[i],maps,3,dimension)
        out_w[i] = ffc_apply_linear_map(tw[i],maps,6,dimension)
        i += 1
      relation = i64[3]
      relation_rank = ffc_relation_analyze(out_u,out_v,out_w,count,relation) ## i64
      meta[0] = dimension
      meta[1] = count
      meta[2] = relation_rank
      meta[3] = relation[1]
      meta[4] = relation[2]
      meta[5] = 0
      if relation[1] == 1 && relation[2] == 1 && relation_rank == count - 1
        meta[5] = 1
      meta[6] = ffc_map_rank(maps,0,dimension)
      meta[7] = ffc_map_rank(maps,3,dimension)
      meta[8] = ffc_map_rank(maps,6,dimension)
      result = count
  result

-> ffc_map_template(template_id, maps, out_u, out_v, out_w, meta) (i64 i64[] i64[] i64[] i64[] i64[]) i64
  result = ffc_map_template_raw(template_id,maps,out_u,out_v,out_w,meta) ## i64
  if result > 0 && meta[5] == 0
    result = 0
  result

# Solve source_mask * columns = destination over GF(2).  The coefficient
# system is at most 3x3; free columns are fixed to zero deterministically.
-> ffc_fit_linear_map(source, destination, count, dimension, maps, offset) (i64[] i64[] i64 i64 i64[] i64) i64
  result = 0 - 1 ## i64
  valid = 1 ## i64
  if count < 1 || dimension < 1 || dimension > 3
    valid = 0
  if source.size() < count || destination.size() < count || maps.size() < offset + 3
    valid = 0
  coefficients = i64[3]
  right_sides = i64[3]
  rank = 0 ## i64
  equation = 0 ## i64
  while equation < count && valid == 1
    coefficient = source[equation] & ((1 << dimension) - 1) ## i64
    right_side = destination[equation] ## i64
    inserted = 0 ## i64
    column = 0 ## i64
    while column < dimension && coefficient != 0
      if ((coefficient >> column) & 1) != 0
        if coefficients[column] != 0
          coefficient = coefficient ^ coefficients[column]
          right_side = right_side ^ right_sides[column]
        else
          coefficients[column] = coefficient
          right_sides[column] = right_side
          rank += 1
          inserted = 1
          coefficient = 0
      column += 1
    if inserted == 0 && coefficient == 0 && right_side != 0
      valid = 0
    equation += 1
  i = 0 ## i64
  while i < 3
    maps[offset + i] = 0
    i += 1
  if valid == 1
    column = dimension - 1 ## i64
    while column >= 0
      if coefficients[column] != 0
        value = right_sides[column] ## i64
        higher = column + 1 ## i64
        while higher < dimension
          if ((coefficients[column] >> higher) & 1) != 0
            value = value ^ maps[offset + higher]
          higher += 1
        maps[offset + column] = value
      column -= 1
    equation = 0
    while equation < count && valid == 1
      made = ffc_apply_linear_map(source[equation],maps,offset,dimension) ## i64
      if made != destination[equation]
        valid = 0
      equation += 1
  if valid == 1
    result = rank
  result

# Recover P,Q,R from corresponding template/observed anchors.  Rank-deficient
# consistent systems are accepted.  The returned mapping is deterministic and
# every supplied anchor is rechecked after solving.
-> ffc_fit_anchors(template_id, anchor_slots, packed, anchor_count, maps, meta) (i64 i64[] i64[] i64 i64[] i64[]) i64
  result = 0 ## i64
  count = ffc_template_count(template_id) ## i64
  dimension = ffc_template_dimension(template_id) ## i64
  if anchor_count >= 1 && anchor_count <= count && anchor_slots.size() >= anchor_count && packed.size() >= anchor_count * 3 && maps.size() >= 9 && meta.size() >= 9
    tu = i64[12]
    tv = i64[12]
    tw = i64[12]
    z = ffc_template_fill(template_id,tu,tv,tw) ## i64
    source = i64[12]
    destination = i64[12]
    valid = 1 ## i64
    axis = 0 ## i64
    while axis < 3 && valid == 1
      i = 0 ## i64
      while i < anchor_count
        slot = anchor_slots[i] ## i64
        if slot < 0 || slot >= count
          valid = 0
        if slot >= 0 && slot < count
          if axis == 0
            source[i] = tu[slot]
          if axis == 1
            source[i] = tv[slot]
          if axis == 2
            source[i] = tw[slot]
          destination[i] = packed[i * 3 + axis]
        i += 1
      if valid == 1
        fitted_rank = ffc_fit_linear_map(source,destination,anchor_count,dimension,maps,axis * 3) ## i64
        if fitted_rank < 0
          valid = 0
      axis += 1
    if valid == 1
      candidate_u = i64[12]
      candidate_v = i64[12]
      candidate_w = i64[12]
      made = ffc_map_template_raw(template_id,maps,candidate_u,candidate_v,candidate_w,meta) ## i64
      if made == count
        i = 0
        while i < anchor_count && valid == 1
          slot = anchor_slots[i]
          if candidate_u[slot] != packed[i*3] || candidate_v[slot] != packed[i*3+1] || candidate_w[slot] != packed[i*3+2]
            valid = 0
          i += 1
      else
        valid = 0
    if valid == 1
      result = count
  result

-> ffc_current_term_position(st, u, v, w) (i64[] i64 i64 i64) i64
  found = 0 - 1 ## i64
  position = 0 ## i64
  while position < st[6] && found < 0
    slot = st[st[50] + position] ## i64
    if ffc_same_term(st[st[44]+slot],st[st[45]+slot],st[st[46]+slot],u,v,w) == 1
      found = position
    position += 1
  found

-> ffc_position_in(values, count, value) (i64[] i64 i64) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < count
    if values[i] == value
      found = 1
    i += 1
  found

# Replace the live side selected by `old_mask` with the complementary side of
# a primitive circuit.  Exact whole-tensor gates bracket the mutation and any
# failed postcondition is rolled back by toggling the same two sets again.
-> ffc_apply_circuit_current(st, circuit_u, circuit_v, circuit_w, count, old_mask) (i64[] i64[] i64[] i64[] i64 i64) i64
  result = 0 - 1 ## i64
  valid = ffw_valid(st) ## i64
  full_mask = (1 << count) - 1 ## i64
  old_mask = old_mask & full_mask
  if count < 5 || count > 12 || old_mask == 0 || old_mask == full_mask
    valid = 0
  if valid == 1 && ffc_is_primitive_circuit(circuit_u,circuit_v,circuit_w,count) == 0
    valid = 0
  selected = i64[12]
  old_count = 0 ## i64
  new_count = count - ffw_popcount(old_mask) ## i64
  bit = 0 ## i64
  while bit < count && valid == 1
    if ((old_mask >> bit) & 1) != 0
      position = ffc_current_term_position(st,circuit_u[bit],circuit_v[bit],circuit_w[bit]) ## i64
      if position < 0 || ffc_position_in(selected,old_count,position) == 1
        valid = 0
      if position >= 0
        selected[old_count] = position
        old_count += 1
    bit += 1
  old_rank = st[6] ## i64
  expected = old_rank - old_count + new_count ## i64
  if expected < 1 || expected > st[4]
    valid = 0
  # Complement terms may not already be live outside the selected old side.
  bit = 0
  while bit < count && valid == 1
    if ((old_mask >> bit) & 1) == 0
      position = ffc_current_term_position(st,circuit_u[bit],circuit_v[bit],circuit_w[bit])
      if position >= 0 && ffc_position_in(selected,old_count,position) == 0
        valid = 0
    bit += 1
  if valid == 1 && ffw_verify_current_exact(st,st[2]) == 0
    valid = 0
  if valid == 1
    rank = old_rank ## i64
    bit = 0
    while bit < count
      if ((old_mask >> bit) & 1) != 0
        rank = ffw_toggle(st,circuit_u[bit],circuit_v[bit],circuit_w[bit],rank)
      bit += 1
    bit = 0
    while bit < count
      if ((old_mask >> bit) & 1) == 0
        rank = ffw_toggle(st,circuit_u[bit],circuit_v[bit],circuit_w[bit],rank)
      bit += 1
    st[6] = rank
    if rank == expected && ffw_verify_current_exact(st,st[2]) == 1
      result = rank
    if result < 0
      bit = 0
      while bit < count
        if ((old_mask >> bit) & 1) == 0
          rank = ffw_toggle(st,circuit_u[bit],circuit_v[bit],circuit_w[bit],rank)
        bit += 1
      bit = 0
      while bit < count
        if ((old_mask >> bit) & 1) != 0
          rank = ffw_toggle(st,circuit_u[bit],circuit_v[bit],circuit_w[bit],rank)
        bit += 1
      st[6] = rank
      z = ffw_verify_current_exact(st,st[2])
  result
