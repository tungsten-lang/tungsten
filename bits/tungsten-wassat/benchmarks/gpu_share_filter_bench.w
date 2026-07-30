# SCRATCH EXPERIMENT — not part of the shipped solver. Do not commit.
#
# GpuShareSat-style batched clause filtering (Prevot, SAT'21), measured
# against the identical CPU pass.
#
# THE IDEA. In a clause-sharing portfolio every arm learns clauses, but most
# of another arm's clauses are useless to this arm — and installing one costs
# a store, two watch appends and a propagation. The measured import cliff in
# wassat's own threaded portfolio makes the point: widening the export gate
# from LBD<=4 to LBD<=10 cuts each arm's conflicts (93k -> 60k) and yet takes
# the wall clock from 1.3s to 22s, because the arms drown in installs.
#
# GpuShareSat's answer is to test the WHOLE pool against each arm's current
# assignment and import only the clauses that are FALSE or UNIT under it —
# the ones that would actually propagate or conflict. The test is
# branch-free and identical for every assignment, so one clause read
# amortizes across every assignment in the batch. That is the property that
# makes it GPU-shaped, unlike propagation itself.
#
# WHAT THIS MEASURES. The kernel, honestly, against the same test written as
# a native CPU loop: a pool of P clauses x A assignment bit-vectors, both
# producing the same per-(clause, assignment) verdict codes, compared by
# fingerprint. The pool and assignments are taken from a REAL search — the
# harness runs wassat's own CDCL on the given instance, exports the learned
# clauses it would have shared, and snapshots the trail periodically — so
# the clause lengths, literal distribution and assignment density are the
# ones the filter would actually see, not a synthetic mix.
#
# Usage: wassat-share-filter <cnf> <metal-path> [conflicts] [assignments]

use ../lib/cnf
use ../lib/policy
use ../lib/solver

# ---- shared layout ----------------------------------------------------------
#
# Pool, CSR over i32:
#   gstart[p]  first literal of clause p in gcls
#   glen[p]    its length
#   gcls[...]  literals, DIMACS-signed
#
# Assignments, two bitsets per arm over 1..nvars, `aw` words each:
#   gasg[a * 2 * aw + w]          bit v set = v assigned TRUE
#   gasg[a * 2 * aw + aw + w]     bit v set = v assigned FALSE
#
# Verdict codes, gout[p * narm + a]:
#   0  satisfied, or still has two or more unassigned literals — no interest
#   1  UNIT under this assignment (exactly one non-false literal, unsatisfied)
#   2  FALSE under this assignment (every literal false)

## i32[]: gcls, gstart, glen, gasg, gout, gparams
@gpu fn wsf_gpu_filter(gcls, gstart, glen, gasg, gout, gparams)
  p = gpu.thread_position_in_grid.x ## i32
  npool = gparams[0] ## i32
  narm = gparams[1] ## i32
  aw = gparams[2] ## i32
  if p < npool
    st = gstart[p] ## i32
    n = glen[p] ## i32
    # The clause is read ONCE into thread-private registers and then tested
    # against every assignment — this loop order IS the amortization the
    # whole design rests on. Reversing it (thread per (clause, assignment))
    # re-reads the clause per arm and throws the property away.
    lit = i32[32]
    j = 0 ## i32
    while j < n
      lit[j] = gcls[st + j]
      j = j + 1
    a = 0 ## i32
    while a < narm
      abase = a * 2 * aw ## i32
      nfalse = 0 ## i32
      sat = 0 ## i32
      k = 0 ## i32
      while k < n
        l = lit[k] ## i32
        v = l ## i32
        if l < 0
          v = 0 - l
        w = v >> 5 ## i32
        b = 1 << (v & 31) ## i32
        pos = gasg[abase + w] & b ## i32
        neg = gasg[abase + aw + w] & b ## i32
        # true-ness and false-ness without && or || (rejected in @gpu)
        istrue = 0 ## i32
        isfalse = 0 ## i32
        if l > 0
          if pos != 0
            istrue = 1
          if neg != 0
            isfalse = 1
        else
          if neg != 0
            istrue = 1
          if pos != 0
            isfalse = 1
        if istrue == 1
          sat = 1
        nfalse = nfalse + isfalse
        k = k + 1
      code = 0 ## i32
      if sat == 0
        if nfalse == n
          code = 2
        else
          if nfalse == n - 1
            code = 1
      gout[p * narm + a] = code
      a = a + 1

# ---- the same test, natively, on the CPU ------------------------------------

