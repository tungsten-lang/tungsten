# Quantum — reversible circuit construction, cost accounting, and simulation.
#
# The module is built around the resource model used by fault-tolerant
# resource estimates: in a surgery-based error-corrected architecture the
# Clifford group is cheap and every non-Clifford gate must be distilled, so
# the cost of a circuit is dominated by its **Toffoli count** and the
# **number of qubits** it must hold live. `QuantumCircuit` therefore counts
# Toffoli and Clifford separately and tracks width, rather than reporting a
# single undifferentiated gate total.
#
# Three layers, deliberately separated by what they can represent:
#
#   `QuantumCircuit`     builds and costs a gate stream. No state.
#   `QuantumBasisState`  simulates the permutation-plus-phase subset
#                        (X/CX/CCX/SWAP/Z/CZ/CCZ/S/T) in O(1) per gate and
#                        O(width) memory, so it runs circuits on hundreds of
#                        qubits. Rejects gates that create superposition.
#   `QuantumState`       full state vector over 2^width amplitudes. Handles
#                        every gate including H, at exponential cost.
#
# The middle layer is the useful one for reversible arithmetic. A circuit of
# X/CX/CCX/SWAP gates is a *permutation* of computational basis states, so one
# basis vector in gives one basis vector out and there is nothing to
# superpose — simulating it needs one bit per qubit, not one amplitude per
# basis state. Adding the diagonal gates (Z/CZ/CCZ/S/T) costs one extra
# integer, because on a basis state a diagonal gate contributes only a global
# phase. Phase is tracked exactly, in units of pi/4 modulo 8, so it stays an
# integer and never accumulates floating-point error.
#
# Width follows the convention used by reversible-circuit scorers: it is
# `max referenced qubit id + 1`, not the number of simultaneously live
# qubits. Those differ whenever ids are allocated without being reused, so
# `QuantumCircuit` reuses freed ids from a free list and reports both numbers
# (`width` and `peak_live`). A gap between them is wasted score.

