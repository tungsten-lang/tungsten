# Exact arbitrary-cardinality partial-automorphism relations.
#
# For one tensor automorphism phi, every term has a complete tensor delta
# d(t)=t XOR phi(t).  A binary nullspace vector of these deltas identifies a
# subset that can be transformed atomically without changing the represented
# tensor.  The existing hot enumerator closes subsets of size 2--4; this
# elimination closes every cardinality at once.  The all-term vector is always
# present for an exact matrix-multiplication scheme, so useful tunneling begins
# only when the kernel contains a non-stable proper subset.

use partial_automorphism

-> ffpan_coeff_words(count) (i64) i64
  (count + 63) / 64

# Production policy helpers live beside the algebra so the coordinator's
# low-cadence gate and generator rotation can be contract-tested without
# importing the executable `fleet.w` coordinator.
-> ffpan_tunnel_due(n, now_ms, last_ms, cooldown_ms) (i64 i64 i64 i64) i64
  if n != 7
    return 0
  cooldown = cooldown_ms ## i64
  if cooldown < 1
    cooldown = 1
  if last_ms < 0
    return 1
  if now_ms < last_ms
    return 0
  if now_ms - last_ms >= cooldown
    return 1
  0

-> ffpan_next_nonce(n, nonce, stride) (i64 i64 i64) i64
  total = ffpan_elementary_count(n) ## i64
  if total < 1
    return 0
  current = nonce % total ## i64
  if current < 0
    current += total
  step = stride % total ## i64
  if step < 0
    step += total
  (current + step) % total

# The retained 7x7 workspace measures about 5--6 ms for the algebraic finder
# on the reference host.  Full archive + MAP intake is the dominant cost at
# roughly 0.2 s when both gates execute, so a fifteen-second coordinator
# cadence keeps this exact tunnel portfolio near one percent duty without
# leaving a two-hour campaign with only a handful of source visits.
-> ffpan_tunnel_cooldown_ms(n) (i64) i64
  if n == 7
    return 15000
  60000

# Deterministic source x generator portfolio for low-cadence 7x7 tunneling.
#
# The previous production loop always scanned the density leader and advanced
# one global nonce.  Rotating sources with that same global nonce would visit
# only 63 of 189 generator starts per source (15*37 mod 189 has gcd 3).  Decode
# instead derives a per-source visit number, so every retained frontier sees
# the full coprime stride-37 cycle.
#
# `campaign_nonce` phases both the source order and one of three disjoint
# 63-start generator arcs.  The AWS three-shard supervisor supplies nonces
# 1,2,3, so equal frontier snapshots do useful complementary work from their
# first call while nonce zero preserves the historical first source/start.
# out = source index, generator start nonce, per-source visit number.
-> ffpan_portfolio_decode(n, source_count, completed, campaign_nonce, out) (i64 i64 i64 i64 i64[]) i64
  if n != 7 || source_count < 1 || completed < 0 || out.size() < 3
    return 0
  total = ffpan_elementary_count(n) ## i64
  if total < 1 || (total % 3) != 0
    return 0
  source_phase = campaign_nonce % source_count ## i64
  shard_phase = campaign_nonce % 3 ## i64
  if source_phase < 0
    source_phase += source_count
  if shard_phase < 0
    shard_phase += 3
  visit = completed / source_count ## i64
  source_offset = completed % source_count ## i64
  out[0] = (source_offset + source_phase) % source_count
  out[1] = (shard_phase * (total / 3) + visit * 37) % total
  out[2] = visit
  1

-> ffpan_clear(row, length) (i64[] i64) i64
  i = 0 ## i64
  while i < length
    row[i] = 0
    i += 1
  length