-> wsf_cpu_filter(cls, start, len, asg, out, npool, narm, aw) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64)
  one = 1 ## i64
  p = 0 ## i64
  while p < npool
    st = start[p] ## i64
    n = len[p] ## i64
    a = 0 ## i64
    while a < narm
      abase = a * 2 * aw ## i64
      nfalse = 0 ## i64
      sat = 0 ## i64
      k = 0 ## i64
      while k < n
        l = cls[st + k] ## i64
        v = l ## i64
        v = 0 - l if l < 0
        w = v >> 6 ## i64
        b = one << (v & 63) ## i64
        pos = asg[abase + w] & b ## i64
        neg = asg[abase + aw + w] & b ## i64
        istrue = pos ## i64
        isfalse = neg ## i64
        if l < 0
          istrue = neg
          isfalse = pos
        sat = 1 if istrue != 0
        nfalse = nfalse + 1 if isfalse != 0
        k = k + 1
      code = 0 ## i64
      if sat == 0
        code = 2 if nfalse == n
        code = 1 if nfalse == n - 1
      out[p * narm + a] = code
      a = a + 1
    p = p + 1
  0

-> wsf_fp(out, n, acc) (i64[] i64 i64[])
  i = 0
  while i < n
    c = out[i]
    acc[0] += c
    acc[1] = acc[1] ^ ((i + 1) * (c + 1))
    acc[2] += 1 if c == 1
    acc[3] += 1 if c == 2
    i += 1
  0

-> wsf_fp32(out, n, acc) (i32[] i64 i64[])
  i = 0
  while i < n
    c = out[i]
    acc[0] += c
    acc[1] = acc[1] ^ ((i + 1) * (c + 1))
    acc[2] += 1 if c == 1
    acc[3] += 1 if c == 2
    i += 1
  0

-> wsf_narrow(src, dst, n) (i64[] i32[] i64)
  i = 0
  while i < n
    dst[i] = src[i]
    i += 1
  0

# The i64 bitsets are rewritten as i32 halves: bit v of word v>>6 becomes bit
# v of word v>>5, so the two sides index the SAME logical bit.
-> wsf_narrow_asg(src, dst, narm, aw64) (i64[] i32[] i64 i64)
  aw32 = 2 * aw64
  a = 0
  while a < narm
    h = 0
    while h < 2
      w = 0
      while w < aw64
        x = src[a * 2 * aw64 + h * aw64 + w]
        dst[a * 2 * aw32 + h * aw32 + 2 * w] = x & 4294967295
        dst[a * 2 * aw32 + h * aw32 + 2 * w + 1] = (x >> 32) & 4294967295
        w += 1
      h += 1
    a += 1
  0

-> wsf_sort(a, n) (i64[] i64)
  i = 1
  while i < n
    v = a[i]
    j = i - 1
    while j >= 0 && a[j] > v
      a[j + 1] = a[j]
      j -= 1
    a[j + 1] = v
    i += 1
  0

-> wsf_now
  ccall("__w_clock_ms")

-> wsf_alloc32(n)
  ccall("w_array_new_aligned", 32, n)

-> wsf_buf(dev, arr)
  ccall("w_array_as_metal_buffer", dev, arr)

# ---- driver -----------------------------------------------------------------

