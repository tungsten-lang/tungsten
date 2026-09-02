# while vs .each -> / .times -> on typed and plain arrays (sum + fill + gather)
n = 2000000
reps = 20
ta = u32[n]
i = 0
while i < n
  ta[i] = i & 1023
  i += 1
pa = []
i = 0
while i < n
  pa.push(i & 1023)
  i += 1
# 1. typed sum: while
t0 = clock_ms
r = 0
s = 0
while r < reps
  s = 0
  i = 0
  while i < n
    s += ta[i]
    i += 1
  r += 1
t1 = clock_ms
<< "typed sum while   " + (t1 - t0).to_s + "ms s=" + s.to_s
# 2. typed sum: times ->
t0 = clock_ms
r = 0
while r < reps
  s = 0
  n.times -> (j)
    s += ta[j]
  r += 1
t1 = clock_ms
<< "typed sum times-> " + (t1 - t0).to_s + "ms s=" + s.to_s
# 3. plain sum: while
t0 = clock_ms
r = 0
while r < reps
  s = 0
  i = 0
  while i < n
    s += pa[i]
    i += 1
  r += 1
t1 = clock_ms
<< "plain sum while   " + (t1 - t0).to_s + "ms s=" + s.to_s
# 4. plain sum: each ->
t0 = clock_ms
r = 0
while r < reps
  s = 0
  pa.each -> (x)
    s += x
  r += 1
t1 = clock_ms
<< "plain sum each->  " + (t1 - t0).to_s + "ms s=" + s.to_s
# 5. typed fill: while vs times
t0 = clock_ms
r = 0
while r < reps
  i = 0
  while i < n
    ta[i] = i
    i += 1
  r += 1
t1 = clock_ms
<< "typed fill while  " + (t1 - t0).to_s + "ms"
t0 = clock_ms
r = 0
while r < reps
  n.times -> (j)
    ta[j] = j
  r += 1
t1 = clock_ms
<< "typed fill times->" + (t1 - t0).to_s + "ms"
# 6. plain map -> vs while-push
t0 = clock_ms
r = 0
q = nil
while r < 3
  q = pa.map -> (x) x + 1
  r += 1
t1 = clock_ms
<< "plain map->       " + (t1 - t0).to_s + "ms q=" + q.size.to_s
t0 = clock_ms
r = 0
while r < 3
  q = []
  i = 0
  while i < n
    q.push(pa[i] + 1)
    i += 1
  r += 1
t1 = clock_ms
<< "plain while-push  " + (t1 - t0).to_s + "ms q=" + q.size.to_s
Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
