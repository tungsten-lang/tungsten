# Search actual KoalaBear mu_512 for cubic maps with many exact 3-fibres.
#
# This is an external Proximity-oriented benchmark over the reusable finite-map
# adapter. It compares ordinary coefficient flips with locator seeding and
# root-preserving locator flips under matched exact-check budgets. A cubic with
# many full 3-fibres would open a different proof ledger from the exhausted
# power-of-two orbit pencil; this benchmark discovers maps only and does not
# translate them into a Lean submission.

use ../lib/metaflip

-> projected_cubic_signature_count(n) (i64) i64
  n * (n - 1) * (n - 2) / 6

-> projected_cubic_fill_signatures(points, n, prime, signatures) (i64[] i64 i64 i64[]) i64
  at = 0
  i = 0
  while i < n - 2
    x = points[i]
    j = i + 1
    while j < n - 1
      y = points[j]
      xy = x * y % prime
      k = j + 1
      while k < n
        z = points[k]
        s1 = (x + y) % prime
        s1 = (s1 + z) % prime
        s2 = (xy + x * z % prime) % prime
        s2 = (s2 + y * z % prime) % prime
        signatures[at] = s1 * prime + s2
        at += 1
        k += 1
      j += 1
    i += 1
  at

-> projected_cubic_radix_pass(source, destination, size, shift, counts) (i64[] i64[] i64 i64 i64[]) i64
  i = 0
  while i < 65536
    counts[i] = 0
    i += 1
  i = 0
  while i < size
    digit = (source[i] >> shift) & 65535
    counts[digit] += 1
    i += 1
  total = 0
  i = 0
  while i < 65536
    count = counts[i]
    counts[i] = total
    total += count
    i += 1
  i = 0
  while i < size
    value = source[i]
    digit = (value >> shift) & 65535
    destination[counts[digit]] = value
    counts[digit] += 1
    i += 1
  size

-> projected_cubic_exact_best(domain, boxed_points, prime)
  n = boxed_points.size() ## i64
  points = i64[n]
  i = 0
  while i < n
    points[i] = boxed_points[i]
    i += 1
  size = projected_cubic_signature_count(n)
  signatures = i64[size]
  scratch = i64[size]
  counts = i64[65536]
  filled = projected_cubic_fill_signatures(points, n, prime, signatures) ## i64
  return nil if filled != size
  z = projected_cubic_radix_pass(signatures, scratch, size, 0, counts) ## i64
  z = projected_cubic_radix_pass(scratch, signatures, size, 16, counts) ## i64
  z = projected_cubic_radix_pass(signatures, scratch, size, 32, counts) ## i64
  z = projected_cubic_radix_pass(scratch, signatures, size, 48, counts) ## i64

  best_signature = signatures[0]
  best_count = 1
  run_start = 0
  i = 1
  while i <= size
    if i == size || signatures[i] != signatures[run_start]
      run_count = i - run_start
      if run_count > best_count
        best_count = run_count
        best_signature = signatures[run_start]
      run_start = i
    i += 1
  s1 = best_signature / prime
  s2 = best_signature % prime
  numerator = [0, s2, metaflip_prime_normalize(0 - s1, prime), 1]
  candidate = Metaflip:PrimeRationalMap.new(numerator, [1])
  {candidate: candidate, triple_fibres: best_count, signatures: size,
    profile: domain.profile(candidate)}

-> projected_cubic_det3(a00, a01, a02, a10, a11, a12,
    a20, a21, a22, prime) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  positive = a00 * a11 % prime * a22 % prime
  positive += a01 * a12 % prime * a20 % prime
  positive += a02 * a10 % prime * a21 % prime
  negative = a02 * a11 % prime * a20 % prime
  negative += a01 * a10 % prime * a22 % prime
  negative += a00 * a12 % prime * a21 % prime
  metaflip_prime_normalize(positive - negative, prime)

