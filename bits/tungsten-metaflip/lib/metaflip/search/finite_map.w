# Exact fibre-profile search for rational maps on finite prime-field subsets.
#
# This is a reusable non-tensor adapter for `Metaflip:Search`.  It is useful
# for covering maps, perfect/near-perfect hashing, collision constructions,
# coding-theory support designs, and finite dynamical systems.  The input set,
# prime, coefficient bounds, and desired fibre size are all caller-owned.

use ../search

-> metaflip_prime_normalize(value, prime) (i64 i64) i64
  result = value % prime ## i64
  if result < 0
    result += prime
  result

# Horner evaluation. `FiniteMapDomain` caps prime at floor(sqrt(INT64_MAX)),
# so every reduced multiply-and-add remains inside signed i64.
-> metaflip_prime_polynomial_eval(coefficients, x, prime) (Array i64 i64) i64
  result = 0 ## i64
  i = coefficients.size() - 1
  while i >= 0
    result = (result * x + metaflip_prime_normalize(coefficients[i], prime)) % prime
    i -= 1
  result

-> metaflip_prime_polynomial_degree(coefficients, prime) (Array i64) i64
  i = coefficients.size() - 1
  while i >= 0
    if metaflip_prime_normalize(coefficients[i], prime) != 0
      return i
    i -= 1
  0 - 1

-> metaflip_prime_polynomial_nonzero_count(coefficients, prime) (Array i64) i64
  count = 0
  i = 0
  while i < coefficients.size()
    count += 1 if metaflip_prime_normalize(coefficients[i], prime) != 0
    i += 1
  count

-> metaflip_finite_map_copy_coefficients(coefficients, prime)
  out = []
  i = 0
  while i < coefficients.size()
    out.push(metaflip_prime_normalize(coefficients[i], prime))
    i += 1
  out

# Return the monic polynomial whose distinct roots are `roots`. Coefficients
# are constant-first. Locator polynomials let a strategy propose candidates on
# a desired collision manifold instead of hoping coefficient noise lands there.
-> metaflip_prime_locator_polynomial(roots, prime)
  return nil if roots == nil || !roots.is_a?(Array) || roots.size() < 1
  coefficients = [1]
  seen = {}
  ri = 0
  while ri < roots.size()
    return nil if !roots[ri].is_a?(Integer)
    root = metaflip_prime_normalize(roots[ri], prime)
    return nil if seen[root] == true
    seen[root] = true
    next_coefficients = []
    i = 0
    while i <= coefficients.size()
      next_coefficients.push(0)
      i += 1
    i = 0
    while i < coefficients.size()
      low = next_coefficients[i] - root * coefficients[i]
      next_coefficients[i] = metaflip_prime_normalize(low, prime)
      high = next_coefficients[i + 1] + coefficients[i]
      next_coefficients[i + 1] = metaflip_prime_normalize(high, prime)
      i += 1
    coefficients = next_coefficients
    ri += 1
  coefficients

-> metaflip_prime_polynomial_add(left, right, prime)
  return nil if left == nil || right == nil || !left.is_a?(Array) || !right.is_a?(Array)
  size = left.size()
  size = right.size() if right.size() > size
  return nil if size < 1
  out = []
  i = 0
  while i < size
    a = 0
    b = 0
    a = left[i] if i < left.size()
    b = right[i] if i < right.size()
    return nil if !a.is_a?(Integer) || !b.is_a?(Integer)
    out.push(metaflip_prime_normalize(a + b, prime))
    i += 1
  out

