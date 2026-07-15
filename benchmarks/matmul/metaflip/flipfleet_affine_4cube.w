# Exact sixteen-corner affine Segre circuits over GF(2).
#
# For affine maps U,V,W on GF(2)^4, every coordinate of
# U(x) tensor V(x) tensor W(x) has Boolean degree at most three.  Its XOR
# over the sixteen points of the four-cube is therefore zero.  Five affinely
# independent live terms determine one such four-flat in the product of the
# three factor spaces.  The bounded search below enumerates those live bases,
# reconstructs all sixteen corners, and scores their overlap with the source.
#
# This is deliberately an offline move-lab operator.  A retained circuit is
# still toggled into the full scheme and exhaustively reconstructed by callers.

use flipfleet_circuit_image_search3

-> ffa4_independent(du, dv, dw) (i64[] i64[] i64[]) i64
  if du.size() < 4 || dv.size() < 4 || dw.size() < 4
    return 0
  subset = 1 ## i64
  while subset < 16
    u = 0 ## i64
    v = 0 ## i64
    w = 0 ## i64
    bit = 0 ## i64
    while bit < 4
      if ((subset >> bit) & 1) != 0
        u = u ^ du[bit]
        v = v ^ dv[bit]
        w = w ^ dw[bit]
      bit += 1
    if u == 0 && v == 0 && w == 0
      return 0
    subset += 1
  1