+ ProjectedCubicPairSearchDomain
  -> new(boxed_points, @prime)
    @n = boxed_points.size()
    @points = i64[@n]
    @point_positions = {}
    i = 0
    while i < @n
      @points[i] = boxed_points[i]
      @point_positions[@points[i]] = i + 1
      i += 1
    @numerators = i64[@n]
    @denominators = i64[@n]
    @prefixes = i64[@n]
    @inverses = i64[@n]
    @hash_keys = i64[2048]
    @hash_counts = i64[2048]
    @hash_epochs = i64[2048]
    @used_slots = i64[@n]
    @linear = i64[12]
    @epoch = 0

  -> snapshot(candidate)
    return nil if candidate == nil || !candidate.is_a?(Array) || candidate.size() != 6
    metaflip_search_copy_values(candidate)

  -> valid?(candidate)
    return false if candidate == nil || !candidate.is_a?(Array) || candidate.size() != 6
    i = 0
    while i < 6
      return false if !candidate[i].is_a?(Integer)
      return false if candidate[i] < 0 || candidate[i] >= @n
      j = 0
      while j < i
        return false if candidate[j] == candidate[i]
        j += 1
      i += 1
    true

  -> __compute_profile(candidate)
    return false if !valid?(candidate)
    left0 = @points[candidate[0]] ## i64
    left1 = @points[candidate[1]] ## i64
    left2 = @points[candidate[2]] ## i64
    right0 = @points[candidate[3]] ## i64
    right1 = @points[candidate[4]] ## i64
    right2 = @points[candidate[5]] ## i64
    product = 1 ## i64
    i = 0
    while i < @n
      x = @points[i] ## i64
      difference = x - left0 ## i64
      difference += @prime if difference < 0
      numerator = difference ## i64
      difference = x - left1
      difference += @prime if difference < 0
      numerator = numerator * difference % @prime
      difference = x - left2
      difference += @prime if difference < 0
      numerator = numerator * difference % @prime
      difference = x - right0
      difference += @prime if difference < 0
      other = difference ## i64
      difference = x - right1
      difference += @prime if difference < 0
      other = other * difference % @prime
      difference = x - right2
      difference += @prime if difference < 0
      other = other * difference % @prime
      denominator = numerator + other
      denominator -= @prime if denominator >= @prime
      return false if denominator == 0
      @numerators[i] = numerator
      @denominators[i] = denominator
      @prefixes[i] = product
      product = product * denominator % @prime
      i += 1
    suffix_inverse = product.invmod(@prime)
    i = @n - 1
    while i >= 0
      @inverses[i] = suffix_inverse * @prefixes[i] % @prime
      suffix_inverse = suffix_inverse * @denominators[i] % @prime
      i -= 1

    @epoch += 1
    used_count = 0
    i = 0
    while i < @n
      value = @numerators[i] * @inverses[i] % @prime
      slot = (value ^ (value >> 11) ^ (value >> 22)) & 2047
      while @hash_epochs[slot] == @epoch && @hash_keys[slot] != value
        slot = (slot + 1) & 2047
      if @hash_epochs[slot] != @epoch
        @hash_epochs[slot] = @epoch
        @hash_keys[slot] = value
        @hash_counts[slot] = 1
        @used_slots[used_count] = slot
        used_count += 1
      else
        @hash_counts[slot] += 1
      i += 1

    exact_fibres = 0
    covered = 0
    capped_pairs = 0
    overfull = 0
    max_fibre = 0
    i = 0
    while i < used_count
      count = @hash_counts[@used_slots[i]]
      max_fibre = count if count > max_fibre
      if count == 3
        exact_fibres += 1
        covered += 3
      capped = count
      capped = 3 if capped > 3
      capped_pairs += capped * (capped - 1) / 2
      overfull += count - 3 if count > 3
      i += 1
    @profile_exact_fibres = exact_fibres
    @profile_covered = covered
    @profile_capped_pairs = capped_pairs
    @profile_overfull = overfull
    @profile_max_fibre = max_fibre
    @profile_image_size = used_count
    true

  -> profile(candidate)
    return nil if !__compute_profile(candidate)
    {exact_fibres: @profile_exact_fibres, covered: @profile_covered,
      capped_pairs: @profile_capped_pairs, overfull: @profile_overfull,
      max_fibre: @profile_max_fibre, image_size: @profile_image_size}

  # Allocation-free lexicographic score for dense local sweeps. Metric bounds
  # here are fixed by the 512-point, target-three adapter, so the packing is
  # exact: covered, then capped pairs, then smaller overfull excess.
  -> profile_score(candidate)
    return 0 - 1 if !__compute_profile(candidate)
    score = @profile_covered * 1000000 + @profile_capped_pairs * 1000
    score + (999 - @profile_overfull)

  -> identity(candidate)
    parts = []
    i = 0
    while i < candidate.size()
      parts.push(candidate[i].to_s())
      i += 1
    parts.join(":")

  -> __load_row(row, a, b, c, rhs)
    offset = row * 4
    @linear[offset] = metaflip_prime_normalize(a, @prime)
    @linear[offset + 1] = metaflip_prime_normalize(b, @prime)
    @linear[offset + 2] = metaflip_prime_normalize(c, @prime)
    @linear[offset + 3] = metaflip_prime_normalize(rhs, @prime)

  -> __solve_loaded
    determinant = projected_cubic_det3(
      @linear[0], @linear[1], @linear[2],
      @linear[4], @linear[5], @linear[6],
      @linear[8], @linear[9], @linear[10], @prime) ## i64
    return false if determinant == 0
    numerator0 = projected_cubic_det3(
      @linear[3], @linear[1], @linear[2],
      @linear[7], @linear[5], @linear[6],
      @linear[11], @linear[9], @linear[10], @prime) ## i64
    numerator1 = projected_cubic_det3(
      @linear[0], @linear[3], @linear[2],
      @linear[4], @linear[7], @linear[6],
      @linear[8], @linear[11], @linear[10], @prime) ## i64
    numerator2 = projected_cubic_det3(
      @linear[0], @linear[1], @linear[3],
      @linear[4], @linear[5], @linear[7],
      @linear[8], @linear[9], @linear[11], @prime) ## i64
    inverse = determinant.invmod(@prime)
    @solution0 = numerator0 * inverse % @prime
    @solution1 = numerator1 * inverse % @prime
    @solution2 = numerator2 * inverse % @prime
    true

  -> __point_index(value)
    normalized = metaflip_prime_normalize(value, @prime)
    position = @point_positions[normalized] || 0
    position - 1

  -> fibre_indices(candidate, desired_size)
    return nil if !desired_size.is_a?(Integer) || desired_size < 1
    return nil if !__compute_profile(candidate)
    fibres = []
    used = 0
    while used < @profile_image_size
      slot = @used_slots[used]
      if @hash_counts[slot] == desired_size
        value = @hash_keys[slot]
        fibre = []
        i = 0
        while i < @n
          image = @numerators[i] * @inverses[i] % @prime
          fibre.push(i) if image == value
          i += 1
        fibres.push(fibre)
      used += 1
    fibres

  -> assess(candidate)
    result = profile(candidate)
    return nil if result == nil
    fibre_bin = result[:exact_fibres]
    fibre_bin = 4 if fibre_bin > 4
    identity_bin = 17
    i = 0
    while i < candidate.size()
      identity_bin = (identity_bin * 257 + candidate[i] + 1) % 64
      i += 1
    descriptor = fibre_bin.to_s() + ":" + identity_bin.to_s()
    Metaflip:Assessment.new(
      [result[:covered], result[:capped_pairs], result[:overfull]],
      descriptor, identity(candidate))

  -> random_candidate(seed)
    candidate = []
    state = seed
    while candidate.size() < 6
      state = metaflip_search_next_seed(state)
      index = state % @n
      duplicate = false
      i = 0
      while i < candidate.size()
        duplicate = true if candidate[i] == index
        i += 1
      candidate.push(index) if !duplicate
    candidate

  -> random_proposal(request)
    Metaflip:Proposal.new(random_candidate(request.seed), 1)

  -> mutate_proposal(request, changes)
    parent = request.parent
    parent = request.best if parent == nil
    return random_proposal(request) if parent == nil
    candidate = snapshot(parent)
    state = request.seed
    changed = 0
    while changed < changes
      state = metaflip_search_next_seed(state)
      slot = state % 6
      state = metaflip_search_next_seed(state)
      replacement = state % @n
      scanned = 0
      duplicate = true
      while duplicate && scanned < @n
        duplicate = false
        i = 0
        while i < 6
          duplicate = true if i != slot && candidate[i] == replacement
          i += 1
        if duplicate
          replacement = (replacement + 1) % @n
          scanned += 1
      return nil if duplicate
      candidate[slot] = replacement
      changed += 1
    Metaflip:Proposal.new(candidate, 1)

  -> fibre_reseed_proposal(request)
    parent = request.parent
    parent = request.best if parent == nil
    return random_proposal(request) if parent == nil
    candidate = snapshot(parent)
    state = request.seed
    side = state & 1
    offset = side * 3
    changed = 0
    while changed < 3
      state = metaflip_search_next_seed(state)
      replacement = state % @n
      duplicate = true
      scanned = 0
      while duplicate && scanned < @n
        duplicate = false
        i = 0
        while i < 6
          in_reseeded_side = i >= offset && i < offset + 3
          duplicate = true if !in_reseeded_side && candidate[i] == replacement
          j = 0
          while j < changed
            duplicate = true if candidate[offset + j] == replacement
            j += 1
          i += 1
        if duplicate
          replacement = (replacement + 1) % @n
          scanned += 1
      return nil if duplicate
      candidate[offset + changed] = replacement
      changed += 1
    Metaflip:Proposal.new(candidate, 1)

  -> mutation_batch(request, changes, count)
    proposals = []
    state = request.seed
    i = 0
    while i < count
      local_request = Metaflip:Request.new(request.parent, request.best,
        request.generation, state, request.arm)
      proposal = mutate_proposal(local_request, changes)
      proposals.push(proposal) if proposal != nil
      state = metaflip_search_next_seed(state)
      i += 1
    return nil if proposals.size() == 0
    Metaflip:ProposalBatch.new(proposals)

  -> fibre_reseed_batch(request, count)
    proposals = []
    state = request.seed
    i = 0
    while i < count
      local_request = Metaflip:Request.new(request.parent, request.best,
        request.generation, state, request.arm)
      proposal = fibre_reseed_proposal(local_request)
      proposals.push(proposal) if proposal != nil
      state = metaflip_search_next_seed(state)
      i += 1
    return nil if proposals.size() == 0
    Metaflip:ProposalBatch.new(proposals)

  -> strategies
    domain = self
    [-> (request) domain.random_proposal(request),
      -> (request) domain.mutate_proposal(request, 1),
      -> (request) domain.mutate_proposal(request, 2),
      -> (request) domain.fibre_reseed_proposal(request)]

  -> search(seed)
    domain = self
    verifier = -> (candidate) domain.assess(candidate)
    copier = -> (candidate) domain.snapshot(candidate)
    Metaflip:Search.new(strategies(), verifier, copier, [1, 1, 0 - 1],
      {capacity: 32, seed: seed, valid_reward: 1000, novel_reward: 0,
        improvement_reward: 1000000, exploration: 50000})

  -> rational_map(candidate)
    left = []
    right = []
    i = 0
    while i < 3
      left.push(@points[candidate[i]])
      right.push(@points[candidate[i + 3]])
      i += 1
    numerator = metaflip_prime_locator_polynomial(left, @prime)
    other = metaflip_prime_locator_polynomial(right, @prime)
    Metaflip:PrimeRationalMap.new(numerator,
      metaflip_prime_polynomial_add(numerator, other, @prime))

  # Exhaust the six one-root coordinate axes around an exact near-winner.
  # The working candidate is mutated in place; only a strict exact improvement
  # is snapshotted, avoiding a Proposal/Assessment allocation per neighbor.
  -> coordinate_sweep(candidate)
    return nil if !valid?(candidate)
    working = snapshot(candidate)
    best = snapshot(candidate)
    best_score = profile_score(best)
    checks = 0
    slot = 0
    while slot < 6
      original = working[slot]
      replacement = 0
      while replacement < @n
        duplicate = false
        i = 0
        while i < 6
          duplicate = true if i != slot && working[i] == replacement
          i += 1
        if !duplicate && replacement != original
          working[slot] = replacement
          result_score = profile_score(working)
          checks += 1
          if result_score > best_score
            best = snapshot(working)
            best_score = result_score
          working[slot] = original
        replacement += 1
      slot += 1
    {candidate: best, profile: profile(best), checks: checks}

  -> __load_same_side_row(row, candidate, side, fixed, point_index)
    offset = side * 3
    other_offset = (1 - side) * 3
    t = @points[point_index] ## i64
    base = metaflip_prime_normalize(t - @points[candidate[offset + fixed]], @prime) ## i64
    other = 1 ## i64
    i = 0
    while i < 3
      factor = metaflip_prime_normalize(t - @points[candidate[other_offset + i]], @prime) ## i64
      other = other * factor % @prime
      i += 1
    __load_row(row, 0 - base * t % @prime, base, 0 - other,
      0 - (base * t % @prime) * t % @prime)

  -> __same_side_repair(candidate, side, pair, x_index, y_index, z_index)
    first = 0
    second = 1
    fixed = 2
    if pair == 1
      first = 0
      second = 2
      fixed = 1
    elsif pair == 2
      first = 1
      second = 2
      fixed = 0
    __load_same_side_row(0, candidate, side, fixed, x_index)
    __load_same_side_row(1, candidate, side, fixed, y_index)
    __load_same_side_row(2, candidate, side, fixed, z_index)
    return nil if !__solve_loaded
    root_sum = @solution0
    root_product = @solution1
    first_index = 0
    while first_index < @n
      first_root = @points[first_index]
      second_root = metaflip_prime_normalize(root_sum - first_root, @prime)
      second_index = __point_index(second_root)
      if second_index > first_index && first_root * second_root % @prime == root_product
        repaired = snapshot(candidate)
        offset = side * 3
        repaired[offset + first] = first_index
        repaired[offset + second] = second_index
        return repaired if valid?(repaired)
      first_index += 1
    nil

  -> __load_mixed_row(row, candidate, left_slot, right_slot, point_index)
    t = @points[point_index] ## i64
    left_base = 1 ## i64
    right_base = 1 ## i64
    i = 0
    while i < 3
      if i != left_slot
        factor = metaflip_prime_normalize(t - @points[candidate[i]], @prime) ## i64
        left_base = left_base * factor % @prime
      if i != right_slot
        factor = metaflip_prime_normalize(t - @points[candidate[i + 3]], @prime) ## i64
        right_base = right_base * factor % @prime
      i += 1
    __load_row(row, 0 - left_base, 0 - right_base * t % @prime,
      right_base, 0 - left_base * t % @prime)

  -> __mixed_repair(candidate, left_slot, right_slot, x_index, y_index, z_index)
    __load_mixed_row(0, candidate, left_slot, right_slot, x_index)
    __load_mixed_row(1, candidate, left_slot, right_slot, y_index)
    __load_mixed_row(2, candidate, left_slot, right_slot, z_index)
    return nil if !__solve_loaded || @solution1 == 0
    left_index = __point_index(@solution0)
    right_root = @solution2 * @solution1.invmod(@prime) % @prime
    right_index = __point_index(right_root)
    return nil if left_index < 0 || right_index < 0
    repaired = snapshot(candidate)
    repaired[left_slot] = left_index
    repaired[right_slot + 3] = right_index
    return nil if !valid?(repaired)
    repaired

  # Promote an observed two-point fibre by solving, rather than enumerating,
  # every two-root move. Removing two roots from one locator makes the desired
  # three-way equality linear in their sum and product; removing one root from
  # each side is linear in r, C, and C*s. Only solutions whose predicted roots
  # return to the finite domain are sent through the full exact profile.
  -> targeted_double_repair(candidate)
    doubles = fibre_indices(candidate, 2)
    return nil if doubles == nil
    best = snapshot(candidate)
    best_score = profile_score(best)
    systems = 0
    subgroup_solutions = 0
    exact_checks = 0
    di = 0
    while di < doubles.size()
      x_index = doubles[di][0]
      y_index = doubles[di][1]
      z_index = 0
      while z_index < @n
        skip = z_index == x_index || z_index == y_index
        i = 0
        while i < 6
          skip = true if candidate[i] == z_index
          i += 1
        if !skip
          side = 0
          while side < 2
            pair = 0
            while pair < 3
              repaired = __same_side_repair(candidate, side, pair,
                x_index, y_index, z_index)
              systems += 1
              if repaired != nil
                subgroup_solutions += 1
                repaired_score = profile_score(repaired)
                exact_checks += 1
                if repaired_score > best_score
                  best = repaired
                  best_score = repaired_score
              pair += 1
            side += 1
          left_slot = 0
          while left_slot < 3
            right_slot = 0
            while right_slot < 3
              repaired = __mixed_repair(candidate, left_slot, right_slot,
                x_index, y_index, z_index)
              systems += 1
              if repaired != nil
                subgroup_solutions += 1
                repaired_score = profile_score(repaired)
                exact_checks += 1
                if repaired_score > best_score
                  best = repaired
                  best_score = repaired_score
              right_slot += 1
            left_slot += 1
        z_index += 1
      di += 1
    {candidate: best, profile: profile(best), systems: systems,
      subgroup_solutions: subgroup_solutions, exact_checks: exact_checks,
      doubles: doubles}

