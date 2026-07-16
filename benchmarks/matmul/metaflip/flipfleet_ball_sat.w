# Hamming-ball anchored rank descent (move 11 intake, lane prefix ffbs_).
#
# EXACT CONTENT.  Fix an exact rank-r anchor scheme c for <n,n,n>.  One
# incremental CDCL instance holds ALL r slots' factor bits as variables
# (3*n^2 per slot) plus one kill indicator z_i per slot:
#
#   products   p(cell, slot) <-> u[a] & v[b] & w[c] & !z_slot
#              (a killed slot contributes nothing anywhere);
#   rows       one XOR row per tensor cell: the XOR of the r gated products
#              equals the matmul coefficient [a=(i,j), b=(j,k), c=(i,k)] --
#              so ANY model is an exact scheme on the non-killed slots;
#   rank drop  at least one z_i is true (clause over the kills), and a
#              killed slot's bits are frozen at the anchor so its distance
#              contribution is zero;
#   ball       distance literal d_q per bit position q (d_q = x_q when the
#              anchor bit is 0, !x_q when it is 1 -- no auxiliary variable),
#              counted by a Sinz sequential counter of width W = b_max + 1
#              encoded ONCE; radius b is imposed per solve through the
#              assumption !s(N, b + 1), so learned clauses persist across
#              the whole radius sweep (the incremental cardinality trick).
#
# VERDICT LABELS (the campaign discipline):
#   SAT           -> decoded, parity-compacted, exhaustively gated scheme of
#                    rank <= r - 1;
#   UNSAT         -> a CERTIFIED rigidity lemma: no exact rank-(r-1) scheme
#                    exists within slot-aligned Hamming distance b of THIS
#                    presentation with THIS slot alignment.  Nothing more.
#   budget-out    -> INDETERMINATE.  Certifies nothing and is labeled so.
#
# Emission order matters: product/counter/freeze clauses use fixed variable
# numbering and are emitted first; the XOR rows run last so ffcdcl_add_xor's
# auxiliaries (allocated above the highest variable referenced so far)
# cannot collide with the fixed map.
#
# ADMISSION.  A SAT model only leaves through ffw_init_terms_cap +
# ffw_verify_current_exact on a fresh worker state, and the driver publishes
# through dump -> re-parse -> re-gate.

use metaflip_worker
use flipfleet_sat_cdcl

# ---------------------------------------------------------------------------
# Variable map

-> ffbs_x_var(slot, axis, pos, nn) (i64 i64 i64 i64) i64
  1 + slot * 3 * nn + axis * nn + pos

-> ffbs_z_var(r, slot, nn) (i64 i64 i64) i64
  1 + r * 3 * nn + slot

-> ffbs_prim(r, nn) (i64 i64) i64
  r * 3 * nn + r

-> ffbs_product_var(r, nn, cell, slot) (i64 i64 i64 i64) i64
  ffbs_prim(r, nn) + 1 + cell * r + slot

# Sinz counter s(i, j), 1-based i in 1..N, j in 1..W.
-> ffbs_counter_var(r, nn, cells, i, j, width) (i64 i64 i64 i64 i64 i64) i64
  ffbs_prim(r, nn) + cells * r + 1 + (i - 1) * width + (j - 1)

-> ffbs_counter_top(r, nn, cells, width) (i64 i64 i64 i64) i64
  ffbs_prim(r, nn) + cells * r + r * 3 * nn * width

# Anchor bit at global distance position q = slot*3*nn + axis*nn + pos.
-> ffbs_anchor_bit(au, av, aw, slot, axis, pos) (i64[] i64[] i64[] i64 i64 i64) i64
  mask = au[slot] ## i64
  if axis == 1
    mask = av[slot]
  if axis == 2
    mask = aw[slot]
  (mask >> pos) & 1

# Distance literal for position q: true iff the bit differs from the anchor.
-> ffbs_distance_lit(au, av, aw, slot, axis, pos, nn) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  x = ffbs_x_var(slot, axis, pos, nn) ## i64
  if ffbs_anchor_bit(au, av, aw, slot, axis, pos) == 1
    return 2 * x + 1
  2 * x