-> ffa4_fill(u0, v0, w0, du, dv, dw, out_u, out_v, out_w) (i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if out_u.size() < 16 || out_v.size() < 16 || out_w.size() < 16 || ffa4_independent(du,dv,dw) == 0
    return 0
  subset = 0 ## i64
  while subset < 16
    u = u0 ## i64
    v = v0 ## i64
    w = w0 ## i64
    bit = 0 ## i64
    while bit < 4
      if ((subset >> bit) & 1) != 0
        u = u ^ du[bit]
        v = v ^ dv[bit]
        w = w ^ dw[bit]
      bit += 1
    # A zero factor is the zero tensor, not a rank-one term.  Excluding such
    # embeddings keeps rank accounting equal to the sixteen-corner formula.
    if u == 0 || v == 0 || w == 0
      return 0
    out_u[subset] = u
    out_v[subset] = v
    out_w[subset] = w
    subset += 1
  16

-> ffa4_zero_relation(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  if count != 16 || us.size() < count || vs.size() < count || ws.size() < count
    return 0
  i = 0 ## i64
  while i < count
    if us[i] == 0 || vs[i] == 0 || ws[i] == 0
      return 0
    j = i + 1 ## i64
    while j < count
      if ffc_same_term(us[i],vs[i],ws[i],us[j],vs[j],ws[j]) == 1
        return 0
      j += 1
    i += 1
  ubits = ffc_max_width(us,count) ## i64
  vbits = ffc_max_width(vs,count) ## i64
  wbits = ffc_max_width(ws,count) ## i64
  ui = 0 ## i64
  while ui < ubits
    vi = 0 ## i64
    while vi < vbits
      wi = 0 ## i64
      while wi < wbits
        parity = 0 ## i64
        term = 0 ## i64
        while term < count
          if ((us[term] >> ui) & 1) != 0 && ((vs[term] >> vi) & 1) != 0 && ((ws[term] >> wi) & 1) != 0
            parity = parity ^ 1
          term += 1
        if parity != 0
          return 0
        wi += 1
      vi += 1
    ui += 1
  1

# Exhaustive when basis_cap is zero.  A positive cap bounds unordered live
# five-tuples.  nonce rotates logical term labels, so repeated bounded archive
# probes do not all consume the same lexicographic prefix.
#
# meta:
#   0 bases visited, 1 independent bases, 2 valid embeddings, 3 max overlap,
#   4 best delta, 5 best density, 6 drops, 7 neutral, 8 debt<=2,
#   9 cap reached, 10 source density, 11 best initialized.
-> ffa4_search(us, vs, ws, rank, basis_cap, nonce, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if rank < 5 || us.size() < rank || vs.size() < rank || ws.size() < rank || out_u.size() < 16 || out_v.size() < 16 || out_w.size() < 16 || meta.size() < 12 || basis_cap < 0
    return 0
  i = 0 ## i64
  while i < 12
    meta[i] = 0
    i += 1
  source_density = ffcis_density(us,vs,ws,rank) ## i64
  meta[10] = source_density
  table = i32[ffcis_table_capacity(rank)]
  ffcis_build_table(us,vs,ws,rank,table)
  candidate_u = i64[16]
  candidate_v = i64[16]
  candidate_w = i64[16]
  du = i64[4]
  dv = i64[4]
  dw = i64[4]
  offset = nonce % rank ## i64
  stop = 0 ## i64
  a0 = 0 ## i64
  while a0 < rank - 4 && stop == 0
    a1 = a0 + 1 ## i64
    while a1 < rank - 3 && stop == 0
      a2 = a1 + 1 ## i64
      while a2 < rank - 2 && stop == 0
        a3 = a2 + 1 ## i64
        while a3 < rank - 1 && stop == 0
          a4 = a3 + 1 ## i64
          while a4 < rank && stop == 0
            p0 = (a0 + offset) % rank ## i64
            p1 = (a1 + offset) % rank ## i64
            p2 = (a2 + offset) % rank ## i64
            p3 = (a3 + offset) % rank ## i64
            p4 = (a4 + offset) % rank ## i64
            meta[0] = meta[0] + 1
            du[0] = us[p0] ^ us[p1]
            du[1] = us[p0] ^ us[p2]
            du[2] = us[p0] ^ us[p3]
            du[3] = us[p0] ^ us[p4]
            dv[0] = vs[p0] ^ vs[p1]
            dv[1] = vs[p0] ^ vs[p2]
            dv[2] = vs[p0] ^ vs[p3]
            dv[3] = vs[p0] ^ vs[p4]
            dw[0] = ws[p0] ^ ws[p1]
            dw[1] = ws[p0] ^ ws[p2]
            dw[2] = ws[p0] ^ ws[p3]
            dw[3] = ws[p0] ^ ws[p4]
            if ffa4_independent(du,dv,dw) == 1
              meta[1] = meta[1] + 1
              count = ffa4_fill(us[p0],vs[p0],ws[p0],du,dv,dw,candidate_u,candidate_v,candidate_w) ## i64
              if count == 16
                meta[2] = meta[2] + 1
                overlap = 0 ## i64
                density = source_density ## i64
                term = 0 ## i64
                while term < 16
                  bits = ffw_popcount(candidate_u[term]) + ffw_popcount(candidate_v[term]) + ffw_popcount(candidate_w[term]) ## i64
                  if ffcis_lookup(us,vs,ws,table,candidate_u[term],candidate_v[term],candidate_w[term]) >= 0
                    overlap += 1
                    density -= bits
                  else
                    density += bits
                  term += 1
                delta = 16 - 2 * overlap ## i64
                if overlap > meta[3]
                  meta[3] = overlap
                if delta < 0
                  meta[6] = meta[6] + 1
                if delta == 0
                  meta[7] = meta[7] + 1
                if delta <= 2
                  meta[8] = meta[8] + 1
                better = 0 ## i64
                if meta[11] == 0 || delta < meta[4]
                  better = 1
                if meta[11] == 1 && delta == meta[4] && density < meta[5]
                  better = 1
                if better == 1
                  meta[4] = delta
                  meta[5] = density
                  meta[11] = 1
                  term = 0
                  while term < 16
                    out_u[term] = candidate_u[term]
                    out_v[term] = candidate_v[term]
                    out_w[term] = candidate_w[term]
                    term += 1
            if basis_cap > 0 && meta[0] >= basis_cap
              meta[9] = 1
              stop = 1
            a4 += 1
          a3 += 1
        a2 += 1
      a1 += 1
    a0 += 1
  if meta[11] == 1
    return 16
  0
