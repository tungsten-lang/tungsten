# Historical-gain validation for the domain-neutral search coordinator.
#
# This benchmark intentionally lives outside `lib/metaflip`: the coordinator
# knows nothing about proximity proofs.  The adapter below reduces the exact
# arithmetic ledger used by Proximity Prize's OrbitPencil construction to a
# small integer state [kind, log2(fibre size), selected fibres, coefficient
# keys].  A kind-zero state is the previously verified PrescribedTop result.
# Kind-one states are admitted only after all construction inequalities pass.
#
# The benchmark asks whether the generic archive/portfolio can rediscover the
# historical 512/272/14 improvement from the older 139502-agreement seed.  A
# matched control receives the same number of exact checks but only uniformly
# samples row-saturating orbit parameters.

use ../lib/metaflip

PP_DOMAIN_SIZE = 262144
PP_ROW_DEGREE_LIMIT = 131071
PP_BASE_FIELD_SIZE = 2130706433
PP_EXTENSION_FIELD_SIZE = PP_BASE_FIELD_SIZE ** 6
PP_REQUIRED_CHALLENGES = PP_EXTENSION_FIELD_SIZE / (2 ** 128) + 1
PP_OLD_AGREEMENT = 139502
PP_TARGET_AGREEMENT = 139775

-> pp_choose(n, k)
  return 0 if k < 0 || k > n
  kk = k
  kk = n - k if n - k < kk
  value = 1 ## BigInt
  i = 1
  while i <= kk
    value = value * (n - kk + i) / i
    i += 1
  value

# Precompute the bounded grammar with exact recurrences.  This remains the
# verifier's trusted arithmetic: caching only avoids rebuilding the same
# binomial and field powers across matched trials.
-> pp_build_orbit_assessments()
  assessments = {}
  log_fibre = 7
  while log_fibre <= 11
    fibre = 2 ** log_fibre
    labels = PP_DOMAIN_SIZE / fibre
    selected = (PP_ROW_DEGREE_LIMIT + 1) / fibre + 2
    candidates = pp_choose(labels - 1, selected)
    field_power = 1 ## BigInt
    keys = 0
    while keys < 256
      identity = log_fibre.to_s() + ":" + selected.to_s() + ":" + keys.to_s()
      assessment = false
      if selected < labels
        quotient_degree = selected - keys - 3
        row_degree = fibre - 1 + quotient_degree * fibre
        key_space = field_power * labels
        excluded = PP_REQUIRED_CHALLENGES * PP_REQUIRED_CHALLENGES * selected + labels + 1
        degree_ok = quotient_degree >= 0 && row_degree <= PP_ROW_DEGREE_LIMIT
        count_ok = candidates > key_space * PP_REQUIRED_CHALLENGES
        alpha_ok = excluded < PP_EXTENSION_FIELD_SIZE
        if degree_ok && count_ok && alpha_ok
          agreement = fibre * (selected + 1) - 1
          descriptor = "fold-" + fibre.to_s()
          assessment = Metaflip:Assessment.new([agreement, keys], descriptor, identity)
        next_selected = selected + 1
        candidates = candidates * (labels - 1 - selected) / next_selected
      assessments[identity] = assessment
      field_power *= PP_BASE_FIELD_SIZE
      selected += 1
      keys += 1
    log_fibre += 1
  assessments

PP_ORBIT_ASSESSMENTS = pp_build_orbit_assessments()

-> pp_copy(candidate)
  return nil if candidate == nil || !candidate.is_a?(Array)
  metaflip_search_copy_values(candidate)

-> pp_orbit_candidate(log_fibre, keys)
  return [1, log_fibre, 0, keys] if log_fibre < 1 || log_fibre > 17
  fibre = 2 ** log_fibre
  # Every proposed orbit state sits on the row-degree boundary.  This is a
  # reusable structural operator, not a trusted shortcut: the exact verifier
  # table above independently checks the boundary and every counting gate.
  selected = (PP_ROW_DEGREE_LIMIT + 1) / fibre + keys + 2
  [1, log_fibre, selected, keys]

-> pp_assess(candidate)
  return nil if candidate == nil || !candidate.is_a?(Array)

  # Exact historical seed: unsafe index 122642, agreement 139502.
  if candidate.size() == 1 && candidate[0] == 0
    return Metaflip:Assessment.new([PP_OLD_AGREEMENT, 8430], "prescribed-top", "baseline-122642")

  return nil if candidate.size() != 4 || candidate[0] != 1
  log_fibre = candidate[1]
  selected = candidate[2]
  keys = candidate[3]
  return nil if !log_fibre.is_a?(Integer) || !selected.is_a?(Integer) || !keys.is_a?(Integer)
  return nil if log_fibre < 7 || log_fibre > 11 || keys < 0
  identity = log_fibre.to_s() + ":" + selected.to_s() + ":" + keys.to_s()
  assessment = PP_ORBIT_ASSESSMENTS[identity]
  return nil if assessment == nil || assessment == false
  assessment

-> pp_boundary_from_seed(seed)
  state = metaflip_search_next_seed(seed)
  log_fibre = 7 + state % 5
  state = metaflip_search_next_seed(state)
  keys = state % 256
  pp_orbit_candidate(log_fibre, keys)

-> pp_random_arm(request)
  Metaflip:Proposal.new(pp_boundary_from_seed(request.seed), 1)

