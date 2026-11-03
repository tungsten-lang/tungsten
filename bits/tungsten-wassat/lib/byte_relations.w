# Refute a circuit mismatch using functions derived from its original CNF.
# The decoder checks every gate definition; original units justify constants.
# Complete equality-cube relations provide byte truth tables. Arithmetic
# candidates need a local CDCL proof before substitution. Symbolic Boolean
# equality then falsifies an original residual clause. Unsupported inputs,
# incomplete relations, resource limits and cancellation return UNKNOWN.
# Proof-producing CLI modes use ordinary certificate-backed solving instead.
use byte_relations/decoder

# Metric cells 0..10: decode/gate/congruence work; 11 stop reason, 12 polls;
# 16..22: table/region/template/query/proof counts; 23 original conflict clause;
# 24..28 cumulative stage times; 29..30 propagation work/units; 31..36 expression
# counts; 37 expression allocation charge; 38..39 verdict/time; 40..41 local
# sample/proof conflicts. A fresh attempt resets all cells before allocation.

-> wassat_byte_flat_valid(lits, offs, lens, nv, nc, nl, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64) i64
  return 0 if offs.size < nc || lens.size < nc || nl < 0 || nl > lits.size
  ci = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_byte_poll(m, stop, deadline) != 0
    n = lens[ci]; off = offs[ci]
    return 0 if n < 1 || n > 65 || off < 0 || off > nl || n > nl - off
    j = 0
    while j < n
      v = wassat_byte_abs(lits[off + j])
      return 0 if v < 1 || v > nv
      j += 1
    ci += 1
  1

# Only UNSAT or UNKNOWN. Every published contradiction is an original clause
# evaluated under consequences checked from this input. No model is produced.
-> wassat_byte_refute(formula, m, stop, deadline = 0)
  started = clock_ms()
  return 0 if m.size < 64 || stop.size < 2
  i = 0
  while i < 64
    m[i] = 0; i += 1
  return 0 if wassat_byte_poll(m, stop, deadline) != 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return 0 if nv < 1 || nv > 1000000 || nc < 1 || nc > 5000000
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  nl = formula["flat_nlits"]
  return 0 if nl > 20000000
  return 0 if wassat_byte_flat_valid(lits, offs, lens, nv, nc, nl, m, stop, deadline) != 1
  program = i64[8 * (nv + 1)]; inputs = i64[nl]
  units = i64[nc]; residual = i64[1024]
  return 0 if wassat_byte_decode(lits, offs, lens, nv, nc, program, inputs, units, residual, m, stop, deadline) != 1
  m[24] = clock_ms() - started
  values = i8[nv + 1]; rm = i64[20]
  r = wassat_byte_root_alternate(lits, offs, lens, nc, values, 32, rm, stop, deadline)
  m[25] = clock_ms() - started; m[29] = rm[5]; m[30] = rm[7]
  m[11] = rm[8] if rm[8] != 0
  return 0 if wassat_byte_poll(m, stop, deadline) != 0
  if r == -1
    m[23] = rm[9]; return -1
  parent = i64[nv + 2]; cap = 1
  while cap < 2 * nv
    cap *= 2
  keys = i64[m[4] + 4 * nv]; slots = i64[cap]; scratch = i64[64]
  return 0 if wassat_byte_congruence(program, inputs, values, parent, nv, keys, slots, scratch, m, stop, deadline) != 1
  m[26] = clock_ms() - started
  groups = i64[80 * 512]; tables = i64[256 * 512]
  table_slots = i64[2048]; table_scratch = i64[72]
  return 0 if wassat_byte_tables(program, inputs, units, m[1], values, groups, tables, table_slots, table_scratch, m, stop, deadline) != 1
  return 0 if wassat_byte_linear_groups(formula, program, inputs, groups, tables, m, stop, deadline) != 1
  m[27] = clock_ms() - started
  e = WassatByteExpressions.new(program, inputs, parent, groups, tables, nv, m[16], m, stop, deadline)
  ri = 0; refuted = false
  while ri < m[2] && !e.failed
    ci = residual[ri]; j = 0; all_false = true
    while j < lens[ci] && !e.failed
      x = e.get(lits[offs[ci] + j])
      all_false = false if x != 0
      j += 1
    if all_false && !e.failed
      refuted = true; m[23] = ci + 1
    ri += 1
  m[28] = clock_ms() - started; m[31] = e.nodes.size; m[32] = e.supports
  m[33] = e.scheduled_gates; m[34] = e.scheduled_tables; m[35] = e.primary; m[36] = e.cycles
  return 0 if e.failed || wassat_byte_poll(m, stop, deadline) != 0
  refuted ? -1 : 0

