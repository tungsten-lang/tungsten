# Runtime-generic pure-Tungsten metaflip worker for the canonical rectangular
# campaign profiles.
#
# The square campaign retains its specialized hot path and public 2..7 CLI;
# its shared state envelope also admits n=2 for the rectangular 2x2x5,
# 2x2x6, 2x3x4, 2x3x5, 2x4x5, and 2x5x6 profiles.
# This module reuses that representation, hash table, and generic flip engine,
# while supplying rectangular import, exhaustive verification, and axis-aware
# split logic.  A rectangular state stores n,m,p packed into header word 3;
# callers must use the ffr_* entry points for initialization, splitting, exact
# verification, and dumping.
#
# Stable child/coordinator surface:
#
#   ffr_supported(n,m,p)
#   ffr_default_capacity(n,m,p)
#   ffr_state_size(capacity)
#   ffr_init_naive_cap(st,n,m,p,cap,seed,dslack,cycles,workq,wanderq)
#   ffr_init_terms_cap(st,us,vs,ws,rank,n,m,p,cap,...)
#   ffr_load_scheme_cap(st,path,n,m,p,cap,...)
#   ffr_verify_current_exact / ffr_verify_best_exact(st,n,m,p)
#   ffr_walk / ffr_work / ffr_wander(st,steps)
#   ffr_dump_best / ffr_dump_current(st,path)
#
# Scheme files use the same format as square FlipFleet seeds: a rank line
# followed by decimal `u v w` factor-mask triples.  `R u v w` lines are also
# accepted for compatibility with the FMM catalogue.

use metaflip_worker
use flipfleet_rect_profiles

-> ffr_supported(n, m, p) (i64 i64 i64) i64
  ffrp_supported(n, m, p)

-> ffr_pack_shape(n, m, p) (i64 i64 i64) i64
  # Four bits per axis admit the p=8 sensitivity profiles while leaving ample
  # room in one header word. This header is in-memory only; scheme files do
  # not serialize it.
  packed = n + m * 16 + p * 256 ## i64
  packed

-> ffr_shape_n(st) (i64[]) i64
  st[3] & 15

-> ffr_shape_m(st) (i64[]) i64
  (st[3] >> 4) & 15

-> ffr_shape_p(st) (i64[]) i64
  (st[3] >> 8) & 15

-> ffr_u_width(st) (i64[]) i64
  ffr_shape_n(st) * ffr_shape_m(st)

-> ffr_v_width(st) (i64[]) i64
  ffr_shape_m(st) * ffr_shape_p(st)

-> ffr_w_width(st) (i64[]) i64
  ffr_shape_n(st) * ffr_shape_p(st)

-> ffr_valid(st) (i64[]) i64
  ok = ffw_valid(st) ## i64
  if ok == 1
    ok = ffr_supported(ffr_shape_n(st), ffr_shape_m(st), ffr_shape_p(st))
  ok

-> ffr_default_capacity(n, m, p) (i64 i64 i64) i64
  # Enough shoulder for variable-rank wandering without bloating child state.
  n * m * p + 4 * (n * m + m * p + n * p) + 64

-> ffr_state_size(capacity) (i64) i64
  ffw_state_size(capacity)

-> ffr_current_rank(st) (i64[]) i64
  ffw_current_rank(st)

-> ffr_best_rank(st) (i64[]) i64
  ffw_best_rank(st)

-> ffr_current_bits(st) (i64[]) i64
  ffw_current_bits(st)

-> ffr_best_bits(st) (i64[]) i64
  ffw_best_bits(st)

-> ffr_moves(st) (i64[]) i64
  ffw_moves(st)

-> ffr_prepare(st, n, m, p, capacity, seed, dslack, cycles, workq, wanderq) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ok = ffr_supported(n, m, p) ## i64
  if ok == 1
    # ffw_prepare validates the leading dimension and establishes the stable
    # flat-state layout.  Word 3 is replaced with our packed rectangular shape;
    # generic flips do not read it and rectangular splits never call ffw split.
    ok = ffw_prepare(st, n, capacity, seed, dslack, cycles, workq, wanderq)
  if ok == 1
    st[3] = ffr_pack_shape(n, m, p)
  ok

-> ffr_factor_mask(width) (i64) i64
  (1 << width) - 1

