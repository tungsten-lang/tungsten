# Compare two-watched literals with raw bit masks on static propagation snapshots.
# Arguments: input.cnf queries maximum-assumptions repetitions. Build --release.
# The occurrence index and masks describe the original clauses throughout the run.
use ../lib/solver
use ../lib/preprocess

# Fields per long clause are stored across consecutive blocks of 64 variable IDs.
# A tautological block makes the whole clause permanently satisfied.
-> word_index(cm, live, ar, nc, nw, pos, neg, ids, offsets, entries, cursor) (i64[] i8[] i32[] i64 i64 i64[] i64[] i32[] i32[] i32[] i32[]) i64
  row = 0 ## i64
  (0...nc).each -> (ci)
    n = cm[2 * ci + 1] ## i64
    if live[ci] == 1 && n >= 3
      ids[row] = ci
      start = cm[2 * ci] ## i64
      (0...n).each -> (k)
        lit = ar[start + k] ## i64
        v = lit ## i64
        v = 0 - lit if lit < 0
        bit = 1 << ((v - 1) & 63) ## i64
        at = row * nw + ((v - 1) >> 6) ## i64
        li = v << 1 ## i64
        if lit < 0
          neg[at] = neg[at] | bit
          li += 1
        else
          pos[at] = pos[at] | bit
        offsets[li + 1] += 1
      row += 1
  i = 1 ## i64
  while i < offsets.size
    offsets[i] += offsets[i - 1]
    cursor[i] = offsets[i]
    i += 1
  (0...row).each -> (r)
    ci = ids[r] ## i64
    start = cm[2 * ci] ## i64
    n = cm[2 * ci + 1] ## i64
    (0...n).each -> (k)
      lit = ar[start + k] ## i64
      li = lit << 1 ## i64
      li = ((0 - lit) << 1) + 1 if lit < 0
      entries[cursor[li]] = r
      cursor[li] += 1
  row

# Return 0 for satisfied or at least two available, a signed literal for unit,
# or the out-of-domain sentinel for conflict. Test a tautology before forcing.
-> word_unit(pos, neg, yes, no, row, nw) (i64[] i64[] i64[] i64[] i64 i64) i64
  unit = 0 ## i64
  w = 0 ## i64
  while w < nw
    p = pos[row * nw + w] ## i64
    n = neg[row * nw + w] ## i64
    t = yes[w] ## i64
    f = no[w] ## i64
    return 0 if ((p & t) | (n & f) | (p & n)) != 0
    free = (p | n) & ((t | f) ^ -1) ## i64
    if free != 0
      return 0 if unit != 0 || popcount(free) > 1
      unit = 64 * w + cttz(free) + 1
      unit = 0 - unit if (n & free) != 0
    w += 1
  return 2147483648 if unit == 0
  unit

-> word_put(yes, no, lit) (i64[] i64[] i64) i64
  v = lit ## i64
  v = 0 - v if v < 0
  w = (v - 1) >> 6 ## i64
  bit = 1 << ((v - 1) & 63) ## i64
  if lit > 0
    yes[w] = yes[w] | bit
  else
    no[w] = no[w] | bit
  0

-> word_reset(yes, no, tr, head) (i64[] i64[] i32[] i64) i64
  w = 0 ## i64
  while w < yes.size
    yes[w] = 0
    no[w] = 0
    w += 1
  i = 0 ## i64
  while i < head
    lit = tr[i] ## i64
    ignored = word_put(yes, no, lit)
    i += 1
  0

# Dirty list is deduplicated per wave. Binary closure uses the production
# kernel with an empty long-watch directory. New units start the next wave.
-> word_dirty(tr, first, stop, offsets, entries, stamps, dirty, stamp, yes, no) (i32[] i64 i64 i32[] i32[] i64[] i32[] i64 i64[] i64[]) i64
  count = 0 ## i64
  i = first ## i64
  while i < stop
    p = tr[i] ## i64
    ignored = word_put(yes, no, p)
    li = ((0 - p) << 1) ## i64
    li = (p << 1) + 1 if p > 0
    k = offsets[li] ## i64
    while k < offsets[li + 1]
      r = entries[k] ## i64
      if stamps[r] != stamp
        stamps[r] = stamp
        dirty[count] = r
        count += 1
      k += 1
    i += 1
  count

-> word_infer(pos, neg, yes, no, ids, dirty, n, asg, lasg, lvl, rsn, ph, tr, st, dl) (i64[] i64[] i64[] i64[] i32[] i32[] i64 i8[] i8[] i64[] i32[] i8[] i32[] i64[] i64) i64
  j = 0 ## i64
  while j < n
    r = dirty[j] ## i64
    lit = word_unit(pos, neg, yes, no, r, yes.size) ## i64
    if lit == 2147483648
      st[2] = ids[r]
      return 0
    if lit != 0
      v = lit ## i64
      pol = 1 ## i64
      if lit < 0
        v = 0 - lit
        pol = 0 - 1
      ignored = word_put(yes, no, lit)
      asg[v] = pol; lasg[v << 1] = pol; lasg[(v << 1) + 1] = 0 - pol
      lvl[v] = dl; rsn[v] = ids[r]; ph[v] = pol
      tr[st[1]] = lit; st[1] += 1
    j += 1
  0