# A bounded additive worker over original clauses. It is admitted last,
# without removing a CDCL basin or sharing its local learned clauses. Large
# races can already exceed the 2.5 GiB optional-arena admission target because
# their retired scouts stay resident. Account for ALL of those arenas here;
# this bounded lane has a separate six-GiB envelope, capped at one third of
# physical RAM, leaving two GiB below the normal eight-GiB process guard.
# This does not change admission of any established worker.
-> wassat_byte_plan(formula, workers, cdcl, sls, pre, extra, lucky = 0)
  mode = env("WASSAT_BYTE_RELATION")
  return nil if mode == "0" || System.cpu_count <= workers || wassat_race_round1_conflicts != 0
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  return nil if nv < 256 || nv > 1000000 || nc < 1000 || nc > 5000000 || nl > 20000000
  # A constant-size prefix screen for byte equality cubes. Exact recognition
  # and all large allocation stay inside the worker. Explicit opt-in allows
  # broader diagnostics, while every verdict uses the same exact checks.
  if mode != "1"
    lens = formula["flat_lens"]; i = 0; units = 0; binary = 0; wide = 0
    while i < nc && i < 256
      n = lens[i]; units += 1 if n == 1; binary += 1 if n == 2
      wide += 1 if n == 9 || n == 33; i += 1
    return nil if units == 0 || binary < 16 || wide < 2
  scratch = 536870912 + 192 * (nv + 1) + 16 * nl + 8 * nc
  # The caller includes retired lucky arenas in cdcl. Replace only those
  # reservations with the lean loader envelope; they cannot resume CDCL.
  return nil if lucky < 0 || lucky > cdcl
  estimate = wassat_cdcl_arena_bytes(formula) * (cdcl - lucky)
  estimate += wassat_lucky_arena_bytes(formula) * lucky if lucky > 0
  estimate += wassat_flat_sls_arena_bytes(formula) * sls
  estimate += wassat_preprocess_arena_bytes(formula) * pre + extra + scratch
  memory = System.physical_memory_bytes ## i64
  ceiling = memory / 3; ceiling = 6442450944 if ceiling > 6442450944
  wassat_prof_note("race.byte_plan estimate=[estimate] ceiling=[ceiling] scratch=[scratch] lucky_arenas=[lucky] preprocess_arenas=[pre]")
  return nil if memory <= 0 || estimate > ceiling
  {"byte_relation": true, "meta": i64[64], "scratch": scratch}

-> wassat_byte_arm(formula, m, stop, res, base, nv)
  started = clock_ms(); res[base + nv + 6] = started
  r = wassat_byte_refute(formula, m, stop, started + 2000)
  res[base + nv + 5] = clock_ms()
  m[38] = r; m[39] = res[base + nv + 5] - started
  if r == -1 && !wassat_stop_requested?(stop)
    z = ccall("__w_arr_store_rel", res, base, -1)
    z = wassat_stop_publish(stop, -1)
  0

-> wassat_byte_profile(m)
  wassat_prof_note("race.byte result=[m[38]] ms=[m[39]] gates=[m[0]] roots=[m[30]] tables=[m[18]] blocks=[m[19]] templates=[m[20]] queries=[m[21]] proofs=[m[22]] clause=[m[23]] decode_ms=[m[24]] root_ms=[m[25]] congruence_ms=[m[26]] linear_ms=[m[27]] symbolic_ms=[m[28]] nodes=[m[31]] expression_bytes=[m[37]] sample_conflicts=[m[40]] proof_conflicts=[m[41]] stop=[m[11]]")
