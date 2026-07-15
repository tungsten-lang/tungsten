# Exact affine-code descent over a bank of matrix-multiplication schemes.
#
# Let x0 and xi be parity sets of rank-one terms representing the same tensor.
# Then di = x0 XOR xi represents zero, and every word
#
#     x0 XOR sum(ci * di)
#
# is exact.  This file indexes the union of canonical rank-one terms once and
# stores the di as contiguous bitset rows.  Single/pair coordinate toggles are
# consequently regular popcount loops (and map directly to a GPU kernel),
# while the CPU retains the authoritative n^6 admission gate.

use metaflip_worker

-> ffacd_hash(u, v, w) (i64 i64 i64) i64
  value = (u * 6364136223846793005 + v * 1442695040888963407 + w * 2862933555777941757) & 9223372036854775807 ## i64
  value ^ (value >> 29)

-> ffacd_table_capacity(bound) (i64) i64
  capacity = 16 ## i64
  while capacity < bound * 4
    capacity *= 2
  capacity

# Return the stable coordinate of a term.  A return equal to `count` means a
# new coordinate was inserted; the caller then increments count.
-> ffacd_intern(coordinate_u, coordinate_v, coordinate_w, count, slots, u, v, w) (i64[] i64[] i64[] i64 i32[] i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0 || count >= coordinate_u.size()
    return 0 - 1
  slot = ffacd_hash(u, v, w) & (slots.size() - 1) ## i64
  probes = 0 ## i64
  while probes < slots.size()
    entry = slots[slot] ## i64
    if entry == 0
      coordinate_u[count] = u
      coordinate_v[count] = v
      coordinate_w[count] = w
      slots[slot] = count + 1
      return count
    coordinate = entry - 1 ## i64
    if coordinate_u[coordinate] == u && coordinate_v[coordinate] == v && coordinate_w[coordinate] == w
      return coordinate
    slot = (slot + 1) & (slots.size() - 1)
    probes += 1
  0 - 1

-> ffacd_lookup(coordinate_u, coordinate_v, coordinate_w, slots, u, v, w) (i64[] i64[] i64[] i32[] i64 i64 i64) i64
  slot = ffacd_hash(u, v, w) & (slots.size() - 1) ## i64
  probes = 0 ## i64
  while probes < slots.size()
    entry = slots[slot] ## i64
    if entry == 0
      return 0 - 1
    coordinate = entry - 1 ## i64
    if coordinate_u[coordinate] == u && coordinate_v[coordinate] == v && coordinate_w[coordinate] == w
      return coordinate
    slot = (slot + 1) & (slots.size() - 1)
    probes += 1
  0 - 1

-> ffacd_clear(row, offset, words) (i64[] i64 i64) i64
  word = 0 ## i64
  while word < words
    row[offset + word] = 0
    word += 1
  words

-> ffacd_copy(source, source_offset, target, target_offset, words) (i64[] i64 i64[] i64 i64) i64
  word = 0 ## i64
  while word < words
    target[target_offset + word] = source[source_offset + word]
    word += 1
  words

-> ffacd_xor_row(target, target_offset, source, source_offset, words) (i64[] i64 i64[] i64 i64) i64
  word = 0 ## i64
  while word < words
    target[target_offset + word] = target[target_offset + word] ^ source[source_offset + word]
    word += 1
  words

-> ffacd_row_equal(left, left_offset, right, right_offset, words) (i64[] i64 i64[] i64 i64) i64
  word = 0 ## i64
  while word < words
    if left[left_offset + word] != right[right_offset + word]
      return 0
    word += 1
  1

-> ffacd_weight(row, offset, words) (i64[] i64 i64) i64
  weight = 0 ## i64
  word = 0 ## i64
  while word < words
    weight += ffw_popcount(row[offset + word])
    word += 1
  weight

-> ffacd_distance(left, left_offset, right, right_offset, words) (i64[] i64 i64[] i64 i64) i64
  distance = 0 ## i64
  word = 0 ## i64
  while word < words
    distance += ffw_popcount(left[left_offset + word] ^ right[right_offset + word])
    word += 1
  distance

# Change in Hamming weight and weighted term density when toggling one row.
# out[0] is rank delta and out[1] density delta.
-> ffacd_toggle_delta(current, generator_a, offset_a, generator_b, offset_b, pair, coordinate_density, coordinate_count, words, out) (i64[] i64[] i64 i64[] i64 i64 i64[] i64 i64 i64[]) i64
  rank_delta = 0 ## i64
  density_delta = 0 ## i64
  word = 0 ## i64
  while word < words
    toggle = generator_a[offset_a + word] ## i64
    if pair == 1
      toggle = toggle ^ generator_b[offset_b + word]
    rank_delta += ffw_popcount(toggle) - 2 * ffw_popcount(current[word] & toggle)
    if toggle != 0
      bit = 0 ## i64
      while bit < 64
        coordinate = word * 64 + bit ## i64
        if coordinate < coordinate_count && ((toggle >> bit) & 1) != 0
          if ((current[word] >> bit) & 1) != 0
            density_delta -= coordinate_density[coordinate]
          if ((current[word] >> bit) & 1) == 0
            density_delta += coordinate_density[coordinate]
        bit += 1
    word += 1
  out[0] = rank_delta
  out[1] = density_delta
  1

-> ffacd_mask_density(mask, coordinate_density, coordinate_count, words) (i64[] i64[] i64 i64) i64
  density = 0 ## i64
  coordinate = 0 ## i64
  while coordinate < coordinate_count
    if ((mask[coordinate / 64] >> (coordinate % 64)) & 1) != 0
      density += coordinate_density[coordinate]
    coordinate += 1
  density

# Rank the zero-tensor generator matrix over GF(2).  The source rows are not
# modified.  This is diagnostic only; the descent keeps the sparse original
# rows because Gaussian basis rows are typically much denser.
-> ffacd_linear_rank(generators, generator_count, coordinate_count, words) (i64[] i64 i64 i64) i64
  if generator_count < 1
    return 0
  rows = i64[generator_count * words]
  ffacd_copy(generators, 0, rows, 0, generator_count * words)
  owners = i32[coordinate_count]
  rank = 0 ## i64
  row = 0 ## i64
  while row < generator_count
    reduced = 0 ## i64
    while reduced == 0
      pivot = 0 - 1 ## i64
      coordinate = 0 ## i64
      while coordinate < coordinate_count && pivot < 0
        if ((rows[row * words + coordinate / 64] >> (coordinate % 64)) & 1) != 0
          pivot = coordinate
        coordinate += 1
      if pivot < 0
        reduced = 1
      if pivot >= 0
        owner = owners[pivot] ## i64
        if owner == 0
          if rank != row
            ffacd_copy(rows, row * words, rows, rank * words, words)
          owners[pivot] = rank + 1
          rank += 1
          reduced = 1
        if owner != 0
          ffacd_xor_row(rows, row * words, rows, (owner - 1) * words, words)
    row += 1
  rank

+ FFAffineCode
  # Bank rows occupy flat buffers with `stride` words per scheme; row zero is
  # the affine base.  Every row has already passed an independent exact gate.
  -> new(bank_u, bank_v, bank_w, bank_rank, bank_count, stride)
    @config = i64[9]
    @config[0] = 0
    @config[1] = bank_count
    @config[2] = stride
    @config[3] = 0
    @config[4] = 0
    @config[5] = 0
    @config[6] = 0
    @config[7] = 0
    @config[8] = 0
    coordinate_bound = 1 ## i64
    if bank_count > 0 && stride > 0
      coordinate_bound = bank_count * stride
    @coordinate_u = i64[coordinate_bound]
    @coordinate_v = i64[coordinate_bound]
    @coordinate_w = i64[coordinate_bound]
    @coordinate_density = i64[coordinate_bound]
    table = i32[ffacd_table_capacity(coordinate_bound)]
    coordinate_count = 0 ## i64
    valid = 1 ## i64
    scheme = 0 ## i64
    while scheme < bank_count && valid == 1
      if bank_rank[scheme] < 1 || bank_rank[scheme] > stride
        valid = 0
      term = 0 ## i64
      while term < bank_rank[scheme] && valid == 1
        coordinate = ffacd_intern(@coordinate_u, @coordinate_v, @coordinate_w, coordinate_count, table, bank_u[scheme * stride + term], bank_v[scheme * stride + term], bank_w[scheme * stride + term]) ## i64
        if coordinate < 0
          valid = 0
        if coordinate == coordinate_count
          @coordinate_density[coordinate_count] = ffw_popcount(bank_u[scheme * stride + term]) + ffw_popcount(bank_v[scheme * stride + term]) + ffw_popcount(bank_w[scheme * stride + term])
          coordinate_count += 1
        term += 1
      scheme += 1
    @config[3] = coordinate_count
    words = (coordinate_count + 63) / 64 ## i64
    if words < 1
      words = 1
    @config[4] = words
    @base = i64[words]
    @generators = i64[(bank_count + 1) * words]
    @best = i64[words]
    scratch = i64[words]
    generator_count = 0 ## i64
    scheme = 0
    while scheme < bank_count && valid == 1
      ffacd_clear(scratch, 0, words)
      term = 0
      while term < bank_rank[scheme] && valid == 1
        coordinate = ffacd_lookup(@coordinate_u, @coordinate_v, @coordinate_w, table, bank_u[scheme * stride + term], bank_v[scheme * stride + term], bank_w[scheme * stride + term])
        if coordinate < 0
          valid = 0
        if coordinate >= 0
          scratch[coordinate / 64] = scratch[coordinate / 64] ^ (1 << (coordinate % 64))
        term += 1
      if scheme == 0
        ffacd_copy(scratch, 0, @base, 0, words)
      if scheme > 0
        word = 0
        while word < words
          scratch[word] = scratch[word] ^ @base[word]
          word += 1
        zero = ffacd_weight(scratch, 0, words) == 0 ## bool
        duplicate = 0 ## i64
        prior = 0 ## i64
        while prior < generator_count && duplicate == 0
          if ffacd_row_equal(scratch, 0, @generators, prior * words, words) == 1
            duplicate = 1
          prior += 1
        if !zero && duplicate == 0
          ffacd_copy(scratch, 0, @generators, generator_count * words, words)
          generator_count += 1
        if zero
          @config[7] = @config[7] + 1
        if duplicate == 1
          @config[8] = @config[8] + 1
      scheme += 1
    @config[0] = valid
    @config[5] = generator_count
    @config[6] = ffacd_linear_rank(@generators, generator_count, coordinate_count, words)
    ffacd_copy(@base, 0, @best, 0, words)

  -> valid()
    @config[0]
  -> bank_count()
    @config[1]
  -> stride()
    @config[2]
  -> coordinate_count()
    @config[3]
  -> words()
    @config[4]
  -> generator_count()
    @config[5]
  -> dimension()
    @config[6]
  -> zero_rows()
    @config[7]
  -> duplicate_rows()
    @config[8]
  -> base()
    @base
  -> generators()
    @generators
  -> best()
    @best
  -> coordinate_u()
    @coordinate_u
  -> coordinate_v()
    @coordinate_v
  -> coordinate_w()
    @coordinate_w
  -> coordinate_density()
    @coordinate_density

  -> single_descent(current, meta)
    words = @config[4] ## i64
    generator_count = @config[5] ## i64
    delta = i64[2]
    steps = 0 ## i64
    progress = 1 ## i64
    while progress == 1
      progress = 0
      chosen = 0 - 1 ## i64
      best_rank_delta = 0 ## i64
      best_density_delta = 0 ## i64
      generator = 0 ## i64
      while generator < generator_count
        ffacd_toggle_delta(current, @generators, generator * words, @generators, 0, 0, @coordinate_density, @config[3], words, delta)
        meta[2] = meta[2] + 1
        better = 0 ## i64
        if delta[0] < best_rank_delta
          better = 1
        if delta[0] == best_rank_delta && delta[1] < best_density_delta
          better = 1
        if better == 1
          chosen = generator
          best_rank_delta = delta[0]
          best_density_delta = delta[1]
        generator += 1
      if chosen >= 0 && (best_rank_delta < 0 || (best_rank_delta == 0 && best_density_delta < 0))
        ffacd_xor_row(current, 0, @generators, chosen * words, words)
        steps += 1
        progress = 1
    meta[3] = meta[3] + steps
    steps

  # Exhaustive pair improvement from a single-coordinate local minimum.  A
  # pair is admitted only when rank falls, or rank is unchanged and density
  # falls.  This avoids neutral two-cycles; randomized restarts supply plateau
  # diversity instead.
  -> pair_step(current, meta)
    words = @config[4] ## i64
    generator_count = @config[5] ## i64
    delta = i64[2]
    chosen_a = 0 - 1 ## i64
    chosen_b = 0 - 1 ## i64
    best_rank_delta = 0 ## i64
    best_density_delta = 0 ## i64
    a = 0 ## i64
    while a < generator_count - 1
      b = a + 1 ## i64
      while b < generator_count
        ffacd_toggle_delta(current, @generators, a * words, @generators, b * words, 1, @coordinate_density, @config[3], words, delta)
        meta[4] = meta[4] + 1
        better = 0 ## i64
        if delta[0] < best_rank_delta
          better = 1
        if delta[0] == best_rank_delta && delta[1] < best_density_delta
          better = 1
        if better == 1
          chosen_a = a
          chosen_b = b
          best_rank_delta = delta[0]
          best_density_delta = delta[1]
        b += 1
      a += 1
    if chosen_a >= 0 && (best_rank_delta < 0 || (best_rank_delta == 0 && best_density_delta < 0))
      ffacd_xor_row(current, 0, @generators, chosen_a * words, words)
      ffacd_xor_row(current, 0, @generators, chosen_b * words, words)
      meta[5] = meta[5] + 1
      return 1
    0

  -> consider(current, meta)
    words = @config[4] ## i64
    rank = ffacd_weight(current, 0, words) ## i64
    density = ffacd_mask_density(current, @coordinate_density, @config[3], words) ## i64
    distance = ffacd_distance(current, 0, @base, 0, words) ## i64
    better = 0 ## i64
    if rank < meta[8]
      better = 1
    if rank == meta[8] && density < meta[9]
      better = 1
    if rank == meta[8] && density == meta[9] && distance > meta[10]
      better = 1
    if better == 1
      ffacd_copy(current, 0, @best, 0, words)
      meta[8] = rank
      meta[9] = density
      meta[10] = distance
      meta[11] = meta[11] + 1
    better

  # meta: restarts, perturb toggles, single probes, single accepts, pair
  # probes, pair accepts, local minima, maximum local rank, best rank,
  # best density, best base distance, best updates, elapsed ms.
  -> search(restarts, max_perturb, pair_restarts, pair_rounds, seed, meta)
    if meta.size() < 13 || @config[0] != 1 || restarts < 1
      return 0 - 1
    i = 0 ## i64
    while i < 13
      meta[i] = 0
      i += 1
    words = @config[4] ## i64
    current = i64[words]
    meta[8] = ffacd_weight(@base, 0, words)
    meta[9] = ffacd_mask_density(@base, @coordinate_density, @config[3], words)
    meta[10] = 0
    ffacd_copy(@base, 0, @best, 0, words)
    rng = seed & 2147483647 ## i64
    if rng == 0
      rng = 1
    started = ccall("__w_clock_ms") ## i64
    restart = 0 ## i64
    while restart < restarts
      ffacd_copy(@base, 0, current, 0, words)
      perturb = 0 ## i64
      if restart > 0 && max_perturb > 0 && @config[5] > 0
        rng = (rng * 1103515245 + 12345) & 2147483647
        perturb = 1 + rng % max_perturb
      toggle = 0 ## i64
      while toggle < perturb
        rng = (rng * 1103515245 + 12345) & 2147483647
        generator = rng % @config[5] ## i64
        ffacd_xor_row(current, 0, @generators, generator * words, words)
        meta[1] = meta[1] + 1
        toggle += 1
      single_descent(current, meta)
      if restart < pair_restarts
        round = 0 ## i64
        pair_progress = 1 ## i64
        while round < pair_rounds && pair_progress == 1
          pair_progress = pair_step(current, meta)
          if pair_progress == 1
            single_descent(current, meta)
          round += 1
      local_rank = ffacd_weight(current, 0, words) ## i64
      if local_rank > meta[7]
        meta[7] = local_rank
      meta[6] = meta[6] + 1
      consider(current, meta)
      restart += 1
    meta[0] = restarts
    meta[12] = ccall("__w_clock_ms") - started
    meta[8]

  -> generator_overlap(left, right)
    words = @config[4] ## i64
    overlap = 0 ## i64
    word = 0 ## i64
    while word < words
      overlap += ffw_popcount(@generators[left * words + word] & @generators[right * words + word])
      word += 1
    overlap

  # Pick an anchor then the most support-correlated unused generator rows.
  # The deterministic seed rotates anchors across repeated neighborhoods.
  -> select_correlated(wanted, seed, selected)
    count = wanted ## i64
    if count > @config[5]
      count = @config[5]
    if count > selected.size()
      count = selected.size()
    if count < 1
      return 0
    anchor = seed % @config[5] ## i64
    if anchor < 0
      anchor += @config[5]
    selected[0] = anchor
    made = 1 ## i64
    while made < count
      chosen = 0 - 1 ## i64
      chosen_score = 0 - 1 ## i64
      candidate = 0 ## i64
      while candidate < @config[5]
        used = 0 ## i64
        i = 0 ## i64
        while i < made
          if selected[i] == candidate
            used = 1
          i += 1
        if used == 0
          # Correlation to the anchor is the primary key; overlap with the
          # most recently selected row breaks broad tied shells into clusters.
          score = generator_overlap(anchor, candidate) * 1000000 + generator_overlap(selected[made - 1], candidate) ## i64
          if chosen < 0 || score > chosen_score
            chosen = candidate
            chosen_score = score
        candidate += 1
      if chosen < 0
        return made
      selected[made] = chosen
      made += 1
    made

  # Exhaust one correlated k-dimensional coefficient cube in Gray order.
  # This explicitly crosses all uphill intermediate states and costs one
  # bitset toggle per codeword. kmeta: neighborhoods, combinations, rank,
  # density and novelty accepts, best rank delta, maximum k, elapsed ms.
  -> kopt_step(current, wanted, seed, kmeta)
    if kmeta.size() < 8 || wanted < 1 || wanted > 16 || @config[5] < 1
      return 0 - 1
    started = ccall("__w_clock_ms") ## i64
    selected = i64[16]
    count = select_correlated(wanted, seed, selected) ## i64
    if count < 1
      return 0
    words = @config[4] ## i64
    candidate = i64[words]
    cube_best = i64[words]
    ffacd_copy(current, 0, candidate, 0, words)
    ffacd_copy(current, 0, cube_best, 0, words)
    origin_rank = ffacd_weight(current, 0, words) ## i64
    origin_density = ffacd_mask_density(current, @coordinate_density, @config[3], words) ## i64
    origin_distance = ffacd_distance(current, 0, @base, 0, words) ## i64
    current_rank = origin_rank ## i64
    current_density = origin_density ## i64
    best_rank = origin_rank ## i64
    best_density = origin_density ## i64
    best_distance = origin_distance ## i64
    limit = 1 << count ## i64
    previous_gray = 0 ## i64
    delta = i64[2]
    index = 1 ## i64
    while index < limit
      gray = index ^ (index >> 1) ## i64
      changed = gray ^ previous_gray ## i64
      bit = 0 ## i64
      while ((changed >> bit) & 1) == 0
        bit += 1
      generator = selected[bit] ## i64
      ffacd_toggle_delta(candidate, @generators, generator * words, @generators, 0, 0, @coordinate_density, @config[3], words, delta)
      ffacd_xor_row(candidate, 0, @generators, generator * words, words)
      current_rank += delta[0]
      current_density += delta[1]
      better = 0 ## i64
      if current_rank < best_rank
        better = 1
      if current_rank == best_rank && current_density < best_density
        better = 1
      distance = 0 ## i64
      if current_rank == best_rank && current_density == best_density
        distance = ffacd_distance(candidate, 0, @base, 0, words)
        if distance > best_distance
          better = 1
      if better == 1
        if current_rank != best_rank || current_density != best_density
          distance = ffacd_distance(candidate, 0, @base, 0, words)
        best_rank = current_rank
        best_density = current_density
        best_distance = distance
        ffacd_copy(candidate, 0, cube_best, 0, words)
      previous_gray = gray
      index += 1
    accepted = 0 ## i64
    if best_rank < origin_rank || (best_rank == origin_rank && best_density < origin_density) || (best_rank == origin_rank && best_density == origin_density && best_distance > origin_distance)
      ffacd_copy(cube_best, 0, current, 0, words)
      accepted = 1
      if best_rank < origin_rank
        kmeta[2] = kmeta[2] + 1
      if best_rank == origin_rank && best_density < origin_density
        kmeta[3] = kmeta[3] + 1
      if best_rank == origin_rank && best_density == origin_density && best_distance > origin_distance
        kmeta[4] = kmeta[4] + 1
      if best_rank - origin_rank < kmeta[5]
        kmeta[5] = best_rank - origin_rank
    kmeta[0] = kmeta[0] + 1
    kmeta[1] = kmeta[1] + limit - 1
    if count > kmeta[6]
      kmeta[6] = count
    kmeta[7] = kmeta[7] + ccall("__w_clock_ms") - started
    accepted

  # Deterministic simulated tempering in coefficient space.  Improving moves
  # are always accepted; uphill moves use an integer heat-vs-energy draw and a
  # hard rank ceiling above the best seen word.  Each epoch then returns to a
  # strict local minimum and exhausts one correlated k-cube.
  #
  # meta: epochs, proposals, improving accepts, uphill accepts, rejects,
  # maximum rank, single probes/accepts, k neighborhoods/combinations/accepts,
  # best rank/density/distance/updates, elapsed ms, final rank/density/distance,
  # coefficient evaluations per second.
  -> search_tempered(epochs, steps_per_epoch, temperature, uphill_cap, neighborhood_size, seed, meta)
    if meta.size() < 20 || @config[0] != 1 || epochs < 1 || steps_per_epoch < 1 || temperature < 1 || uphill_cap < 0 || neighborhood_size < 1 || neighborhood_size > 16
      return 0 - 1
    i = 0 ## i64
    while i < 20
      meta[i] = 0
      i += 1
    words = @config[4] ## i64
    current = i64[words]
    ffacd_copy(@base, 0, current, 0, words)
    ffacd_copy(@base, 0, @best, 0, words)
    best_meta = i64[13]
    best_meta[8] = ffacd_weight(@base, 0, words)
    best_meta[9] = ffacd_mask_density(@base, @coordinate_density, @config[3], words)
    best_meta[10] = 0
    current_rank = best_meta[8] ## i64
    current_density = best_meta[9] ## i64
    meta[11] = best_meta[8]
    meta[12] = best_meta[9]
    meta[13] = 0
    rng = seed & 2147483647 ## i64
    if rng == 0
      rng = 1
    delta = i64[2]
    descent_meta = i64[13]
    kmeta = i64[8]
    kmeta[5] = 0
    started = ccall("__w_clock_ms") ## i64
    epoch = 0 ## i64
    while epoch < epochs
      heat = temperature * (epochs - epoch) / epochs ## i64
      if heat < 1
        heat = 1
      step = 0 ## i64
      while step < steps_per_epoch
        rng = (rng * 1103515245 + 12345) & 2147483647
        generator = rng % @config[5] ## i64
        ffacd_toggle_delta(current, @generators, generator * words, @generators, 0, 0, @coordinate_density, @config[3], words, delta)
        next_rank = current_rank + delta[0] ## i64
        next_density = current_density + delta[1] ## i64
        accept = 0 ## i64
        improving = 0 ## i64
        if next_rank < current_rank || (next_rank == current_rank && next_density < current_density)
          accept = 1
          improving = 1
        if accept == 0 && next_rank <= meta[11] + uphill_cap
          rank_energy = delta[0] ## i64
          if rank_energy < 0
            rank_energy = 0
          density_energy = delta[1] ## i64
          if density_energy < 0
            density_energy = 0
          energy = rank_energy * 4096 + density_energy + 1 ## i64
          rng = (rng * 1103515245 + 12345) & 2147483647
          if rng % (heat + energy) < heat
            accept = 1
        if accept == 1
          ffacd_xor_row(current, 0, @generators, generator * words, words)
          current_rank = next_rank
          current_density = next_density
          if improving == 1
            meta[2] = meta[2] + 1
          if improving == 0
            meta[3] = meta[3] + 1
          consider(current, best_meta)
        if accept == 0
          meta[4] = meta[4] + 1
        if current_rank > meta[5]
          meta[5] = current_rank
        meta[1] = meta[1] + 1
        step += 1

      # Collapse the heated word, then test a whole correlated coefficient
      # neighborhood without paying for intermediate admission gates.
      before_probes = descent_meta[2] ## i64
      before_accepts = descent_meta[3] ## i64
      single_descent(current, descent_meta)
      meta[6] = meta[6] + descent_meta[2] - before_probes
      meta[7] = meta[7] + descent_meta[3] - before_accepts
      current_rank = ffacd_weight(current, 0, words)
      current_density = ffacd_mask_density(current, @coordinate_density, @config[3], words)
      consider(current, best_meta)
      accepted = kopt_step(current, neighborhood_size, seed + epoch * 104729, kmeta) ## i64
      if accepted == 1
        meta[10] = meta[10] + 1
      current_rank = ffacd_weight(current, 0, words)
      current_density = ffacd_mask_density(current, @coordinate_density, @config[3], words)
      consider(current, best_meta)

      # Long hot excursions are useful, but periodically return to the best
      # exact word so later coefficient cubes are not all spent at the ceiling.
      if (epoch & 7) == 7
        ffacd_copy(@best, 0, current, 0, words)
        current_rank = best_meta[8]
        current_density = best_meta[9]
      epoch += 1
    meta[0] = epochs
    meta[8] = kmeta[0]
    meta[9] = kmeta[1]
    meta[11] = best_meta[8]
    meta[12] = best_meta[9]
    meta[13] = best_meta[10]
    meta[14] = best_meta[11]
    meta[15] = ccall("__w_clock_ms") - started
    meta[16] = current_rank
    meta[17] = current_density
    meta[18] = ffacd_distance(current, 0, @base, 0, words)
    evaluations = meta[1] + meta[6] + meta[9] ## i64
    if meta[15] > 0
      meta[19] = evaluations * 1000 / meta[15]
    meta[11]

  -> materialize(mask, out_u, out_v, out_w)
    rank = 0 ## i64
    coordinate = 0 ## i64
    while coordinate < @config[3]
      if ((mask[coordinate / 64] >> (coordinate % 64)) & 1) != 0
        if rank >= out_u.size() || rank >= out_v.size() || rank >= out_w.size()
          return 0 - 1
        out_u[rank] = @coordinate_u[coordinate]
        out_v[rank] = @coordinate_v[coordinate]
        out_w[rank] = @coordinate_w[coordinate]
        rank += 1
      coordinate += 1
    rank

  -> materialize_best(out_u, out_v, out_w)
    materialize(@best, out_u, out_v, out_w)
