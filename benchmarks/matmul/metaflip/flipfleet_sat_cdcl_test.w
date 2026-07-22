# Regression suite for the in-process incremental CDCL solver
# (flipfleet_sat_cdcl).  Pure CPU, no external solver, no GPU.  Covers unit
# propagation, pigeonhole UNSAT, planted random 3-SAT with full model
# re-evaluation, XOR ingestion, assumption solving, failed-assumption cores,
# conflict budgets, clause mark/release, and equivalence with the shared
# Brent-window encoder (ffsdr_prepare_window + ffsdr_emit_clauses) feeding
# the CDCL the exact clause runs the DIMACS path would format.  Run from the
# repo root (lexer tables are CWD-relative).

use flipfleet_sat_cdcl
use flipfleet_sat_destroy_repair

-> ffcdt_expect(label, condition) (String bool) i64
  if !condition
    << "CDCL_FAIL " + label
    exit(1)
  1

# Campaign LCG idiom: deterministic, no Math.random.
-> ffcdt_lcg(x) (i64) i64
  (x * 6364136223846793005 + 1442695040888963407) & 9223372036854775807

# Build a planted satisfiable random 3-SAT instance.  Every clause gets three
# distinct variables and random polarities, then one randomly chosen position
# is forced to agree with the plant, so every clause has at least one literal
# true under the plant and the plant satisfies the whole formula by
# construction (the classic planted generator).  Clauses are added to the
# solver and recorded (three CDCL literals per clause) in cls so the returned
# model can be re-evaluated directly.  Draws come from the high bits of the
# LCG state: the low bit of a power-of-two-modulus LCG alternates with
# period 2 and would produce a structured, trivially-propagatable formula.
# Returns 1, or 0 on any solver ingestion failure.
-> ffcdt_plant_3sat(st, cls, vars, clauses, seed) (i64[] i64[] i64 i64 i64) i64
  plant = i64[vars + 1]
  x = seed ## i64
  v = 1 ## i64
  while v <= vars
    x = ffcdt_lcg(x)
    plant[v] = (x >> 33) & 1
    v += 1
  lits = i64[3]
  c = 0 ## i64
  while c < clauses
    x = ffcdt_lcg(x)
    a = 1 + ((x >> 13) % vars) ## i64
    b = a ## i64
    while b == a
      x = ffcdt_lcg(x)
      b = 1 + ((x >> 13) % vars)
    d = a ## i64
    while d == a || d == b
      x = ffcdt_lcg(x)
      d = 1 + ((x >> 13) % vars)
    x = ffcdt_lcg(x)
    sa = (x >> 33) & 1 ## i64
    x = ffcdt_lcg(x)
    sb = (x >> 33) & 1 ## i64
    x = ffcdt_lcg(x)
    sd = (x >> 33) & 1 ## i64
    x = ffcdt_lcg(x)
    forced = (x >> 33) % 3 ## i64
    if forced == 0
      sa = 1 - plant[a]
    if forced == 1
      sb = 1 - plant[b]
    if forced == 2
      sd = 1 - plant[d]
    lits[0] = 2 * a + sa
    lits[1] = 2 * b + sb
    lits[2] = 2 * d + sd
    if ffcdcl_add_clause(st, lits, 3) != 1
      return 0
    cls[c * 3] = lits[0]
    cls[c * 3 + 1] = lits[1]
    cls[c * 3 + 2] = lits[2]
    c += 1
  1

# Re-evaluate every recorded 3-SAT clause against the solver model.
-> ffcdt_model_ok(st, cls, clauses) (i64[] i64[] i64) i64
  c = 0 ## i64
  while c < clauses
    satisfied = 0 ## i64
    j = 0 ## i64
    while j < 3
      lit = cls[c * 3 + j] ## i64
      value = ffcdcl_value(st, lit / 2) ## i64
      if (lit & 1) == 0 && value == 1
        satisfied = 1
      if (lit & 1) == 1 && value == 0
        satisfied = 1
      j += 1
    if satisfied == 0
      return 0
    c += 1
  1

# Pigeonhole PHP(pigeons, holes): variable of pigeon i in hole j is
# 1 + i*holes + j.  At-least-one clause per pigeon plus pairwise at-most-one
# per hole.  UNSAT whenever pigeons > holes.
-> ffcdt_add_php(st, pigeons, holes) (i64[] i64 i64) i64
  row = i64[holes]
  pair = i64[2]
  i = 0 ## i64
  while i < pigeons
    j = 0 ## i64
    while j < holes
      row[j] = 2 * (1 + i * holes + j)
      j += 1
    if ffcdcl_add_clause(st, row, holes) != 1
      return 0
    i += 1
  j = 0 ## i64
  while j < holes
    i = 0
    while i < pigeons
      i2 = i + 1 ## i64
      while i2 < pigeons
        pair[0] = 2 * (1 + i * holes + j) + 1
        pair[1] = 2 * (1 + i2 * holes + j) + 1
        if ffcdcl_add_clause(st, pair, 2) != 1
          return 0
        i2 += 1
      i += 1
    j += 1
  1

