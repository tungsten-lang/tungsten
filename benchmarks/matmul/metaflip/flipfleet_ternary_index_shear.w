use flipfleet_ternary_worker

# Exact matrix-index basis shears for the strict {-1,0,1} worker.
#
# Matrix multiplication contracts three physical index spaces.  For the row
# index i, for example, its diagonal pairing in the A and C factors is
#
#                  sum_i e_i tensor e_i.
#
# Applying P to the A rows and P^-T to the C rows therefore preserves the
# complete multiplication tensor.  The same construction couples A columns
# to B rows (the j index) and B columns to C columns (the k index).
#
# This module uses P = I + s E_destination,source, s in {-1,+1}.  Its inverse
# is I - s E_destination,source, so both sides remain integer.  The endpoint
# is accepted only when every changed coefficient is still in {-1,0,1}; the
# two coupled transforms are preflighted before either is committed.  This is
# a global exact orbit move, not a rank-one pair flip: it can replace most of
# a scheme's terms at once and expose a different local-move presentation.


# Transform one row or column of a signed n*n factor.  orientation == 0
# means rows and orientation == 1 means columns.  The endpoint masks are
# returned in the worker scratch words st[44]/st[45].
-> fft_index_shear_vector(st, positive,negative, orientation,destination,source,sign) (i64[] i64 i64 i64 i64 i64 i64) i64
  if destination < 0 || source < 0 || destination >= st[2] || source >= st[2] || destination == source
    return 0
  if orientation < 0 || orientation > 1
    return 0
  if sign >= 0
    sign = 1
  if sign < 0
    sign = 0 - 1
  outp = positive ## i64
  outn = negative ## i64
  ok = 1 ## i64
  q = 0 ## i64
  while q < st[2] && ok == 1
    destination_bit = destination * st[2] + q ## i64
    source_bit = source * st[2] + q ## i64
    if orientation == 1
      destination_bit = q * st[2] + destination
      source_bit = q * st[2] + source
    value = fft_coefficient(positive,negative,destination_bit) + sign * fft_coefficient(positive,negative,source_bit) ## i64
    if value < 0 - 1 || value > 1
      ok = 0
    if ok == 1
      bit = 1 << destination_bit ## i64
      keep = st[30] ^ bit ## i64
      outp = outp & keep
      outn = outn & keep
      if value == 1
        outp = outp | bit
      if value == 0 - 1
        outn = outn | bit
    q += 1
  st[44] = outp
  st[45] = outn
  ok

# Decode the two factor transforms coupled by one physical matrix index.
# Results are returned in st[60..63]: factor, orientation, destination,
# source.  The first sign is the caller's sign; the second is its negation.
-> fft_index_shear_spec(st, physical, side,destination,source) (i64[] i64 i64 i64 i64) i64
  if physical < 0 || physical > 2 || side < 0 || side > 1
    return 0
  factor = 0 ## i64
  orientation = 0 ## i64
  to = destination ## i64
  from = source ## i64
  if physical == 0
    if side == 1
      factor = 2
      to = source
      from = destination
  if physical == 1
    orientation = 1
    if side == 1
      factor = 1
      orientation = 0
      to = source
      from = destination
  if physical == 2
    factor = 1
    orientation = 1
    if side == 1
      factor = 2
      to = source
      from = destination
  st[60] = factor
  st[61] = orientation
  st[62] = to
  st[63] = from
  1

# Preflight and then commit one coupled shear.  No counter or objective state
# changes here, which also makes this helper safe for deterministic probing
# and exact inverse rollback.
-> fft_index_shear_raw(st, physical,destination,source,sign) (i64[] i64 i64 i64 i64) i64
  if physical < 0 || physical > 2 || destination < 0 || source < 0 || destination >= st[2] || source >= st[2] || destination == source
    return 0
  if sign >= 0
    sign = 1
  if sign < 0
    sign = 0 - 1

  ok = 1 ## i64
  side = 0 ## i64
  while side < 2 && ok == 1
    z = fft_index_shear_spec(st,physical,side,destination,source) ## i64
    factor = st[60] ## i64
    orientation = st[61] ## i64
    to = st[62] ## i64
    from = st[63] ## i64
    side_sign = sign ## i64
    if side == 1
      side_sign = 0 - sign
    slot = 0 ## i64
    while slot < st[5] && ok == 1
      base = 32 + 2 * factor ## i64
      ok = fft_index_shear_vector(st,st[st[base]+slot],st[st[base+1]+slot],orientation,to,from,side_sign)
      if ok == 1 && (st[44] | st[45]) == 0
        ok = 0
      slot += 1
    side += 1
  if ok == 0
    return 0

  side = 0
  while side < 2
    z = fft_index_shear_spec(st,physical,side,destination,source)
    factor = st[60]
    orientation = st[61]
    to = st[62]
    from = st[63]
    side_sign = sign
    if side == 1
      side_sign = 0 - sign
    slot = 0
    while slot < st[5]
      base = 32 + 2 * factor
      z = fft_index_shear_vector(st,st[st[base]+slot],st[st[base+1]+slot],orientation,to,from,side_sign)
      st[st[base]+slot] = st[44]
      st[st[base+1]+slot] = st[45]
      slot += 1
    side += 1
  slot = 0
  while slot < st[5]
    z = fft_canonicalize_slot(st,slot)
    slot += 1
  1

