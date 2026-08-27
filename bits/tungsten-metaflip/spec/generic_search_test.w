# Focused regression for the public domain-neutral exact-search coordinator.

use ../lib/metaflip

-> generic_search_expect(label, condition) (String bool) i64
  if !condition
    << "GENERIC_SEARCH_FAIL " + label
    exit(1)
  1

directions = [1, 0 - 1]
generic_search_expect("maximize primary", metaflip_search_compare_scores([4, 9], [3, 0], directions) == 1)
generic_search_expect("minimize secondary", metaflip_search_compare_scores([4, 2], [4, 9], directions) == 1)
generic_search_expect("equal scores", metaflip_search_compare_scores([4, 2], [4, 2], directions) == 0)

snapshot = -> (state) [state[0], state[1]]

# Exact domain contract for this toy non-tensor search: non-negative integer
# pairs only.  Primary score is maximized, secondary score minimized, and x%3
# supplies the bounded archive niche.
verifier = -> (state)
  result = nil
  if state != nil && state.is_a?(Array) && state.size() == 2
    if state[0].is_a?(Integer) && state[1].is_a?(Integer) && state[0] >= 0 && state[1] >= 0
      result = Metaflip:Assessment.new([state[0], state[1]], state[0] % 3,
        state[0] * 100000 + state[1])
  result

# Arm zero emits attractive but invalid candidates.  They must neither enter
# the archive nor earn reward.  Arm one advances from the exact global best.
invalid_arm = -> (request)
  x = 1000
  x = request.best[0] + 1000 if request.best != nil
  Metaflip:Proposal.new([x, 0 - 1], 1)

progress_arm = -> (request)
  x = 0
  x = request.best[0] if request.best != nil
  Metaflip:Proposal.new([x + 1, (x + 1) % 2], 1)

search = Metaflip:Search.new([invalid_arm, progress_arm], verifier, snapshot,
  directions, {capacity: 3, seed: 71017})

seed = [0, 7]
generic_search_expect("exact seed admitted", search.seed(seed))
seed[0] = 9999
generic_search_expect("seed snapshotted", search.best_scores[0] == 0)

search.run(12)
best = search.best_state
generic_search_expect("invalid proxy cannot win", best[0] > 0 && best[0] < 1000 && best[1] >= 0)
generic_search_expect("bounded niches", search.archive_size == 3)

stats = search.stats
generic_search_expect("exact rejections counted", stats[:exact_rejects] > 0)
generic_search_expect("exact progress counted", stats[:best_improvements] > 1)
generic_search_expect("one exact check per proposal plus seed",
  stats[:exact_checks] == stats[:proposals] + 1)

arms = search.arm_stats
generic_search_expect("invalid arm has no exact reward", arms[0][:exact_valid] == 0)
generic_search_expect("productive arm rewarded", arms[1][:exact_valid] > 0 && arms[1][:improvements] > 0)

archive = search.archive
archive[0][:state][0] = 424242
generic_search_expect("archive introspection is snapshotted", search.archive[0][:state][0] != 424242)

# Direct admissions exercise same-niche improvement and stable-identity
# deduplication independently of the adaptive schedule.
manual = Metaflip:Search.new([progress_arm], verifier, snapshot, directions,
  {capacity: 2, seed: 71019})
generic_search_expect("manual first niche", manual.seed([1, 9]))
generic_search_expect("same niche improves", manual.seed([4, 8]) && manual.archive_size == 1)
generic_search_expect("stable identity deduplicates", !manual.seed([4, 8]) && manual.archive_size == 1)
generic_search_expect("second niche appends", manual.seed([5, 7]) && manual.archive_size == 2)

# An unseeded search must not credit whichever arm happens to establish the
# first exact baseline as an incumbent improvement. Later strict gains count.
cold = Metaflip:Search.new([progress_arm], verifier, snapshot, directions,
  {capacity: 2, seed: 71023})
cold.run(1)
generic_search_expect("first unseeded candidate is not arm improvement",
  cold.best_scores[0] == 1 && cold.arm_stats[0][:improvements] == 0 &&
    cold.arm_stats[0][:novel] == 0 && cold.stats[:best_improvements] == 1)
cold.run(1)
generic_search_expect("later unseeded gain rewards arm",
  cold.best_scores[0] == 2 && cold.arm_stats[0][:improvements] == 1)

# Neighborhood-producing strategies remain exact-gated candidate by
# candidate. Invalid members cannot win; later valid members in the same batch
# may improve the baseline and all exposure is attributed to one arm pull.
batch_arm = -> (request)
  Metaflip:ProposalBatch.new([
    Metaflip:Proposal.new([3, 3], 2),
    Metaflip:Proposal.new([900, 0 - 1], 3),
    Metaflip:Proposal.new([6, 1], 5)])
batched = Metaflip:Search.new([batch_arm], verifier, snapshot, directions,
  {capacity: 3, seed: 71027})
batch_event = batched.step()
generic_search_expect("batch exact gate", batched.best_scores == [6, 1] &&
  batched.stats[:proposals] == 3 && batched.stats[:exact_checks] == 3 &&
  batched.stats[:exact_rejects] == 1)
generic_search_expect("batch exposure accounting", batched.arm_stats[0][:pulls] == 1 &&
  batched.arm_stats[0][:exposure] == 10 && batched.arm_stats[0][:exact_valid] == 2 &&
  batched.arm_stats[0][:improvements] == 1 && batch_event[:improved])

<< "generic_search_test: all checks passed"