-> projected_cubic_coefficient_strategies(domain)
  [-> (request) domain.mutate(request, 0),
    -> (request) domain.mutate(request, 1),
    -> (request) domain.mutate(request, 2),
    -> (request) domain.mutate(request, 3)]

-> projected_cubic_search(domain, strategies, seed)
  domain.search_with(strategies,
    {capacity: 32, seed: seed, valid_reward: 1000, novel_reward: 100000,
      improvement_reward: 1000000, exploration: 50000})

# Small-field repair oracle: this chart has two triples plus a double, and a
# one-root (therefore also two-root-equation) repair reaches three triples.
# It guards the linear solver before a no-solution result is trusted on mu_512.
repair_test_points = []
i = 0
while i < 17
  repair_test_points.push(i)
  i += 1
repair_test_domain = ProjectedCubicPairSearchDomain.new(repair_test_points, 17)
repair_test_start = [0, 1, 2, 3, 4, 8]
repair_test_result = repair_test_domain.targeted_double_repair(repair_test_start)
repair_test_ok = repair_test_domain.profile(repair_test_start)[:exact_fibres] == 2
repair_test_ok = false if repair_test_result == nil
repair_test_ok = false if repair_test_ok && repair_test_result[:profile][:exact_fibres] < 3
if !repair_test_ok
  << "PROJECTED_CUBIC_FAIL targeted double repair oracle"
  exit(1)