# The matmul coefficient at cell (a, b, c): a = (i, j), b = (j2, k),
# c = (i2, k2); the tensor bit is 1 iff j == j2, i == i2, k == k2.
-> ffbs_coefficient(a, b, c, n) (i64 i64 i64 i64) i64
  i = a / n ## i64
  j = a % n ## i64
  j2 = b / n ## i64
  k = b % n ## i64
  i2 = c / n ## i64
  k2 = c % n ## i64
  if j == j2 && i == i2 && k == k2
    return 1
  0

# ---------------------------------------------------------------------------
# Encoding

# Encode the whole anchored instance.  width = b_max + 1 counter columns.
# Returns 1, or 0 on any arena/plan failure.
-> ffbs_encode(sat, au, av, aw, r, n, width) (i64[] i64[] i64[] i64[] i64 i64 i64) i64
  nn = n * n ## i64
  cells = nn * nn * nn ## i64
  lits = i64[r + 8]
  # Pass 1: gated products (fixed numbering, references every product var).
  cell = 0 ## i64
  while cell < cells
    c = cell % nn ## i64
    rest = cell / nn ## i64
    b = rest % nn ## i64
    a = rest / nn ## i64
    slot = 0 ## i64
    while slot < r
      p = ffbs_product_var(r, nn, cell, slot) ## i64
      xu = ffbs_x_var(slot, 0, a, nn) ## i64
      xv = ffbs_x_var(slot, 1, b, nn) ## i64
      xw = ffbs_x_var(slot, 2, c, nn) ## i64
      zk = ffbs_z_var(r, slot, nn) ## i64
      lits[0] = 2 * p + 1
      lits[1] = 2 * xu
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[1] = 2 * xv
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[1] = 2 * xw
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[1] = 2 * zk + 1
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[0] = 2 * p
      lits[1] = 2 * xu + 1
      lits[2] = 2 * xv + 1
      lits[3] = 2 * xw + 1
      lits[4] = 2 * zk
      if ffcdcl_add_clause(sat, lits, 5) != 1
        return 0
      slot += 1
    cell += 1
  # Pass 2a: at least one kill.
  slot = 0
  while slot < r
    lits[slot] = 2 * ffbs_z_var(r, slot, nn)
    slot += 1
  if ffcdcl_add_clause(sat, lits, r) != 1
    return 0
  # Pass 2b: a killed slot is frozen at the anchor.
  slot = 0
  while slot < r
    zk = ffbs_z_var(r, slot, nn) ## i64
    axis = 0 ## i64
    while axis < 3
      pos = 0 ## i64
      while pos < nn
        x = ffbs_x_var(slot, axis, pos, nn) ## i64
        lits[0] = 2 * zk + 1
        if ffbs_anchor_bit(au, av, aw, slot, axis, pos) == 1
          lits[1] = 2 * x
        else
          lits[1] = 2 * x + 1
        if ffcdcl_add_clause(sat, lits, 2) != 1
          return 0
        pos += 1
      axis += 1
    slot += 1
  # Pass 2c: Sinz sequential counter over the N distance literals.
  bits = r * 3 * nn ## i64
  q = 1 ## i64
  while q <= bits
    slot = (q - 1) / (3 * nn) ## i64
    within = (q - 1) % (3 * nn) ## i64
    axis = within / nn ## i64
    pos = within % nn ## i64
    d = ffbs_distance_lit(au, av, aw, slot, axis, pos, nn) ## i64
    # (!d or s(q,1))
    lits[0] = d ^ 1
    lits[1] = 2 * ffbs_counter_var(r, nn, nn * nn * nn, q, 1, width)
    if ffcdcl_add_clause(sat, lits, 2) != 1
      return 0
    if q > 1
      j = 1 ## i64
      while j <= width
        # (!s(q-1, j) or s(q, j))
        lits[0] = 2 * ffbs_counter_var(r, nn, nn * nn * nn, q - 1, j, width) + 1
        lits[1] = 2 * ffbs_counter_var(r, nn, nn * nn * nn, q, j, width)
        if ffcdcl_add_clause(sat, lits, 2) != 1
          return 0
        j += 1
      j = 2
      while j <= width
        # (!d or !s(q-1, j-1) or s(q, j))
        lits[0] = d ^ 1
        lits[1] = 2 * ffbs_counter_var(r, nn, nn * nn * nn, q - 1, j - 1, width) + 1
        lits[2] = 2 * ffbs_counter_var(r, nn, nn * nn * nn, q, j, width)
        if ffcdcl_add_clause(sat, lits, 3) != 1
          return 0
        j += 1
    q += 1
  # Pass 3: the Brent XOR rows, last so add_xor aux vars land above the map.
  xvars = i64[r + 1]
  cell = 0
  while cell < cells
    c = cell % nn ## i64
    rest = cell / nn ## i64
    b = rest % nn ## i64
    a = rest / nn ## i64
    slot = 0
    while slot < r
      xvars[slot] = ffbs_product_var(r, nn, cell, slot)
      slot += 1
    if ffcdcl_add_xor(sat, xvars, r, ffbs_coefficient(a, b, c, n)) != 1
      return 0
    cell += 1
  1