# Shared binary lists and the same trail, reasons and assignment storage as Wassat.
-> word_propagate(ar, asg, lasg, lvl, rsn, ph, blank, wp, ws, tr, st, dl, bd, bp, pos, neg, yes, no, ids, offsets, entries, stamps, dirty, state) (i32[] i8[] i8[] i64[] i32[] i8[] i32[] i64[] i64[] i32[] i64[] i64 i32[] i64[] i64[] i64[] i64[] i64[] i32[] i32[] i32[] i64[] i32[] i64[]) i64
  while st[0] < st[1] && st[2] < 0
    first = st[0] ## i64
    ignored = wassat_propagate(ar, asg, lasg, lvl, rsn, ph, blank, wp, ws, tr, st, dl, bd, bp)
    if st[2] < 0
      state[0] += 1
      count = word_dirty(tr, first, st[0], offsets, entries, stamps, dirty, state[0], yes, no)
      ignored = word_infer(pos, neg, yes, no, ids, dirty, count, asg, lasg, lvl, rsn, ph, tr, st, dl)
  0

+ WordSnapshot < Wassat
  -> install_words
    nw = (@nvars + 63) / 64 ## i64
    count = 0 ## i64
    occurrences = 0 ## i64
    cm = @cmeta ## i64[]
    (0...@ncl).each -> (ci)
      if @alive[ci] == 1 && cm[2 * ci + 1] >= 3
        count += 1
        occurrences += cm[2 * ci + 1]
    raise "mask table exceeds the typed array index range" if count * nw > 2147483647
    raise "literal occurrences exceed i32 offsets" if occurrences > 2147483647
    @mw_pos = i64[count * nw]; @mw_neg = i64[count * nw]
    @mw_yes = i64[nw]; @mw_no = i64[nw]
    @mw_ids = i32[count]; @mw_entries = i32[occurrences]
    @mw_dirty = i32[count]; @mw_stamps = i64[count]; @word_state = i64[1]
    @mw_offsets = i32[2 * @nvars + 4]
    cursor = i32[2 * @nvars + 4]
    @mw_blank = i32[4 * (2 * @nvars + 4)]
    n = word_index(cm, @alive, @arena, @ncl, nw, @mw_pos, @mw_neg, @mw_ids, @mw_offsets, @mw_entries, cursor)
    raise "bad row count" unless n == count
    0

  ro :word_state

  -> probe(assumptions, values, counters)
    ignored = word_reset(@mw_yes, @mw_no, @trail, @qhead)
    self.propagation_snapshot(assumptions, values, counters)

  -> propagate
    return super if @mw_dirty == nil
    s = @pstate ## i64[]
    s[0] = @qhead; s[1] = @tsize; s[2] = -1; s[3] = 0
    ignored = word_propagate(@arena, @assign, @lassign, @level, @reason, @phase,
                             @mw_blank, @wpool, @wp_state, @trail, s, @dlevel, @bldir, @bl_pool,
                             @mw_pos, @mw_neg, @mw_yes, @mw_no, @mw_ids, @mw_offsets,
                             @mw_entries, @mw_stamps, @mw_dirty, @word_state)
    @qhead = s[0]; @tsize = s[1]
    s[2]

-> word_queries(nv, num, width, seed) (i64 i64 i64 i64)
  queries = []
  seen = i32[nv + 1]
  state = seed ## i64
  (0...num).each -> (q)
    trial = []
    target = width ## i64
    target = 1 + (q % width) if q % 4 == 0
    while trial.size < target
      state = (state * 48271) % 2147483647
      v = 1 + (state % nv) ## i64
      if seen[v] != q + 1
        seen[v] = q + 1
        lit = v ## i64
        lit = 0 - lit if q % 3 == 0 || (q % 3 == 1 && (state & 256) != 0)
        trial.push(lit)
    queries.push(trial)
  queries

-> word_time
  (ccall("__w_clock") * 1000000).to_i

args = argv()
raise "usage: word_propagation input.cnf queries maximum-assumptions repetitions" unless args.size == 4
num = args[1].to_i
width = args[2].to_i
reps = args[3].to_i
raise "queries must be in 1..2147483647" if num < 1 || num > 2147483647
raise "repetitions must be positive" if reps < 1
formula = wassat_parse_cnf_native(read_file(args[0]))
nv = formula["nvars"]
raise "maximum assumptions must be in 1..nvars" if width < 1 || width > nv
raise "literal directory exceeds the typed array index range" if 4 * (2 * nv + 4) > 2147483647
art = wassat_raw_artifact(formula, nv)
base = Wassat.new(nv, [], WASSAT_PROOF_NONE, 0, true)
raise "input is too large to share between snapshot solvers" if base.consume_flat_input?(art, false)
base.load_flat(art)
candidate = WordSnapshot.new(nv, [], WASSAT_PROOF_NONE, 0, true)
candidate.load_flat(art); candidate.install_words
queries = word_queries(nv, num, width, 190205)
a = i8[nv + 1]; b = i8[nv + 1]; ca = i64[4]; cb = i64[4]
conflicts = 0
queries.each -> (q)
  status = base.propagation_snapshot(q, a, ca)
  alt = candidate.probe(q, b, cb)
  raise "different conflict [status] [alt]" if status != alt
  if status == 1
    (1..nv).each -> (v)
      raise "different assignment [v] [a[v]] [b[v]]" if a[v] != b[v]
  else
    conflicts += 1
<< "checked=[queries.size] conflicts=[conflicts] mask_waves=[candidate.word_state[0]]"
(0...reps).each -> (rep)
  (0...2).each -> (arm)
    mask = (arm + rep) % 2 == 1
    start = word_time
    if mask
      queries.each -> (q)
        candidate.probe(q, nil, cb)
    else
      queries.each -> (q)
        base.propagation_snapshot(q, nil, ca)
    elapsed = word_time - start
    << "trial=[rep] mask=[mask] us=[elapsed]"
