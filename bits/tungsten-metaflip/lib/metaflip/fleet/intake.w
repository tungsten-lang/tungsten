# Deterministic coordinator intake for wide CPU fleets.
#
# Exact verification, structural identity, MAP admission, archive admission,
# and symmetry classification are deliberately coordinator-owned.  Running
# that full pipeline for every island is inexpensive in the canonical fleet,
# but serializes hundreds of otherwise independent workers on large hosts.
# Wide fleets therefore inspect one rotating canonical-width window per round.
# A candidate that can improve fleet rank or same-rank density always bypasses
# the window and is inspected immediately.

use ../strategies/delta_components

-> ffci_canonical_intake_width() i64
  12

-> ffci_wide_fleet_threshold() i64
  32

-> ffci_round_budget(walkers) (i64) i64
  if walkers < 1
    return 0
  if walkers <= ffci_wide_fleet_threshold()
    return walkers
  ffci_canonical_intake_width()

-> ffci_candidate_better(rank, bits, fleet_rank, fleet_bits) (i64 i64 i64 i64) i64
  if rank < fleet_rank
    return 1
  if rank == fleet_rank && bits < fleet_bits
    return 1
  0

-> ffci_rotating_slot(slot, walkers, round) (i64 i64 i64) i64
  if walkers < 1 || slot < 0 || slot >= walkers
    return 0
  budget = ffci_round_budget(walkers) ## i64
  if budget >= walkers
    return 1
  start = (round * budget) % walkers ## i64
  if start < 0
    start += walkers
  distance = slot - start ## i64
  if distance < 0
    distance += walkers
  if distance < budget
    return 1
  0

-> ffci_should_intake(changed, slot, walkers, round, rank, bits, fleet_rank, fleet_bits) (i64 i64 i64 i64 i64 i64 i64 i64) i64
  if changed == 0
    return 0
  if ffci_candidate_better(rank, bits, fleet_rank, fleet_bits) == 1
    return 1
  ffci_rotating_slot(slot, walkers, round)

-> ffci_component_difference_bound() i64
  64

# Cold-path postprocessor for a same-rank density improvement.  The ordinary
# worker hot path pays only the rank/density branch.  A qualifying candidate
# is independently combined with the incumbent through support-component
# peeling and is replaced only when the exact hybrid is strictly better.
-> ffci_try_component_peel(incumbent, candidate, n, capacity, seed, dslack, cycles, workq, wanderq, meta) (i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  incumbent_rank = ffw_best_rank(incumbent) ## i64
  candidate_rank = ffw_best_rank(candidate) ## i64
  if incumbent_rank != candidate_rank
    return 0
  incumbent_bits = ffw_best_bits(incumbent) ## i64
  candidate_bits = ffw_best_bits(candidate) ## i64
  if candidate_bits >= incumbent_bits
    return 0
  peeled = i64[ffw_state_size(capacity)]
  rank = ffdc_crossover_best_states(incumbent, candidate, n, ffci_component_difference_bound(), peeled, capacity, seed, dslack, cycles, workq, wanderq, meta) ## i64
  if rank < 1
    return 0
  if ffci_candidate_better(rank, ffw_best_bits(peeled), candidate_rank, candidate_bits) == 0
    return 0
  original = i64[ffw_state_size(capacity)]
  saved = ffw_reseed_from(original, candidate, seed + 99991) ## i64
  if saved != candidate_rank || ffw_verify_best_exact(original, n) != 1
    return 0
  loaded = ffw_reseed_from(candidate, peeled, seed + 100003) ## i64
  if loaded != rank || ffw_verify_best_exact(candidate, n) != 1
    restored = ffw_reseed_from(candidate, original, seed + 100019) ## i64
    if restored == candidate_rank
      z = ffw_verify_best_exact(candidate, n) ## i64
    return 0
  rank
