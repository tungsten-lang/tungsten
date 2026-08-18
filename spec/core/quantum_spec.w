# Dogfood for core/quantum.w — circuit construction, cost accounting, and
# both simulation layers.
#
# The load-bearing claims are:
#   * width is `max referenced id + 1`, and freed ids get reused, so a
#     circuit that allocates and releases in waves does not inflate width;
#   * the basis-state layer enforces the reversibility contract (an ancilla
#     freed while set is an error, not a silent wrong answer);
#   * the basis-state and state-vector layers agree on every permutation
#     circuit, which is what makes the cheap layer trustworthy;
#   * phase is exact, so a phase-clean circuit reports exactly zero.
#
# Run: `bin/tungsten -o /tmp/qs spec/core/quantum_spec.w && /tmp/qs`.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# Amplitudes involve 1/sqrt(2), which has no exact binary representation, so
# probabilities are compared to a tolerance rather than bit-for-bit.
-> check_close(name, got, want)
  diff = got - want
  diff = 0.0 - diff if diff < 0.0
  if diff < 0.000000000001
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# -- cost accounting ---------------------------------------------------

c = QuantumCircuit.new
a = c.alloc
b = c.alloc
t = c.alloc
c.ccx(a, b, t)
c.cx(a, b)
c.x(t)
check("gate count", c.size, 6)
check("toffoli count", c.toffoli_count, 1)
check("clifford count", c.clifford_count, 2)
check("width", c.width, 3)
check("peak live", c.peak_live, 3)
check("score", c.score, 3)

# Freed ids are reused, so width tracks peak liveness instead of the total
# number of allocations. This is the difference a scorer charges for.
r = QuantumCircuit.new
first = r.alloc_register(4)
r.free_register(first)
second = r.alloc_register(4)
r.free_register(second)
check("reuse keeps width at 4", r.width, 4)
check("reuse keeps peak_live at 4", r.peak_live, 4)
check("all released", r.live, 0)

# Without reuse the two would diverge; confirm nothing is live-locked.
hold = QuantumCircuit.new
keep = hold.alloc_register(3)
extra = hold.alloc_register(2)
hold.free_register(extra)
check("held register pins width", hold.width, 5)
check("peak live counts the overlap", hold.peak_live, 5)
check("two still held", hold.live, 3)

# -- basis-state simulation --------------------------------------------

# A Toffoli is an AND into the target: only 1,1 flips it.
-> toffoli_out(x, y)
  circ = QuantumCircuit.new
  st = QuantumBasisState.new(3)
  st.set_bit(0, x)
  st.set_bit(1, y)
  circ.ccx(0, 1, 2)
  st.apply(circ)
  st.bit(2)

check("ccx 0,0", toffoli_out(0, 0), 0)
check("ccx 0,1", toffoli_out(0, 1), 0)
check("ccx 1,0", toffoli_out(1, 0), 0)
check("ccx 1,1", toffoli_out(1, 1), 1)

# SWAP exchanges two qubits.
sw = QuantumCircuit.new
sws = QuantumBasisState.new(2)
sws.set_bit(0, 1)
sw.swap(0, 1)
sws.apply(sw)
check("swap moves the bit", sws.read_register([0, 1]), 2)

# Register load/read round-trips little-endian.
reg = QuantumBasisState.new(8)
reg.load_register([0, 1, 2, 3, 4, 5, 6, 7], 202)
check("register round-trip", reg.read_register([0, 1, 2, 3, 4, 5, 6, 7]), 202)

# Phase is exact and integral. Z on |1> is a half turn: 4 quarter-pi units.
ph = QuantumCircuit.new
phs = QuantumBasisState.new(1)
phs.set_bit(0, 1)
ph.z(0)
phs.apply(ph)
check("z on |1> is 4 pi/4", phs.phase, 4)
check("z on |1> is not phase clean", phs.phase_clean?, false)

# Z on |0> does nothing, and two Z gates cancel exactly.
ph2 = QuantumCircuit.new
phs2 = QuantumBasisState.new(1)
phs2.set_bit(0, 1)
ph2.z(0)
ph2.z(0)
phs2.apply(ph2)
check("z twice is phase clean", phs2.phase_clean?, true)

# T eight times is a full turn back to clean, with no float drift.
ph3 = QuantumCircuit.new
phs3 = QuantumBasisState.new(1)
phs3.set_bit(0, 1)
i = 0
while i < 8
  ph3.t_gate(0)
  i += 1
phs3.apply(ph3)
check("t^8 returns to phase clean", phs3.phase_clean?, true)

# -- the reversibility contract ----------------------------------------

