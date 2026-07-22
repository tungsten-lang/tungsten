use ../lib/metaflip/fleet/archive

failures = 0 ## i64

-> archive_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL archive admission: " + label
    return 1
  0

# Frozen copy of the pre-optimization exhaustive policy. This is the semantic
# oracle: every slot is tried in ascending order and equal trial minima retain
# the earlier slot.
-> archive_exhaustive_action(archive, candidate, capacity, min_distance) i64
  duplicate = 0 ## i64
  closest = 999999999 ## i64
  i = 0 ## i64
  while i < archive.size()
    distance = ffn_distance(archive[i], candidate) ## i64
    if distance == 0
      duplicate = 1
    if distance < closest
      closest = distance
    i += 1
  if archive.size() == 0
    closest = 999999999
  if duplicate == 0
    if closest >= min_distance
      if archive.size() < capacity
        return 1
      if archive.size() >= capacity
        current_min = ffn_archive_min_distance(archive) ## i64
        replace = 0 - 1 ## i64
        best_min = current_min ## i64
        i = 0
        while i < archive.size()
          trial_min = ffn_replacement_min_distance(archive, i, candidate) ## i64
          if trial_min > best_min
            best_min = trial_min
            replace = i
          i += 1
        if replace >= 0
          return replace + 2
  0

-> archive_compare(label, archive, candidate, capacity, min_distance) i64
  expected = archive_exhaustive_action(archive, candidate, capacity, min_distance) ## i64
  actual = ffn_archive_admission_action(archive, candidate, capacity, min_distance) ## i64
  archive_expect(label + " expected=" + expected.to_s() + " actual=" + actual.to_s(), actual == expected)

# Build a small deterministic term set without requiring tensor exactness. The
# admission policy depends only on state identities and term-set distances;
# exact packaged schemes exercise the exhaustive gate separately below.
-> archive_synthetic_state(term_mask)
  capacity = 16 ## i64
  state = i64[ffw_state_size(capacity)]
  if ffw_layout(state, 2, capacity) == 0
    return nil
  rank = 0 ## i64
  density = 0 ## i64
  term = 0 ## i64
  while term < 12
    if ((term_mask >> term) & 1) == 1
      u = (term % 15) + 1 ## i64
      v = ((term * 5 + 2) % 15) + 1 ## i64
      w = ((term * 7 + 4) % 15) + 1 ## i64
      state[state[47] + rank] = u
      state[state[48] + rank] = v
      state[state[49] + rank] = w
      density += ffw_popcount(u) + ffw_popcount(v) + ffw_popcount(w)
      rank += 1
    term += 1
  state[7] = rank
  state[36] = density
  state

a = archive_synthetic_state(15)       # {0,1,2,3}
b = archive_synthetic_state(23)       # {0,1,2,4}
c = archive_synthetic_state(51)       # {0,1,4,5}
d = archive_synthetic_state(960)      # {6,7,8,9}
e = archive_synthetic_state(39)       # {0,1,2,5}
p = archive_synthetic_state(3)        # {0,1}
q = archive_synthetic_state(5)        # {0,2}
r = archive_synthetic_state(48)       # {4,5}
s = archive_synthetic_state(192)      # {6,7}
t = archive_synthetic_state(320)      # {6,8}
u = archive_synthetic_state(768)      # {8,9}

# Construction guards make these tests readable as distance configurations,
# rather than relying only on oracle agreement.
failures += archive_expect("shared-min construction", ffn_distance(a, b) == 2 && ffn_distance(b, c) == 2 && ffn_distance(a, c) == 4)
shared = []
shared.push(a)
shared.push(b)
shared.push(c)
failures += archive_expect("shared endpoint is the only improvement", ffn_archive_admission_action(shared, d, 3, 0) == 3)
failures += archive_compare("shared minimum endpoint", shared, d, 3, 0)

triangle = []
triangle.push(a)
triangle.push(b)
triangle.push(e)
failures += archive_expect("multiple minimum triangle rejects", ffn_archive_admission_action(triangle, d, 3, 0) == 0)
failures += archive_compare("multiple minimum triangle", triangle, d, 3, 0)

disjoint = []
disjoint.push(p)
disjoint.push(q)
disjoint.push(s)
disjoint.push(t)
failures += archive_expect("disjoint-min construction", ffn_distance(p, q) == 2 && ffn_distance(s, t) == 2 && ffn_distance(p, s) == 4)
failures += archive_expect("disjoint minima reject", ffn_archive_admission_action(disjoint, u, 4, 0) == 0)
failures += archive_compare("disjoint minimum pairs", disjoint, u, 4, 0)