+ QuantumCircuit
  # Gate kind codes. Small integers rather than symbols so that the
  # simulators can dispatch on them in a hot loop without allocating.
  -> .gate_alloc
    0

  -> .gate_free
    1

  -> .gate_x
    2

  -> .gate_cx
    3

  -> .gate_ccx
    4

  -> .gate_z
    5

  -> .gate_cz
    6

  -> .gate_ccz
    7

  -> .gate_swap
    8

  -> .gate_h
    9

  -> .gate_s
    10

  -> .gate_t
    11

  # Sentinel for an unused control/target slot.
  -> .no_qubit
    0 - 1

  # Human-readable name for a gate kind, for tracing and error messages.
  -> .gate_name(kind)
    return "alloc" if kind == QuantumCircuit.gate_alloc
    return "free" if kind == QuantumCircuit.gate_free
    return "x" if kind == QuantumCircuit.gate_x
    return "cx" if kind == QuantumCircuit.gate_cx
    return "ccx" if kind == QuantumCircuit.gate_ccx
    return "z" if kind == QuantumCircuit.gate_z
    return "cz" if kind == QuantumCircuit.gate_cz
    return "ccz" if kind == QuantumCircuit.gate_ccz
    return "swap" if kind == QuantumCircuit.gate_swap
    return "h" if kind == QuantumCircuit.gate_h
    return "s" if kind == QuantumCircuit.gate_s
    return "t" if kind == QuantumCircuit.gate_t
    "gate[kind]"

  # Gates are held in four parallel arrays rather than as objects: a
  # reversible arithmetic circuit runs to millions of gates, and one boxed
  # record per gate dominates both allocation and cache behaviour.
  -> new
    @kind = []
    @c1 = []
    @c2 = []
    @target = []
    @next_id = 0
    @free_ids = []
    @live = 0
    @peak_live = 0
    @max_id = 0 - 1
    @toffoli = 0
    @clifford = 0

  -> size
    @kind.size()

  -> kind_at(i)
    @kind[i]

  -> control1_at(i)
    @c1[i]

  -> control2_at(i)
    @c2[i]

  -> target_at(i)
    @target[i]

  # Toffoli-class gates: CCX and CCZ. These are the distilled, expensive
  # ones — the numerator of the usual cost figure.
  -> toffoli_count
    @toffoli

  -> clifford_count
    @clifford

  # `max referenced qubit id + 1`. This is the width a scorer charges for,
  # and it is unaffected by how many qubits are live at any instant.
  -> width
    @max_id + 1

  # Greatest number of qubits simultaneously allocated. `width - peak_live`
  # is pure fragmentation: ids that were charged for but never reused.
  -> peak_live
    @peak_live

  -> live
    @live

  # The standard reversible-circuit objective: Toffoli count times width.
  # Lower is better.
  -> score
    @toffoli * width

  # -- qubit allocation --------------------------------------------------

  # Take a qubit id, preferring a previously freed one so that ids stay
  # densely packed and `width` tracks `peak_live`.
  -> alloc
    id = 0
    if @free_ids.size() > 0
      id = @free_ids.pop()
    else
      id = @next_id
      @next_id += 1
    @live += 1
    @peak_live = @live if @live > @peak_live
    record(QuantumCircuit.gate_alloc, QuantumCircuit.no_qubit, QuantumCircuit.no_qubit, id)
    id

  # Allocate `n` qubits and return their ids as an array.
  -> alloc_register(n)
    raise "register size must be nonnegative, got [n]" if n < 0
    ids = []
    i = 0
    while i < n
      ids.push(alloc)
      i += 1
    ids

  # Release a qubit id back to the free list. The caller is asserting the
  # qubit has been uncomputed to |0>; `QuantumBasisState` checks that claim
  # when it replays the stream and raises if it was false.
  -> free(id)
    raise "cannot free unallocated qubit [id]" if id < 0 || id >= @next_id
    @free_ids.push(id)
    @live -= 1
    record(QuantumCircuit.gate_free, QuantumCircuit.no_qubit, QuantumCircuit.no_qubit, id)
    self

  -> free_register(ids)
    i = ids.size() - 1
    while i >= 0
      free(ids[i])
      i -= 1
    self

  # -- gate emission -----------------------------------------------------

  -> x(t)
    @clifford += 1
    record(QuantumCircuit.gate_x, QuantumCircuit.no_qubit, QuantumCircuit.no_qubit, t)

  -> cx(c, t)
    raise "cx control and target must differ (both [t])" if c == t
    @clifford += 1
    record(QuantumCircuit.gate_cx, c, QuantumCircuit.no_qubit, t)

  -> ccx(a, b, t)
    raise "ccx needs three distinct qubits" if a == b || a == t || b == t
    @toffoli += 1
    record(QuantumCircuit.gate_ccx, a, b, t)

  -> z(t)
    @clifford += 1
    record(QuantumCircuit.gate_z, QuantumCircuit.no_qubit, QuantumCircuit.no_qubit, t)

  -> cz(c, t)
    raise "cz control and target must differ (both [t])" if c == t
    @clifford += 1
    record(QuantumCircuit.gate_cz, c, QuantumCircuit.no_qubit, t)

  -> ccz(a, b, t)
    raise "ccz needs three distinct qubits" if a == b || a == t || b == t
    @toffoli += 1
    record(QuantumCircuit.gate_ccz, a, b, t)

  -> swap(a, b)
    raise "swap needs two distinct qubits (both [a])" if a == b
    @clifford += 1
    record(QuantumCircuit.gate_swap, a, QuantumCircuit.no_qubit, b)

  -> h(t)
    @clifford += 1
    record(QuantumCircuit.gate_h, QuantumCircuit.no_qubit, QuantumCircuit.no_qubit, t)

  -> s(t)
    @clifford += 1
    record(QuantumCircuit.gate_s, QuantumCircuit.no_qubit, QuantumCircuit.no_qubit, t)

  # T is non-Clifford but not Toffoli-class; counted separately from both so
  # that a T-count estimate stays available without polluting `toffoli`.
  -> t_gate(t)
    record(QuantumCircuit.gate_t, QuantumCircuit.no_qubit, QuantumCircuit.no_qubit, t)

  # Multi-controlled NOT over an arbitrary control list, using `ancilla` as
  # a borrowed scratch register. This is the V-chain construction: with
  # k >= 3 controls it needs k-2 ancillas and emits 2k-3 Toffoli, of which
  # the second half uncomputes the chain so every ancilla is returned to
  # |0> and may be freed immediately afterwards. Returns self.
  -> mcx(controls, ancilla, t)
    k = controls.size()
    return x(t) if k == 0
    return cx(controls[0], t) if k == 1
    return ccx(controls[0], controls[1], t) if k == 2
    raise "mcx with [k] controls needs [k - 2] ancilla, got [ancilla.size()]" if ancilla.size() < k - 2
    # Compute the running AND of the controls into the ancilla chain.
    ccx(controls[0], controls[1], ancilla[0])
    i = 2
    while i < k - 1
      ccx(controls[i], ancilla[i - 2], ancilla[i - 1])
      i += 1
    ccx(controls[k - 1], ancilla[k - 3], t)
    # Uncompute the chain in reverse so every ancilla returns to |0>.
    i = k - 2
    while i >= 2
      ccx(controls[i], ancilla[i - 2], ancilla[i - 1])
      i -= 1
    ccx(controls[0], controls[1], ancilla[0])
    self

  # -- transformation ----------------------------------------------------

  # Gate-reversed inverse. Every gate here is its own inverse except S and T,
  # which are not represented separately; a circuit containing them cannot be
  # inverted by reversal alone and is rejected rather than silently wrong.
  -> inverse
    out = QuantumCircuit.new
    i = @kind.size() - 1
    while i >= 0
      k = @kind[i]
      if k == QuantumCircuit.gate_s || k == QuantumCircuit.gate_t
        raise "cannot invert by reversal: [QuantumCircuit.gate_name(k)] is not self-inverse"
      # alloc and free swap roles under reversal.
      out_kind = k
      out_kind = QuantumCircuit.gate_free if k == QuantumCircuit.gate_alloc
      out_kind = QuantumCircuit.gate_alloc if k == QuantumCircuit.gate_free
      out.push_raw(out_kind, @c1[i], @c2[i], @target[i])
      i -= 1
    out

  # Append another circuit's gate stream to this one.
  -> concat(other)
    i = 0
    n = other.size()
    while i < n
      push_raw(other.kind_at(i), other.control1_at(i), other.control2_at(i), other.target_at(i))
      i += 1
    self

  # Append a pre-formed gate, updating cost and width bookkeeping. Used by
  # `inverse` and `concat`, which must not re-run allocation logic.
  -> push_raw(kind, c1, c2, target)
    if kind == QuantumCircuit.gate_ccx || kind == QuantumCircuit.gate_ccz
      @toffoli += 1
    else
      if kind != QuantumCircuit.gate_alloc && kind != QuantumCircuit.gate_free && kind != QuantumCircuit.gate_t
        @clifford += 1
    record(kind, c1, c2, target)

  # Single point where a gate enters the stream, so width accounting cannot
  # drift from the gate list.
  -> record(kind, c1, c2, target)
    @kind.push(kind)
    @c1.push(c1)
    @c2.push(c2)
    @target.push(target)
    note_id(c1)
    note_id(c2)
    note_id(target)
    self

  -> note_id(id)
    return self if id == QuantumCircuit.no_qubit
    @max_id = id if id > @max_id
    self

  -> to_s
    "QuantumCircuit(gates: [size], toffoli: [@toffoli], clifford: [@clifford], width: [width], peak_live: [peak_live])"


