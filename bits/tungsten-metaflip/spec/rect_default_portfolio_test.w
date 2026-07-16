use ../lib/metaflip/rect/portfolio

labels = []
codes = i64[32]
count = ffrpo_parse_shapes(ffrpo_default_shape_spec(), labels, codes) ## i64

if count != 13
  << "FAIL rectangular default count=" + count.to_s()
  exit(1)
expected = i64[13]
expected[0] = 225
expected[1] = 226
expected[2] = 227
expected[3] = 228
expected[4] = 229
expected[5] = 457
expected[6] = 346
expected[7] = 456
expected[8] = 446
expected[9] = 445
expected[10] = 256
expected[11] = 347
expected[12] = 356
i = 0 ## i64
while i < count
  if codes[i] != expected[i]
    << "FAIL rectangular default ordering slot=" + i.to_s() + " got=" + codes[i].to_s()
    exit(1)
  i += 1
if ffrgb_supported(2, 2, 6) != 1 || ffrmw_supported(2, 2, 6) != 1
  << "FAIL 2x2x6 production engines"
  exit(1)
if ffrgb_supported(2, 2, 7) != 1 || ffrgb_supported(2, 2, 8) != 1 || ffrgb_supported(2, 2, 9) != 1
  << "FAIL 2x2x7/8/9 production GPU engines"
  exit(1)
if ffrgb_supported(3, 4, 6) != 1
  << "FAIL 3x4x6 production GPU engine"
  exit(1)
if ffrgb_supported(3, 4, 7) != 1
  << "FAIL 3x4x7 production GPU engine"
  exit(1)
if ffrgb_supported(3, 5, 6) != 1
  << "FAIL 3x5x6 production GPU engine"
  exit(1)
if ffrgb_supported(4, 4, 6) != 1 || ffrgb_supported(4, 5, 6) != 1 || ffrgb_supported(4, 5, 7) != 1
  << "FAIL 4x4x6/4x5x6/4x5x7 production GPU engines"
  exit(1)

shapes = i64[13]
ready = i64[13]
gpu = i64[13]
leverage = i64[13]
if ffrpp_fill_defaults(shapes, ready, gpu, leverage) != 13
  << "FAIL rectangular policy defaults"
  exit(1)
i = 0
while i < count
  if shapes[i] != expected[i]
    << "FAIL rectangular policy ordering slot=" + i.to_s()
    exit(1)
  i += 1
i = 0
while i < 5
  if gpu[i] != 1
    << "FAIL two-wide default lacks GPU coverage slot=" + i.to_s()
    exit(1)
  i += 1
i = 0
while i < count
  if gpu[i] != 1
    << "FAIL default rectangular shape lacks GPU coverage slot=" + i.to_s()
    exit(1)
  i += 1
if leverage[2] != 1 || leverage[3] != 1 || leverage[4] != 800
  << "FAIL 2x2x7/8/9 portfolio priorities"
  exit(1)

# With one host slot per shape, every default receives its hard floor. With
# fewer slots, the epoch window must eventually visit every shape rather than
# starving the newly appended primitive fronts.
drops = i64[13]
density = i64[13]
exposure = i64[13]
failures = i64[13]
allocation = i64[13]
scores = i64[13]
used = ffrpp_allocate(13, 0, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores) ## i64
if used != 13 || ffrpp_allocation_valid(13, ready, allocation, count) != 1
  << "FAIL rectangular full starvation floor"
  exit(1)
i = 0
while i < count
  if allocation[i] != 1
    << "FAIL rectangular full floor slot=" + i.to_s()
    exit(1)
  i += 1

seen = i64[13]
epoch = 0 ## i64
while epoch < count
  used = ffrpp_allocate(3, epoch, shapes, ready, gpu, drops, density, leverage, exposure, failures, allocation, scores)
  if used != 3 || ffrpp_allocation_valid(3, ready, allocation, count) != 1
    << "FAIL rectangular rotating floor epoch=" + epoch.to_s()
    exit(1)
  i = 0
  while i < count
    if allocation[i] > 0
      seen[i] += 1
    i += 1
  epoch += 1
i = 0
while i < count
  if seen[i] < 1
    << "FAIL rectangular starvation slot=" + i.to_s()
    exit(1)
  i += 1

# Three occupancy-width GPU children can cover all new fronts concurrently
# when they are the eligible set; this exercises adaptive selection as well as
# the static capability flags used by the coordinator.
new_gpu_ready = i64[13]
new_gpu_ready[2] = 1
new_gpu_ready[3] = 1
new_gpu_ready[4] = 1
gpu_allocation = i64[13]
gpu_scores = i64[13]
gpu_used = ffrpo_gpu_allocate(24576, 0, "adaptive", shapes, new_gpu_ready, drops, density, leverage, exposure, failures, gpu_allocation, gpu_scores) ## i64
if gpu_used != 24576 || gpu_allocation[2] != 8192 || gpu_allocation[3] != 8192 || gpu_allocation[4] != 8192
  << "FAIL 2x2x7/8/9 adaptive GPU allocation"
  exit(1)

<< "PASS rectangular default includes 13 GPU-backed shapes and rotating CPU floors"
