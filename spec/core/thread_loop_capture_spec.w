# Thread.new must snapshot loop-local capture cells at spawn time.  In
# particular, a later iteration must not overwrite an earlier thread's index
# or branch selector.

count = 8 ## i64
seen = i64[count]
workers = []
i = 0 ## i64
while i < count
  slot = i ## i64
  branch = 0 ## i64
  if i == count - 1
    branch = 1
  worker = Thread.new ->
    # Delay early slots long enough that the spawning loop has advanced.
    spin = 0 ## i64
    while spin < (count - slot) * 10000
      spin += 1
    seen[slot] = slot * 10 + branch
  workers.push(worker)
  i += 1

i = 0
while i < count
  workers[i].join
  i += 1

i = 0
while i < count
  expected = i * 10 ## i64
  if i == count - 1
    expected += 1
  if seen[i] != expected
    << "thread loop capture mismatch slot=" + i.to_s() + " got=" + seen[i].to_s() + " expected=" + expected.to_s()
    exit(1)
  i += 1

<< "thread loop capture ok"

-> mark_normal(state) (i64[]) i64
  state[0] = 100
  0

-> mark_special(state) (i64[]) i64
  state[0] = 200
  0

# Mirror a coordinator loop that captures both a typed array and a branch flag
# and then calls one of two typed functions from the thread body.
states = []
workers = []
i = 0
while i < count
  state = i64[1]
  state[0] = i
  states.push(state)
  worker_state = states[i]
  special = 0 ## i64
  if i == count - 1
    special = 1
  worker = Thread.new ->
    if special == 0
      z = mark_normal(worker_state) ## i64
    if special != 0
      z = mark_special(worker_state) ## i64
  workers.push(worker)
  i += 1

i = 0
while i < count
  workers[i].join
  expected = 100 ## i64
  if i == count - 1
    expected = 200
  if states[i][0] != expected
    << "thread typed capture mismatch slot=" + i.to_s() + " got=" + states[i][0].to_s() + " expected=" + expected.to_s()
    exit(1)
  i += 1

<< "thread typed loop capture ok"
