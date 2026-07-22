use ../lib/metaflip/fleet/cpu_experiments

-> four_split_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL four-split arm " + label
    exit(1)
  1

# Seed 37 deliberately initializes the ordinary walk band at two.  The
# four-split arm must widen that arm-local band before opening its promised
# exact +4 shoulder.
n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
rank = ffw_init_naive_cap(state, n, capacity, 37, 6, 4, 1000, 250) ## i64
source_rank = ffw_current_rank(state) ## i64
four_split_expect("fixture starts in band two", rank == 27 && source_rank == 27 && state[10] == 2)

controls = i64[7]
setup = i64[7]
arm = ffcr_apply_arm_measured(state, 8, 1000, 250, controls, setup) ## i64
four_split_expect("selected", arm == 8)
four_split_expect("reaches source plus four", ffw_current_rank(state) == source_rank + 4)
four_split_expect("shoulder remains exact", ffw_verify_current_exact(state, n) == 1)

<< "PASS four-split arm opens exact +4 shoulder from band two"