# QuantumBasisState — permutation-and-phase simulation.
#
# Holds one bit per qubit plus an exact phase. Every gate in the
# X/CX/CCX/SWAP/Z/CZ/CCZ/S/T set maps a computational basis state to a single
# computational basis state times a phase, so this representation is closed
# under them and needs no amplitudes. H is not in that set and is rejected.
#
# Phase is an integer in units of pi/4 taken modulo 8: T contributes 1, S
# contributes 2, and Z/CZ/CCZ contribute 4 when their controls are satisfied.
# Keeping it integral means a circuit that should be phase-clean is checked
# exactly, with no tolerance to choose.
+ QuantumBasisState
  -> new(width)
    raise "width must be nonnegative, got [width]" if width < 0
    @width = width
    @bits = []
    @allocated = []
    i = 0
    while i < width
      @bits.push(0)
      @allocated.push(0)
      i += 1
    @phase = 0

  -> width
    @width

  -> bits
    @bits

  -> bit(i)
    @bits[i]

  -> set_bit(i, value)
    @bits[i] = value == 0 ? 0 : 1
    self

  # Phase in units of pi/4, modulo 8.
  -> phase
    @phase

  -> phase_clean?
    @phase == 0

  # Load a big-endian-free integer-indexed register: `ids` lists qubit ids
  # least-significant first, `value` supplies the bits.
  -> load_register(ids, value)
    i = 0
    v = value
    while i < ids.size()
      set_bit(ids[i], v % 2)
      v = v / 2
      i += 1
    self

  # Read a register back out as an integer, least-significant qubit first.
  -> read_register(ids)
    total = 0
    i = ids.size() - 1
    while i >= 0
      total = total * 2 + @bits[ids[i]]
      i -= 1
    total

  -> apply_gate(kind, c1, c2, target)
    if kind == QuantumCircuit.gate_alloc
      # No |0> assertion here. Input registers are allocated by the circuit
      # and then loaded by the caller, so a set bit at alloc time is normal.
      # Re-allocation of a recycled id is still covered: `free` already
      # proved the qubit was |0> when released, and nothing references it
      # between release and reuse.
      @allocated[target] = 1
      return self
    if kind == QuantumCircuit.gate_free
      # The reversibility contract: an ancilla is uncomputed before release.
      raise "qubit [target] freed in state |1>, not uncomputed" if @bits[target] != 0
      @allocated[target] = 0
      return self
    if kind == QuantumCircuit.gate_x
      @bits[target] = 1 - @bits[target]
      return self
    if kind == QuantumCircuit.gate_cx
      @bits[target] = 1 - @bits[target] if @bits[c1] == 1
      return self
    if kind == QuantumCircuit.gate_ccx
      @bits[target] = 1 - @bits[target] if @bits[c1] == 1 && @bits[c2] == 1
      return self
    if kind == QuantumCircuit.gate_swap
      tmp = @bits[c1]
      @bits[c1] = @bits[target]
      @bits[target] = tmp
      return self
    if kind == QuantumCircuit.gate_z
      @phase = (@phase + 4) % 8 if @bits[target] == 1
      return self
    if kind == QuantumCircuit.gate_cz
      @phase = (@phase + 4) % 8 if @bits[c1] == 1 && @bits[target] == 1
      return self
    if kind == QuantumCircuit.gate_ccz
      @phase = (@phase + 4) % 8 if @bits[c1] == 1 && @bits[c2] == 1 && @bits[target] == 1
      return self
    if kind == QuantumCircuit.gate_s
      @phase = (@phase + 2) % 8 if @bits[target] == 1
      return self
    if kind == QuantumCircuit.gate_t
      @phase = (@phase + 1) % 8 if @bits[target] == 1
      return self
    if kind == QuantumCircuit.gate_h
      raise "H takes a basis state out of the computational basis; use QuantumState"
    raise "unknown gate kind [kind]"

  -> apply(circuit)
    i = 0
    n = circuit.size()
    while i < n
      apply_gate(circuit.kind_at(i), circuit.control1_at(i), circuit.control2_at(i), circuit.target_at(i))
      i += 1
    self

  -> to_s
    "QuantumBasisState(width: [@width], phase: [@phase]pi/4)"


