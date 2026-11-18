# Prove corresponding signals equal in two bit-level circuits. Forward AND
# congruence and backward XOR cancellation propose implications. Each one
# must pass unit propagation on the original CNF plus earlier proved lemmas.
use induction_certificate

WASSAT_PAIRED_CIRCUIT_MS = 2500

-> wassat_paired_prefix?(formula)
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return false if nv < 10 || nv > 50000 || nc < nv || nc > 3 * nv + 1
  lens = formula["flat_lens"]
  offs = formula["flat_offs"]
  lits = formula["flat_lits"]
  return false unless lens[nc - 1] == 1 && lens[0] == 2 && lens[1] == 2 && lens[2] == 2 && lens[3] == 2
  g = lits[offs[0]]
  h = lits[offs[2]]
  return false unless g < 0 && h < 0 && g != h && lits[offs[1]] == g && lits[offs[3]] == h
  lits[offs[0] + 1] == 0 - lits[offs[2] + 1] && lits[offs[1] + 1] == 0 - lits[offs[3] + 1]

# A complete AND has two negative-output binaries and one positive-output
# ternary. The miter can omit one polarity of a gate. These incomplete
# definitions give candidate pairs only and never authorize a proof step.
-> wassat_paired_gates(formula, left, right, full)
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  binary = i8[nv + 1]
  ternary = i8[nv + 1]
  ci = 0
  while ci < nc
    off = offs[ci]
    width = lens[ci]
    return false if width < 1 || width > 3
    if width >= 2
      at = 0
      j = 1
      while j < width
        at = j if lits[off + j].abs > lits[off + at].abs
        j += 1
      head = lits[off + at]
      v = head.abs
      if width == 2 && head < 0
        a = lits[off + 1 - at]
        if ternary[v] == 0
          if binary[v] == 0
            left[v] = a
          elsif binary[v] == 1
            right[v] = a
        binary[v] += 1 if binary[v] < 3
      elsif width == 3 && head > 0
        left[v] = 0 - lits[off + (at + 1) % 3]
        right[v] = 0 - lits[off + (at + 2) % 3]
        ternary[v] = 1
    ci += 1
  v = 1
  while v <= nv
    if ternary[v] == 0 && binary[v] != 2
      left[v] = 0
      right[v] = 0
    full[v] = 1 if ternary[v] != 0 && binary[v] == 2
    v += 1
  true

-> wassat_paired_sign(lit, mirror)
  v = mirror[lit.abs]
  lit < 0 ? 0 - v : v

# The partial comparator gates propose an involution on primary inputs.
# Keep shared inputs fixed, then match each gate with the gate obtained by
# exchanging its operands' two circuit copies. An ambiguous match is skipped.
-> wassat_paired_signals(formula, left, right, full, mirror)
  nv = formula["nvars"]
  first = formula["flat_lits"][formula["flat_offs"][0]].abs
  return false if first < 3 || first > nv
  index = {}
  v = first
  while v <= nv
    if left[v] != 0 && right[v] != 0
      key = wassat_induction_pair(left[v], right[v], nv)
      index[key] = index.has_key?(key) ? 0 : v
    v += 1
  v = 1
  while v < first
    mirror[v] = v
    v += 1
  pairs = 0
  while v <= nv && full[v] == 0
    a = left[v]
    b = right[v]
    if a > 0 && b < 0 || b > 0 && a < 0
      if a.abs < first && b.abs < first && a.abs != b.abs && index.has_key?(wassat_induction_pair(0 - a, 0 - b, nv))
        if mirror[a.abs] == a.abs && mirror[b.abs] == b.abs
          mirror[a.abs] = b.abs
          mirror[b.abs] = a.abs
          pairs += 1
    v += 1
  return false if pairs < 2
  v = first
  while v <= nv
    a = wassat_paired_sign(left[v], mirror)
    b = wassat_paired_sign(right[v], mirror)
    if a != 0 && b != 0
      match = index[wassat_induction_pair(a, b, nv)]
      mirror[v] = match if match != nil
    v += 1
  true

