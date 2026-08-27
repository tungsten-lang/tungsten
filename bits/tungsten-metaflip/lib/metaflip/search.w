# Domain-neutral, exact-gated adaptive search.
#
# Metaflip's matrix-multiplication fleets deliberately keep their specialized
# flat-array hot paths.  This module exposes the coordinator pattern without
# importing any GF(2), tensor, or scheme assumptions.  Domain adapters own the
# candidate representation and all speculative/heuristic work.  The search
# only admits a candidate after the adapter's exact verifier returns a typed
# `Metaflip:Assessment`.
#
# Callback arity stays at one so native closure calls remain portable:
#
#   strategy.call(request) -> Metaflip:Proposal | Metaflip:ProposalBatch | nil
#   verifier.call(candidate) -> Metaflip:Assessment | nil
#   snapshot.call(candidate) -> independent candidate copy
#
# Strategies may batch arbitrary CPU/GPU work internally.  Proposal `cost`
# is an adapter-defined positive exposure unit used to normalize portfolio
# reward.  Proxy scores never cross this API boundary and can neither enter
# the archive nor reward a strategy.

# Return 1 when `left` is lexicographically better, -1 when worse, and 0 for
# equality or malformed inputs.  Every direction must be +1 (maximize) or -1
# (minimize).  The comparison never negates a score, avoiding MIN_INT overflow.
-> metaflip_search_compare_scores(left, right, directions) i64
  if left == nil || right == nil || directions == nil
    return 0
  if !left.is_a?(Array) || !right.is_a?(Array) || !directions.is_a?(Array)
    return 0
  if directions.size() < 1 || left.size() != directions.size() || right.size() != directions.size()
    return 0
  i = 0
  while i < directions.size()
    direction = directions[i]
    if !left[i].is_a?(Integer) || !right[i].is_a?(Integer)
      return 0
    if direction != 1 && direction != 0 - 1
      return 0
    if left[i] < right[i]
      if direction == 1
        return 0 - 1
      return 1
    if left[i] > right[i]
      if direction == 1
        return 1
      return 0 - 1
    i += 1
  0

-> metaflip_search_scores_valid(scores, directions) i64
  if scores == nil || directions == nil
    return 0
  if !scores.is_a?(Array) || !directions.is_a?(Array)
    return 0
  if directions.size() < 1 || scores.size() != directions.size()
    return 0
  i = 0
  while i < directions.size()
    if !scores[i].is_a?(Integer)
      return 0
    if directions[i] != 1 && directions[i] != 0 - 1
      return 0
    i += 1
  1

-> metaflip_search_copy_values(values)
  out = []
  i = 0
  while i < values.size()
    out.push(values[i])
    i += 1
  out

# A deterministic positive 63-bit stream.  Domain strategies receive one seed
# per step and decide how (or whether) to expand it into their own RNG state.
-> metaflip_search_next_seed(seed) (i64) i64
  next_seed = (seed * 6364136223846793005 + 1442695040888963407) & 9223372036854775807 ## i64
  if next_seed == 0
    return 1
  next_seed

+ Metaflip:Proposal
  ro :candidate
  ro :cost

  -> new(@candidate, @cost = 1)
    if @candidate == nil
      raise "Metaflip::Proposal candidate must not be nil"
    if !@cost.is_a?(Integer) || @cost < 1
      raise "Metaflip::Proposal cost must be a positive Integer"

# A strategy may expose a bounded neighborhood instead of guessing which one
# of several flips deserves the single exact check.  The coordinator verifies
# and admits every member independently, then credits the arm by total
# exposure.  This keeps candidate selection behind the same exact gate and is
# useful for coordinate sweeps, beam mutations, repair sets, and accelerator
# harvests in domains that have no meaningful scalar "flip".
+ Metaflip:ProposalBatch
  ro :proposals

  -> new(proposals)
    if proposals == nil || !proposals.is_a?(Array) || proposals.size() < 1
      raise "Metaflip::ProposalBatch requires a nonempty Array"
    @proposals = []
    i = 0
    while i < proposals.size()
      if !proposals[i].is_a?(Metaflip:Proposal)
        raise "Metaflip::ProposalBatch entries must be Metaflip::Proposal values"
      @proposals.push(proposals[i])
      i += 1

+ Metaflip:Assessment
  ro :scores
  ro :descriptor
  ro :identity

  # `scores` are exact lexicographic objective components.  `descriptor`
  # chooses a MAP-Elites niche.  A non-nil `identity` suppresses rediscovery
  # across niches; nil intentionally disables identity deduplication.
  -> new(@scores, @descriptor, @identity = nil)