# ---------------------------------------------------------------------------
# One anchored sweep

# Build once, then solve radius b = b_start, b_start + b_step, ... <= b_max
# under the single counter-output assumption.  Stops at the first SAT.
# per_radius (i64[3 * count] laid out [b, status, conflicts] per probed
# radius) records the sweep; meta (i64[16]):
#   [0] anchor rank  [1] vars  [2] clauses  [3] radii probed
#   [4] first SAT radius (-1 none)  [5] decoded terms  [6] compacted rank
#   [7] gate flag  [8] total conflicts  [9] instance builds (always 1)
#   [10] certified-UNSAT radii  [11] indeterminate radii  [12] elapsed ms
# Returns the gated rank on a SAT hit, 0 when every probed radius is
# certified UNSAT or indeterminate, negative on structural errors
# (-1 plan, -2 encode, -3 anchor not exact).
-> ffbs_sweep_terms(au, av, aw, r, n, b_start, b_step, b_max, budget, seed, out_u, out_v, out_w, per_radius, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 16
    meta[i] = 0
    i += 1
  meta[4] = 0 - 1
  started = ccall("__w_clock_ms") ## i64
  if n < 2 || n > 4 || r < 2 || b_start < 0 || b_step < 1 || b_max < b_start
    return 0 - 1
  nn = n * n ## i64
  cells = nn * nn * nn ## i64
  # Anchor must be exact before we certify anything about it.
  capacity = ffw_default_capacity(n) ## i64
  gate = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(gate, au, av, aw, r, n, capacity, 77001 + (seed % 100000), 0, 1, 1, 1) ## i64
  if loaded != r || ffw_verify_current_exact(gate, n) != 1
    return 0 - 3
  width = b_max + 1 ## i64
  bits = r * 3 * nn ## i64
  if width > bits
    width = bits
  aux = cells * (r + 2) ## i64
  max_vars = ffbs_counter_top(r, nn, cells, width) + aux + 64 ## i64
  clause_words = cells * r * 40 + bits * width * 12 + cells * (r + 2) * 12 + r * 3 * nn * 8 + 300000 ## i64
  sat = i64[ffcdcl_state_size(max_vars, clause_words)]
  if ffcdcl_init(sat, max_vars, seed) != 1
    return 0 - 2
  if ffbs_encode(sat, au, av, aw, r, n, width) != 1
    return 0 - 2
  meta[0] = r
  meta[1] = ffcdcl_top_var(sat)
  meta[2] = ffcdcl_clause_count(sat)
  meta[9] = 1
  assumptions = i64[1]
  probes = 0 ## i64
  hit_rank = 0 ## i64
  b = b_start ## i64
  while b <= b_max && hit_rank == 0
    bound_col = b + 1 ## i64
    if bound_col > width
      bound_col = width
    assumptions[0] = 2 * ffbs_counter_var(r, nn, cells, bits, bound_col, width) + 1
    status = ffcdcl_solve(sat, assumptions, 1, budget) ## i64
    per_radius[probes * 3] = b
    per_radius[probes * 3 + 1] = status
    per_radius[probes * 3 + 2] = ffcdcl_conflicts(sat)
    meta[8] = meta[8] + ffcdcl_conflicts(sat)
    probes += 1
    if status == 1
      meta[4] = b
      count = 0 ## i64
      slot = 0 ## i64
      while slot < r
        if ffcdcl_value(sat, ffbs_z_var(r, slot, nn)) == 0
          u = 0 ## i64
          v = 0 ## i64
          w = 0 ## i64
          pos = 0 ## i64
          while pos < nn
            if ffcdcl_value(sat, ffbs_x_var(slot, 0, pos, nn)) == 1
              u = u | (1 << pos)
            if ffcdcl_value(sat, ffbs_x_var(slot, 1, pos, nn)) == 1
              v = v | (1 << pos)
            if ffcdcl_value(sat, ffbs_x_var(slot, 2, pos, nn)) == 1
              w = w | (1 << pos)
            pos += 1
          if u != 0 && v != 0 && w != 0
            out_u[count] = u
            out_v[count] = v
            out_w[count] = w
            count += 1
        slot += 1
      meta[5] = count
      if count >= 1 && count < r
        reloaded = ffw_init_terms_cap(gate, out_u, out_v, out_w, count, n, capacity, 77103 + (seed % 100000), 0, 1, 1, 1) ## i64
        if reloaded >= 1 && reloaded <= count && ffw_verify_current_exact(gate, n) == 1
          meta[6] = reloaded
          meta[7] = 1
          hit_rank = reloaded
    if status == 0 - 1
      meta[10] = meta[10] + 1
    if status == 0 - 2
      meta[11] = meta[11] + 1
    b += b_step
  meta[3] = probes
  meta[12] = ccall("__w_clock_ms") - started
  hit_rank

-> ffbs_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

# Path driver: load the anchor, sweep, and on a hit publish through
# dump -> re-parse -> re-gate.  Returns the hit rank, 0 miss, negatives as
# in ffbs_sweep_terms plus -4 load and -6 publish.
-> ffbs_sweep(path, n, b_start, b_step, b_max, budget, seed, out_path, per_radius, meta) (String i64 i64 i64 i64 i64 i64 String i64[] i64[]) i64
  capacity = ffw_default_capacity(n) ## i64
  st = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(st, path, n, capacity, 77201 + (seed % 100000), 0, 1, 1, 1) ## i64
  if rank < 2
    return 0 - 4
  au = i64[capacity]
  av = i64[capacity]
  aw = i64[capacity]
  count = ffw_export_current(st, au, av, aw) ## i64
  if count != rank
    return 0 - 4
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  hit = ffbs_sweep_terms(au, av, aw, rank, n, b_start, b_step, b_max, budget, seed, out_u, out_v, out_w, per_radius, meta) ## i64
  if hit <= 0
    return hit
  if out_path.size() > 0
    z = system("/bin/rm -f " + ffbs_shell_quote(out_path))
    fresh = i64[ffw_state_size(capacity)]
    loaded = ffw_init_terms_cap(fresh, out_u, out_v, out_w, meta[5], n, capacity, 77301, 0, 1, 1, 1) ## i64
    if loaded != hit || ffw_verify_current_exact(fresh, n) != 1
      return 0 - 6
    written = ffw_dump_current(fresh, out_path) ## i64
    if written != hit
      return 0 - 6
    replay = i64[ffw_state_size(capacity)]
    reloaded = ffw_load_scheme_cap(replay, out_path, n, capacity, 77401, 0, 1, 1, 1) ## i64
    if reloaded != hit || ffw_verify_current_exact(replay, n) != 1
      z = system("/bin/rm -f " + ffbs_shell_quote(out_path))
      return 0 - 6
  hit
