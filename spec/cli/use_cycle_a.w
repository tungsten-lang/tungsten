# E_LOAD_CYCLE fixture (scripts/test-cli-contracts.sh): this file and
# use_cycle_b.w `use` each other. Loading either must fail with a circular
# use diagnostic pointing at the `use` that closes the cycle.
use use_cycle_b

-> from_a
  "a"
