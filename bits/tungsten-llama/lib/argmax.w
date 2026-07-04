# Find argmax of an f32 array. Single threadgroup of TG_SIZE threads
# (e.g. 1024 = 32 simdgroups for big vocabs). Each thread scans
# n/TG_SIZE elements, tracking running max + index. tg_max reduces to
# the global max value across the whole TG via threadgroup memory.
# A second strided pass picks the smallest index whose value equals
# the max, reduced via tg_min. Result written to result[0].
#
# Dispatched with `metal_dispatch_groups(queue, pipe, [...], 1, TG_SIZE)`
# where TG_SIZE should be tuned to vocab size; 1024 is a sweet spot for
# vocab=151K (~148 elements per thread) on M3 Max.

## f32[]: x
## i32[]: result
## i32: n
@gpu fn argmax(x, result, n)
  tg_size = gpu.threads_per_threadgroup ## i32
  tid = gpu.thread_position_in_threadgroup.x ## i32
  m_local = ~-1000000000.0 ## f32
  i = tid ## i32
  while i < n
    v = x[i] ## f32
    if v > m_local
      m_local = v
    i = i + tg_size
  m = tg_max(m_local) ## f32
  # Each lane finds the FIRST index in its stride that equals m.
  best = n ## i32
  i = tid
  while i < n
    if x[i] == m
      if i < best
        best = i
    i = i + tg_size
  g_best = tg_min(best) ## i32
  if tid == 0
    result[0] = g_best