-> pp_local_key_arm(request)
  parent = request.parent
  parent = request.best if parent == nil
  if parent == nil || parent.size() != 4 || parent[0] != 1
    return Metaflip:Proposal.new(pp_boundary_from_seed(request.seed), 1)
  delta = 1
  delta = 0 - 1 if (request.seed & 1) == 0
  Metaflip:Proposal.new(pp_orbit_candidate(parent[1], parent[3] + delta), 1)

-> pp_fold_arm(request)
  parent = request.best
  if parent == nil || parent.size() != 4 || parent[0] != 1
    return Metaflip:Proposal.new(pp_boundary_from_seed(request.seed), 1)
  delta = 1
  delta = 0 - 1 if (request.seed & 1) == 0
  log_fibre = parent[1] + delta
  log_fibre = 7 if log_fibre > 11
  log_fibre = 11 if log_fibre < 7
  # Preserve the parent's key density approximately across adjacent folds.
  keys = parent[3]
  keys = keys * 2 + 1 if delta < 0
  keys = keys / 2 if delta > 0
  Metaflip:Proposal.new(pp_orbit_candidate(log_fibre, keys), 1)

-> pp_sweep_arm(request)
  # Coverage arm: visits every (fold, key) boundary point once per 1280 pulls.
  offset = request.seed % 1280
  index = (request.generation + offset) % 1280
  Metaflip:Proposal.new(pp_orbit_candidate(7 + index % 5, index / 5), 1)

-> pp_new_search(strategies, seed)
  verifier = -> (candidate) pp_assess(candidate)
  snapshot = -> (candidate) pp_copy(candidate)
  Metaflip:Search.new(strategies, verifier, snapshot, [1, 0 - 1],
    {capacity: 6, seed: seed, valid_reward: 1000, novel_reward: 100000,
      improvement_reward: 1000000, exploration: 50000})

-> pp_ground_truth()
  best = [0]
  best_assessment = pp_assess(best)
  log_fibre = 7
  while log_fibre <= 11
    keys = 0
    while keys < 256
      candidate = pp_orbit_candidate(log_fibre, keys)
      assessment = pp_assess(candidate)
      if assessment != nil && metaflip_search_compare_scores(
          assessment.scores, best_assessment.scores, [1, 0 - 1]) > 0
        best = candidate
        best_assessment = assessment
      keys += 1
    log_fibre += 1
  [best, best_assessment.scores]

ground = pp_ground_truth()
if ground[0] != [1, 9, 272, 14] || ground[1][0] != PP_TARGET_AGREEMENT
  << "PROXIMITY_GAIN_FAIL ground truth " + ground.to_s()
  exit(1)

# These are the exact viable/failing pair recorded by the later upstream
# 1024-fold obstruction: five keys with 135 fibres works but is weaker, while
# the score-improving 136-fibre point needs six keys and fails pigeonholing.
fold1024_viable = pp_assess([1, 10, 135, 5])
if fold1024_viable == nil || fold1024_viable.scores[0] != 139263
  << "PROXIMITY_GAIN_FAIL 1024-fold viable control"
  exit(1)
if pp_assess([1, 10, 136, 6]) != nil
  << "PROXIMITY_GAIN_FAIL 1024-fold barrier"
  exit(1)

trials = 64
steps = 384
adaptive_hits = 0
random_hits = 0
adaptive_gain_hits = 0
random_gain_hits = 0
adaptive_checks = 0
random_checks = 0
trial = 0
while trial < trials
  seed = 880301 + trial * 7919

  adaptive = pp_new_search([-> (r) pp_local_key_arm(r), -> (r) pp_fold_arm(r),
    -> (r) pp_random_arm(r), -> (r) pp_sweep_arm(r)], seed)
  adaptive.seed([0])
  adaptive.run(steps)
  adaptive_best = adaptive.best_scores[0]
  adaptive_hits += 1 if adaptive_best == PP_TARGET_AGREEMENT
  adaptive_gain_hits += 1 if adaptive_best > PP_OLD_AGREEMENT
  adaptive_checks += adaptive.stats[:exact_checks]

  control = pp_new_search([-> (r) pp_random_arm(r)], seed)
  control.seed([0])
  control.run(steps)
  control_best = control.best_scores[0]
  random_hits += 1 if control_best == PP_TARGET_AGREEMENT
  random_gain_hits += 1 if control_best > PP_OLD_AGREEMENT
  random_checks += control.stats[:exact_checks]

  trial += 1

ground_line = "proximity_orbit_gain_bench ground=" + ground[0].to_s()
ground_line += " agreement=" + ground[1][0].to_s()
<< ground_line
adaptive_line = "adaptive target_hits=" + adaptive_hits.to_s() + "/" + trials.to_s()
adaptive_line += " gain_hits=" + adaptive_gain_hits.to_s() + "/" + trials.to_s()
adaptive_line += " exact_checks=" + adaptive_checks.to_s()
<< adaptive_line
random_line = "random target_hits=" + random_hits.to_s() + "/" + trials.to_s()
random_line += " gain_hits=" + random_gain_hits.to_s() + "/" + trials.to_s()
random_line += " exact_checks=" + random_checks.to_s()
<< random_line

if adaptive_hits < random_hits || adaptive_gain_hits != trials || adaptive_checks != random_checks
  << "PROXIMITY_GAIN_FAIL matched rediscovery"
  exit(1)

<< "proximity_orbit_gain_bench: validation passed"
