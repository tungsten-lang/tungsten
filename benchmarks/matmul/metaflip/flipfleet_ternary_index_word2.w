use flipfleet_ternary_index_shear

# Atomic length-two words in the physical-index isotropy group.
#
# flipfleet_ternary_index_shear.w applies one elementary matrix
# S(destination,source,sign) and its paired inverse-transpose action.  This
# module composes two such generators on the same physical index but evaluates
# the final P / P^-T endpoint directly.  The intermediate coefficient vector
# may contain +/-2; only the final endpoint must be strict {-1,0,1}.
# Consequently return 2 is a genuine strict-alphabet barrier endpoint that the
# existing single-shear implementation cannot traverse one generator at a
# time.  Return 1 means the same endpoint had a strict first intermediate and
# is therefore already covered; zero means the final endpoint is not strict.

# Apply two directed coordinate additions to every row/column line of one
# signed factor vector.  st[44]/st[45] receive the final masks.  st[46] is one
# iff the first intermediate left {-1,0,1}, even when the final endpoint is
# strict.  Intermediate integers are bounded by three for a length-two word.
-> fftiw2_vector(st, positive,negative, orientation,d1,s1,c1,d2,s2,c2) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  if orientation < 0 || orientation > 1
    return 0
  n = st[2] ## i64
  if d1 < 0 || d1 >= n || s1 < 0 || s1 >= n || d1 == s1 || d2 < 0 || d2 >= n || s2 < 0 || s2 >= n || d2 == s2
    return 0
  if c1 >= 0
    c1 = 1
  else
    c1 = 0 - 1
  if c2 >= 0
    c2 = 1
  else
    c2 = 0 - 1

  st[46] = 0
  outp = 0 ## i64
  outn = 0 ## i64
  line = 0 ## i64
  values = i64[7]
  while line < n
    coordinate = 0 ## i64
    while coordinate < n
      bit = line * n + coordinate ## i64
      if orientation == 0
        bit = coordinate * n + line
      values[coordinate] = fft_coefficient(positive,negative,bit)
      coordinate += 1

    values[d1] = values[d1] + c1 * values[s1]
    if values[d1] < 0 - 1 || values[d1] > 1
      st[46] = 1
    values[d2] = values[d2] + c2 * values[s2]

    coordinate = 0
    while coordinate < n
      value = values[coordinate] ## i64
      if value < 0 - 1 || value > 1
        return 0
      bit = line * n + coordinate
      if orientation == 0
        bit = coordinate * n + line
      if value == 1
        outp = outp | (1 << bit)
      if value == 0 - 1
        outn = outn | (1 << bit)
      coordinate += 1
    line += 1
  st[44] = outp
  st[45] = outn
  1

# Evaluate and commit one atomic word.  The two operations use the same
# physical index but may touch any directed coordinate pairs.  The paired
# factor receives each generator's inverse-transpose transform in the same
# chronological order, exactly matching two globally valid elementary
# isotropies when their intermediate happens to be strict.
-> fftiw2_raw(st,physical,d1,s1,c1,d2,s2,c2) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  if fft_valid(st) == 0 || st[5] < 1 || physical < 0 || physical > 2
    return 0 - 1
  n = st[2] ## i64
  if d1 < 0 || d1 >= n || s1 < 0 || s1 >= n || d1 == s1 || d2 < 0 || d2 >= n || s2 < 0 || s2 >= n || d2 == s2
    return 0 - 1
  if c1 >= 0
    c1 = 1
  else
    c1 = 0 - 1
  if c2 >= 0
    c2 = 1
  else
    c2 = 0 - 1
  # Reject the immediate inverse word, which is the identity transformation.
  if d1 == d2 && s1 == s2 && c1 == 0 - c2
    return 0

  atomic = 0 ## i64
  ok = 1 ## i64
  side = 0 ## i64
  while side < 2 && ok == 1
    z = fft_index_shear_spec(st,physical,side,d1,s1) ## i64
    factor1 = st[60] ## i64
    orientation1 = st[61] ## i64
    to1 = st[62] ## i64
    from1 = st[63] ## i64
    z = fft_index_shear_spec(st,physical,side,d2,s2)
    factor2 = st[60]
    orientation2 = st[61]
    to2 = st[62]
    from2 = st[63]
    if factor1 != factor2 || orientation1 != orientation2
      return 0 - 1
    side_c1 = c1 ## i64
    side_c2 = c2 ## i64
    if side == 1
      side_c1 = 0 - c1
      side_c2 = 0 - c2
    slot = 0 ## i64
    while slot < st[5] && ok == 1
      base = 32 + 2 * factor1 ## i64
      ok = fftiw2_vector(st,st[st[base]+slot],st[st[base+1]+slot],orientation1,to1,from1,side_c1,to2,from2,side_c2)
      if ok == 1 && (st[44] | st[45]) == 0
        ok = 0
      if st[46] != 0
        atomic = 1
      slot += 1
    side += 1
  if ok == 0
    return 0

  side = 0
  while side < 2
    z = fft_index_shear_spec(st,physical,side,d1,s1)
    factor1 = st[60]
    orientation1 = st[61]
    to1 = st[62]
    from1 = st[63]
    z = fft_index_shear_spec(st,physical,side,d2,s2)
    factor2 = st[60]
    orientation2 = st[61]
    to2 = st[62]
    from2 = st[63]
    side_c1 = c1
    side_c2 = c2
    if side == 1
      side_c1 = 0 - c1
      side_c2 = 0 - c2
    slot = 0
    while slot < st[5]
      base = 32 + 2 * factor1
      z = fftiw2_vector(st,st[st[base]+slot],st[st[base+1]+slot],orientation1,to1,from1,side_c1,to2,from2,side_c2)
      st[st[base]+slot] = st[44]
      st[st[base+1]+slot] = st[45]
      slot += 1
    side += 1
  slot = 0
  while slot < st[5]
    z = fft_canonicalize_slot(st,slot)
    slot += 1
  st[20] = fft_current_density(st)
  if atomic != 0
    return 2
  1