-> ffr_view_error(st, uo, vo, wo, liveo, rank, n, m, p) (i64[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  error = 0 ## i64
  uw = n * m ## i64
  vw = m * p ## i64
  ww = n * p ## i64
  umask = ffr_factor_mask(uw) ## i64
  vmask = ffr_factor_mask(vw) ## i64
  wmask = ffr_factor_mask(ww) ## i64
  if ffr_supported(n, m, p) == 0
    error = 0 - 1
  if rank < 1
    error = 0 - 2
  if rank > st[4]
    error = 0 - 3
  t = 0 ## i64
  while t < rank && error == 0
    slot = t ## i64
    if liveo >= 0
      slot = st[liveo + t]
    u = st[uo + slot] ## i64
    v = st[vo + slot] ## i64
    w = st[wo + slot] ## i64
    if u <= 0 || (u & umask) != u
      error = 0 - 10
    if v <= 0 || (v & vmask) != v
      error = 0 - 11
    if w <= 0 || (w & wmask) != w
      error = 0 - 12
    t += 1

  # Exhaust all (nm)(mp)(np) tensor coefficients.  The largest current profile
  # has 10,000 coefficients and 760,000 rank-one term probes, so no
  # probabilistic gate is needed.
  ai = 0 ## i64
  while ai < uw && error == 0
    bi = 0 ## i64
    while bi < vw && error == 0
      ci = 0 ## i64
      while ci < ww && error == 0
        got = 0 ## i64
        t = 0
        while t < rank
          slot = t
          if liveo >= 0
            slot = st[liveo + t]
          if ((st[uo + slot] >> ai) & 1) == 1
            if ((st[vo + slot] >> bi) & 1) == 1
              if ((st[wo + slot] >> ci) & 1) == 1
                got = got ^ 1
          t += 1
        arow = ai / m ## i64
        acol = ai % m ## i64
        brow = bi / p ## i64
        bcol = bi % p ## i64
        crow = ci / p ## i64
        ccol = ci % p ## i64
        want = 0 ## i64
        if acol == brow && arow == crow && bcol == ccol
          want = 1
        if got != want
          error = 1 + (ai * vw + bi) * ww + ci
        ci += 1
      bi += 1
    ai += 1
  error

-> ffr_verify_current_exact(st, n, m, p) (i64[] i64 i64 i64) i64
  ok = 0 ## i64
  st[29] = st[29] + 1
  if ffr_valid(st) == 1
    if ffr_shape_n(st) == n && ffr_shape_m(st) == m && ffr_shape_p(st) == p
      if ffr_view_error(st, st[44], st[45], st[46], st[50], st[6], n, m, p) == 0
        ok = 1
  st[38] = ok
  if ok == 0
    st[30] = st[30] + 1
  ok

-> ffr_verify_best_exact(st, n, m, p) (i64[] i64 i64 i64) i64
  ok = 0 ## i64
  st[29] = st[29] + 1
  if ffr_valid(st) == 1
    if ffr_shape_n(st) == n && ffr_shape_m(st) == m && ffr_shape_p(st) == p
      if st[7] > 0
        if ffr_view_error(st, st[47], st[48], st[49], 0 - 1, st[7], n, m, p) == 0
          ok = 1
  st[38] = ok
  if ok == 0
    st[30] = st[30] + 1
  ok

-> ffr_adopt_current(st, allow_density_tie) (i64[] i64) i64
  result = 0 ## i64
  rank = st[6] ## i64
  best = st[7] ## i64
  bits = ffw_view_bits(st, st[44], st[45], st[46], st[50], rank) ## i64
  useful = 0 ## i64
  if best < 0 || rank < best
    useful = 1
  if allow_density_tie != 0 && rank == best && bits < st[36]
    useful = 1
  if useful == 1
    exact = ffr_verify_current_exact(st, ffr_shape_n(st), ffr_shape_m(st), ffr_shape_p(st)) ## i64
    if exact == 1
      old_best = best ## i64
      z = ffw_copy_current_to_best(st) ## i64
      st[25] = st[25] + 1
      st[33] = st[33] + 1
      result = 1
      if old_best >= 0 && rank < old_best
        st[24] = st[24] + 1
        result = 2
      st[10] = st[40]
      st[14] = st[13] + st[18]
    if exact == 0
      result = 0 - 1
      if best > 0
        z = ffw_restore_best(st)
  result

-> ffr_init_naive_cap(st, n, m, p, capacity, seed, dslack, cycles, workq, wanderq) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ok = ffr_prepare(st, n, m, p, capacity, seed, dslack, cycles, workq, wanderq) ## i64
  result = 0 - 1 ## i64
  if ok == 1
    rank = 0 ## i64
    i = 0 ## i64
    while i < n
      j = 0 ## i64
      while j < m
        k = 0 ## i64
        while k < p
          u = 1 << (i * m + j) ## i64
          v = 1 << (j * p + k) ## i64
          w = 1 << (i * p + k) ## i64
          rank = ffw_toggle(st, u, v, w, rank)
          k += 1
        j += 1
      i += 1
    st[6] = rank
    adopted = ffr_adopt_current(st, 1) ## i64
    if adopted > 0
      result = rank
  result

-> ffr_init_terms_cap(st, us, vs, ws, rank, n, m, p, capacity, seed, dslack, cycles, workq, wanderq) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ok = 1 ## i64
  if rank < 1 || rank > capacity
    ok = 0
  if ok == 1
    ok = ffr_prepare(st, n, m, p, capacity, seed, dslack, cycles, workq, wanderq)
  result = 0 - 1 ## i64
  if ok == 1
    umask = ffr_factor_mask(n * m) ## i64
    vmask = ffr_factor_mask(m * p) ## i64
    wmask = ffr_factor_mask(n * p) ## i64
    current = 0 ## i64
    i = 0 ## i64
    while i < rank
      valid = 1 ## i64
      if us[i] <= 0 || (us[i] & umask) != us[i]
        valid = 0
      if vs[i] <= 0 || (vs[i] & vmask) != vs[i]
        valid = 0
      if ws[i] <= 0 || (ws[i] & wmask) != ws[i]
        valid = 0
      if valid == 1
        current = ffw_toggle(st, us[i], vs[i], ws[i], current)
      if valid == 0
        ok = 0
      i += 1
    st[6] = current
    if current != rank
      ok = 0
    if ok == 1
      adopted = ffr_adopt_current(st, 1) ## i64
      if adopted > 0
        st[31] = st[31] + 1
        result = current
      if adopted <= 0
        ok = 0
    if ok == 0
      st[39] = st[39] + 1
  result

-> ffr_load_scheme_cap(st, path, n, m, p, capacity, seed, dslack, cycles, workq, wanderq) (i64[] String i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  result = 0 - 1 ## i64
  content = read_file(path)
  if content != nil
    lines = content.split("\n")
    if lines.size() > 0
      line_base = 1 ## i64
      field_base = 0 ## i64
      rank = lines[0].to_i() ## i64
      first = lines[0].split(" ")
      if first.size() >= 4 && first[0] == "R"
        line_base = 0
        field_base = 1
        rank = lines.size()
        if rank > 0 && lines[rank - 1].size() == 0
          rank -= 1
      # Some imported catalog files retain both a numeric rank header and
      # `R u v w` row prefixes. Accept that unambiguous mixed spelling too;
      # the rank header remains authoritative and every row is still checked.
      if line_base == 1 && lines.size() > 1
        first_row = lines[1].split(" ")
        if first_row.size() >= 4 && first_row[0] == "R"
          field_base = 1
      ok = 1 ## i64
      if rank < 1 || rank > capacity || lines.size() < rank + line_base
        ok = 0
      if ok == 1
        ok = ffr_prepare(st, n, m, p, capacity, seed, dslack, cycles, workq, wanderq)
      if ok == 1
        umask = ffr_factor_mask(n * m) ## i64
        vmask = ffr_factor_mask(m * p) ## i64
        wmask = ffr_factor_mask(n * p) ## i64
        current = 0 ## i64
        i = 0 ## i64
        while i < rank
          parts = lines[i + line_base].split(" ")
          valid = 1 ## i64
          if parts.size() < field_base + 3
            valid = 0
          if valid == 1
            u = ffw_parse_decimal_i64(parts[field_base]) ## i64
            v = ffw_parse_decimal_i64(parts[field_base + 1]) ## i64
            w = ffw_parse_decimal_i64(parts[field_base + 2]) ## i64
            if u <= 0 || (u & umask) != u
              valid = 0
            if v <= 0 || (v & vmask) != v
              valid = 0
            if w <= 0 || (w & wmask) != w
              valid = 0
            if valid == 1
              current = ffw_toggle(st, u, v, w, current)
          if valid == 0
            ok = 0
          i += 1
        st[6] = current
        if current != rank
          ok = 0
        if ok == 1
          adopted = ffr_adopt_current(st, 1) ## i64
          if adopted > 0
            st[31] = st[31] + 1
            result = current
          if adopted <= 0
            ok = 0
        if ok == 0
          st[39] = st[39] + 1
  result

-> ffr_try_split(st) (i64[]) i64
  st[20] = st[20] + 1
  st[27] = st[27] + 1
  result = 0 ## i64
  rank_before = st[6] ## i64
  if rank_before >= st[4]
    st[22] = st[22] + 1
  if rank_before < st[4]
    word = ffw_rand31(st) ## i64
    rank_index = (word * rank_before) >> 31 ## i64
    slot = st[st[50] + rank_index] ## i64
    u = st[st[44] + slot] ## i64
    v = st[st[45] + slot] ## i64
    w = st[st[46] + slot] ## i64
    word = ffw_rand31(st)
    axis = (((word >> 22) & 511) * 3) >> 9 ## i64
    width = ffr_u_width(st) ## i64
    factor = u ## i64
    if axis == 1
      width = ffr_v_width(st)
      factor = v
    if axis == 2
      width = ffr_w_width(st)
      factor = w
    high = ffw_rand31(st) ## i64
    low = ffw_rand31(st) ## i64
    part = ((high << 31) ^ low) & ffr_factor_mask(width) ## i64
    if part == 0
      part = 1
    if part == factor
      part = part ^ 1
      if part == 0
        part = 2
    au = u ## i64
    av = v ## i64
    aw = w ## i64
    bu = u ## i64
    bv = v ## i64
    bw = w ## i64
    if axis == 0
      au = part
      bu = factor ^ part
    if axis == 1
      av = part
      bv = factor ^ part
    if axis == 2
      aw = part
      bw = factor ^ part
    rank = rank_before ## i64
    rank = ffw_toggle(st, u, v, w, rank)
    rank = ffw_toggle(st, au, av, aw, rank)
    rank = ffw_toggle(st, bu, bv, bw, rank)
    accept = 0 ## i64
    if rank <= st[7] + st[10]
      accept = 1
    if accept == 0
      rank = ffw_toggle(st, u, v, w, rank)
      rank = ffw_toggle(st, au, av, aw, rank)
      rank = ffw_toggle(st, bu, bv, bw, rank)
      st[22] = st[22] + 1
    if accept == 1
      st[6] = rank
      st[21] = st[21] + 1
      st[28] = st[28] + 1
      result = 1
      adopted = ffw_adopt_algebraic(st, 1) ## i64
      if adopted == 2
        result = 2
    if accept == 0
      st[6] = rank_before
  result

-> ffr_one(st, mode) (i64[] i64) i64
  result = 0 ## i64
  do_split = 0 ## i64
  if mode != 0 && st[13] > 0 && (st[13] % 2000) == 0
    do_split = 1
  if do_split == 1
    result = ffr_try_split(st)
  if do_split == 0
    result = ffw_try_flip(st, mode)
  st[13] = st[13] + 1
  st[42] = mode
  if mode == 0
    st[34] = st[34] + 1
  if mode != 0
    st[35] = st[35] + 1
  if st[7] > 0 && st[6] > st[7] + st[10]
    z = ffw_restore_best(st) ## i64
  result

-> ffr_work(st, steps) (i64[] i64) i64
  i = 0 ## i64
  while i < steps
    z = ffr_one(st, 0) ## i64
    i += 1
  st[7]

-> ffr_wander(st, steps) (i64[] i64) i64
  i = 0 ## i64
  while i < steps
    z = ffr_one(st, 1) ## i64
    i += 1
  st[7]

-> ffr_walk(st, steps) (i64[] i64) i64
  i = 0 ## i64
  while i < steps
    mode = 0 ## i64
    if st[10] > st[11]
      mode = 1
    z = ffr_one(st, mode) ## i64
    if st[13] >= st[14]
      z = ffw_advance_zone(st)
    i += 1
  st[7]

-> ffr_dump_best(st, path) (i64[] String) i64
  result = 0 - 1 ## i64
  n = ffr_shape_n(st) ## i64
  m = ffr_shape_m(st) ## i64
  p = ffr_shape_p(st) ## i64
  if ffr_verify_best_exact(st, n, m, p) == 1
    rank = st[7] ## i64
    body = rank.to_s() + "\n"
    i = 0 ## i64
    while i < rank
      body = body + st[st[47] + i].to_s() + " " + st[st[48] + i].to_s() + " " + st[st[49] + i].to_s() + "\n"
      i += 1
    z = write_file(path, body)
    st[32] = st[32] + 1
    result = rank
  result

-> ffr_dump_current(st, path) (i64[] String) i64
  result = 0 - 1 ## i64
  n = ffr_shape_n(st) ## i64
  m = ffr_shape_m(st) ## i64
  p = ffr_shape_p(st) ## i64
  if ffr_verify_current_exact(st, n, m, p) == 1
    rank = st[6] ## i64
    body = rank.to_s() + "\n"
    i = 0 ## i64
    while i < rank
      slot = st[st[50] + i] ## i64
      body = body + st[st[44] + slot].to_s() + " " + st[st[45] + slot].to_s() + " " + st[st[46] + slot].to_s() + "\n"
      i += 1
    z = write_file(path, body)
    st[32] = st[32] + 1
    result = rank
  result