# Header counters used only by this module:
#   54 attempts, 55 accepted, 56 illegal strict endpoint,
#   57 objective/no-op rejection, 58 strict density improvements,
#   59 inverse rollbacks.
# wander < 0 requires strict density descent; wander == 0 accepts non-worse
# endpoints; wander > 0 accepts every changed legal endpoint as an orbit door.
-> fft_index_shear_apply(st, physical,destination,source,sign,wander) (i64[] i64 i64 i64 i64 i64) i64
  st[54] = st[54] + 1
  old_density = st[20] ## i64
  old_fingerprint = fft_current_fingerprint(st) ## i64
  if fft_index_shear_raw(st,physical,destination,source,sign) == 0
    st[56] = st[56] + 1
    return 0
  new_density = fft_current_density(st) ## i64
  new_fingerprint = fft_current_fingerprint(st) ## i64
  accept = 0 ## i64
  if wander < 0 && new_density < old_density
    accept = 1
  if wander == 0 && new_density <= old_density
    accept = 1
  if wander > 0
    accept = 1
  if new_fingerprint == old_fingerprint
    accept = 0
  if accept == 0
    restored = fft_index_shear_raw(st,physical,destination,source,0-sign) ## i64
    if restored == 0
      st[19] = st[19] + 1
      return 0 - 1
    st[59] = st[59] + 1
    st[57] = st[57] + 1
    st[20] = old_density
    return 0

  st[20] = new_density
  st[10] = st[10] + 1
  st[55] = st[55] + 1
  if new_density < old_density
    st[58] = st[58] + 1
  adopted = fft_maybe_adopt(st) ## i64
  if adopted < 0
    return 0 - 1
  if adopted == 2
    return 2
  1

-> fft_index_shear_try(st, wander) (i64[] i64) i64
  if st[2] < 2
    st[54] = st[54] + 1
    st[56] = st[56] + 1
    return 0
  physical = fft_rand31(st) % 3 ## i64
  destination = fft_rand31(st) % st[2] ## i64
  source = fft_rand31(st) % (st[2] - 1) ## i64
  if source >= destination
    source += 1
  sign = 1 ## i64
  if (fft_rand31(st) & 1) != 0
    sign = 0 - 1
  fft_index_shear_apply(st,physical,destination,source,sign,wander)

# Select at most one shallow positive-density isotropy door from a normalized
# fixed point.  This is intended only as a GPU seed variant: the caller must
# promote the current view into a separately gated state and must not publish
# the denser door as an objective.  A positive return is the exact density
# debt; zero means no legal door within max_delta; -1 is an internal failure.
-> fft_index_shear_shallow_positive_door(st, max_delta) (i64[] i64) i64
  if max_delta < 1
    return 0
  best_delta = max_delta + 1 ## i64
  best_physical = 0 ## i64
  best_destination = 0 ## i64
  best_source = 0 ## i64
  best_sign = 1 ## i64
  physical = 0 ## i64
  while physical < 3
    destination = 0 ## i64
    while destination < st[2]
      source = 0 ## i64
      while source < st[2]
        if source != destination
          sign = 0 - 1 ## i64
          while sign <= 1
            delta = fft_index_shear_delta(st,physical,destination,source,sign) ## i64
            if delta > 0 && delta < best_delta && delta <= max_delta
              best_delta = delta
              best_physical = physical
              best_destination = destination
              best_source = source
              best_sign = sign
            sign += 2
        source += 1
      destination += 1
    physical += 1
  if best_delta > max_delta
    return 0
  result = fft_index_shear_apply(st,best_physical,best_destination,best_source,best_sign,1) ## i64
  if result < 0
    return 0 - 1
  if result == 0
    return 0 - 1
  best_delta

# Return the exact density delta and restore the canonical source.  A large
# sentinel denotes an illegal strict-ternary endpoint.
-> fft_index_shear_delta(st, physical,destination,source,sign) (i64[] i64 i64 i64 i64) i64
  old_density = st[20] ## i64
  if fft_index_shear_raw(st,physical,destination,source,sign) == 0
    return 1000000000
  delta = fft_current_density(st) - old_density ## i64
  restored = fft_index_shear_raw(st,physical,destination,source,0-sign) ## i64
  if restored == 0
    st[19] = st[19] + 1
    return 1000000000
  st[20] = old_density
  delta

# Steepest deterministic closure over every elementary index shear.  A full
# scan is restarted after each improvement, so return zero means a strict
# fixed point for all 6*n*(n-1) directed signed shears.
-> fft_index_shear_directed_descent(st) (i64[]) i64
  improvements = 0 ## i64
  searching = 1 ## i64
  while searching == 1
    searching = 0
    best_delta = 0 ## i64
    best_physical = 0 ## i64
    best_destination = 0 ## i64
    best_source = 0 ## i64
    best_sign = 1 ## i64
    physical = 0 ## i64
    while physical < 3
      destination = 0 ## i64
      while destination < st[2]
        source = 0 ## i64
        while source < st[2]
          if source != destination
            sign = 0 - 1 ## i64
            while sign <= 1
              delta = fft_index_shear_delta(st,physical,destination,source,sign) ## i64
              if delta < best_delta
                best_delta = delta
                best_physical = physical
                best_destination = destination
                best_source = source
                best_sign = sign
              sign += 2
          source += 1
        destination += 1
      physical += 1
    if best_delta < 0
      result = fft_index_shear_apply(st,best_physical,best_destination,best_source,best_sign,0-1) ## i64
      if result < 0
        return 0 - 1
      if result > 0
        improvements += 1
        searching = 1
  improvements