# Montgomery batch inversion: one field inversion plus O(n) multiplies.
# Returns nil if any input is zero.  The empty input has an empty inverse list.
-> metaflip_prime_batch_inverses(values, prime)
  prefixes = []
  product = 1 ## i64
  i = 0
  while i < values.size()
    value = metaflip_prime_normalize(values[i], prime)
    return nil if value == 0
    prefixes.push(product)
    product = (product * value) % prime
    i += 1
  inverses = []
  i = 0
  while i < values.size()
    inverses.push(0)
    i += 1
  return inverses if values.size() == 0
  suffix_inverse = product.invmod(prime)
  i = values.size() - 1
  while i >= 0
    value = metaflip_prime_normalize(values[i], prime)
    inverses[i] = (suffix_inverse * prefixes[i]) % prime
    suffix_inverse = (suffix_inverse * value) % prime
    i -= 1
  inverses

+ Metaflip:PrimeRationalMap
  ro :numerator
  ro :denominator

  # Coefficients are constant-first.  Domain snapshots normalize them modulo
  # the configured prime; construction itself remains field-agnostic.
  -> new(numerator, denominator)
    if numerator == nil || denominator == nil || !numerator.is_a?(Array) || !denominator.is_a?(Array)
      raise "Metaflip::PrimeRationalMap coefficients must be Arrays"
    if numerator.size() < 1 || denominator.size() < 1
      raise "Metaflip::PrimeRationalMap coefficient Arrays must be nonempty"
    @numerator = metaflip_search_copy_values(numerator)
    @denominator = metaflip_search_copy_values(denominator)

