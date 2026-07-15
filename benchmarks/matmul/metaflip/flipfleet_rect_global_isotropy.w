# Rectangular whole-scheme GL density descent.
#
# The three contracted domains have independent extents n,m,p.  Reuse the
# exact leaf transvections from the block composer; each candidate receives a
# complete rectangular tensor gate, making this slower but especially useful
# for small primitive leaves such as <2,3,4>.

use flipfleet_leaf_conjugation

# stats: start density, final density, accepted generators, candidates gated.
-> ffrgir_descent(source, max_steps, stats) (FFBCScheme i64 i64[])
  if source == nil || ffbc_verify_exact(source) != 1
    return nil
  current = fflc_clone(source)
  start = fflc_density(current) ## i64
  density = start ## i64
  accepted = 0 ## i64
  gated = 0 ## i64
  running = 1 ## i64
  while running == 1 && accepted < max_steps
    best = nil
    best_density = density ## i64
    axis = 0 ## i64
    while axis < 3
      extent = current.n() ## i64
      if axis == 1
        extent = current.m()
      if axis == 2
        extent = current.p()
      src = 0 ## i64
      while src < extent
        dst = 0 ## i64
        while dst < extent
          if src != dst
            candidate = fflc_transvection(current, axis, dst, src)
            gated += 1
            if candidate != nil
              candidate_density = fflc_density(candidate) ## i64
              if candidate_density < best_density
                best = candidate
                best_density = candidate_density
          dst += 1
        src += 1
      axis += 1
    if best == nil
      running = 0
    if best != nil
      current = best
      density = best_density
      accepted += 1
  stats[0] = start
  stats[1] = density
  stats[2] = accepted
  stats[3] = gated
  current

-> ffrgir_multistart(source, restarts, max_steps, stats) (FFBCScheme i64 i64 i64[])
  base_stats = i64[4]
  best = ffrgir_descent(source, max_steps, base_stats)
  if best == nil
    return nil
  best_density = fflc_density(best) ## i64
  attempts = 0 ## i64
  total_steps = base_stats[2] ## i64
  restart = 0 ## i64
  while restart < restarts
    moves = 1 + (restart % 24) ## i64
    image = fflc_sparse_leaf_image(source, 104729 * (restart + 1) + source.rank() * 65537, moves)
    attempts += 1
    if image != nil
      local_stats = i64[4]
      candidate = ffrgir_descent(image, max_steps, local_stats)
      total_steps += local_stats[2]
      if candidate != nil && fflc_density(candidate) < best_density
        best = candidate
        best_density = fflc_density(candidate)
    restart += 1
  stats[0] = fflc_density(source)
  stats[1] = best_density
  stats[2] = total_steps
  stats[3] = attempts
  best