prime = 2130706433
generator = 3.modpow((prime - 1) / 512, prime)
points = []
x = 1
i = 0
while i < 512
  points.push(x)
  x = x * generator % prime
  i += 1

if x != 1 || points.uniq.size() != 512
  << "PROJECTED_CUBIC_FAIL mu_512 generation"
  exit(1)

domain = Metaflip:FiniteMapDomain.new(points, prime, 3, 4, 4,
  {coverage_bin: 3})

trials = 8
steps = 8192
trials = ARGV[0].to_i() if ARGV.size() > 0
steps = ARGV[1].to_i() if ARGV.size() > 1
run_exact = ARGV.size() > 2 && ARGV[2] == "exact"
fast_steps = 0
fast_steps = ARGV[3].to_i() if ARGV.size() > 3
fast_seed = 1701103
fast_seed = ARGV[4].to_i() if ARGV.size() > 4
run_sweep = ARGV.size() > 5 && ARGV[5] == "sweep"
sweep_roots = nil
if ARGV.size() >= 12 && ARGV[5] == "sweep-roots"
  sweep_roots = []
  i = 0
  while i < 6
    sweep_roots.push(ARGV[i + 6].to_i())
    i += 1
repair_roots = nil
if ARGV.size() >= 12 && ARGV[5] == "repair-roots"
  repair_roots = []
  i = 0
  while i < 6
    repair_roots.push(ARGV[i + 6].to_i())
    i += 1
