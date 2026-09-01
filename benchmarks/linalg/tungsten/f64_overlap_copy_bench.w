# Matched copy benchmark for reusable dense-factor solve_into boundaries.
# Compares the former Tungsten element loop with the retained overlap-safe
# native f64 memmove/conversion bridge. Both reuse caller-owned storage.

-> loop_copy(src, dst, n)
  i = 0
  while i < n
    dst[i] = src[i] + ~0.0
    i += 1

-> native_copy(src, dst, n)
  ccall("w_array_memmove_f64", src, dst, n)

-> run_case(n, reps)
  src = f64[n]
  dst = f64[n]
  i = 0
  while i < n
    src[i] = (i + 1).to_f
    i += 1

  loop_copy(src, dst, n)
  native_copy(src, dst, n)
  raise "copy mismatch" if dst[n - 1] != n.to_f

  t0 = clock()
  r = 0
  while r < reps
    loop_copy(src, dst, n)
    r += 1
  loop_ns = (clock() - t0) * ~1000000000.0 / reps

  t0 = clock()
  r = 0
  while r < reps
    native_copy(src, dst, n)
    r += 1
  native_ns = (clock() - t0) * ~1000000000.0 / reps

  line = "BENCH f64_copy n=" + n.to_s
  line += " loop_ns=" + loop_ns.round(1).to_s
  line += " native_ns=" + native_ns.round(1).to_s
  line += " speedup=" + (loop_ns / native_ns).round(2).to_s
  << line

run_case(3, 500000)
run_case(64, 200000)
run_case(512, 50000)
run_case(4096, 10000)

# Shifted views share one backing allocation. The native boundary must retain
# all source values before the destination overwrites them.
overlap = f64[5]
i = 0
while i < 5
  overlap[i] = (i + 1).to_f
  i += 1
native_copy(overlap.slice(0, 4), overlap.slice(1, 4), 4)
raise "overlap copy mismatch" if overlap[1] != ~1.0 || overlap[4] != ~4.0
<< "BENCH f64_copy overlap=PASS"
