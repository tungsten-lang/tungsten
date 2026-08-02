# Compiled Core Probability microbenchmarks.
#
#   bin/tungsten -o /tmp/probability_bench benchmarks/probability/monte_carlo.w
#   /tmp/probability_bench

use probability

-> time_counter_rng(draw_count)
  rng = Probability.counter_rng(20260802, 0)
  checksum = 0
  start = ccall("__w_clock_ms")
  i = 0
  while i < draw_count
    checksum = checksum ^ rng.next_u32
    i += 1
  elapsed = ccall("__w_clock_ms") - start
  << ("philox_u32 draws=" + draw_count.to_s + " elapsed_ms=" +
      elapsed.to_s + " checksum=" + checksum.to_s)

-> time_multivariate_log_density(evaluations)
  distribution = Probability.multivariate_normal(
    [~0.0, ~0.0, ~0.0, ~0.0],
    [[~1.0, ~0.2, ~0.0, ~0.0],
     [~0.2, ~1.0, ~0.1, ~0.0],
     [~0.0, ~0.1, ~1.0, ~0.3],
     [~0.0, ~0.0, ~0.3, ~1.0]])
  point = [~0.25, ~-0.5, ~1.0, ~-1.5]
  total = ~0.0
  start = ccall("__w_clock_ms")
  i = 0
  while i < evaluations
    total += distribution.log_prob(point)
    i += 1
  elapsed = ccall("__w_clock_ms") - start
  << ("mvn_logpdf dimension=4 evaluations=" + evaluations.to_s +
      " elapsed_ms=" + elapsed.to_s + " checksum=" + total.to_s)

time_counter_rng(500000)
time_multivariate_log_density(100000)
