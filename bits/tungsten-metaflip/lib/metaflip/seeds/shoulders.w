# File-backed cross-field shoulder inventory for pure-Tungsten Metaflip.
#
# Loading happens only at coordinator boundaries.  Every certificate crosses
# the ordinary parser and complete tensor gate before it can enter a best+1 or
# best+2 bank; the declared delta prevents stale inventory from being
# mislabeled after the frontier changes.

use ../scheme
use ../fleet/banks
use catalog

-> ffps_add_profile_near_seeds(root, best, n, capacity, state_size, dslack, cycles, workq, wanderq, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, signature_quota, counters)
  admitted = 0 ## i64
  delta = 1 ## i64
  while delta <= 2
    paths = ffp_near_seed_paths(n, delta)
    i = 0 ## i64
    while i < paths.size()
      candidate = i64[state_size]
      path = root + "/" + paths[i]
      rank = ffw_load_scheme_cap(candidate, path, n, capacity, 38501 + delta * 101 + i * 17, dslack, cycles, workq, wanderq) ## i64
      if rank == ffw_best_rank(best) + delta
        if ffw_verify_best_exact(candidate, n) == 1
          if delta == 1
            admitted += ffbp_near_add(near1, near1_signatures, near1_uses, near1_successes, candidate, near1_capacity, signature_quota, 4, counters)
          if delta == 2
            admitted += ffbp_near_add(near2, near2_signatures, near2_uses, near2_successes, candidate, near2_capacity, signature_quota, 4, counters)
      i += 1
    delta += 1
  admitted
