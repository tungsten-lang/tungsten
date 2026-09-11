# Shard 2 of the interpreted metaflip unit tests (see spec/interpreted_tests.txt).
# The root gate (scripts/test-bit-specs.sh) discovers this suite by its _spec.w
# name and runs it under the 300 s interpreter watchdog; the harness runs each
# listed test as a child interpreter process and prints PASS/FAIL per test.
use metaflip_unit_harness

exit(mfu_run_shard(2))