+ WassatPairedSweep
  -> new(@solver, @mirror, @emit, @deadline)
    @proved = i8[@mirror.size]
    @counters = i64[4]
    @closed = false
    @proof = StringBuffer()
    @steps = 0

  -> equal_signal(v)
    v = v.abs
    w = @mirror[v]
    w == v || (w > 0 && @mirror[w] == v && @proved[v < w ? v : w] == 3)

  -> rup(assumptions)
    @solver.propagation_snapshot(assumptions, nil, @counters) == -1

  -> add(row)
    if @emit
      row.each -> (lit)
        @proof.append("[lit] ")
      @proof.append("0\n")
    @steps += 1
    @closed = true if @solver.install_pruning_clause(row, false, true) < 0

  # Under the negation of the candidate clause, either propagation closes
  # immediately or both values of a common XOR operand close. The latter
  # case needs its two guarded lemmas in the proof before the binary lemma.
  -> derive(a, b, pivot)
    unless self.rup([0 - a, 0 - b])
      return false if pivot == 0
      return false unless self.rup([0 - a, 0 - b, pivot]) && self.rup([0 - a, 0 - b, 0 - pivot])
      self.add([a, b, pivot])
      self.add([a, b, 0 - pivot])
    self.add([a, b])
    true

  -> try_pair(signal, pivot)
    v = signal.abs
    w = @mirror[v]
    return 0 if w == 0 || w == v || @mirror[w] != v || @closed
    a = v < w ? v : w
    b = v < w ? w : v
    flags = @proved[a]
    return 0 if flags == 3
    flags = flags | 1 if (flags & 1) == 0 && self.derive(0 - a, b, pivot)
    flags = flags | 2 if (flags & 2) == 0 && self.derive(a, 0 - b, pivot)
    @proved[a] = flags

  -> expired
    @deadline != 0 && clock_ms() >= @deadline

  -> run(left, right, pairs)
    pass = 0
    while !@closed
      before = @steps
      i = 0
      while i < pairs.size && !@closed
        return nil if (i & 127) == 0 && self.expired
        v = pairs[i]
        a = left[v]
        b = right[v]
        self.try_pair(v, 0) if pass == 0 || (a != 0 && self.equal_signal(a) && self.equal_signal(b))
        if a < 0 && b < 0 && self.equal_signal(v)
          # An AND of two negated complementary minterms represents XOR.
          # If the two outputs and one operand agree, the other must agree.
          p = left[0 - a]
          q = right[0 - a]
          r = left[0 - b]
          s = right[0 - b]
          if p != 0 && q != 0 && ((p == 0 - r && q == 0 - s) || (p == 0 - s && q == 0 - r))
            self.try_pair(q, p.abs) if self.equal_signal(p)
            self.try_pair(p, q.abs) if self.equal_signal(q)
        i += 1
      break if before == @steps
      pass += 1
    return nil if @steps == 0
    # The output asserts an input mismatch. Discharge the remaining
    # mismatch witnesses by unit propagation under each single literal.
    v = 1
    while !@closed && v < @mirror.size
      return nil if (v & 127) == 0 && self.expired
      if @solver.value(v) == 0
        if self.rup([v])
          self.add([0 - v])
        elsif self.rup([0 - v])
          self.add([v])
      v += 1
    return nil unless self.rup([])
    @proof.append("0\n") if @emit
    @proof.to_s

-> wassat_paired_refutation(formula, emit, deadline)
  return nil unless wassat_paired_prefix?(formula)
  return nil if deadline != 0 && clock_ms() >= deadline
  nv = formula["nvars"]
  left = i64[nv + 1]
  right = i64[nv + 1]
  full = i8[nv + 1]
  mirror = i64[nv + 1]
  return nil unless wassat_paired_gates(formula, left, right, full) && wassat_paired_signals(formula, left, right, full, mirror)
  pairs = []
  v = 1
  while v <= nv
    pairs.push(v) if mirror[v] > v && mirror[mirror[v]] == v
    v += 1
  return nil if pairs.empty? || (deadline != 0 && clock_ms() >= deadline)
  solver = Wassat.from_flat(nv, wassat_raw_artifact(formula, nv), WASSAT_PROOF_NONE)
  WassatPairedSweep.new(solver, mirror, emit, deadline).run(left, right, pairs)
