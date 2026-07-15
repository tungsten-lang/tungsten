use flipfleet_rect_portfolio_policy

-> ffrpp_test_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

count = ffrpp_default_shape_count() ## i64
shapes = i64[count]
ready = i64[count]
gpu = i64[count]
leverage = i64[count]
z = ffrpp_test_expect("defaults fill", ffrpp_fill_defaults(shapes, ready, gpu, leverage) == 9) ## i64
z = ffrpp_test_expect("default order", shapes[0] == 225 && shapes[1] == 457 && shapes[2] == 346 && shapes[3] == 456 && shapes[4] == 446 && shapes[5] == 445 && shapes[6] == 256 && shapes[7] == 347 && shapes[8] == 356)
z = ffrpp_test_expect("default capabilities", gpu[0] == 0 && gpu[1] == 0 && gpu[2] == 0 && gpu[3] == 0 && gpu[4] == 0 && gpu[5] == 1 && gpu[6] == 1 && gpu[7] == 0 && gpu[8] == 0)
z = ffrpp_test_expect("default leverage", leverage[0] == 2500 && leverage[1] == 2043 && leverage[2] == 1417 && leverage[3] == 1683 && leverage[4] == 1106 && leverage[5] == 1067 && leverage[6] == 734 && leverage[7] == 1342 && leverage[8] == 1277)
z = ffrpp_test_expect("admitted leverage", ffrpp_default_leverage(225) == 2500 && ffrpp_default_leverage(226) == 400 && ffrpp_default_leverage(256) == 734 && ffrpp_default_leverage(467) == 2002 && ffrpp_default_leverage(567) == 1579 && ffrpp_default_leverage(347) == 1342 && ffrpp_default_leverage(356) == 1277 && ffrpp_default_leverage(357) == 1223 && ffrpp_default_leverage(458) == 1325 && ffrpp_default_leverage(466) == 1176 && ffrpp_default_leverage(468) == 1202 && ffrpp_default_leverage(245) == 1 && ffrpp_default_leverage(234) == 1)
z = ffrpp_test_expect("shape labels", ffrpp_shape_name(225) == "2x2x5" && ffrpp_shape_name(256) == "2x5x6" && ffrpp_shape_name(457) == "4x5x7" && ffrpp_shape_name(347) == "3x4x7")

drops = i64[count]
density = i64[count]
exposure = i64[count]
failures = i64[count]
allocation = i64[count]
scores = i64[count]
used = ffrpp_allocate(12, 0, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores) ## i64
z = ffrpp_test_expect("default conservation", used == 12 && ffrpp_allocation_valid(12, ready, allocation, count) == 1)
i = 0 ## i64
while i < count
  z = ffrpp_test_expect("default starvation floor " + i.to_s(), allocation[i] >= 1)
  i += 1
z = ffrpp_test_expect("default priority ordering", allocation[0] >= allocation[1] && allocation[1] >= allocation[3])

# Conservation over many fleet sizes, including J below and above shape count.
j = 0 ## i64
while j <= 64
  got = ffrpp_allocate(j, 7, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores) ## i64
  z = ffrpp_test_expect("conservation J=" + j.to_s(), got == j && ffrpp_allocation_valid(j, ready, allocation, count) == 1)
  j += 1

# With only two workers, rotating floors cover every shape across one cycle.
floor_seen = i64[count]
epoch = 0 ## i64
while epoch < count
  z = ffrpp_allocate(2, epoch, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores)
  i = 0
  while i < count
    if allocation[i] > 0
      floor_seen[i] = 1
    i += 1
  epoch += 1
i = 0
while i < count
  z = ffrpp_test_expect("small-J rotating floor " + i.to_s(), floor_seen[i] == 1)
  i += 1

# Readiness is a hard gate and remaining ready shapes conserve all workers.
ready[1] = 0
ready[4] = 0
used = ffrpp_allocate(17, 3, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores) ## i64
z = ffrpp_test_expect("readiness conservation", used == 17 && ffrpp_allocation_valid(17, ready, allocation, count) == 1)
z = ffrpp_test_expect("unready shapes zero", allocation[1] == 0 && allocation[4] == 0)
ready[1] = 1
ready[4] = 1