none = i64[1]

# --- 1. Unit propagation chain: (x1), (-x1 x2), (-x2 x3) ---
st1 = i64[ffcdcl_state_size(3, 4096)]
z = ffcdt_expect("chain init", ffcdcl_init(st1, 3, 11) == 1) ## i64
lits1 = i64[2]
lits1[0] = 2
z = ffcdt_expect("chain add unit", ffcdcl_add_clause(st1, lits1, 1) == 1)
lits1[0] = 3
lits1[1] = 4
z = ffcdt_expect("chain add imp1", ffcdcl_add_clause(st1, lits1, 2) == 1)
lits1[0] = 5
lits1[1] = 6
z = ffcdt_expect("chain add imp2", ffcdcl_add_clause(st1, lits1, 2) == 1)
z = ffcdt_expect("chain SAT", ffcdcl_solve(st1, none, 0, 0) == 1)
z = ffcdt_expect("chain model", ffcdcl_value(st1, 1) == 1 && ffcdcl_value(st1, 2) == 1 && ffcdcl_value(st1, 3) == 1)

# --- 2. Pigeonhole PHP(4,3) is UNSAT ---
st2 = i64[ffcdcl_state_size(12, 16384)]
z = ffcdt_expect("php43 init", ffcdcl_init(st2, 12, 22) == 1)
z = ffcdt_expect("php43 clauses", ffcdt_add_php(st2, 4, 3) == 1)
z = ffcdt_expect("php43 UNSAT", ffcdcl_solve(st2, none, 0, 0) == 0 - 1)

# --- 2b. Reserved variable capacity is not logical search state ---
# Only x1/x2 occur, although the arena reserves 4096 variables.  A complete
# model therefore needs at most two decisions; the historical full-capacity
# heap made 4096 decisions and changed trajectories when callers adjusted
# harmless headroom.
sth = i64[ffcdcl_state_size(4096, 4096)]
z = ffcdt_expect("headroom init", ffcdcl_init(sth, 4096, 23) == 1)
head_clause = i64[2]
head_clause[0] = 2
head_clause[1] = 4
z = ffcdt_expect("headroom clause", ffcdcl_add_clause(sth, head_clause, 2) == 1)
z = ffcdt_expect("headroom top variable", ffcdcl_top_var(sth) == 2)
z = ffcdt_expect("headroom SAT", ffcdcl_solve(sth, none, 0, 0) == 1)
z = ffcdt_expect("headroom excluded from decisions", ffcdcl_decisions(sth) <= 2)

# --- 3. Planted random 3-SAT: 30 vars, 120 clauses ---
st3 = i64[ffcdcl_state_size(30, 65536)]
z = ffcdt_expect("planted init", ffcdcl_init(st3, 30, 33) == 1)
cls3 = i64[360]
z = ffcdt_expect("planted build", ffcdt_plant_3sat(st3, cls3, 30, 120, 987654321) == 1)
z = ffcdt_expect("planted SAT", ffcdcl_solve(st3, none, 0, 0) == 1)
z = ffcdt_expect("planted model satisfies every clause", ffcdt_model_ok(st3, cls3, 120) == 1)

# --- 4. XOR ingestion ---
# x1 ^ x2 ^ x3 = 1 with x1, x2 pinned false: x3 is forced true.  The arity-3
# chain allocates one aux variable above the highest referenced var, so
# max_vars carries headroom.
st4 = i64[ffcdcl_state_size(8, 4096)]
z = ffcdt_expect("xor3 init", ffcdcl_init(st4, 8, 44) == 1)
unit4 = i64[1]
unit4[0] = 3
z = ffcdt_expect("xor3 pin x1 false", ffcdcl_add_clause(st4, unit4, 1) == 1)
unit4[0] = 5
z = ffcdt_expect("xor3 pin x2 false", ffcdcl_add_clause(st4, unit4, 1) == 1)
xvars = i64[3]
xvars[0] = 1
xvars[1] = 2
xvars[2] = 3
z = ffcdt_expect("xor3 add", ffcdcl_add_xor(st4, xvars, 3, 1) == 1)
z = ffcdt_expect("xor3 SAT", ffcdcl_solve(st4, none, 0, 0) == 1)
z = ffcdt_expect("xor3 forces x3", ffcdcl_value(st4, 3) == 1 && ffcdcl_value(st4, 1) == 0 && ffcdcl_value(st4, 2) == 0)
# x1 ^ x2 = 0 with x1 true: x2 is forced true.
st4b = i64[ffcdcl_state_size(4, 4096)]
z = ffcdt_expect("xor2 init", ffcdcl_init(st4b, 4, 45) == 1)
unit4[0] = 2
z = ffcdt_expect("xor2 pin x1 true", ffcdcl_add_clause(st4b, unit4, 1) == 1)
xpair = i64[2]
xpair[0] = 1
xpair[1] = 2
z = ffcdt_expect("xor2 add", ffcdcl_add_xor(st4b, xpair, 2, 0) == 1)
z = ffcdt_expect("xor2 SAT", ffcdcl_solve(st4b, none, 0, 0) == 1)
z = ffcdt_expect("xor2 forces x2", ffcdcl_value(st4b, 1) == 1 && ffcdcl_value(st4b, 2) == 1)

