# Typed-array inline path — `## i64[]` element access lowers to the
# emitter's inline mask+load sequences (the exact IR the W_TAG_ARRAY
# move rewrites). Read-modify-write stores plus xor accumulation so
# neither the stores nor the sum can be closed-formed away; SIMD
# vectorization is fine (identical on both sides of the comparison).

fn work(n, rounds)
  buf = Array.new(n, 0) ## i64[]
  total = 0 ## i64
  r = 0 ## i64
  while r < rounds
    i = 0 ## i64
    while i < n
      buf[i] = buf[i] + (i ^ r)
      i += 1
    i = 0
    s = 0 ## i64
    while i < n
      s = s ^ buf[i]
      i += 3
    total = total + s
    r += 1
  total

<< work(100000, 600)