tie = []
tie.push(p)
tie.push(q)
failures += archive_expect("equal endpoint trials choose ascending slot", ffn_archive_admission_action(tie, r, 2, 0) == 2)
failures += archive_compare("ascending endpoint tie", tie, r, 2, 0)
failures += archive_expect("distance threshold rejects", ffn_archive_admission_action(tie, r, 2, 5) == 0)

empty = []
failures += archive_expect("empty archive appends", ffn_archive_admission_action(empty, p, 1, 0) == 1)
failures += archive_expect("zero-capacity archive rejects", ffn_archive_admission_action(empty, p, 0, 0) == 0)
singleton = []
singleton.push(p)
failures += archive_expect("capacity-one exhaustive edge", ffn_archive_admission_action(singleton, r, 1, 0) == 0)
failures += archive_expect("duplicate rejects", ffn_archive_admission_action(tie, p, 2, 0) == 0)

# Deterministic property sweep over constructed set-distance geometries,
# varying archive order, fullness, candidate, and policy threshold.
masks = []
masks.push(15)
masks.push(23)
masks.push(39)
masks.push(51)
masks.push(60)
masks.push(85)
masks.push(90)
masks.push(105)
masks.push(150)
masks.push(170)
masks.push(204)
masks.push(240)
masks.push(291)
masks.push(325)
masks.push(390)
masks.push(480)
synthetic = []
i = 0
while i < masks.size()
  synthetic.push(archive_synthetic_state(masks[i]))
  i += 1

size = 2 ## i64
while size <= 8
  start = 0 ## i64
  while start < synthetic.size()
    archive = []
    offset = 0 ## i64
    while offset < size
      archive.push(synthetic[(start + offset * 5) % synthetic.size()])
      offset += 1
    candidate_index = 0 ## i64
    while candidate_index < synthetic.size()
      threshold = 0 ## i64
      while threshold <= 6
        failures += archive_compare("synthetic-full", archive, synthetic[candidate_index], size, threshold)
        failures += archive_compare("synthetic-append", archive, synthetic[candidate_index], size + 1, threshold)
        threshold += 2
      candidate_index += 1
    start += 1
  size += 1

# Real exact 2x2 record states cover canonical-identity duplicates and term
# geometries produced by actual decomposition search.
root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
paths2 = []
paths2.push("matmul_2x2_rank7_d36_gl120_gf2.txt")
paths2.push("matmul_2x2_rank7_d36_gl190_gf2.txt")
paths2.push("matmul_2x2_rank7_d40_gl01_gf2.txt")
paths2.push("matmul_2x2_rank7_d40_gl108_gf2.txt")
paths2.push("matmul_2x2_rank7_d40_gl214_gf2.txt")
paths2.push("matmul_2x2_rank7_d42_gl08_gf2.txt")
paths2.push("matmul_2x2_rank7_d42_gl110_gf2.txt")
paths2.push("matmul_2x2_rank7_d42_gl207_gf2.txt")
paths2.push("matmul_2x2_rank7_strassen_gf2.txt")
exact2 = []
i = 0
while i < paths2.size()
  state = i64[ffw_state_size(32)]
  loaded = ffw_load_scheme_cap(state, root + paths2[i], 2, 32, 2001 + i, 0, 1, 1, 1) ## i64
  failures += archive_expect("load exact 2x2 " + paths2[i], loaded == 7 && ffw_verify_best_exact(state, 2) == 1)
  exact2.push(state)
  i += 1

size = 2
while size <= 8
  start = 0
  while start < exact2.size()
    archive = []
    offset = 0
    while offset < size
      archive.push(exact2[(start + offset * 5) % exact2.size()])
      offset += 1
    candidate_index = 0
    while candidate_index < exact2.size()
      threshold = 0
      while threshold <= 4
        failures += archive_compare("exact-2x2", archive, exact2[candidate_index], size, threshold)
        threshold += 2
      candidate_index += 1
    start += 1
  size += 1

comparisons = 4 + 7 * 16 * 16 * 4 * 2 + 7 * 9 * 9 * 3 ## i64
if failures > 0
  << "archive admission: " + failures.to_s() + " failure(s), comparisons=" + comparisons.to_s()
  exit(1)

<< "PASS archive admission exhaustive-equivalent comparisons=" + comparisons.to_s() + " multiple-min=covered"