# The inverse of S2*S1 is S1^-1*S2^-1: reverse the two generator records and
# negate both signs.  A successful round trip must restore the canonical
# fingerprint and density exactly.
-> fftiw2_inverse_raw(st,physical,d1,s1,c1,d2,s2,c2) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  fftiw2_raw(st,physical,d2,s2,0-c2,d1,s1,0-c1)

# Probe without changing the source.  meta (minimum six words):
# [0] forward result, [1] inverse result, [2] density delta,
# [3] changed endpoint, [4] round-trip failure, [5] inverse is also atomic.
-> fftiw2_probe(st,physical,d1,s1,c1,d2,s2,c2,meta) (i64[] i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  i = 0 ## i64
  while i < 6
    meta[i] = 0
    i += 1
  old_density = st[20] ## i64
  old_fingerprint = fft_current_fingerprint(st) ## i64
  result = fftiw2_raw(st,physical,d1,s1,c1,d2,s2,c2) ## i64
  meta[0] = result
  if result <= 0
    return result
  meta[2] = st[20] - old_density
  if fft_current_fingerprint(st) != old_fingerprint
    meta[3] = 1
  inverse = fftiw2_inverse_raw(st,physical,d1,s1,c1,d2,s2,c2) ## i64
  meta[1] = inverse
  if inverse == 2
    meta[5] = 1
  if inverse <= 0 || st[20] != old_density || fft_current_fingerprint(st) != old_fingerprint
    meta[4] = 1
    return 0 - 1
  result

# Select and apply the shallowest changed atomic endpoint within a density
# debt cap.  This exhaustive scan is intended for admission of at most one CPU
# island, never for the hot loop.  meta (minimum four words): [0] debt,
# [1] atomic candidates within cap, [2] all changed atomic candidates,
# [3] selected endpoint result.  The source best view is deliberately left
# untouched when debt is positive.
-> fftiw2_shallow_atomic_door(st,max_delta,meta) (i64[] i64 i64[]) i64
  i = 0 ## i64
  while i < 4
    meta[i] = 0
    i += 1
  if max_delta < 0 || fft_valid(st) == 0 || st[5] < 1
    return 0 - 1
  best_delta = max_delta + 1 ## i64
  best_physical = 0 ## i64
  best_d1 = 0 ## i64
  best_s1 = 1 ## i64
  best_c1 = 1 ## i64
  best_d2 = 0 ## i64
  best_s2 = 1 ## i64
  best_c2 = 1 ## i64
  probe = i64[6]
  physical = 0 ## i64
  while physical < 3
    d1 = 0 ## i64
    while d1 < st[2]
      s1 = 0 ## i64
      while s1 < st[2]
        if d1 != s1
          c1 = 0 - 1 ## i64
          while c1 <= 1
            d2 = 0 ## i64
            while d2 < st[2]
              s2 = 0 ## i64
              while s2 < st[2]
                if d2 != s2
                  c2 = 0 - 1 ## i64
                  while c2 <= 1
                    result = fftiw2_probe(st,physical,d1,s1,c1,d2,s2,c2,probe) ## i64
                    if result < 0
                      return 0 - 1
                    if result == 2 && probe[3] != 0
                      meta[2] += 1
                      delta = probe[2] ## i64
                      if delta <= max_delta
                        meta[1] += 1
                        if delta < best_delta
                          best_delta = delta
                          best_physical = physical
                          best_d1 = d1
                          best_s1 = s1
                          best_c1 = c1
                          best_d2 = d2
                          best_s2 = s2
                          best_c2 = c2
                    c2 += 2
                s2 += 1
              d2 += 1
            c1 += 2
        s1 += 1
      d1 += 1
    physical += 1
  if best_delta > max_delta
    return 0
  result = fftiw2_raw(st,best_physical,best_d1,best_s1,best_c1,best_d2,best_s2,best_c2) ## i64
  meta[3] = result
  if result != 2
    return 0 - 1
  meta[0] = st[20] - st[21]
  if meta[0] <= 0
    adopted = fft_maybe_adopt(st) ## i64
    if adopted < 0
      return 0 - 1
  1
