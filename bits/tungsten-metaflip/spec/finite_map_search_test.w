# Focused non-tensor adapter regression: exact rational-map fibres over F_17.

use ../lib/metaflip

-> finite_map_expect(label, condition) (String bool) i64
  if !condition
    << "FINITE_MAP_FAIL " + label
    exit(1)
  1

points = []
i = 0
while i < 17
  points.push(i)
  i += 1

domain = Metaflip:FiniteMapDomain.new(points, 17, 2, 3, 2)
inverses = metaflip_prime_batch_inverses([2, 3, 4], 17)
finite_map_expect("batch inversion", inverses[0] * 2 % 17 == 1 &&
  inverses[1] * 3 % 17 == 1 && inverses[2] * 4 % 17 == 1)

# x^2 has one singleton fibre at zero and eight exact two-point fibres on F_17.
square = Metaflip:PrimeRationalMap.new([0, 0, 1], [1])
profile = domain.profile(square)
finite_map_expect("square profile", profile[:poles] == 0 && profile[:exact_fibres] == 8 &&
  profile[:covered] == 16 && profile[:max_fibre] == 2)
assessment = domain.assess(square)
finite_map_expect("square exact assessment", assessment != nil && assessment.scores[0] == 16)
finite_map_expect("near-cover is not total target cover", !domain.goal?(square))

# Scalar-equivalent presentations share a stable exact identity.
scaled_square = Metaflip:PrimeRationalMap.new([0, 0, 2], [2])
finite_map_expect("scalar identity", domain.identity(square) == domain.identity(scaled_square))

# Metric-equal maps can occupy different optional identity bins, retaining
# multiple basins for parent-first local flips without changing exact scores.
diverse_domain = Metaflip:FiniteMapDomain.new(points, 17, 2, 3, 2,
  {diversity_bins: 17})
shifted_square = Metaflip:PrimeRationalMap.new([1, 0, 1], [1])
finite_map_expect("identity diversity bins", diverse_domain.profile(square)[:covered] ==
  diverse_domain.profile(shifted_square)[:covered] &&
  diverse_domain.assess(square).descriptor != diverse_domain.assess(shifted_square).descriptor)

# Denominator x has a pole at zero and is rejected by the default total-map
# verifier, while a pole-aware domain retains its exact profile.
pole = Metaflip:PrimeRationalMap.new([1], [0, 1])
finite_map_expect("total map rejects pole", domain.assess(pole) == nil)
pole_domain = Metaflip:FiniteMapDomain.new(points, 17, 2, 3, 2, {allow_poles: true})
finite_map_expect("pole-aware profile", pole_domain.assess(pole) != nil &&
  pole_domain.profile(pole)[:poles] == 1)

# Exercise the documented signed-i64 field bound with a large prime: +1 and
# -1 collide under x^2 without overflowing Horner multiplication.
large_prime = 2147483647
large_domain = Metaflip:FiniteMapDomain.new([0, 1, large_prime - 1],
  large_prime, 2, 3, 1)
large_profile = large_domain.profile(square)
finite_map_expect("large-prime exact arithmetic", large_profile[:covered] == 2 &&
  large_profile[:max_fibre] == 2)

# Locator proposals start on the useful collision manifold. A cubic locator
# forces three sampled points into one exact three-fibre; its root-preserving
# flip changes one point while keeping an exact three-fibre.
triple_domain = Metaflip:FiniteMapDomain.new(points, 17, 3, 4, 1)
locator_coefficients = metaflip_prime_locator_polynomial([2, 5, 9], 17)
finite_map_expect("locator coefficients", locator_coefficients == [12, 5, 1, 1])
locator = triple_domain.locator_candidate([2, 5, 9])
finite_map_expect("locator roots", locator != nil &&
  metaflip_prime_polynomial_eval(locator.numerator, 2, 17) == 0 &&
  metaflip_prime_polynomial_eval(locator.numerator, 5, 17) == 0 &&
  metaflip_prime_polynomial_eval(locator.numerator, 9, 17) == 0)
locator_profile = triple_domain.profile(locator)
finite_map_expect("locator guarantees target fibre", locator_profile[:covered] >= 3 &&
  locator_profile[:max_fibre] >= 3)
locator_proposal = triple_domain.locator_seed(733)
finite_map_expect("locator seed proposal", locator_proposal != nil &&
  triple_domain.profile(locator_proposal.candidate)[:covered] >= 3)
locator_request = Metaflip:Request.new(locator_proposal.candidate,
  locator_proposal.candidate, 0, 739, 0)
flipped_locator = triple_domain.locator_flip(locator_request)
finite_map_expect("locator flip preserves target fibre", flipped_locator != nil &&
  triple_domain.profile(flipped_locator.candidate)[:covered] >= 3)

pair_domain = Metaflip:FiniteMapDomain.new(points, 17, 3, 4, 4)
locator_pair = pair_domain.locator_pair_candidate([0, 1, 2], [3, 4, 7])
pair_profile = pair_domain.profile(locator_pair)
finite_map_expect("paired locator has two finite target fibres", pair_profile[:poles] == 0 &&
  pair_profile[:exact_fibres] >= 2 && pair_profile[:covered] >= 6)
pair_request = Metaflip:Request.new(locator_pair, locator_pair, 0, 743, 0)
flipped_pair = pair_domain.locator_pair_flip(pair_request)
finite_map_expect("paired locator flip preserves two fibres", flipped_pair != nil &&
  pair_domain.profile(flipped_pair.candidate)[:covered] >= 6)

batch_pair_domain = Metaflip:FiniteMapDomain.new(points, 17, 3, 4, 4,
  {diversity_bins: 8, locator_batch: 4})
batch_pair = batch_pair_domain.locator_pair_flip_batch(pair_request)
finite_map_expect("paired locator neighborhood", batch_pair != nil &&
  batch_pair.is_a?(Metaflip:ProposalBatch) && batch_pair.proposals.size() == 4)

search = domain.search({capacity: 8, seed: 717})
finite_map_expect("finite-map seed", search.seed(square))
finite_map_expect("equivalent seed deduplicates", !search.seed(scaled_square))
search.run(16)
finite_map_expect("default mutation smoke", search.stats[:exact_checks] == 18 &&
  search.archive_size > 0 && search.best_scores != nil)

unseeded = domain.search({capacity: 4, seed: 719})
unseeded.run(4)
finite_map_expect("unseeded total-map search starts valid", unseeded.stats[:exact_valid] > 0)

<< "finite_map_search_test: all checks passed"
