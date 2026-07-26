# Stack-promoted small typed arrays are zero-initialised, like every other
# Tungsten array.
#
# `i64[n]` / `SmallArray.new(:i64, n)` are zero-filled by contract; the heap
# forms get that from calloc. The stack-promoted form (lowering emits an LLVM
# `alloca` plus w_small_array_init, which stamps only the 2-byte WSmallArray
# header) used to inherit whatever the previous frame at that depth left
# behind. A flat program reads zeros by luck — the frames don't overlap once
# LLVM inlines them apart — so the probe below is recursive: `writer` descends
# 30 frames stamping a sentinel, `reader` then descends the same 30 frames and
# sums its own freshly-allocated array. Pre-fix this totalled a different
# garbage value on every run (224506947022150, -120332341117210, …); it must
# total 0.
#
# The fix is a `store [N x i8] zeroinitializer` paired with every
# small_array_alloca (emitter.w). SROA/DSE delete it again at sites that
# overwrite every slot before reading.
#
# Run: `bin/tungsten -o /tmp/sazi spec/compiler/small_array_stack_zero_init_spec.w && /tmp/sazi`

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> writer(n)
  a = i64[16]
  i = 0
  while i < 16
    a[i] = 777777777
    i += 1
  if n > 0
    writer(n - 1)
  a[0]

-> reader(n)
  b = i64[16]
  s = 0
  i = 0
  while i < 16
    s += b[i]
    i += 1
  if n > 0
    s += reader(n - 1)
  s

# Same shape for a sub-byte element width (packed payload, 4 bits/slot).
-> writer_u4(n)
  a = u4[64]
  i = 0
  while i < 64
    a[i] = 15
    i += 1
  if n > 0
    writer_u4(n - 1)
  a[0]

-> reader_u4(n)
  b = u4[64]
  s = 0
  i = 0
  while i < 64
    s += b[i]
    i += 1
  if n > 0
    s += reader_u4(n - 1)
  s

# And for floats.
-> writer_f64(n)
  a = f64[16]
  i = 0
  while i < 16
    a[i] = ~2.5
    i += 1
  if n > 0
    writer_f64(n - 1)
  a[0]

-> reader_f64(n)
  b = f64[16]
  s = ~0.0
  i = 0
  while i < 16
    s += b[i]
    i += 1
  if n > 0
    s += reader_f64(n - 1)
  s

check("zero_init.i64_sentinel_written", writer(30) == 777777777)
check("zero_init.i64_dirty_stack_reads_zero", reader(30) == 0)

check("zero_init.u4_sentinel_written", writer_u4(30) == 15)
check("zero_init.u4_dirty_stack_reads_zero", reader_u4(30) == 0)

check("zero_init.f64_sentinel_written", writer_f64(30) == ~2.5)
check("zero_init.f64_dirty_stack_reads_zero", reader_f64(30) == ~0.0)
