use metaflip_worker

n = 3 ## i64
av = argv()
if av.size() > 0
  n = av[0].to_i()
cap = ffw_default_capacity(n) ## i64
st = i64[ffw_state_size(cap)]
<< "SMOKE begin n=" + n.to_s() + " cap=" + cap.to_s()
flush()
t0 = ccall("__w_clock_ms") ## i64
rank = ffw_init_naive_cap(st, n, cap, 17, 4, 2, 1000, 200) ## i64
t1 = ccall("__w_clock_ms") ## i64
<< "SMOKE init rank=" + rank.to_s() + " exact=" + ffw_last_verify(st).to_s() + " ms=" + (t1 - t0).to_s()
flush()
if n == 3
  loaded = i64[ffw_state_size(cap)]
  t2 = ccall("__w_clock_ms") ## i64
  lr = ffw_load_scheme_cap(loaded, "benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt", n, cap, 19, 4, 2, 1000, 200) ## i64
  t3 = ccall("__w_clock_ms") ## i64
  << "SMOKE load rank=" + lr.to_s() + " exact=" + ffw_last_verify(loaded).to_s() + " ms=" + (t3 - t2).to_s()
  flush()
t4 = ccall("__w_clock_ms") ## i64
r = ffw_walk(st, 1000) ## i64
t5 = ccall("__w_clock_ms") ## i64
<< "SMOKE walk rank=" + r.to_s() + " current=" + ffw_current_rank(st).to_s() + " ms=" + (t5 - t4).to_s()