# A verified rank drop overwhelms static priority in its own low-exposure
# context, demonstrating actual adaptation rather than fixed weights.
drops[4] = 1
exposure[4] = 1
used = ffrpp_allocate(32, 0, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores) ## i64
z = ffrpp_test_expect("rank yield adapts", allocation[4] > allocation[0] && scores[4] > scores[0])
drops[4] = 0
exposure[4] = 0

# Same-rank density evidence also changes allocation, but exposure normalizes
# cumulative observations so one old gain cannot own the portfolio forever.
density[5] = 500
exposure[5] = 1
z = ffrpp_allocate(24, 0, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores)
density_hot = allocation[5] ## i64
exposure[5] = 10000
z = ffrpp_allocate(24, 0, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores)
density_cold = allocation[5] ## i64
z = ffrpp_test_expect("density yield adapts and decays", density_hot > density_cold)
density[5] = 0
exposure[5] = 0

# Failure history is a soft penalty; the ready floor remains intact.
failures[0] = 7
z = ffrpp_allocate(24, 0, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores)
failed_allocation = allocation[0] ## i64
failures[0] = 0
z = ffrpp_allocate(24, 0, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores)
healthy_allocation = allocation[0] ## i64
z = ffrpp_test_expect("failure penalty", failed_allocation >= 1 && failed_allocation < healthy_allocation)

# Isolate GPU capability with otherwise identical unknown shapes. CPU-only
# gets more CPU workers, but GPU-covered retains its starvation floor.
pair_shapes = i64[2]
pair_shapes[0] = 111
pair_shapes[1] = 222
pair_ready = i64[2]
pair_ready[0] = 1
pair_ready[1] = 1
pair_gpu = i64[2]
pair_gpu[1] = 1
pair_zero0 = i64[2]
pair_zero1 = i64[2]
pair_zero2 = i64[2]
pair_zero3 = i64[2]
pair_zero4 = i64[2]
pair_alloc = i64[2]
pair_scores = i64[2]
z = ffrpp_allocate(20, 0, pair_shapes, pair_ready, pair_gpu, pair_zero0, pair_zero1, pair_zero2, pair_zero3, pair_zero4, pair_alloc, pair_scores)
z = ffrpp_test_expect("GPU coverage shifts CPU", pair_alloc[0] > pair_alloc[1] && pair_alloc[1] >= 1)

# Exact ties rotate deterministically with epoch. Repeated calls are stable.
z = ffrpp_allocate(1, 0, pair_shapes, pair_ready, pair_zero0, pair_zero1, pair_zero2, pair_zero3, pair_zero4, pair_zero0, pair_alloc, pair_scores)
first0 = pair_alloc[0] ## i64
first1 = pair_alloc[1] ## i64
z = ffrpp_allocate(1, 0, pair_shapes, pair_ready, pair_zero0, pair_zero1, pair_zero2, pair_zero3, pair_zero4, pair_zero0, pair_alloc, pair_scores)
z = ffrpp_test_expect("deterministic epoch", pair_alloc[0] == first0 && pair_alloc[1] == first1)
z = ffrpp_allocate(1, 1, pair_shapes, pair_ready, pair_zero0, pair_zero1, pair_zero2, pair_zero3, pair_zero4, pair_zero0, pair_alloc, pair_scores)
z = ffrpp_test_expect("tie rotates by epoch", pair_alloc[0] == first1 && pair_alloc[1] == first0)

# No-ready and malformed inputs fail safely without inventing allocation.
i = 0
while i < count
  ready[i] = 0
  i += 1
z = ffrpp_test_expect("no ready returns zero", ffrpp_allocate(10, 0, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores) == 0 && ffrpp_sum(allocation, count) == 0)
short = i64[1]
z = ffrpp_test_expect("malformed rejected", ffrpp_allocate(10, 0, shapes, short, gpu, drops, density, leverage, exposure, failures, allocation, scores) == -1)

i = 0
while i < count
  ready[i] = 1
  i += 1
z = ffrpp_allocate(192, 11, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores)
<< ffrpp_report(11, shapes, ready, gpu, allocation, scores)
<< "flipfleet_rect_portfolio_policy_test: all checks passed"
