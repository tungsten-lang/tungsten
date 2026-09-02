# C: typed parameter signature (module-level fn, space-separated types)
-> sum_typed(b, n) (u32[] i64) i64
  s = 0
  i = 0
  while i < n
    s += b[i]
    i += 1
  s

+ Holder
  -> new(n)
    @buf = u32[n]
    i = 0
    while i < n
      @buf[i] = i & 1023
      i += 1
    @n = n

  # A: local loaded from ivar, no annotation
  -> sum_plain
    b = @buf
    n = @n
    s = 0
    i = 0
    while i < n
      s += b[i]
      i += 1
    s

  # B: local loaded from ivar with a type annotation
  -> sum_annot
    b = @buf ## u32[]
    n = @n ## i64
    s = 0
    i = 0
    while i < n
      s += b[i]
      i += 1
    s

  -> call_typed
    sum_typed(@buf, @n)

h = Holder.new(4000000)
reps = 10
t0 = clock_ms
r = 0
s = 0
while r < reps
  s = h.sum_plain
  r += 1
<< "ivar plain  " + (clock_ms - t0).to_s + "ms s=" + s.to_s
t0 = clock_ms
r = 0
while r < reps
  s = h.sum_annot
  r += 1
<< "ivar annot  " + (clock_ms - t0).to_s + "ms s=" + s.to_s
t0 = clock_ms
r = 0
while r < reps
  s = h.call_typed
  r += 1
<< "typed param " + (clock_ms - t0).to_s + "ms s=" + s.to_s
Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