if trials < 1 || steps < 1
  << "usage: proximity_projected_cubic_bench [trials>=1] [steps>=1]"
  exit(2)

coefficient_best = 0
locator_best = 0
coefficient_checks = 0
locator_checks = 0
best_map = nil
trial = 0
while trial < trials
  seed = 991027 + trial * 104729

  coefficient = projected_cubic_search(domain,
    projected_cubic_coefficient_strategies(domain), seed)
  coefficient.run(steps)
  coefficient_best = coefficient.best_scores[0] if coefficient.best_scores[0] > coefficient_best
  coefficient_checks += coefficient.stats[:exact_checks]

  locator = projected_cubic_search(domain, domain.default_strategies(), seed)
  locator.run(steps)
  if locator.best_scores[0] > locator_best
    locator_best = locator.best_scores[0]
    best_map = locator.best_state
  locator_checks += locator.stats[:exact_checks]
  trial += 1

<< "proximity_projected_cubic_bench trials=" + trials.to_s() + " steps=" + steps.to_s()
coefficient_line = "coefficient best_covered=" + coefficient_best.to_s()
coefficient_line += " exact_checks=" + coefficient_checks.to_s()
<< coefficient_line
locator_line = "locator best_covered=" + locator_best.to_s()
locator_line += " exact_checks=" + locator_checks.to_s()
<< locator_line
if best_map != nil
  profile = domain.profile(best_map)
  << "locator best_numerator=" + best_map.numerator.to_s()
  << "locator best_profile=" + profile.to_s()

