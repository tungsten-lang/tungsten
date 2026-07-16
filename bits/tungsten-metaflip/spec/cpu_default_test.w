use ../lib/metaflip/seeds/catalog

failures = 0 ## i64

-> expect_default(label, actual, expected) (String i64 i64) i64
  if actual != expected
    << "FAIL " + label + " actual=" + actual.to_s() + " expected=" + expected.to_s()
    return 1
  0

# The measured reference machine has eighteen logical CPUs and peaks at twelve
# ordinary walkers.  Small hosts retain at least one worker and reserve half
# their CPUs rather than starving coordination entirely.
failures += expect_default("18-vCPU GPU", ffp_default_cpu_walkers(18, 1), 12)
failures += expect_default("18-vCPU CPU-only", ffp_default_cpu_walkers(18, 0), 12)
failures += expect_default("12-vCPU", ffp_default_cpu_walkers(12, 1), 6)
failures += expect_default("6-vCPU", ffp_default_cpu_walkers(6, 1), 3)
failures += expect_default("2-vCPU", ffp_default_cpu_walkers(2, 1), 1)
failures += expect_default("1-vCPU", ffp_default_cpu_walkers(1, 1), 1)

if failures != 0
  exit(1)

<< "PASS hardware-derived CPU default reserves six logical CPUs"