# Uncomputing before free is accepted.
good = QuantumCircuit.new
ga = good.alloc
gb = good.alloc
gt = good.alloc
good.ccx(ga, gb, gt)
good.ccx(ga, gb, gt)
good.free(gt)
gs = QuantumBasisState.new(good.width)
gs.set_bit(ga, 1)
gs.set_bit(gb, 1)
gs.apply(good)
check("uncomputed ancilla frees cleanly", gs.bit(gt), 0)

# Skipping the uncompute is a caught error, not a silent wrong answer.
-> dirty_free_raises
  bad = QuantumCircuit.new
  ba = bad.alloc
  bb = bad.alloc
  bt = bad.alloc
  bad.ccx(ba, bb, bt)
  bad.free(bt)
  bs = QuantumBasisState.new(bad.width)
  bs.set_bit(ba, 1)
  bs.set_bit(bb, 1)
  ok = false
  begin
    bs.apply(bad)
  rescue e
    ok = true
  ok

check("dirty free is rejected", dirty_free_raises, true)

# -- inverse -----------------------------------------------------------

# Forward then reversed-inverse restores every qubit: the identity check a
# reversible-circuit verifier runs.
fwd = QuantumCircuit.new
fwd.ccx(0, 1, 2)
fwd.cx(0, 1)
fwd.x(0)
round = QuantumCircuit.new
round.concat(fwd)
round.concat(fwd.inverse)
rs = QuantumBasisState.new(3)
rs.set_bit(0, 1)
rs.set_bit(1, 1)
rs.apply(round)
check("forward then inverse restores q0", rs.bit(0), 1)
check("forward then inverse restores q1", rs.bit(1), 1)
check("forward then inverse restores q2", rs.bit(2), 0)
check("forward then inverse is phase clean", rs.phase_clean?, true)
check("inverse preserves toffoli count", fwd.inverse.toffoli_count, 1)

# -- the two simulators agree ------------------------------------------

# A permutation circuit must give the same answer both ways; this is what
# licenses using the cheap layer on circuits the dense one cannot hold.
perm = QuantumCircuit.new
perm.x(0)
perm.ccx(0, 1, 2)
perm.cx(0, 1)
perm.ccx(0, 1, 2)
perm.swap(1, 2)

dense = QuantumState.new(3)
dense.apply(perm)
sparse = QuantumBasisState.new(3)
sparse.apply(perm)
check("state vector stays normalised", dense.norm, 1.0)
check("simulators agree on the basis state", dense.most_likely, sparse.read_register([0, 1, 2]))

# -- superposition -----------------------------------------------------

# H on one qubit splits probability evenly.
hc = QuantumCircuit.new
hc.h(0)
hs = QuantumState.new(1)
hs.apply(hc)
check_close("h gives even split on |0>", hs.probability(0), 0.5)
check_close("h gives even split on |1>", hs.probability(1), 0.5)
check_close("h preserves norm", hs.norm, 1.0)

# H twice is the identity.
h2 = QuantumCircuit.new
h2.h(0)
h2.h(0)
hs2 = QuantumState.new(1)
hs2.apply(h2)
check_close("h twice returns to |0>", hs2.probability(0), 1.0)

# A Bell pair: H then CX correlates the two qubits and leaves the
# anti-correlated states empty.
bell = QuantumCircuit.new
bell.h(0)
bell.cx(0, 1)
bs2 = QuantumState.new(2)
bs2.apply(bell)
check_close("bell |00>", bs2.probability(0), 0.5)
check_close("bell |01> empty", bs2.probability(1), 0.0)
check_close("bell |10> empty", bs2.probability(2), 0.0)
check_close("bell |11>", bs2.probability(3), 0.5)
check_close("bell preserves norm", bs2.norm, 1.0)

# -- multi-controlled NOT ----------------------------------------------

# mcx over 4 controls fires only when all four are set, and returns its
# ancilla to |0> so they can be freed.
-> mcx_out(all_set)
  m = QuantumCircuit.new
  ctrl = m.alloc_register(4)
  tgt = m.alloc
  anc = m.alloc_register(2)
  m.mcx(ctrl, anc, tgt)
  ms = QuantumBasisState.new(m.width)
  i = 0
  while i < 4
    ms.set_bit(ctrl[i], all_set == 1 ? 1 : 0)
    i += 1
  ms.set_bit(ctrl[0], 1) if all_set == 0
  ms.apply(m)
  [ms.bit(tgt), ms.bit(anc[0]), ms.bit(anc[1])]

check("mcx fires on all controls set", mcx_out(1), [1, 0, 0])
check("mcx silent otherwise", mcx_out(0), [0, 0, 0])

# The V-chain costs 2k-3 Toffoli and k-2 ancillas for k controls.
mc = QuantumCircuit.new
mctrl = mc.alloc_register(5)
mtgt = mc.alloc
manc = mc.alloc_register(3)
mc.mcx(mctrl, manc, mtgt)
check("mcx toffoli count for k=5", mc.toffoli_count, 7)