if run_exact
  exact = projected_cubic_exact_best(domain, points, prime)
  if exact == nil
    << "PROJECTED_CUBIC_FAIL exact signature index"
    exit(1)
  exact_line = "exact signatures=" + exact[:signatures].to_s()
  exact_line += " triple_fibres=" + exact[:triple_fibres].to_s()
  << exact_line
  << "exact numerator=" + exact[:candidate].numerator.to_s()
  << "exact profile=" + exact[:profile].to_s()
  if exact[:profile] == nil || exact[:profile][:exact_fibres] != exact[:triple_fibres]
    << "PROJECTED_CUBIC_FAIL signature/profile disagreement"
    exit(1)

if fast_steps > 0
  fast_domain = ProjectedCubicPairSearchDomain.new(points, prime)
  fast_search = fast_domain.search(fast_seed)
  fast_search.run(fast_steps)
  fast_best = fast_search.best_state
  fast_profile = fast_domain.profile(fast_best)
  fast_map = fast_domain.rational_map(fast_best)
  fast_line = "fast_pair seed=" + fast_seed.to_s() + " steps=" + fast_steps.to_s()
  fast_line += " roots=" + fast_best.to_s()
  << fast_line
  << "fast_pair profile=" + fast_profile.to_s()
  << "fast_pair numerator=" + fast_map.numerator.to_s()
  << "fast_pair denominator=" + fast_map.denominator.to_s()
  << "fast_pair exact_checks=" + fast_search.stats[:exact_checks].to_s()
  << "fast_pair archive_size=" + fast_search.archive_size.to_s()
  << "fast_pair arms=" + fast_search.arm_stats.to_s()
  if run_sweep
    swept = fast_domain.coordinate_sweep(fast_best)
    << "fast_pair sweep_checks=" + swept[:checks].to_s()
    << "fast_pair sweep_roots=" + swept[:candidate].to_s()
    << "fast_pair sweep_profile=" + swept[:profile].to_s()