# --- 5. Assumption solving over one persistent clause DB: (a -> b) ---
st5 = i64[ffcdcl_state_size(2, 4096)]
z = ffcdt_expect("assume init", ffcdcl_init(st5, 2, 55) == 1)
imp = i64[2]
imp[0] = 3
imp[1] = 4
z = ffcdt_expect("assume add a->b", ffcdcl_add_clause(st5, imp, 2) == 1)
hyp = i64[2]
hyp[0] = 2
z = ffcdt_expect("assume a SAT", ffcdcl_solve(st5, hyp, 1, 0) == 1)
z = ffcdt_expect("assume a forces b", ffcdcl_value(st5, 2) == 1 && ffcdcl_value(st5, 1) == 1)
hyp[0] = 2
hyp[1] = 5
z = ffcdt_expect("assume a and not-b UNSAT", ffcdcl_solve(st5, hyp, 2, 0) == 0 - 1)
hyp[0] = 3
hyp[1] = 5
z = ffcdt_expect("assume not-a not-b SAT", ffcdcl_solve(st5, hyp, 2, 0) == 1)
z = ffcdt_expect("assume not-a not-b model", ffcdcl_value(st5, 1) == 0 && ffcdcl_value(st5, 2) == 0)

# --- 6. Failed-assumption core: (-a -b) under assumptions a, b ---
st6 = i64[ffcdcl_state_size(2, 4096)]
z = ffcdt_expect("core init", ffcdcl_init(st6, 2, 66) == 1)
nand = i64[2]
nand[0] = 3
nand[1] = 5
z = ffcdt_expect("core add nand", ffcdcl_add_clause(st6, nand, 2) == 1)
hyp[0] = 2
hyp[1] = 4
z = ffcdt_expect("core UNSAT", ffcdcl_solve(st6, hyp, 2, 0) == 0 - 1)
core = i64[4]
core_size = ffcdcl_failed_assumptions(st6, core, 4) ## i64
z = ffcdt_expect("core size in range", core_size >= 1 && core_size <= 2)
i = 0 ## i64
while i < core_size
  z = ffcdt_expect("core var is an assumption var", core[i] == 1 || core[i] == 2)
  i += 1
rehyp = i64[2]
i = 0
while i < core_size
  rehyp[i] = 2 * core[i]
  i += 1
z = ffcdt_expect("core alone still UNSAT", ffcdcl_solve(st6, rehyp, core_size, 0) == 0 - 1)

# --- 7. Conflict budget exhaustion on PHP(7,6) ---
st7 = i64[ffcdcl_state_size(42, 16384)]
z = ffcdt_expect("budget init", ffcdcl_init(st7, 42, 77) == 1)
z = ffcdt_expect("budget clauses", ffcdt_add_php(st7, 7, 6) == 1)
z = ffcdt_expect("budget exhausted status", ffcdcl_solve(st7, none, 0, 1) == 0 - 2)

# --- 8. Mark/release: retract a contradicting unit pair ---
st8 = i64[ffcdcl_state_size(4, 4096)]
z = ffcdt_expect("mark init", ffcdcl_init(st8, 4, 88) == 1)
base8 = i64[2]
base8[0] = 2
base8[1] = 4
z = ffcdt_expect("mark base clause", ffcdcl_add_clause(st8, base8, 2) == 1)
z = ffcdt_expect("mark base SAT", ffcdcl_solve(st8, none, 0, 0) == 1)
mark8 = ffcdcl_mark(st8) ## i64
z = ffcdt_expect("mark taken", mark8 >= 0)
unit8 = i64[1]
unit8[0] = 6
z = ffcdt_expect("mark add x3", ffcdcl_add_clause(st8, unit8, 1) == 1)
unit8[0] = 7
z = ffcdt_expect("mark add not-x3", ffcdcl_add_clause(st8, unit8, 1) == 1)
z = ffcdt_expect("mark contradiction UNSAT", ffcdcl_solve(st8, none, 0, 0) == 0 - 1)
z = ffcdt_expect("release accepted", ffcdcl_release(st8, mark8) == 1)
z = ffcdt_expect("released SAT again", ffcdcl_solve(st8, none, 0, 0) == 1)

