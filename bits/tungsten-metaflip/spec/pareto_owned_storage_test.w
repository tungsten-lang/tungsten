use ../lib/metaflip/fleet/banks

-> expect(label, condition) (String bool) i64
  if !condition
    << "FAIL owned Pareto bank: " + label
    exit(1)
  1

-> new_bank()
  [[], [], [], [], [], [], [], i64[4], []]

-> offer(bank, candidate, best, capacity, size, owned, seed) i64
  if owned == 1
    return ffbp_pareto_add(bank[0], bank[1], bank[2], bank[3], bank[4], bank[5], bank[6], candidate, best, capacity, seed % 11, bank[7], bank[8], size, seed)
  ffbp_pareto_add(bank[0], bank[1], bank[2], bank[3], bank[4], bank[5], bank[6], candidate, best, capacity, seed % 11, bank[7])

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
paths = ["matmul_2x2_rank7_strassen_gf2.txt", "matmul_2x2_rank7_d36_gl120_gf2.txt", "matmul_2x2_rank7_d36_gl190_gf2.txt", "matmul_2x2_rank7_d40_gl01_gf2.txt", "matmul_2x2_rank7_d40_gl108_gf2.txt", "matmul_2x2_rank7_d42_gl08_gf2.txt"]
size = ffw_state_size(32) ## i64
fixtures = []
naive = i64[size]
z = ffw_init_naive_cap(naive, 2, 32, 719, 8, 100, 1000000, 1000000)
fixtures.push(naive)
i = 0 ## i64
while i < paths.size()
  state = i64[size]
  z = expect("fixture load", ffw_load_scheme_cap(state, root + paths[i], 2, 32, 819 + i, 8, 100, 1000000, 1000000) == 7)
  fixtures.push(state)
  i += 1
best = fixtures[1]
capacity = 1 ## i64
while capacity <= 4
  reference = new_bank()
  owned = new_bank()
  candidate = i64[size]
  turn = 0 ## i64
  while turn < 120
    source = fixtures[(turn * 5) % fixtures.size()]
    old_candidate = i64[size]
    z = ffw_reseed_from(old_candidate, source, 919 + turn)
    z = ffw_reseed_from(candidate, source, 919 + turn)
    old_action = offer(reference, old_candidate, best, capacity, size, 0, 919 + turn) ## i64
    new_action = offer(owned, candidate, best, capacity, size, 1, 919 + turn) ## i64
    z = expect("same admission", old_action == new_action)
    z = expect("bounded live plus free buffers", owned[0].size() + owned[8].size() <= capacity)
    z = expect("same bank size", reference[0].size() == owned[0].size())
    field = 1 ## i64
    while field <= 7
      z = expect("same metadata and counters", reference[field] == owned[field])
      field += 1
    # Reusing the GPU intake buffer cannot mutate admitted bank storage.
    z = ffw_init_naive_cap(candidate, 2, 32, 1019 + turn, 8, 100, 1000000, 1000000)
    i = 0
    while i < owned[0].size()
      z = expect("same owned best", ffbp_distance(reference[0][i], owned[0][i]) == 0)
      z = expect("exact owned best", ffw_verify_best_exact(owned[0][i], 2) == 1)
      i += 1
    if turn % 19 == 18
      # A generation reset returns every live slot to the same free list.
      while owned[0].size() > 0
        z = ffbp_pareto_remove(owned[0], owned[1], owned[2], owned[3], owned[4], owned[5], owned[6], owned[0].size() - 1, owned[8])
        z = ffbp_pareto_remove(reference[0], reference[1], reference[2], reference[3], reference[4], reference[5], reference[6], reference[0].size() - 1)
    turn += 1
  capacity += 1
<< "PASS owned Pareto bank: 480 reference-policy comparisons, reusable intake isolation, rank drops, resets, capacity high-water bound"