-> wsf_main
  av = argv()
  path = av[0]
  metal_path = av[1]
  budget = av.size > 2 ? av[2].to_i : 20000
  narm = av.size > 3 ? av[3].to_i : 32
  text = read_file(path)
  raise "cannot read [path]" if text == nil
  parse = wassat_parse_cnf_native(text)
  nv = parse["nvars"]
  << "c instance [path] nvars=[nv] clauses=[parse["flat_ncl"]] budget=[budget] assignments=[narm]"

  # ---- harvest a REAL pool and REAL assignments ----------------------------
  #
  # One CDCL run over the instance, stopped at `budget` conflicts, with the
  # sharing ring attached: the ring then holds exactly the clauses this arm
  # would have exported. Assignments are the trail bitsets sampled while it
  # ran, which is what gives the pool the density a live filter would see.
  ring_maxlen = 24
  ring_cap = 65536
  ring_stride = 3 + ring_maxlen
  ring = i64[8 + ring_cap * ring_stride]
  aw64 = nv / 64 + 2
  asg = i64[narm * 2 * aw64 + 8]

  s = Wassat.new(nv, parse["clauses"], WASSAT_PROOF_NONE, 0)
  s.enable_sharing(ring, ring_cap, ring_maxlen, 0)
  s.set_share_lbd(12)
  s.set_assignment_sink(asg, aw64, narm, budget / narm + 1)
  t0 = wsf_now
  r = s.solve_budget(budget)
  harvest_ms = wsf_now - t0
  nasg = s.assignment_samples
  npool = ring[0]
  npool = ring_cap if npool > ring_cap
  raise "no clauses harvested — raise the conflict budget" if npool < 1
  raise "no assignments harvested" if nasg < 1
  narm = nasg if nasg < narm
  << "c harvest [harvest_ms]ms status=[r["status"]] conflicts=[r["conflicts"]] pool=[npool] assignments=[narm]"

  # ---- flatten the ring into CSR ------------------------------------------
  start = i64[npool + 2]
  len = i64[npool + 2]
  cls = i64[npool * ring_maxlen + 4]
  acc = 0
  totlen = 0
  p = 0
  while p < npool
    base = 8 + (p % ring_cap) * ring_stride
    n = ring[base + 2]
    n = ring_maxlen if n > ring_maxlen
    n = 0 if n < 0
    start[p] = acc
    len[p] = n
    i = 0
    while i < n
      cls[acc + i] = ring[base + 3 + i]
      i += 1
    acc += n
    totlen += n
    p += 1
  avg = npool == 0 ? 0 : 100 * totlen / npool
  << "c pool literals=[totlen] avg_len_x100=[avg]"

  cpu_out = i64[npool * narm + 4]
  cpu_acc = i64[8]
  gpu_acc = i64[8]

  # ---- GPU setup -----------------------------------------------------------
  tg0 = wsf_now
  dev = ccall("w_metal_device_default")
  raise "no Metal device" if dev == nil
  msl = read_file(metal_path)
  raise "cannot read [metal_path]" if msl == nil
  lib = ccall("w_metal_compile_source", dev, msl)
  raise "Metal compile failed" if lib == nil
  queue = ccall("w_metal_queue_new", dev)
  pipe = ccall("w_metal_pipeline_for", lib, "wsf_gpu_filter")
  init_ms = wsf_now - tg0
  << "c gpu device+compile+pipeline [init_ms] ms"

  tnar = wsf_now
  aw32 = 2 * aw64
  gcls = wsf_alloc32(acc + 4)
  gstart = wsf_alloc32(npool + 2)
  glen = wsf_alloc32(npool + 2)
  gasg = wsf_alloc32(narm * 2 * aw32 + 8)
  gout = wsf_alloc32(npool * narm + 4)
  gparams = wsf_alloc32(8)
  wsf_narrow(cls, gcls, acc)
  wsf_narrow(start, gstart, npool)
  wsf_narrow(len, glen, npool)
  wsf_narrow_asg(asg, gasg, narm, aw64)
  gparams[0] = npool
  gparams[1] = narm
  gparams[2] = aw32
  nar_ms = wsf_now - tnar
  << "c narrow+alloc [nar_ms] ms"

  # ---- interleaved A/B -----------------------------------------------------
  reps = 5
  cms = i64[16]
  gms = i64[16]
  nth = npool
  r2 = 0
  while r2 < reps
    cpu_acc[0] = 0
    cpu_acc[1] = 0
    cpu_acc[2] = 0
    cpu_acc[3] = 0
    tc = wsf_now
    wsf_cpu_filter(cls, start, len, asg, cpu_out, npool, narm, aw64)
    cms[r2] = wsf_now - tc
    wsf_fp(cpu_out, npool * narm, cpu_acc)

    gpu_acc[0] = 0
    gpu_acc[1] = 0
    gpu_acc[2] = 0
    gpu_acc[3] = 0
    td = wsf_now
    z = ccall("w_metal_dispatch_n", queue, pipe,
              [wsf_buf(dev, gcls), wsf_buf(dev, gstart), wsf_buf(dev, glen),
               wsf_buf(dev, gasg), wsf_buf(dev, gout), wsf_buf(dev, gparams)], nth)
    gms[r2] = wsf_now - td
    wsf_fp32(gout, npool * narm, gpu_acc)
    << "c round [r2]: cpu=[cms[r2]]ms gpu=[gms[r2]]ms"
    r2 += 1

  wsf_sort(cms, reps)
  wsf_sort(gms, reps)
  cmed = cms[reps / 2]
  gmed = gms[reps / 2]
  agree = "MATCH"
  agree = "MISMATCH" unless cpu_acc[0] == gpu_acc[0] && cpu_acc[1] == gpu_acc[1] && cpu_acc[2] == gpu_acc[2] && cpu_acc[3] == gpu_acc[3]
  tests = npool * narm
  << "c verdicts [agree]  sum=[cpu_acc[0]]/[gpu_acc[0]] xor=[cpu_acc[1]]/[gpu_acc[1]] unit=[cpu_acc[2]]/[gpu_acc[2]] false=[cpu_acc[3]]/[gpu_acc[3]]"
  << "c selectivity: [cpu_acc[2] + cpu_acc[3]] of [tests] clause-assignment tests are unit-or-false"
  crate = cmed == 0 ? 0 : tests / cmed
  grate = gmed == 0 ? 0 : tests / gmed
  << "c SUMMARY cpu_median=[cmed]ms ([crate]k tests/s) | gpu_median=[gmed]ms ([grate]k tests/s) | setup init=[init_ms]ms narrow=[nar_ms]ms"
  0

wsf_main
