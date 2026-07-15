use flipfleet_ternary_index_shear

# Fixed-size guardrail benchmark for the random helper.  Production uses the
# deterministic strict-descent closure at seed admission and only once per
# 8,388,608 ordinary moves thereafter; 10,000 back-to-back random probes
# intentionally overstate the cost of either policy.
probes = 10000 ## i64
root = "benchmarks/matmul/metaflip/"

capacity5 = fft_default_capacity(5) ## i64
state5 = i64[fft_state_size(capacity5)]
rank5 = fft_load_seed(state5,root+"matmul_5x5_rank93_d1248_gl3_ternary.txt",5,capacity5,2026071505,3) ## i64
start5 = ccall("__w_clock_ms") ## i64
ok5 = 1 ## i64
i = 0 ## i64
while i < probes
  wander = 0 ## i64
  if (i & 3) == 3
    wander = 1
  if fft_index_shear_try(state5,wander) < 0
    ok5 = 0
  i += 1
elapsed5 = ccall("__w_clock_ms") - start5 ## i64
if elapsed5 < 1
  elapsed5 = 1
exact5 = fft_verify_current_exact(state5) * fft_verify_best_exact(state5) ## i64
accepted5 = state5[55] ## i64
improving5 = state5[58] ## i64
best5 = state5[21] ## i64
rate5 = probes * 1000 / elapsed5 ## i64
<< "INDEX_SHEAR_BENCH tensor=5x5 rank=" + rank5.to_s() + " probes=" + probes.to_s() + " ms=" + elapsed5.to_s() + " rate=" + rate5.to_s() + "/s accepted=" + accepted5.to_s() + " improving=" + improving5.to_s() + " best_d=" + best5.to_s() + " exact=" + exact5.to_s()

capacity6 = fft_default_capacity(6) ## i64
state6 = i64[fft_state_size(capacity6)]
rank6 = fft_load_seed(state6,root+"matmul_6x6_rank153_d2502_ternary_walk.txt",6,capacity6,2026071506,3) ## i64
start6 = ccall("__w_clock_ms") ## i64
ok6 = 1 ## i64
i = 0
while i < probes
  wander = 0
  if (i & 3) == 3
    wander = 1
  if fft_index_shear_try(state6,wander) < 0
    ok6 = 0
  i += 1
elapsed6 = ccall("__w_clock_ms") - start6 ## i64
if elapsed6 < 1
  elapsed6 = 1
exact6 = fft_verify_current_exact(state6) * fft_verify_best_exact(state6) ## i64
accepted6 = state6[55] ## i64
improving6 = state6[58] ## i64
best6 = state6[21] ## i64
rate6 = probes * 1000 / elapsed6 ## i64
<< "INDEX_SHEAR_BENCH tensor=6x6 rank=" + rank6.to_s() + " probes=" + probes.to_s() + " ms=" + elapsed6.to_s() + " rate=" + rate6.to_s() + "/s accepted=" + accepted6.to_s() + " improving=" + improving6.to_s() + " best_d=" + best6.to_s() + " exact=" + exact6.to_s()

capacity7 = fft_default_capacity(7) ## i64
state7 = i64[fft_state_size(capacity7)]
rank7 = fft_load_seed(state7,root+"matmul_7x7_rank250_dronperminov_ternary.txt",7,capacity7,2026071507,3) ## i64
start7 = ccall("__w_clock_ms") ## i64
ok7 = 1 ## i64
i = 0
while i < probes
  wander = 0
  if (i & 3) == 3
    wander = 1
  if fft_index_shear_try(state7,wander) < 0
    ok7 = 0
  i += 1
elapsed7 = ccall("__w_clock_ms") - start7 ## i64
if elapsed7 < 1
  elapsed7 = 1
exact7 = fft_verify_current_exact(state7) * fft_verify_best_exact(state7) ## i64
accepted7 = state7[55] ## i64
improving7 = state7[58] ## i64
best7 = state7[21] ## i64
rate7 = probes * 1000 / elapsed7 ## i64
<< "INDEX_SHEAR_BENCH tensor=7x7 rank=" + rank7.to_s() + " probes=" + probes.to_s() + " ms=" + elapsed7.to_s() + " rate=" + rate7.to_s() + "/s accepted=" + accepted7.to_s() + " improving=" + improving7.to_s() + " best_d=" + best7.to_s() + " exact=" + exact7.to_s()

if rank5 != 93 || rank6 != 153 || rank7 != 250 || ok5 != 1 || ok6 != 1 || ok7 != 1 || exact5 != 1 || exact6 != 1 || exact7 != 1
  exit(1)
