+ Mixer
  -> new(@k)
    self
  -> mix(v)
    (v * 2654435761) ^ @k

# primitive: method_call — 8000000 ops
chk = 0 ## i64
o = Mixer.new(7)
n = 8000000 ## i64
t0 = clock
i = 0 ## i64
while i < n
  chk = chk ^ o.mix(i)
  i = i + 1
t1 = clock
<< "ops: 8000000"
<< chk
<< "elapsed: [t1 - t0]s"
