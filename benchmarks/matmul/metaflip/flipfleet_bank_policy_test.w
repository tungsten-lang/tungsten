use metaflip_worker
use flipfleet_escape
use flipfleet_bank_policy

failures = 0 ## i64

-> ffbpt_check(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    return 1
  0

-> ffbpt_escape(base, kind, nonce, n, capacity, state_size)
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_best(base, us, vs, ws) ## i64
  meta = i64[8]
  escaped = ffe_apply(us, vs, ws, rank, capacity, n, kind, nonce, meta) ## i64
  if escaped < 1 || meta[7] != 1
    return nil
  state = i64[state_size]
  loaded = ffw_init_terms_cap(state, us, vs, ws, escaped, n, capacity, 1000 + kind * 31 + nonce, 4, 4, 10000, 2000) ## i64
  if loaded != escaped
    return nil
  state

n = 3 ## i64
capacity = 96 ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
rank = ffw_init_naive_cap(base, n, capacity, 17, 4, 4, 10000, 2000) ## i64
failures += ffbpt_check("naive exact", rank == 27 && ffw_verify_best_exact(base, n) == 1)

split0 = ffbpt_escape(base, 1, 0, n, capacity, state_size)
split1 = ffbpt_escape(base, 1, 1, n, capacity, state_size)
split2 = ffbpt_escape(base, 1, 2, n, capacity, state_size)
compose = ffbpt_escape(base, 5, 0, n, capacity, state_size)
failures += ffbpt_check("escape states", split0 != nil && split1 != nil && split2 != nil && compose != nil)

bank = []
signatures = []
uses = []
successes = []
near_counters = i64[5]
z = ffbp_near_add(bank, signatures, uses, successes, split0, 4, 1, 1, near_counters) ## i64
z = ffbp_near_add(bank, signatures, uses, successes, split1, 4, 1, 1, near_counters)
z = ffbp_near_add(bank, signatures, uses, successes, split2, 4, 1, 1, near_counters)
failures += ffbpt_check("near bounded", bank.size() >= 1 && bank.size() <= 4)
failures += ffbpt_check("near metadata aligned", bank.size() == signatures.size() && bank.size() == uses.size() && bank.size() == successes.size())
first = ffbp_select_least_used(bank, uses, 0) ## i64
second = ffbp_select_least_used(bank, uses, 1) ## i64
failures += ffbpt_check("least-used replay", first >= 0 && second >= 0)
marked = ffbp_mark_success(bank, successes, bank[first]) ## i64
failures += ffbpt_check("near success attribution", marked == 1 && successes[first] == 1)

pareto_states = []
pareto_ranks = []
pareto_bits = []
pareto_pairs = []
pareto_novelties = []
pareto_roles = []
pareto_uses = []
pareto_counters = i64[4]
admitted0 = ffbp_pareto_add(pareto_states, pareto_ranks, pareto_bits, pareto_pairs, pareto_novelties, pareto_roles, pareto_uses, split1, split0, 4, 3, pareto_counters) ## i64
admitted1 = ffbp_pareto_add(pareto_states, pareto_ranks, pareto_bits, pareto_pairs, pareto_novelties, pareto_roles, pareto_uses, split2, split0, 4, 8, pareto_counters) ## i64
rejected_rank = ffbp_pareto_add(pareto_states, pareto_ranks, pareto_bits, pareto_pairs, pareto_novelties, pareto_roles, pareto_uses, compose, split0, 4, 7, pareto_counters) ## i64
failures += ffbpt_check("pareto first admitted", admitted0 == 1)
failures += ffbpt_check("pareto aligned", pareto_states.size() == pareto_bits.size() && pareto_states.size() == pareto_pairs.size() && pareto_states.size() == pareto_novelties.size() && pareto_states.size() == pareto_uses.size())
failures += ffbpt_check("pareto rejects worse rank", rejected_rank == 0)
novel = ffbp_pareto_select(pareto_states, pareto_bits, pareto_pairs, pareto_novelties, pareto_uses, 5) ## i64
failures += ffbpt_check("pareto novelty replay", novel >= 0)
failures += ffbpt_check("connectivity metric", ffbp_flip_pairs(split0) >= 0)

if failures > 0
  << "flipfleet_bank_policy_test: " + failures.to_s() + " failure(s)"
  exit(1)
<< "flipfleet_bank_policy_test: all native checks passed"