+ Metaflip:FiniteMapDomain
  # `numerator_terms` and `denominator_terms` are inclusive coefficient counts
  # for the built-in random/mutation strategies.  External strategies may emit
  # shorter candidates, but never longer ones.
  #
  # Options:
  #   allow_poles:    retain exactly profiled poles instead of rejecting (false)
  #   coverage_bin:   descriptor bin width for exactly covered points (target)
  #   diversity_bins: stable coefficient-identity bins in each metric niche (1)
  #   locator_batch:  alternatives emitted by each locator flip (1, max 64)
  -> new(points, prime, target_fibre, numerator_terms, denominator_terms, options = {})
    if points == nil || !points.is_a?(Array) || points.size() < 1
      raise "Metaflip::FiniteMapDomain points must be a nonempty Array"
    if !prime.is_a?(Integer) || prime < 3 || prime > 3037000499 || !prime.prime?()
      raise "Metaflip::FiniteMapDomain prime must be an odd prime at most 3037000499"
    if !target_fibre.is_a?(Integer) || target_fibre < 2
      raise "Metaflip::FiniteMapDomain target_fibre must be at least two"
    if !numerator_terms.is_a?(Integer) || numerator_terms < 1
      raise "Metaflip::FiniteMapDomain numerator_terms must be positive"
    if !denominator_terms.is_a?(Integer) || denominator_terms < 1
      raise "Metaflip::FiniteMapDomain denominator_terms must be positive"

    @prime = prime
    @target_fibre = target_fibre
    @numerator_terms = numerator_terms
    @denominator_terms = denominator_terms
    @allow_poles = options[:allow_poles] == true
    @coverage_bin = options[:coverage_bin] || target_fibre
    @diversity_bins = options[:diversity_bins] || 1
    @locator_batch = options[:locator_batch] || 1
    if !@coverage_bin.is_a?(Integer) || @coverage_bin < 1
      raise "Metaflip::FiniteMapDomain coverage_bin must be positive"
    if !@diversity_bins.is_a?(Integer) || @diversity_bins < 1 || @diversity_bins > 65536
      raise "Metaflip::FiniteMapDomain diversity_bins must be between 1 and 65536"
    if !@locator_batch.is_a?(Integer) || @locator_batch < 1 || @locator_batch > 64
      raise "Metaflip::FiniteMapDomain locator_batch must be between 1 and 64"

    @points = []
    seen = {}
    i = 0
    while i < points.size()
      if !points[i].is_a?(Integer)
        raise "Metaflip::FiniteMapDomain points must contain only Integers"
      value = metaflip_prime_normalize(points[i], @prime)
      if seen[value] == true
        raise "Metaflip::FiniteMapDomain points must be distinct modulo prime"
      seen[value] = true
      @points.push(value)
      i += 1

  -> prime
    @prime

  -> target_fibre
    @target_fibre

  -> points
    metaflip_search_copy_values(@points)

  -> directions
    # Exactly covered points, capped collision pairs, overfull excess, poles.
    [1, 1, 0 - 1, 0 - 1]

  -> snapshot(candidate)
    if candidate == nil || !candidate.is_a?(Metaflip:PrimeRationalMap)
      return nil
    Metaflip:PrimeRationalMap.new(
      metaflip_finite_map_copy_coefficients(candidate.numerator, @prime),
      metaflip_finite_map_copy_coefficients(candidate.denominator, @prime))

  -> __candidate_shape_valid(candidate)
    if candidate == nil || !candidate.is_a?(Metaflip:PrimeRationalMap)
      return false
    if candidate.numerator.size() < 1 || candidate.numerator.size() > @numerator_terms
      return false
    if candidate.denominator.size() < 1 || candidate.denominator.size() > @denominator_terms
      return false
    arrays = [candidate.numerator, candidate.denominator]
    side = 0
    while side < arrays.size()
      i = 0
      while i < arrays[side].size()
        return false if !arrays[side][i].is_a?(Integer)
        i += 1
      side += 1
    true

  # Scalar-normalized coefficient identity. Equivalent numerator/denominator
  # pairs differing by a common nonzero field scalar deduplicate exactly.
  -> identity(candidate)
    return nil if !__candidate_shape_valid(candidate)
    pivot = 0
    i = 0
    while i < candidate.denominator.size() && pivot == 0
      pivot = metaflip_prime_normalize(candidate.denominator[i], @prime)
      i += 1
    return nil if pivot == 0
    inverse = pivot.invmod(@prime)
    parts = []
    numerator_degree = metaflip_prime_polynomial_degree(candidate.numerator, @prime)
    numerator_limit = numerator_degree + 1
    numerator_limit = 1 if numerator_limit < 1
    i = 0
    while i < numerator_limit
      value = metaflip_prime_normalize(candidate.numerator[i], @prime)
      parts.push(((value * inverse) % @prime).to_s())
      i += 1
    parts.push("/")
    denominator_limit = metaflip_prime_polynomial_degree(candidate.denominator, @prime) + 1
    i = 0
    while i < denominator_limit
      value = metaflip_prime_normalize(candidate.denominator[i], @prime)
      parts.push(((value * inverse) % @prime).to_s())
      i += 1
    parts.join(",")

  # Exact image histogram and fibre metrics. `nil` means malformed candidate,
  # not merely a candidate that misses the covering objective.
  -> profile(candidate)
    return nil if !__candidate_shape_valid(candidate)
    denominator_degree = metaflip_prime_polynomial_degree(candidate.denominator, @prime)
    return nil if denominator_degree < 0

    counts = {}
    poles = 0
    defined = 0
    numerators = []
    denominators = []
    i = 0
    while i < @points.size()
      x = @points[i]
      denominator = metaflip_prime_polynomial_eval(candidate.denominator, x, @prime)
      if denominator == 0
        poles += 1
      else
        numerator = metaflip_prime_polynomial_eval(candidate.numerator, x, @prime)
        numerators.push(numerator)
        denominators.push(denominator)
        defined += 1
      i += 1

    denominator_inverses = metaflip_prime_batch_inverses(denominators, @prime)
    return nil if denominator_inverses == nil
    i = 0
    while i < numerators.size()
      value = (numerators[i] * denominator_inverses[i]) % @prime
      previous = counts[value] || 0
      counts[value] = previous + 1
      i += 1

    exact_fibres = 0
    covered = 0
    capped_pairs = 0
    overfull = 0
    max_fibre = 0
    values = counts.values
    i = 0
    while i < values.size()
      count = values[i]
      max_fibre = count if count > max_fibre
      if count == @target_fibre
        exact_fibres += 1
        covered += count
      capped = count
      capped = @target_fibre if capped > @target_fibre
      capped_pairs += capped * (capped - 1) / 2
      overfull += count - @target_fibre if count > @target_fibre
      i += 1

    {points: @points.size(), defined: defined, poles: poles,
      image_size: counts.size(), exact_fibres: exact_fibres, covered: covered,
      capped_pairs: capped_pairs, overfull: overfull, max_fibre: max_fibre,
      numerator_degree: metaflip_prime_polynomial_degree(candidate.numerator, @prime),
      denominator_degree: denominator_degree,
      numerator_support: metaflip_prime_polynomial_nonzero_count(candidate.numerator, @prime),
      denominator_support: metaflip_prime_polynomial_nonzero_count(candidate.denominator, @prime)}

  -> descriptor(candidate, profile)
    covered_bin = profile[:covered] / @coverage_bin
    max_bin = profile[:max_fibre]
    max_bin = @target_fibre + 1 if max_bin > @target_fibre
    pole_bin = profile[:poles]
    pole_bin = 3 if pole_bin > 3
    result = profile[:numerator_degree].to_s() + ":" + profile[:denominator_degree].to_s()
    result += ":" + profile[:numerator_support].to_s() + ":" + profile[:denominator_support].to_s()
    result += ":" + covered_bin.to_s() + ":" + max_bin.to_s() + ":" + pole_bin.to_s()
    result += ":" + __diversity_bin(candidate).to_s() if @diversity_bins > 1
    result

  # Stable scalar-normalized coefficient bucket. Metric descriptors alone can
  # collapse a broad plateau into one archive entry, so local flips repeatedly
  # restart from the same basin. Callers may opt into a bounded number of
  # identity bins without exposing domain-specific features to Search.
  -> __diversity_bin(candidate)
    return 0 if @diversity_bins <= 1
    pivot = 0
    i = 0
    while i < candidate.denominator.size() && pivot == 0
      pivot = metaflip_prime_normalize(candidate.denominator[i], @prime)
      i += 1
    return 0 if pivot == 0
    inverse = pivot.invmod(@prime)
    bucket = 17 % @diversity_bins
    arrays = [candidate.numerator, candidate.denominator]
    side = 0
    while side < arrays.size()
      degree = metaflip_prime_polynomial_degree(arrays[side], @prime)
      limit = degree + 1
      limit = 1 if limit < 1
      i = 0
      while i < limit
        coefficient = metaflip_prime_normalize(arrays[side][i], @prime)
        normalized = coefficient * inverse % @prime
        bucket = (bucket * 257 + normalized % @diversity_bins + 1) % @diversity_bins
        i += 1
      bucket = (bucket * 257 + 251 + side) % @diversity_bins
      side += 1
    bucket

  -> assess(candidate)
    profile = self.profile(candidate)
    return nil if profile == nil
    return nil if !@allow_poles && profile[:poles] > 0
    identity = self.identity(candidate)
    return nil if identity == nil
    scores = [profile[:covered], profile[:capped_pairs], profile[:overfull], profile[:poles]]
    Metaflip:Assessment.new(scores, descriptor(candidate, profile), identity)

  -> goal?(candidate)
    profile = self.profile(candidate)
    return false if profile == nil
    profile[:poles] == 0 && profile[:covered] == @points.size() && profile[:overfull] == 0

  # Build a polynomial map with the supplied points as the zero fibre. This
  # operation is exact and general, but available only when the configured
  # numerator degree can represent a target-sized locator.
  -> locator_candidate(roots)
    return nil if roots == nil || !roots.is_a?(Array) || roots.size() != @target_fibre
    return nil if @numerator_terms < @target_fibre + 1 || @denominator_terms < 1
    numerator = metaflip_prime_locator_polynomial(roots, @prime)
    return nil if numerator == nil || numerator.size() > @numerator_terms
    Metaflip:PrimeRationalMap.new(numerator, [1])

  # For disjoint root sets A and B, locatorA/(locatorA+locatorB) maps A to
  # zero and B to one. It therefore starts with two target fibres while keeping
  # both finite; any incidental pole is still rejected by the ordinary exact
  # verifier. This is useful whenever both configured degree bounds can hold a
  # target-sized locator.
  -> locator_pair_candidate(left_roots, right_roots)
    return nil if left_roots == nil || right_roots == nil
    return nil if !left_roots.is_a?(Array) || !right_roots.is_a?(Array)
    return nil if left_roots.size() != @target_fibre || right_roots.size() != @target_fibre
    return nil if @numerator_terms < @target_fibre + 1
    return nil if @denominator_terms < @target_fibre + 1
    seen = {}
    sides = [left_roots, right_roots]
    side = 0
    while side < sides.size()
      i = 0
      while i < sides[side].size()
        return nil if !sides[side][i].is_a?(Integer)
        root = metaflip_prime_normalize(sides[side][i], @prime)
        return nil if seen[root] == true
        seen[root] = true
        i += 1
      side += 1
    numerator = metaflip_prime_locator_polynomial(left_roots, @prime)
    other = metaflip_prime_locator_polynomial(right_roots, @prime)
    return nil if numerator == nil || other == nil
    denominator = metaflip_prime_polynomial_add(numerator, other, @prime)
    return nil if denominator == nil
    Metaflip:PrimeRationalMap.new(numerator, denominator)

  # Deterministically sample distinct domain points and force them into one
  # exact-size fibre. The degree bound means the zero fibre cannot silently
  # acquire another field root.
  -> locator_seed(seed)
    return nil if @points.size() < @target_fibre
    return nil if @numerator_terms < @target_fibre + 1 || @denominator_terms < 1
    roots = []
    used = {}
    state = seed
    while roots.size() < @target_fibre
      state = metaflip_search_next_seed(state)
      index = state % @points.size()
      scanned = 0
      while used[index] == true && scanned < @points.size()
        index = (index + 1) % @points.size()
        scanned += 1
      return nil if scanned == @points.size()
      used[index] = true
      roots.push(@points[index])
    candidate = locator_candidate(roots)
    return nil if candidate == nil
    Metaflip:Proposal.new(candidate, @target_fibre)

  -> locator_pair_seed(seed)
    needed = @target_fibre * 2
    return nil if @points.size() < needed
    return nil if @numerator_terms < @target_fibre + 1
    return nil if @denominator_terms < @target_fibre + 1
    roots = []
    used = {}
    state = seed
    while roots.size() < needed
      state = metaflip_search_next_seed(state)
      index = state % @points.size()
      scanned = 0
      while used[index] == true && scanned < @points.size()
        index = (index + 1) % @points.size()
        scanned += 1
      return nil if scanned == @points.size()
      used[index] = true
      roots.push(@points[index])
    left = []
    right = []
    i = 0
    while i < @target_fibre
      left.push(roots[i])
      right.push(roots[i + @target_fibre])
      i += 1
    candidate = locator_pair_candidate(left, right)
    return nil if candidate == nil
    Metaflip:Proposal.new(candidate, needed)

  # Recover one exact-size fibre from an admitted parent. The selected fibre
  # varies with `seed`; callers receive a private point Array or nil.
  -> exact_fibres(candidate)
    return nil if !__candidate_shape_valid(candidate)
    buckets = {}
    numerators = []
    denominators = []
    points = []
    i = 0
    while i < @points.size()
      x = @points[i]
      denominator = metaflip_prime_polynomial_eval(candidate.denominator, x, @prime)
      if denominator != 0
        numerators.push(metaflip_prime_polynomial_eval(candidate.numerator, x, @prime))
        denominators.push(denominator)
        points.push(x)
      i += 1
    inverses = metaflip_prime_batch_inverses(denominators, @prime)
    return nil if inverses == nil
    i = 0
    while i < numerators.size()
      value = (numerators[i] * inverses[i]) % @prime
      bucket = buckets[value]
      if bucket == nil
        bucket = []
        buckets[value] = bucket
      bucket.push(points[i])
      i += 1
    exact = []
    values = buckets.values
    i = 0
    while i < values.size()
      exact.push(values[i]) if values[i].size() == @target_fibre
      i += 1
    exact

  -> exact_fibre_points(candidate, seed = 0)
    exact = exact_fibres(candidate)
    return nil if exact == nil || exact.size() == 0
    chosen = exact[seed % exact.size()]
    metaflip_search_copy_values(chosen)

  # Preserve a useful collision while replacing one of its points. This flip
  # explores the target-fibre manifold rather than almost-always-injective
  # coefficient space.
  -> locator_flip(request)
    parent = request.parent
    parent = request.best if parent == nil
    return locator_seed(request.seed) if parent == nil
    roots = exact_fibre_points(parent, request.seed)
    return locator_seed(request.seed) if roots == nil
    state = metaflip_search_next_seed(request.seed)
    slot = state % roots.size()
    used = {}
    i = 0
    while i < roots.size()
      used[roots[i]] = true if i != slot
      i += 1
    state = metaflip_search_next_seed(state)
    index = state % @points.size()
    scanned = 0
    while used[@points[index]] == true && scanned < @points.size()
      index = (index + 1) % @points.size()
      scanned += 1
    return nil if scanned == @points.size()
    roots[slot] = @points[index]
    candidate = locator_candidate(roots)
    return nil if candidate == nil
    Metaflip:Proposal.new(candidate, @points.size() + @target_fibre)

  # Retain two exact fibres from a rational parent, replace one point, and
  # rebuild the paired-locator chart. Proposals remain on a two-collision
  # manifold unless the exact pole gate rejects the rebuilt denominator.
  -> locator_pair_flip(request)
    parent = request.parent
    parent = request.best if parent == nil
    return locator_pair_seed(request.seed) if parent == nil
    fibres = exact_fibres(parent)
    return locator_pair_seed(request.seed) if fibres == nil || fibres.size() < 2
    state = metaflip_search_next_seed(request.seed)
    left_index = state % fibres.size()
    state = metaflip_search_next_seed(state)
    right_index = state % (fibres.size() - 1)
    right_index += 1 if right_index >= left_index
    left = metaflip_search_copy_values(fibres[left_index])
    right = metaflip_search_copy_values(fibres[right_index])
    state = metaflip_search_next_seed(state)
    side = state & 1
    target = left
    target = right if side == 1
    state = metaflip_search_next_seed(state)
    slot = state % target.size()
    used = {}
    i = 0
    while i < left.size()
      used[left[i]] = true if side != 0 || i != slot
      used[right[i]] = true if side != 1 || i != slot
      i += 1
    state = metaflip_search_next_seed(state)
    index = state % @points.size()
    scanned = 0
    while used[@points[index]] == true && scanned < @points.size()
      index = (index + 1) % @points.size()
      scanned += 1
    return nil if scanned == @points.size()
    target[slot] = @points[index]
    candidate = locator_pair_candidate(left, right)
    return nil if candidate == nil
    Metaflip:Proposal.new(candidate, @points.size() + @target_fibre * 2)

  # Emit several root-preserving neighbors when requested. Search verifies and
  # admits each member independently, so the best candidate is selected by the
  # exact objective while MAP-Elites may retain alternatives from other bins.
  # A batch of one preserves the historical single-Proposal API.
  -> locator_flip_batch(request)
    return locator_flip(request) if @locator_batch == 1
    proposals = []
    state = request.seed
    i = 0
    while i < @locator_batch
      local_request = Metaflip:Request.new(request.parent, request.best,
        request.generation, state, request.arm)
      proposal = locator_flip(local_request)
      proposals.push(proposal) if proposal != nil
      state = metaflip_search_next_seed(state)
      i += 1
    return nil if proposals.size() == 0
    Metaflip:ProposalBatch.new(proposals)

  -> locator_pair_flip_batch(request)
    return locator_pair_flip(request) if @locator_batch == 1
    proposals = []
    state = request.seed
    i = 0
    while i < @locator_batch
      local_request = Metaflip:Request.new(request.parent, request.best,
        request.generation, state, request.arm)
      proposal = locator_pair_flip(local_request)
      proposals.push(proposal) if proposal != nil
      state = metaflip_search_next_seed(state)
      i += 1
    return nil if proposals.size() == 0
    Metaflip:ProposalBatch.new(proposals)

  -> random_candidate(seed)
    state = seed & 9223372036854775807
    state = 1 if state == 0
    numerator = []
    denominator = []
    i = 0
    while i < @numerator_terms
      state = metaflip_search_next_seed(state)
      numerator.push(state % @prime)
      i += 1
    i = 0
    while i < @denominator_terms
      if @allow_poles
        state = metaflip_search_next_seed(state)
        denominator.push(state % @prime)
      else
        denominator.push(0)
      i += 1
    denominator[0] = 1 if !@allow_poles || metaflip_prime_polynomial_degree(denominator, @prime) < 0
    Metaflip:PrimeRationalMap.new(numerator, denominator)

  -> mutate(request, mode)
    parent = request.parent
    parent = request.best if parent == nil
    parent = random_candidate(request.seed) if parent == nil
    if !parent.is_a?(Metaflip:PrimeRationalMap)
      return nil
    numerator = metaflip_finite_map_copy_coefficients(parent.numerator, @prime)
    denominator = metaflip_finite_map_copy_coefficients(parent.denominator, @prime)
    numerator.push(0) while numerator.size() < @numerator_terms
    denominator.push(0) while denominator.size() < @denominator_terms
    state = request.seed
    changes = 1
    changes = 2 if mode == 3
    change = 0
    while change < changes
      state = metaflip_search_next_seed(state)
      slot = state % (numerator.size() + denominator.size())
      state = metaflip_search_next_seed(state)
      replacement = state % @prime
      target = numerator
      local_slot = slot
      if slot >= numerator.size()
        target = denominator
        local_slot = slot - numerator.size()
      if mode == 0 || mode == 3
        delta = (state % 17) - 8
        replacement = metaflip_prime_normalize(target[local_slot] + delta, @prime)
      elsif mode == 2
        replacement = 0
        replacement = 1 if (state & 1) != 0
      target[local_slot] = replacement
      change += 1
    if metaflip_prime_polynomial_degree(denominator, @prime) < 0
      denominator[0] = 1
    Metaflip:Proposal.new(Metaflip:PrimeRationalMap.new(numerator, denominator), 1)

  -> default_strategies
    domain = self
    local_step = -> (request) domain.mutate(request, 0)
    resample = -> (request) domain.mutate(request, 1)
    sparse = -> (request) domain.mutate(request, 2)
    double_step = -> (request) domain.mutate(request, 3)
    strategies = [local_step, resample, sparse, double_step]
    if @numerator_terms >= @target_fibre + 1 && @denominator_terms >= 1
      strategies.push(-> (request) domain.locator_seed(request.seed))
      strategies.push(-> (request) domain.locator_flip_batch(request))
    if @numerator_terms >= @target_fibre + 1 && @denominator_terms >= @target_fibre + 1
      strategies.push(-> (request) domain.locator_pair_seed(request.seed))
      strategies.push(-> (request) domain.locator_pair_flip_batch(request))
    strategies

  -> search(options = {})
    search_with(default_strategies(), options)

  -> search_with(strategies, options = {})
    domain = self
    verifier = -> (candidate) domain.assess(candidate)
    snapshot = -> (candidate) domain.snapshot(candidate)
    Metaflip:Search.new(strategies, verifier, snapshot, directions(), options)