-> ffpan_copy(source, source_offset, target, target_offset, length) (i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < length
    target[target_offset + i] = source[source_offset + i]
    i += 1
  length

-> ffpan_xor_into(target, target_offset, source, source_offset, length) (i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < length
    target[target_offset + i] = target[target_offset + i] ^ source[source_offset + i]
    i += 1
  length

-> ffpan_first_pivot(row, length) (i64[] i64) i64
  word = 0 ## i64
  while word < length
    value = row[word] ## i64
    if value != 0
      bit = 0 ## i64
      while bit < 64
        if ((value >> bit) & 1) != 0
          return word * 64 + bit
        bit += 1
    word += 1
  0 - 1

# Scratch sizes:
#   dependencies >= count*ceil(count/64)
#   basis_rows >= count*words
#   basis_coefficients >= count*ceil(count/64)
#   pivot_owners >= words*64 (i32, zero means unused)
#   work >= words; work_coefficients >= ceil(count/64)
# meta: independent rank, nullity, basis XORs, pivot probes.
-> ffpan_nullspace_into(deltas, count, words, dependencies, basis_rows, basis_coefficients, pivot_owners, work, work_coefficients, meta) (i64[] i64 i64 i64[] i64[] i64[] i32[] i64[] i64[] i64[]) i64
  if count < 1 || words < 1 || meta.size() < 4
    return 0 - 1
  coefficient_words = ffpan_coeff_words(count) ## i64
  if deltas.size() < count * words || dependencies.size() < count * coefficient_words
    return 0 - 1
  if basis_rows.size() < count * words || basis_coefficients.size() < count * coefficient_words
    return 0 - 1
  if pivot_owners.size() < words * 64 || work.size() < words || work_coefficients.size() < coefficient_words
    return 0 - 1

  i = 0 ## i64
  while i < words * 64
    pivot_owners[i] = 0
    i += 1
  basis_count = 0 ## i64
  nullity = 0 ## i64
  xor_count = 0 ## i64
  pivot_probes = 0 ## i64
  input = 0 ## i64
  while input < count
    ffpan_copy(deltas, input * words, work, 0, words)
    ffpan_clear(work_coefficients, coefficient_words)
    work_coefficients[input / 64] = 1 << (input % 64)
    placed = 0 ## i64
    while placed == 0
      pivot = ffpan_first_pivot(work, words) ## i64
      pivot_probes += 1
      if pivot < 0
        ffpan_copy(work_coefficients, 0, dependencies, nullity * coefficient_words, coefficient_words)
        nullity += 1
        placed = 1
      else
        owner = pivot_owners[pivot] ## i64
        if owner == 0
          ffpan_copy(work, 0, basis_rows, basis_count * words, words)
          ffpan_copy(work_coefficients, 0, basis_coefficients, basis_count * coefficient_words, coefficient_words)
          pivot_owners[pivot] = basis_count + 1
          basis_count += 1
          placed = 1
        else
          basis = owner - 1 ## i64
          ffpan_xor_into(work, 0, basis_rows, basis * words, words)
          ffpan_xor_into(work_coefficients, 0, basis_coefficients, basis * coefficient_words, coefficient_words)
          xor_count += 1
    input += 1
  meta[0] = basis_count
  meta[1] = nullity
  meta[2] = xor_count
  meta[3] = pivot_probes
  if basis_count + nullity != count
    return 0 - 1
  nullity

-> ffpan_nullspace(deltas, count, words, dependencies, meta) (i64[] i64 i64 i64[] i64[]) i64
  coefficient_words = ffpan_coeff_words(count) ## i64
  basis_rows = i64[count * words]
  basis_coefficients = i64[count * coefficient_words]
  pivot_owners = i32[words * 64]
  work = i64[words]
  work_coefficients = i64[coefficient_words]
  ffpan_nullspace_into(deltas, count, words, dependencies, basis_rows, basis_coefficients, pivot_owners, work, work_coefficients, meta)

-> ffpan_dependency_weight(dependencies, dependency, count) (i64[] i64 i64) i64
  coefficient_words = ffpan_coeff_words(count) ## i64
  weight = 0 ## i64
  word = 0 ## i64
  while word < coefficient_words
    weight += ffw_popcount(dependencies[dependency * coefficient_words + word])
    word += 1
  weight

-> ffpan_dependency_ids(dependencies, dependency, count, ids) (i64[] i64 i64 i64[]) i64
  coefficient_words = ffpan_coeff_words(count) ## i64
  made = 0 ## i64
  index = 0 ## i64
  while index < count
    value = dependencies[dependency * coefficient_words + index / 64] ## i64
    if ((value >> (index % 64)) & 1) != 0
      ids[made] = index
      made += 1
    index += 1
  made

# Reusable production scratch for whole-frontier elementary automorphism
# tunnels.  A fleet should retain one workspace per coordinating thread; the
# n^6 rows are intentionally not reallocated for every generator.
+ FFPANWorkspace
  -> new(rank, n, capacity)
    @config = i64[5]
    @config[0] = rank
    @config[1] = n
    @config[2] = capacity
    @config[3] = rank
    @config[4] = 0
    words = ffpa_tensor_words(n) ## i64
    coefficient_words = ffpan_coeff_words(rank) ## i64
    @transformed_u = i64[capacity]
    @transformed_v = i64[capacity]
    @transformed_w = i64[capacity]
    @deltas = i64[rank * words]
    @dependencies = i64[rank * coefficient_words]
    @basis_rows = i64[rank * words]
    @basis_coefficients = i64[rank * coefficient_words]
    @pivot_owners = i32[words * 64]
    @work = i64[words]
    @work_coefficients = i64[coefficient_words]
    @ids = i64[rank]
    @raw_u = i64[capacity]
    @raw_v = i64[capacity]
    @raw_w = i64[capacity]
    @endpoint = i64[ffw_state_size(capacity)]
    @decoded = i64[4]
    @nullspace_meta = i64[4]

  -> rank()
    @config[0]
  -> n()
    @config[1]
  -> capacity()
    @config[2]
  -> max_rank()
    @config[3]
  -> scan_count()
    @config[4]
  -> configure_rank(rank)
    if rank < 2 || rank > @config[3]
      return 0
    @config[0] = rank
    rank
  -> begin_scan()
    @config[4] = @config[4] + 1
    @config[4]
  -> transformed_u()
    @transformed_u
  -> transformed_v()
    @transformed_v
  -> transformed_w()
    @transformed_w
  -> deltas()
    @deltas
  -> dependencies()
    @dependencies
  -> basis_rows()
    @basis_rows
  -> basis_coefficients()
    @basis_coefficients
  -> pivot_owners()
    @pivot_owners
  -> work()
    @work
  -> work_coefficients()
    @work_coefficients
  -> ids()
    @ids
  -> raw_u()
    @raw_u
  -> raw_v()
    @raw_v
  -> raw_w()
    @raw_w
  -> endpoint()
    @endpoint
  -> decoded()
    @decoded
  -> nullspace_meta()
    @nullspace_meta

-> ffpan_row_zero(rows, offset, words) (i64[] i64 i64) i64
  zero = 1 ## i64
  word = 0 ## i64
  while word < words && zero == 1
    if rows[offset + word] != 0
      zero = 0
    word += 1
  zero

-> ffpan_copy_terms(source_u, source_v, source_w, target_u, target_v, target_w, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    target_u[i] = source_u[i]
    target_v[i] = source_v[i]
    target_w[i] = source_w[i]
    i += 1
  count

# Source schemes and parity-compacted endpoints are term sets, so a simple
# unique-set intersection is sufficient and avoids allocating a `used` array
# for every quotient check.
-> ffpan_term_set_distance_unique(left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left_count
    found = 0 ## i64
    j = 0 ## i64
    while j < right_count && found == 0
      if left_u[i] == right_u[j] && left_v[i] == right_v[j] && left_w[i] == right_w[j]
        found = 1
        common += 1
      j += 1
    i += 1
  left_count + right_count - common - common

-> ffpan_parity_compact(raw_u, raw_v, raw_w, raw_count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < raw_count
    if raw_u[i] == 0 || raw_v[i] == 0 || raw_w[i] == 0
      return 0 - 1
    found = 0 - 1 ## i64
    j = 0 ## i64
    while j < count && found < 0
      if raw_u[i] == out_u[j] && raw_v[i] == out_v[j] && raw_w[i] == out_w[j]
        found = j
      j += 1
    if found >= 0
      count -= 1
      if found < count
        out_u[found] = out_u[count]
        out_v[found] = out_v[count]
        out_w[found] = out_w[count]
    if found < 0
      out_u[count] = raw_u[i]
      out_v[count] = raw_v[i]
      out_w[count] = raw_w[i]
      count += 1
    i += 1
  count

-> ffpan_elementary_count(n) (i64) i64
  # Three domains times C(n,2) swaps plus three times n(n-1) shears.
  3 * n * (n - 1) / 2 + 3 * n * (n - 1)

# Decode the canonical flat order used by the benchmark and production
# scanner. out = operation, domain, source, target.
-> ffpan_elementary_decode(n, index, out) (i64 i64 i64[]) i64
  if n < 2 || n > 7 || out.size() < 4 || index < 0 || index >= ffpan_elementary_count(n)
    return 0
  pair_count = n * (n - 1) / 2 ## i64
  swap_count = 3 * pair_count ## i64
  if index < swap_count
    out[0] = 0
    out[1] = index / pair_count
    wanted = index % pair_count ## i64
    pair = 0 ## i64
    left = 0 ## i64
    while left < n - 1
      right = left + 1 ## i64
      while right < n
        if pair == wanted
          out[2] = left
          out[3] = right
        pair += 1
        right += 1
      left += 1
    return 1
  local = index - swap_count ## i64
  ordered = n * (n - 1) ## i64
  out[0] = 1
  out[1] = local / ordered
  pair = local % ordered
  source = pair / (n - 1) ## i64
  target = pair % (n - 1) ## i64
  if target >= source
    target += 1
  out[2] = source
  out[3] = target
  1

# Find one genuine elementary-automorphism tunnel.  `nonce` rotates the
# generator order, allowing repeated low-frequency calls to knock on different
# doors.  `min_weight=5` excludes the 2/3/4-term moves already covered by the
# bounded partial-automorphism enumerator.
#
# An apparent proper dependency is not admitted until its fully materialized,
# parity-compacted endpoint is independently n^6-gated and compared exactly
# with both the source set and the whole-scheme automorphism image.  This last
# quotient rejects, for example, the apparent weight-55 5x5 relation whose
# omitted two-term complement is set-stable and therefore yields only the
# global image.
#
# meta: operations, nullity sum, bases, apparent proper, source quotients,
# global quotients, genuine, chosen weight, operation, domain, source, target,
# source distance, global distance, exact gates, failures, selected nonstable,
# total nonstable.
-> ffpan_find_elementary_escape(us, vs, ws, rank, n, capacity, nonce, min_weight, workspace, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 FFPANWorkspace i64[] i64[] i64[] i64[]) i64
  if meta.size() < 18 || rank < 2 || rank > capacity || n < 2 || n > 7
    return 0 - 1
  i = 0 ## i64
  while i < 18
    meta[i] = 0
    i += 1
  meta[8] = 0 - 1
  meta[9] = 0 - 1
  meta[10] = 0 - 1
  meta[11] = 0 - 1
  if workspace == nil || workspace.rank() != rank || workspace.n() != n || workspace.capacity() < capacity
    return 0 - 1
  if out_u.size() < capacity || out_v.size() < capacity || out_w.size() < capacity
    return 0 - 1
  workspace.begin_scan()
  if min_weight < 2
    min_weight = 2

  transformed_u = workspace.transformed_u()
  transformed_v = workspace.transformed_v()
  transformed_w = workspace.transformed_w()
  deltas = workspace.deltas()
  dependencies = workspace.dependencies()
  basis_rows = workspace.basis_rows()
  basis_coefficients = workspace.basis_coefficients()
  pivot_owners = workspace.pivot_owners()
  work = workspace.work()
  work_coefficients = workspace.work_coefficients()
  ids = workspace.ids()
  raw_u = workspace.raw_u()
  raw_v = workspace.raw_v()
  raw_w = workspace.raw_w()
  endpoint = workspace.endpoint()
  words = ffpa_tensor_words(n) ## i64
  total = ffpan_elementary_count(n) ## i64
  start = nonce % total ## i64
  if start < 0
    start += total
  decoded = workspace.decoded()
  nullspace_meta = workspace.nullspace_meta()
  step = 0 ## i64
  while step < total
    flat = (start + step) % total ## i64
    if ffpan_elementary_decode(n, flat, decoded) != 1
      return 0 - 1
    operation = decoded[0] ## i64
    domain = decoded[1] ## i64
    source = decoded[2] ## i64
    target = decoded[3] ## i64
    built = ffpa_build_deltas_kind(us, vs, ws, rank, n, operation, domain, source, target, transformed_u, transformed_v, transformed_w, deltas) ## i64
    meta[0] = meta[0] + 1
    if built != words
      meta[15] = meta[15] + 1
    if built == words
      nullity = ffpan_nullspace_into(deltas, rank, words, dependencies, basis_rows, basis_coefficients, pivot_owners, work, work_coefficients, nullspace_meta) ## i64
      if nullity < 0
        meta[15] = meta[15] + 1
      if nullity >= 0
        meta[1] = meta[1] + nullity
        stable_terms = 0 ## i64
        i = 0
        while i < rank
          stable_terms += ffpan_row_zero(deltas, i * words, words)
          i += 1
        nonstable_terms = rank - stable_terms ## i64
        dependency = 0 ## i64
        while dependency < nullity
          meta[2] = meta[2] + 1
          weight = ffpan_dependency_weight(dependencies, dependency, rank) ## i64
          made = ffpan_dependency_ids(dependencies, dependency, rank, ids) ## i64
          if weight >= min_weight && ffpa_relation_exact(deltas, ids, made, words) == 1
            selected_nonstable = 0 ## i64
            selected = 0 ## i64
            while selected < made
              if ffpan_row_zero(deltas, ids[selected] * words, words) == 0
                selected_nonstable += 1
              selected += 1
            apparent = 0 ## i64
            if selected_nonstable > 0 && selected_nonstable < nonstable_terms
              if ffpa_selected_image_same_set(us, vs, ws, transformed_u, transformed_v, transformed_w, ids, made) == 0
                apparent = 1
            if apparent == 1
              meta[3] = meta[3] + 1
              z = ffpan_copy_terms(us, vs, ws, raw_u, raw_v, raw_w, rank) ## i64
              selected = 0
              while selected < made
                position = ids[selected] ## i64
                raw_u[position] = transformed_u[position]
                raw_v[position] = transformed_v[position]
                raw_w[position] = transformed_w[position]
                selected += 1
              endpoint_rank = ffpan_parity_compact(raw_u, raw_v, raw_w, rank, out_u, out_v, out_w) ## i64
              full_exact = 0 ## i64
              if endpoint_rank > 0 && endpoint_rank <= capacity
                loaded = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, endpoint_rank, n, capacity, 870011 + flat * 17 + nonce * 31, 0, 1, 1, 1) ## i64
                if loaded == endpoint_rank && ffw_verify_current_exact(endpoint, n) == 1
                  full_exact = 1
                  meta[14] = meta[14] + 1
              if full_exact == 0
                meta[15] = meta[15] + 1
              if full_exact == 1
                source_distance = ffpan_term_set_distance_unique(us, vs, ws, rank, out_u, out_v, out_w, endpoint_rank) ## i64
                global_distance = ffpan_term_set_distance_unique(transformed_u, transformed_v, transformed_w, rank, out_u, out_v, out_w, endpoint_rank) ## i64
                if source_distance == 0
                  meta[4] = meta[4] + 1
                if source_distance != 0 && global_distance == 0
                  meta[5] = meta[5] + 1
                if source_distance != 0 && global_distance != 0
                  meta[6] = meta[6] + 1
                  meta[7] = weight
                  meta[8] = operation
                  meta[9] = domain
                  meta[10] = source
                  meta[11] = target
                  meta[12] = source_distance
                  meta[13] = global_distance
                  meta[16] = selected_nonstable
                  meta[17] = nonstable_terms
                  return endpoint_rank
          dependency += 1
    step += 1
  0
