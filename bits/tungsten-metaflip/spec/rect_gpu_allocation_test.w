use ../lib/metaflip/rect/portfolio

-> rect_gpu_alloc_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    return 1
  0

-> rect_gpu_alloc_active(allocation) (i64[]) i64
  active = 0 ## i64
  i = 0 ## i64
  while i < allocation.size()
    if allocation[i] > 0
      active += 1
    i += 1
  active

-> rect_gpu_alloc_sum(allocation) (i64[]) i64
  total = 0 ## i64
  i = 0 ## i64
  while i < allocation.size()
    total += allocation[i]
    i += 1
  total

count = 4 ## i64
# Equal shape codes make the score rows exactly equal, exposing deterministic
# epoch tie rotation without coupling the test to static campaign weights.
shapes = i64[count]
ready = i64[count]
drops = i64[count]
density = i64[count]
leverage = i64[count]
exposure = i64[count]
failures = i64[count]
allocation = i64[count]
scores = i64[count]
failed = 0 ## i64
i = 0 ## i64
while i < count
  shapes[i] = 346
  ready[i] = 1
  leverage[i] = 1679
  i += 1

used = ffrpo_gpu_allocate(8192, 0, "adaptive", shapes, ready, drops, density, leverage, exposure, failures, allocation, scores) ## i64
failed += rect_gpu_alloc_expect("8192 adaptive lanes are conserved", used == 8192 && rect_gpu_alloc_sum(allocation) == 8192)
failed += rect_gpu_alloc_expect("8192 adaptive lanes launch one full-width child", rect_gpu_alloc_active(allocation) == 1 && allocation[0] == 8192)

used = ffrpo_gpu_allocate(4096, 0, "adaptive", shapes, ready, drops, density, leverage, exposure, failures, allocation, scores)
failed += rect_gpu_alloc_expect("sub-floor adaptive lanes stay on one child", used == 4096 && rect_gpu_alloc_sum(allocation) == 4096 && rect_gpu_alloc_active(allocation) == 1 && allocation[0] == 4096)

used = ffrpo_gpu_allocate(16384, 0, "adaptive", shapes, ready, drops, density, leverage, exposure, failures, allocation, scores)
failed += rect_gpu_alloc_expect("16384 adaptive lanes are conserved", used == 16384 && rect_gpu_alloc_sum(allocation) == 16384)
failed += rect_gpu_alloc_expect("16384 adaptive lanes preserve two occupancy floors", rect_gpu_alloc_active(allocation) == 2 && allocation[0] == 8192 && allocation[1] == 8192)

used = ffrpo_gpu_allocate(20000, 0, "adaptive", shapes, ready, drops, density, leverage, exposure, failures, allocation, scores)
failed += rect_gpu_alloc_expect("non-floor-multiple lanes are conserved", used == 20000 && rect_gpu_alloc_sum(allocation) == 20000)
failed += rect_gpu_alloc_expect("remainder does not create an underfilled third child", rect_gpu_alloc_active(allocation) == 2 && allocation[0] >= 8192 && allocation[1] >= 8192)

used = ffrpo_gpu_allocate(32768, 0, "adaptive", shapes, ready, drops, density, leverage, exposure, failures, allocation, scores)
failed += rect_gpu_alloc_expect("32768 adaptive lanes scale to four occupied children", used == 32768 && rect_gpu_alloc_sum(allocation) == 32768 && rect_gpu_alloc_active(allocation) == 4 && allocation[0] == 8192 && allocation[1] == 8192 && allocation[2] == 8192 && allocation[3] == 8192)

# A GPU-ready shape without a CPU host is represented as not ready by the
# coordinator's gpu_launch_ready gate and must receive no allocation.
ready[0] = 0
ready[1] = 1
ready[2] = 0
ready[3] = 1
used = ffrpo_gpu_allocate(8192, 0, "adaptive", shapes, ready, drops, density, leverage, exposure, failures, allocation, scores)
failed += rect_gpu_alloc_expect("ready and CPU-host gate is honored", used == 8192 && allocation[0] == 0 && allocation[1] == 8192 && allocation[2] == 0 && allocation[3] == 0)

# Equal-score one-child epochs rotate rather than pinning a fixed array slot.
ready[0] = 1
ready[1] = 1
ready[2] = 1
ready[3] = 1
epoch = 0 ## i64
seen = i64[count]
while epoch < count
  used = ffrpo_gpu_allocate(8192, epoch, "adaptive", shapes, ready, drops, density, leverage, exposure, failures, allocation, scores)
  i = 0 ## i64
  while i < count
    if allocation[i] > 0
      seen[i] += 1
    i += 1
  epoch += 1
failed += rect_gpu_alloc_expect("adaptive equal-score epochs cover every shape", seen[0] == 1 && seen[1] == 1 && seen[2] == 1 && seen[3] == 1)

# Empirical/exploration scoring remains live: after only shape zero has heavy
# exposure, a fresh sibling wins the next adaptive epoch even without a tie.
exposure[0] = 1000000
exposure[1] = 0
exposure[2] = 0
exposure[3] = 0
used = ffrpo_gpu_allocate(8192, 0, "adaptive", shapes, ready, drops, density, leverage, exposure, failures, allocation, scores)
failed += rect_gpu_alloc_expect("underexposed shape displaces an overexposed incumbent", allocation[0] == 0 && rect_gpu_alloc_active(allocation) == 1)

# Single mode ignores the adaptive concurrency cap and assigns the whole width
# to exactly one best eligible child.
exposure[0] = 0
used = ffrpo_gpu_allocate(32768, 2, "single", shapes, ready, drops, density, leverage, exposure, failures, allocation, scores)
failed += rect_gpu_alloc_expect("single policy conserves full width on one child", used == 32768 && rect_gpu_alloc_sum(allocation) == 32768 && rect_gpu_alloc_active(allocation) == 1 && allocation[2] == 32768)

ready[0] = 0
ready[1] = 0
ready[2] = 0
ready[3] = 0
used = ffrpo_gpu_allocate(8192, 0, "adaptive", shapes, ready, drops, density, leverage, exposure, failures, allocation, scores)
failed += rect_gpu_alloc_expect("no eligible host means no GPU allocation", used == 0 && rect_gpu_alloc_sum(allocation) == 0)

if failed != 0
  exit(1)
<< "PASS rectangular GPU allocation preserves occupancy, rotation, and host gates"
