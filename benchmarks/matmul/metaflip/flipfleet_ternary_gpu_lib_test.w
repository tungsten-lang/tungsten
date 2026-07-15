use core/system
use flipfleet_ternary_gpu_lib

root = capture("pwd").strip()
base = root + "/benchmarks/matmul/metaflip/"
n = 5 ## i64
capacity = fft_default_capacity(n) ## i64
words = fft_state_size(capacity) ## i64
left = i64[words]
right = i64[words]
z = fft_load_seed(left,base + "matmul_5x5_rank93_d1245_ternary_gpu.txt",n,capacity,71,3) ## i64
if z != 93
  << "FAIL first exact seed"
  exit(1)
z = fft_load_seed(right,base + "matmul_5x5_rank93_kauers_ternary.txt",n,capacity,73,3)
if z != 93
  << "FAIL second exact seed"
  exit(1)

seeds = [left,right]
outputs = []
metrics = i64[15]
result = fftgs_scout_portfolio(seeds,outputs,root,32,64,2,metrics) ## i64
if result < 0 || metrics[0] != 1
  << "FAIL GPU scout completed"
  exit(1)
if metrics[7] != 2 || metrics[11] != 2
  << "FAIL portfolio rotated"
  exit(1)
if metrics[1] != 4096
  << "FAIL attempt accounting"
  exit(1)
if metrics[2] <= 0
  << "FAIL accepted exact moves"
  exit(1)
if metrics[3] != outputs.size() || metrics[4] != 0
  << "FAIL every returned endpoint gated"
  exit(1)
i = 0 ## i64
while i < outputs.size()
  if fft_verify_current_exact(outputs[i]) != 1
    << "FAIL output exact"
    exit(1)
  i += 1

# Exercise the production wrapper's rank-250/cap-256 path, rather than only
# the standalone harness' direct buffers.
capacity7 = fft_default_capacity(7) ## i64
seven_left = i64[fft_state_size(capacity7)]
seven_right = i64[fft_state_size(capacity7)]
z = fft_load_seed(seven_left,base + "matmul_7x7_rank250_dronperminov_ternary.txt",7,capacity7,79,3)
if z != 250
  << "FAIL first 7x7 exact seed"
  exit(1)
z = fft_load_seed(seven_right,base + "matmul_7x7_rank250_d3069_ternary_door.txt",7,capacity7,83,3)
if z != 250
  << "FAIL second 7x7 exact seed"
  exit(1)
seven_outputs = []
seven_metrics = i64[15]
result = fftgs_scout_portfolio([seven_left,seven_right],seven_outputs,root,16,64,2,seven_metrics)
if result < 0 || seven_metrics[0] != 1 || seven_metrics[4] != 0 || seven_outputs.size() != 2
  << "FAIL production 7x7 GPU path"
  exit(1)
i = 0
while i < seven_outputs.size()
  if fft_verify_current_exact(seven_outputs[i]) != 1
    << "FAIL production 7x7 output exact"
    exit(1)
  i += 1

# Missing resources take the same rescue path as a host without a Metal
# device.  The optional GPU lane degrades; it does not raise through the fleet.
degraded_outputs = []
degraded_metrics = i64[15]
degraded = fftgs_scout_portfolio(seeds,degraded_outputs,"/tmp/flipfleet-no-metal-resource",2,1,1,degraded_metrics) ## i64
if degraded >= 0 || degraded_metrics[0] >= 0
  << "FAIL clean degraded result"
  exit(1)

<< "PASS ternary GPU library: outputs=" + outputs.size().to_s() + " attempts=" + metrics[1].to_s() + " accepted=" + metrics[2].to_s() + " rank250_outputs=" + seven_outputs.size().to_s() + " rank250_rejects=" + seven_metrics[4].to_s() + " degraded=" + degraded_metrics[0].to_s()
