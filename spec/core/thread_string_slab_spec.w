# Native OS threads must enable string slab/intern locking before the first
# worker can concatenate paths. Nested Thread.new mirrors FlipFleet's CPU/GPU
# controller topology and forces concurrent insertion of unique strings.

parents = 4 ## i64
children_per_parent = 4 ## i64
iterations = 1000 ## i64
slots = parents * children_per_parent ## i64
results = []
i = 0 ## i64
while i < slots * iterations
  results.push(nil)
  i += 1

outer = []
p = 0 ## i64
while p < parents
  parent_id = p ## i64
  parent = Thread.new ->
    inner = []
    c = 0 ## i64
    while c < children_per_parent
      child_id = c ## i64
      slot = parent_id * children_per_parent + child_id ## i64
      child = Thread.new ->
        k = 0 ## i64
        while k < iterations
          value = "/tmp/thread-slab-" + parent_id.to_s() + "-" + child_id.to_s() + "-" + k.to_s() + ".txt"
          results[slot * iterations + k] = value
          k += 1
        0
      inner.push(child)
      c += 1
    c = 0
    while c < children_per_parent
      inner[c].join
      c += 1
    0
  outer.push(parent)
  p += 1

p = 0
while p < parents
  outer[p].join
  p += 1

p = 0
while p < parents
  c = 0 ## i64
  while c < children_per_parent
    slot = p * children_per_parent + c ## i64
    k = 0 ## i64
    while k < iterations
      expected = "/tmp/thread-slab-" + p.to_s() + "-" + c.to_s() + "-" + k.to_s() + ".txt"
      actual = results[slot * iterations + k]
      if actual != expected
        << "thread string slab mismatch slot=" + slot.to_s() + " iteration=" + k.to_s()
        exit(1)
      k += 1
    c += 1
  p += 1

<< "thread string slab concurrency ok"