if sweep_roots != nil
  sweep_domain = ProjectedCubicPairSearchDomain.new(points, prime)
  << "fast_pair direct_roots=" + sweep_roots.to_s()
  << "fast_pair direct_profile=" + sweep_domain.profile(sweep_roots).to_s()
  swept = sweep_domain.coordinate_sweep(sweep_roots)
  << "fast_pair sweep_checks=" + swept[:checks].to_s()
  << "fast_pair sweep_roots=" + swept[:candidate].to_s()
  << "fast_pair sweep_profile=" + swept[:profile].to_s()

if repair_roots != nil
  repair_domain = ProjectedCubicPairSearchDomain.new(points, prime)
  << "fast_pair repair_roots=" + repair_roots.to_s()
  << "fast_pair repair_profile=" + repair_domain.profile(repair_roots).to_s()
  repaired = repair_domain.targeted_double_repair(repair_roots)
  << "fast_pair repair_doubles=" + repaired[:doubles].to_s()
  << "fast_pair repair_systems=" + repaired[:systems].to_s()
  << "fast_pair repair_subgroup_solutions=" + repaired[:subgroup_solutions].to_s()
  << "fast_pair repair_exact_checks=" + repaired[:exact_checks].to_s()
  << "fast_pair repair_best_roots=" + repaired[:candidate].to_s()
  << "fast_pair repair_best_profile=" + repaired[:profile].to_s()

if coefficient_checks != locator_checks || locator_best < 3
  << "PROJECTED_CUBIC_FAIL matched collision search"
  exit(1)

<< "proximity_projected_cubic_bench: search complete"