# --- 9. Equivalence smoke with the Brent-window encoder ---
# The planted 2->1 merge window from flipfleet_sat_destroy_repair_test:
# joint support compresses to a 2x1x1 cube (au=2, av=1, aw=1), want=1, and
# the unique model is local u=3, v=1, w=1 (ambient 3, 4, 8).
su9 = i64[2]
sv9 = i64[2]
sw9 = i64[2]
su9[0] = 1
su9[1] = 2
sv9[0] = 4
sv9[1] = 4
sw9[0] = 8
sw9[1] = 8
uc9 = i64[4]
vc9 = i64[4]
wc9 = i64[4]
lu9 = i64[2]
lv9 = i64[2]
lw9 = i64[2]
target9 = i64[4]
wmeta = i64[12]
z = ffcdt_expect("window prepares", ffsdr_prepare_window(su9, sv9, sw9, 2, 4, 4, 4, uc9, vc9, wc9, lu9, lv9, lw9, target9, wmeta) == 1)
z = ffcdt_expect("window dims", wmeta[0] == 2 && wmeta[1] == 1 && wmeta[2] == 1)
runs9 = i64[64]
words9 = ffsdr_emit_clauses(target9, wmeta[0], wmeta[1], wmeta[2], 1, 64, runs9, wmeta) ## i64
z = ffcdt_expect("clause runs emitted", words9 == 32)
z = ffcdt_expect("clause run dimensions", wmeta[4] == 6 && wmeta[5] == 10)
st9 = i64[ffcdcl_state_size(6, 4096)]
z = ffcdt_expect("window solver init", ffcdcl_init(st9, 6, 99) == 1)
z = ffcdt_expect("window runs ingested", ffcdcl_add_runs(st9, runs9, words9) == 1)
z = ffcdt_expect("window SAT", ffcdcl_solve(st9, none, 0, 0) == 1)
dec_u = i64[1]
dec_v = i64[1]
dec_w = i64[1]
dec_u[0] = ffcdcl_value(st9, ffsdr_primary_u(0, 0, 2, 1, 1)) + 2 * ffcdcl_value(st9, ffsdr_primary_u(0, 1, 2, 1, 1))
dec_v[0] = ffcdcl_value(st9, ffsdr_primary_v(0, 0, 2, 1, 1))
dec_w[0] = ffcdcl_value(st9, ffsdr_primary_w(0, 0, 2, 1, 1))
z = ffcdt_expect("window model matches target", ffsdr_local_terms_match(target9, 2, 1, 1, dec_u, dec_v, dec_w, 1) == 1)
z = ffcdt_expect("window ambient factors", ffsdr_expand_factor(dec_u[0], uc9, 2) == 3 && ffsdr_expand_factor(dec_v[0], vc9, 1) == 4 && ffsdr_expand_factor(dec_w[0], wc9, 1) == 8)
cnf9 = ffsdr_emit_cnf(target9, 2, 1, 1, 1, 64, wmeta)
z = ffcdt_expect("DIMACS path still alive", cnf9 != nil && cnf9.starts_with?("p cnf 6 10\n"))

# --- 10. Performance sanity: planted 3-SAT at 800 vars / 3400 clauses ---
stp = i64[ffcdcl_state_size(800, 1000000)]
z = ffcdt_expect("perf init", ffcdcl_init(stp, 800, 101) == 1)
clsp = i64[10200]
z = ffcdt_expect("perf build", ffcdt_plant_3sat(stp, clsp, 800, 3400, 123456789) == 1)
t0 = ccall("__w_clock_ms") ## i64
perf_status = ffcdcl_solve(stp, none, 0, 200000) ## i64
perf_ms = ccall("__w_clock_ms") - t0 ## i64
<< "CDCL_PERF vars=800 clauses=3400 status=" + perf_status.to_s() + " conflicts=" + ffcdcl_conflicts(stp).to_s() + " learnt=" + ffcdcl_learnt_count(stp).to_s() + " ms=" + perf_ms.to_s()
z = ffcdt_expect("perf SAT within budget", perf_status == 1)
z = ffcdt_expect("perf model satisfies every clause", ffcdt_model_ok(stp, clsp, 3400) == 1)

<< "flipfleet_sat_cdcl_test: all checks passed"
