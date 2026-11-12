# Shard 6 of the native-only metaflip unit tests (see spec/native_tests.txt).
# The root gate (scripts/test-bit-specs.sh) discovers this suite by its _spec.w
# name and runs it under the 300 s watchdog; the harness compiles and runs each
# listed test as a child `tungsten spec/<name>_test.w` and prints PASS/FAIL
# per test.
use metaflip_unit_harness

exit(mfu_run_native_shard(6))