+ Metaflip:Request
  ro :parent
  ro :best
  ro :generation
  ro :seed
  ro :arm

  -> new(@parent, @best, @generation, @seed, @arm)

+ Metaflip:Search
  # `directions` is one +1/-1 entry per exact objective component.
  # Supported options:
  #   capacity:           exact archive entries (default 64)
  #   seed:               deterministic coordinator seed (default 1)
  #   valid_reward:       reward for an exact-valid result (default 1000)
  #   novel_reward:       reward for a new descriptor (default 100000)
  #   improvement_reward: reward for a new global best (default 1000000)
  #   exploration:        untried/low-pull portfolio bonus (default 50000)
  -> new(strategies, verifier, snapshot, directions, options = {})
    if strategies == nil || !strategies.is_a?(Array) || strategies.size() < 1
      raise "Metaflip::Search requires at least one strategy closure"
    if verifier == nil || snapshot == nil
      raise "Metaflip::Search requires verifier and snapshot closures"
    if directions == nil || !directions.is_a?(Array) || directions.size() < 1
      raise "Metaflip::Search requires at least one objective direction"

    @directions = metaflip_search_copy_values(directions)
    i = 0
    while i < @directions.size()
      if !@directions[i].is_a?(Integer) || (@directions[i] != 1 && @directions[i] != 0 - 1)
        raise "Metaflip::Search directions must contain only +1 or -1"
      i += 1

    @capacity = options[:capacity] || 64
    @rng_seed = options[:seed] || 1
    @valid_reward = options[:valid_reward] || 1000
    @novel_reward = options[:novel_reward] || 100000
    @improvement_reward = options[:improvement_reward] || 1000000
    @exploration = options[:exploration] || 50000
    if !@capacity.is_a?(Integer) || @capacity < 1
      raise "Metaflip::Search capacity must be a positive Integer"
    if !@rng_seed.is_a?(Integer)
      raise "Metaflip::Search seed must be an Integer"
    @rng_seed = @rng_seed & 9223372036854775807
    @rng_seed = 1 if @rng_seed == 0
    rewards = [@valid_reward, @novel_reward, @improvement_reward, @exploration]
    i = 0
    while i < rewards.size()
      if !rewards[i].is_a?(Integer) || rewards[i] < 0
        raise "Metaflip::Search reward weights must be non-negative Integers"
      i += 1

    @strategies = metaflip_search_copy_values(strategies)
    @verifier = verifier
    @snapshot = snapshot

    @states = []
    @scores = []
    @descriptors = []
    @identities = []
    @uses = []
    @sources = []
    @generations = []

    @best_state = nil
    @best_scores = nil
    @best_descriptor = nil
    @best_identity = nil

    @arm_pulls = []
    @arm_exposure = []
    @arm_valid = []
    @arm_novel = []
    @arm_improvements = []
    i = 0
    while i < @strategies.size()
      @arm_pulls.push(0)
      @arm_exposure.push(0)
      @arm_valid.push(0)
      @arm_novel.push(0)
      @arm_improvements.push(0)
      i += 1

    @iterations = 0
    @proposals = 0
    @proposal_misses = 0
    @exact_checks = 0
    @exact_rejects = 0
    @exact_valid = 0
    @archive_inserts = 0
    @archive_replacements = 0
    @archive_rejects = 0
    @best_improvements = 0

  -> capacity
    @capacity

  -> iterations
    @iterations

  -> archive_size
    @states.size()

  -> directions
    metaflip_search_copy_values(@directions)

  -> best_state
    return nil if @best_state == nil
    @snapshot.call(@best_state)

  -> best_scores
    return nil if @best_scores == nil
    metaflip_search_copy_values(@best_scores)

  -> best_descriptor
    @best_descriptor

  -> best_identity
    @best_identity

  -> __find_descriptor(descriptor)
    i = 0
    while i < @descriptors.size()
      return i if @descriptors[i] == descriptor
      i += 1
    0 - 1

  -> __find_identity(identity)
    return 0 - 1 if identity == nil
    i = 0
    while i < @identities.size()
      return i if @identities[i] != nil && @identities[i] == identity
      i += 1
    0 - 1

  # Prefer evicting the most-used entry; ties evict worse exact quality and
  # then the oldest generation.  The global best is snapshotted separately and
  # remains available to every strategy even if its niche later rotates out.
  -> __victim
    victim = 0
    i = 1
    while i < @states.size()
      choose = false
      if @uses[i] > @uses[victim]
        choose = true
      elsif @uses[i] == @uses[victim]
        comparison = metaflip_search_compare_scores(@scores[i], @scores[victim], @directions)
        if comparison < 0
          choose = true
        elsif comparison == 0 && @generations[i] < @generations[victim]
          choose = true
      if choose
        victim = i
      i += 1
    victim

  -> __write_slot(slot, candidate, assessment, source)
    # `candidate` is already the private snapshot made after exact verification.
    @states[slot] = candidate
    @scores[slot] = metaflip_search_copy_values(assessment.scores)
    @descriptors[slot] = assessment.descriptor
    @identities[slot] = assessment.identity
    @uses[slot] = 0
    @sources[slot] = source
    @generations[slot] = @iterations
    slot

  -> __append(candidate, assessment, source)
    # `candidate` is already the private snapshot made after exact verification.
    @states.push(candidate)
    @scores.push(metaflip_search_copy_values(assessment.scores))
    @descriptors.push(assessment.descriptor)
    @identities.push(assessment.identity)
    @uses.push(0)
    @sources.push(source)
    @generations.push(@iterations)
    @states.size() - 1

  -> __update_best(candidate, assessment)
    improved = false
    if @best_scores == nil || metaflip_search_compare_scores(assessment.scores, @best_scores, @directions) > 0
      @best_state = @snapshot.call(candidate)
      @best_scores = metaflip_search_copy_values(assessment.scores)
      @best_descriptor = assessment.descriptor
      @best_identity = assessment.identity
      @best_improvements += 1
      improved = true
    improved

  # Return [archive_action, novel, improved]. Actions are:
  #   0 exact-valid but dominated/duplicate
  #   1 appended new niche
  #   2 replaced the incumbent in the same niche
  #   3 evicted an old niche for a new one
  -> __admit_exact(candidate, assessment, source)
    identity_slot = __find_identity(assessment.identity)
    if identity_slot >= 0
      # Identity is an exact, stable fingerprint: rediscovering it cannot be a
      # new niche or a new mathematical result.  Reject even if a stateful
      # verifier reports different scores, rather than letting inconsistent
      # metadata create duplicate descriptors.
      @archive_rejects += 1
      return [0, 0, 0]

    descriptor_slot = __find_descriptor(assessment.descriptor)
    if descriptor_slot >= 0
      if metaflip_search_compare_scores(assessment.scores, @scores[descriptor_slot], @directions) <= 0
        @archive_rejects += 1
        return [0, 0, 0]
      __write_slot(descriptor_slot, candidate, assessment, source)
      @archive_replacements += 1
      improved = __update_best(candidate, assessment)
      return [2, 0, improved ? 1 : 0]

    if @states.size() < @capacity
      __append(candidate, assessment, source)
      @archive_inserts += 1
      improved = __update_best(candidate, assessment)
      return [1, 1, improved ? 1 : 0]

    victim = __victim()
    __write_slot(victim, candidate, assessment, source)
    @archive_replacements += 1
    improved = __update_best(candidate, assessment)
    [3, 1, improved ? 1 : 0]

  -> __assessment_valid(assessment)
    if assessment == nil || !assessment.is_a?(Metaflip:Assessment)
      return false
    if assessment.descriptor == nil
      return false
    metaflip_search_scores_valid(assessment.scores, @directions) == 1

  -> __verify_and_admit(candidate, source)
    @exact_checks += 1
    assessment = @verifier.call(candidate)
    if !__assessment_valid(assessment)
      @exact_rejects += 1
      return [0, 0, 0]
    stored = @snapshot.call(candidate)
    if stored == nil
      @exact_rejects += 1
      return [0, 0, 0]
    @exact_valid += 1
    __admit_exact(stored, assessment, source)

  # Exact-gate and archive an externally supplied seed.  It does not charge a
  # strategy arm.  Return true only when the seed enters the bounded archive.
  -> seed(candidate)
    result = __verify_and_admit(candidate, 0 - 1)
    result[0] > 0

  -> __select_parent
    return nil if @states.size() == 0
    start = @iterations % @states.size()
    selected = start
    offset = 1
    while offset < @states.size()
      index = (start + offset) % @states.size()
      if @uses[index] < @uses[selected]
        selected = index
      offset += 1
    @uses[selected] += 1
    @snapshot.call(@states[selected])

  -> __select_arm
    count = @strategies.size()
    offset = 0
    while offset < count
      arm = (@iterations + offset) % count
      return arm if @arm_pulls[arm] == 0
      offset += 1
    best = 0
    best_score = 0 - 9223372036854775807
    arm = 0
    while arm < count
      exposure = @arm_exposure[arm]
      exposure = 1 if exposure < 1
      utility = @arm_improvements[arm] * @improvement_reward
      utility += @arm_novel[arm] * @novel_reward
      utility += @arm_valid[arm] * @valid_reward
      score = utility / exposure + @exploration / (@arm_pulls[arm] + 1)
      if score > best_score
        best = arm
        best_score = score
      arm += 1
    best

  -> __record_arm(arm, cost, valid, novel, improved)
    @arm_pulls[arm] += 1
    @arm_exposure[arm] += cost
    @arm_valid[arm] += valid
    @arm_novel[arm] += novel
    @arm_improvements[arm] += improved

  # Run one adaptive proposal.  The returned event is telemetry only; all
  # trusted state is retained behind the exact gate.
  -> step
    arm = __select_arm()
    parent = __select_parent()
    best = nil
    best = @snapshot.call(@best_state) if @best_state != nil
    @rng_seed = metaflip_search_next_seed(@rng_seed)
    request = Metaflip:Request.new(parent, best, @iterations, @rng_seed, arm)
    @iterations += 1

    emitted = @strategies[arm].call(request)
    valid_emission = emitted != nil
    valid_emission = false if valid_emission && !emitted.is_a?(Metaflip:Proposal) && !emitted.is_a?(Metaflip:ProposalBatch)
    if !valid_emission
      @proposal_misses += 1
      __record_arm(arm, 1, 0, 0, 0)
      return {status: :no_proposal, arm: arm, archive_action: 0, improved: false}

    proposals = [emitted]
    proposals = emitted.proposals if emitted.is_a?(Metaflip:ProposalBatch)
    total_cost = 0
    valid = 0
    novel = 0
    improved = 0
    rewarded_novel = 0
    rewarded_improvement = 0
    archive_action = 0
    i = 0
    while i < proposals.size()
      proposal = proposals[i]
      @proposals += 1
      total_cost += proposal.cost
      valid_before = @exact_valid
      candidate_had_best = @best_state != nil
      result = __verify_and_admit(proposal.candidate, arm)
      # Dominated exact candidates still deserve the small valid reward. Use a
      # per-candidate counter delta so every verifier call is counted once.
      valid += 1 if @exact_valid > valid_before
      novel += result[1]
      improved += result[2]
      archive_action = result[0] if result[0] > archive_action
      # The first exact-valid candidate establishes the comparison baseline.
      # It is not evidence that its arm improves incumbents or discovers a
      # meaningful niche. Later members of the same batch may earn both.
      if candidate_had_best
        rewarded_novel += result[1]
        rewarded_improvement += result[2]
      i += 1
    __record_arm(arm, total_cost, valid, rewarded_novel, rewarded_improvement)
    {status: valid > 0 ? :exact_valid : :exact_reject, arm: arm,
      archive_action: archive_action, novel: novel > 0, improved: improved > 0}

  -> run(steps)
    if !steps.is_a?(Integer) || steps < 0
      raise "Metaflip::Search run steps must be a non-negative Integer"
    i = 0
    while i < steps
      step()
      i += 1
    best_state()

  -> archive
    out = []
    i = 0
    while i < @states.size()
      out.push({state: @snapshot.call(@states[i]),
        scores: metaflip_search_copy_values(@scores[i]),
        descriptor: @descriptors[i], identity: @identities[i], uses: @uses[i],
        source: @sources[i], generation: @generations[i]})
      i += 1
    out

  -> arm_stats
    out = []
    i = 0
    while i < @strategies.size()
      out.push({arm: i, pulls: @arm_pulls[i], exposure: @arm_exposure[i],
        exact_valid: @arm_valid[i], novel: @arm_novel[i],
        improvements: @arm_improvements[i]})
      i += 1
    out

  -> stats
    {iterations: @iterations, proposals: @proposals,
      proposal_misses: @proposal_misses, exact_checks: @exact_checks,
      exact_rejects: @exact_rejects, exact_valid: @exact_valid,
      archive_size: @states.size(), archive_inserts: @archive_inserts,
      archive_replacements: @archive_replacements,
      archive_rejects: @archive_rejects, best_improvements: @best_improvements}