# QuantumState — dense state vector over 2^width complex amplitudes.
#
# Amplitudes are kept as two parallel Float arrays rather than boxed complex
# values: the inner loops touch every amplitude twice per gate, and one boxed
# object per amplitude costs more than the arithmetic does. Use this layer
# only when superposition is actually needed; a permutation circuit belongs
# in `QuantumBasisState`, which is exponentially cheaper.
+ QuantumState
  # Above this width a dense vector stops being reasonable: 2^26 amplitudes
  # is already a gigabyte across the two arrays.
  -> .max_width
    26

  -> new(width)
    raise "width must be nonnegative, got [width]" if width < 0
    if width > QuantumState.max_width
      raise "state vector width [width] exceeds [QuantumState.max_width]; use QuantumBasisState"
    @width = width
    @dim = 1 << width
    @re = []
    @im = []
    i = 0
    while i < @dim
      @re.push(0.0)
      @im.push(0.0)
      i += 1
    # Start in |0...0>.
    @re[0] = 1.0

  -> width
    @width

  -> dimension
    @dim

  -> amplitude_real(i)
    @re[i]

  -> amplitude_imag(i)
    @im[i]

  -> probability(i)
    @re[i] * @re[i] + @im[i] * @im[i]

  # Total probability. Should stay at 1 for a unitary circuit; drift is a
  # useful check on a hand-written gate.
  -> norm
    total = 0.0
    i = 0
    while i < @dim
      total = total + probability(i)
      i += 1
    total

  # Index of the basis state carrying the largest probability.
  -> most_likely
    best = 0
    best_p = probability(0)
    i = 1
    while i < @dim
      p = probability(i)
      if p > best_p
        best_p = p
        best = i
      i += 1
    best

  # True when bit `q` of basis index `i` is set.
  -> .bit_set?(i, q)
    (i / (1 << q)) % 2 == 1

  # Swap the amplitudes of every pair of basis states that differ only in
  # the target bit, subject to the control bits being set. This single
  # primitive implements X, CX and CCX.
  -> flip(c1, c2, target)
    i = 0
    while i < @dim
      # Visit each pair once, from the member whose target bit is 0.
      if !QuantumState.bit_set?(i, target)
        ok = true
        ok = false if c1 != QuantumCircuit.no_qubit && !QuantumState.bit_set?(i, c1)
        ok = false if c2 != QuantumCircuit.no_qubit && !QuantumState.bit_set?(i, c2)
        if ok
          j = i + (1 << target)
          tr = @re[i]
          ti = @im[i]
          @re[i] = @re[j]
          @im[i] = @im[j]
          @re[j] = tr
          @im[j] = ti
      i += 1
    self

  # Multiply by exp(i*pi*turns/4) on every basis state where the target and
  # any controls are set. Implements Z, CZ, CCZ, S and T.
  -> phase_shift(c1, c2, target, turns)
    cos_t = Math.cos(Math.pi * turns / 4.0)
    sin_t = Math.sin(Math.pi * turns / 4.0)
    i = 0
    while i < @dim
      ok = QuantumState.bit_set?(i, target)
      ok = false if c1 != QuantumCircuit.no_qubit && !QuantumState.bit_set?(i, c1)
      ok = false if c2 != QuantumCircuit.no_qubit && !QuantumState.bit_set?(i, c2)
      if ok
        r = @re[i]
        m = @im[i]
        @re[i] = r * cos_t - m * sin_t
        @im[i] = r * sin_t + m * cos_t
      i += 1
    self

  -> hadamard(target)
    inv = 1.0 / Math.sqrt(2.0)
    i = 0
    while i < @dim
      if !QuantumState.bit_set?(i, target)
        j = i + (1 << target)
        ar = @re[i]
        ai = @im[i]
        br = @re[j]
        bi = @im[j]
        @re[i] = (ar + br) * inv
        @im[i] = (ai + bi) * inv
        @re[j] = (ar - br) * inv
        @im[j] = (ai - bi) * inv
      i += 1
    self

  -> apply_gate(kind, c1, c2, target)
    return self if kind == QuantumCircuit.gate_alloc || kind == QuantumCircuit.gate_free
    return flip(QuantumCircuit.no_qubit, QuantumCircuit.no_qubit, target) if kind == QuantumCircuit.gate_x
    return flip(c1, QuantumCircuit.no_qubit, target) if kind == QuantumCircuit.gate_cx
    return flip(c1, c2, target) if kind == QuantumCircuit.gate_ccx
    return phase_shift(QuantumCircuit.no_qubit, QuantumCircuit.no_qubit, target, 4) if kind == QuantumCircuit.gate_z
    return phase_shift(c1, QuantumCircuit.no_qubit, target, 4) if kind == QuantumCircuit.gate_cz
    return phase_shift(c1, c2, target, 4) if kind == QuantumCircuit.gate_ccz
    return phase_shift(QuantumCircuit.no_qubit, QuantumCircuit.no_qubit, target, 2) if kind == QuantumCircuit.gate_s
    return phase_shift(QuantumCircuit.no_qubit, QuantumCircuit.no_qubit, target, 1) if kind == QuantumCircuit.gate_t
    return hadamard(target) if kind == QuantumCircuit.gate_h
    if kind == QuantumCircuit.gate_swap
      # SWAP as three CNOTs, so the pair-visiting primitive is reused.
      flip(c1, QuantumCircuit.no_qubit, target)
      flip(target, QuantumCircuit.no_qubit, c1)
      flip(c1, QuantumCircuit.no_qubit, target)
      return self
    raise "unknown gate kind [kind]"

  -> apply(circuit)
    i = 0
    n = circuit.size()
    while i < n
      apply_gate(circuit.kind_at(i), circuit.control1_at(i), circuit.control2_at(i), circuit.target_at(i))
      i += 1
    self

  -> to_s
    "QuantumState(width: [@width], dimension: [@dim])"
