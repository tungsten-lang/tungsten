use ../lib/metaflip/seeds/catalog

failures = 0 ## i64

-> expect_default(label, actual, expected) (String i64 i64) i64
  if actual != expected
    << "FAIL " + label + " actual=" + actual.to_s() + " expected=" + expected.to_s()
    return 1
  0

# Keep the same reserve with or without a GPU and at least one CPU worker.
failures += expect_default("18-vCPU GPU", ffp_default_cpu_walkers(18, 1), 16)
failures += expect_default("18-vCPU CPU-only", ffp_default_cpu_walkers(18, 0), 16)
failures += expect_default("12-vCPU", ffp_default_cpu_walkers(12, 1), 10)
failures += expect_default("6-vCPU", ffp_default_cpu_walkers(6, 1), 4)
failures += expect_default("3-vCPU", ffp_default_cpu_walkers(3, 1), 1)
failures += expect_default("2-vCPU", ffp_default_cpu_walkers(2, 1), 1)
failures += expect_default("1-vCPU", ffp_default_cpu_walkers(1, 1), 1)
failures += expect_default("unknown CPU count", ffp_default_cpu_walkers(0, 1), 1)

if failures != 0
  exit(1)

<< "PASS hardware-derived CPU default reserves two logical CPUs"
