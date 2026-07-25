# SCRATCH EXPERIMENT — not part of the shipped solver. Do not commit.
#
# A/B harness for GPU-parallel subsumption + self-subsuming resolution
# against the CPU native scan (wassat_pre_subpass). Both sides run over the
# SAME frozen post-intake snapshot and must produce the same survivor set.

use ../lib/preprocess

# ---- GPU kernel -------------------------------------------------------------
#
# One thread per subsumer clause. Mirrors wassat_pre_subpass exactly, except
# that literal membership uses a linear scan of the subsumer's (short) literal
# list instead of the shared generation-stamp array, which cannot be
# per-thread on a GPU.
#
#   params: 0 ncl  1 bucket cap  2 out capacity (triples)
#   out triple: [sci, ci, pass_i]   pass_i 0 = subsumption, k>0 = SSR on
#               literal k-1 of the subsumer (host derives the flip literal)

## i32[]: gfcs, gfcl, gfalive, gftaut, gsiglo, gsighi, gfla, gostart, golist, gocount, gout, gctr, gparams
@gpu fn wsub_gpu_scan(gfcs, gfcl, gfalive, gftaut, gsiglo, gsighi, gfla, gostart, golist, gocount, gout, gctr, gparams)
  s = gpu.thread_position_in_grid.x ## i32
  ncl = gparams[0] ## i32
  cap = gparams[1] ## i32
  outcap = gparams[2] ## i32
  if s < ncl
    keep = 1 ## i32
    if gfalive[s] != 1
      keep = 0
    if gftaut[s] == 1
      keep = 0
    slen = 0 ## i32
    if keep == 1
      slen = gfcl[s]
      if slen < 1
        keep = 0
    if keep == 1
      stx = gfcs[s] ## i32
      siglo = gsiglo[s] ## i32
      sighi = gsighi[s] ## i32
      has_dup = 0 ## i32
      a = 0 ## i32
      while a < slen
        b = a + 1 ## i32
        while b < slen
          if gfla[stx + a] == gfla[stx + b]
            has_dup = 1
          b = b + 1
        a = a + 1
      best_li = 0 - 1 ## i32
      best_cnt = 0 ## i32
      j = 0 ## i32
      while j < slen
        l = gfla[stx + j] ## i32
        li = l + l ## i32
        if l < 0
          li = (0 - l) + (0 - l) + 1
        c = gocount[li] ## i32
        if best_li < 0
          best_li = li
          best_cnt = c
        else
          if c < best_cnt
            best_li = li
            best_cnt = c
        j = j + 1
      pass_i = 0 ## i32
      while pass_i <= slen
        mode = 0 ## i32
        li = best_li ## i32
        flip = 0 ## i32
        run = 1 ## i32
        if pass_i > 0
          if has_dup == 1
            run = 0
          else
            mode = 1
            fl = gfla[stx + pass_i - 1] ## i32
            flip = 0 - fl
            li = flip + flip
            if flip < 0
              li = (0 - flip) + (0 - flip) + 1
        if run == 1
          scanned = 0 ## i32
          w = gostart[li] ## i32
          wend = gostart[li + 1] ## i32
          if wend - w > cap
            wend = w + cap
          while w < wend
            ci = golist[w] ## i32
            ok = 1 ## i32
            if ci == s
              ok = 0
            if gfalive[ci] != 1
              ok = 0
            if mode == 1
              if gftaut[ci] == 1
                ok = 0
            n = 0 ## i32
            if ok == 1
              n = gfcl[ci]
              if n < slen
                ok = 0
              if n < 2
                ok = 0
            if ok == 1
              if mode == 0
                if (siglo & gsiglo[ci]) != siglo
                  ok = 0
                if (sighi & gsighi[ci]) != sighi
                  ok = 0
            if ok == 1
              dstx = gfcs[ci] ## i32
              matched = 0 ## i32
              flip_seen = 0 ## i32
              j2 = 0 ## i32
              while j2 < n
                l2 = gfla[dstx + j2] ## i32
                found = 0 ## i32
                k = 0 ## i32
                while k < slen
                  if gfla[stx + k] == l2
                    found = 1
                    k = slen
                  else
                    k = k + 1
                matched = matched + found
                if mode == 1
                  if l2 == flip
                    flip_seen = 1
                j2 = j2 + 1
              hit = 0 ## i32
              if mode == 0
                if matched >= slen
                  hit = 1
              else
                if flip_seen == 1
                  if matched >= slen - 1
                    hit = 1
              if hit == 1
                slot = gpu.atomic_fetch_add_i32(gctr, 0, 1) ## i32
                if slot < outcap
                  gout[3 * slot] = s
                  gout[3 * slot + 1] = ci
                  gout[3 * slot + 2] = pass_i
            w = w + 1
        pass_i = pass_i + 1

# ---- CSR occurrence build (CPU, native typed) -------------------------------

-> wsub_build_csr(fla, fcs, fcl, falive, ocount, ostart, olist, pm) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
  ncl = pm[0]
  nlits = pm[1]
  acc = 0
  li = 0
  while li <= nlits
    ostart[li] = acc
    acc = acc + ocount[li]
    li += 1
  ostart[nlits + 1] = acc
  fill = i64[1]
  ci = 0
  while ci < ncl
    if falive[ci] == 1
      st = fcs[ci]
      n = fcl[ci]
      j = 0
      while j < n
        l = fla[st + j]
        idx = l + l
        if l < 0
          idx = (0 - l) + (0 - l) + 1
        olist[ostart[idx]] = ci
        ostart[idx] = ostart[idx] + 1
        j += 1
    ci += 1
  # rewind the cursors
  acc = 0
  li = 0
  while li <= nlits
    t = ostart[li]
    ostart[li] = acc
    acc = t
    li += 1
  0

# ---- narrowing i64 mirror -> aligned i32 GPU array ---------------------------

-> wsub_narrow(src, dst, n) (i64[] i32[] i64)
  i = 0
  while i < n
    dst[i] = src[i]
    i += 1
  0

-> wsub_split_sig(fsig, lo, hi, n) (i64[] i32[] i32[] i64)
  i = 0
  while i < n
    s = fsig[i]
    lo[i] = s & 4294967295
    hi[i] = (s >> 32) & 4294967295
    i += 1
  0

# Order-independent fingerprint of a survivor multiset. The CPU pass reports
# the flip LITERAL, the GPU the pass index; both are folded to the same key
# (pass index) so the two multisets are directly comparable.
-> wsub_fp_cpu(out, hits, fla, fcs, fcl, acc) (i64[] i64 i64[] i64[] i64[] i64[])
  k = 0
  while k < hits
    sci = out[3 * k + 1]
    ci = out[3 * k + 2]
    fl = out[3 * k + 3]
    pass_i = 0
    if fl != 0
      want = fl
      st = fcs[sci]
      n = fcl[sci]
      j = 0
      while j < n
        if fla[st + j] == want
          pass_i = j + 1
          j = n
        else
          j += 1
    key = (sci * 1000000 + ci) * 64 + pass_i
    acc[0] = acc[0] + 1
    acc[1] = acc[1] + key
    acc[2] = acc[2] ^ key
    k += 1
  0

-> wsub_fp_gpu(gout, hits, acc) (i32[] i64 i64[])
  k = 0
  while k < hits
    sci = gout[3 * k]
    ci = gout[3 * k + 1]
    pass_i = gout[3 * k + 2]
    key = (sci * 1000000 + ci) * 64 + pass_i
    acc[0] = acc[0] + 1
    acc[1] = acc[1] + key
    acc[2] = acc[2] ^ key
    k += 1
  0

-> wsub_sort(a, n) (i64[] i64)
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

-> wsub_now
  ccall("__w_clock_ms")

-> wsub_alloc32(n)
  ccall("w_array_new_aligned", 32, n)

-> wsub_buf(dev, arr)
  ccall("w_array_as_metal_buffer", dev, arr)

# ---- driver -----------------------------------------------------------------

-> wsub_main
  av = argv()
  path = av[0]
  metal_path = av[1]
  text = read_file(path)
  raise "cannot read [path]" if text == nil
  parse = wassat_parse_cnf_native(text)
  nv = parse["nvars"]
  ncl = parse["flat_ncl"]
  nlits = parse["flat_nlits"]
  << "c instance [path] nvars=[nv] clauses=[ncl] literals=[nlits]"

  fccap = 2 * ncl + 4 * nv + 1024
  facap = 2 * nlits + 8 * nv + 4096
  fcs = i64[fccap]
  fcl = i64[fccap]
  falive = i64[fccap]
  ftaut = i64[fccap]
  fsig = i64[fccap]
  fpgid = i64[fccap]
  fla = i64[facap]
  oh = i64[2 * nv + 2]
  onx = i64[facap]
  ov = i64[facap]
  ocount = i64[2 * nv + 2]
  i = 0
  while i < 2 * nv + 2
    oh[i] = 0 - 1
    i += 1
  pm = i64[8]
  pm[0] = ncl
  t0 = wsub_now
  wassat_pre_intake(parse["flat_lits"], parse["flat_offs"], parse["flat_lens"],
                    fla, fcs, fcl, falive, ftaut, fsig, fpgid, oh, onx, ov, ocount, pm)
  asize = pm[1]
  osize = pm[2]
  << "c intake [wsub_now - t0] ms  arena=[asize] occ=[osize]"

  # ---- setup ---------------------------------------------------------------
  lstamp = i64[2 * nv + 2]
  spm = i64[10]
  sout = i64[65536]
  cpu_acc = i64[4]
  gpu_acc = i64[4]

  tg0 = wsub_now
  dev = ccall("w_metal_device_default")
  raise "no Metal device" if dev == nil
  msl = read_file(metal_path)
  raise "cannot read [metal_path]" if msl == nil
  lib = ccall("w_metal_compile_source", dev, msl)
  raise "Metal compile failed" if lib == nil
  queue = ccall("w_metal_queue_new", dev)
  pipe = ccall("w_metal_pipeline_for", lib, "wsub_gpu_scan")
  init_ms = wsub_now - tg0
  << "c gpu device+compile+pipeline [init_ms] ms"

  tcsr = wsub_now
  nlit_idx = 2 * nv + 1
  ostart64 = i64[2 * nv + 4]
  olist64 = i64[osize + 2]
  cpm = i64[4]
  cpm[0] = ncl
  cpm[1] = nlit_idx
  wsub_build_csr(fla, fcs, fcl, falive, ocount, ostart64, olist64, cpm)
  csr_ms = wsub_now - tcsr

  tnar = wsub_now
  gfcs = wsub_alloc32(ncl + 2)
  gfcl = wsub_alloc32(ncl + 2)
  galive = wsub_alloc32(ncl + 2)
  gtaut = wsub_alloc32(ncl + 2)
  gsiglo = wsub_alloc32(ncl + 2)
  gsighi = wsub_alloc32(ncl + 2)
  gfla = wsub_alloc32(asize + 2)
  gostart = wsub_alloc32(2 * nv + 4)
  golist = wsub_alloc32(osize + 2)
  gocount = wsub_alloc32(2 * nv + 4)
  outcap = 1400000
  gout = wsub_alloc32(3 * outcap + 4)
  gctr = wsub_alloc32(4)
  gparams = wsub_alloc32(8)
  wsub_narrow(fcs, gfcs, ncl)
  wsub_narrow(fcl, gfcl, ncl)
  wsub_narrow(falive, galive, ncl)
  wsub_narrow(ftaut, gtaut, ncl)
  wsub_narrow(fla, gfla, asize)
  wsub_narrow(ostart64, gostart, 2 * nv + 3)
  wsub_narrow(olist64, golist, osize)
  wsub_narrow(ocount, gocount, 2 * nv + 2)
  wsub_split_sig(fsig, gsiglo, gsighi, ncl)
  gparams[0] = ncl
  gparams[1] = 1024
  gparams[2] = outcap
  nar_ms = wsub_now - tnar
  << "c csr build [csr_ms] ms  narrow+alloc [nar_ms] ms"

  # ---- interleaved A/B ------------------------------------------------------
  reps = 5
  cms = i64[16]
  gms = i64[16]
  cpu_hits = 0
  gpu_hits = 0
  nth = ncl
  r = 0
  while r < reps
    lgen = 0
    next_ci = 0
    cpu_hits = 0
    cpu_acc[0] = 0
    cpu_acc[1] = 0
    cpu_acc[2] = 0
    tc = wsub_now
    while next_ci < ncl
      base = lgen + 1
      spm[0] = base
      spm[1] = next_ci
      spm[2] = ncl
      spm[3] = 1024
      spm[4] = 4000
      spm[5] = 0
      spm[6] = 0
      wassat_pre_subpass(fla, fcs, fcl, falive, ftaut, fsig, oh, onx, ov, ocount,
                         lstamp, sout, spm)
      lgen = base + ncl + 1
      cpu_hits += sout[0]
      wsub_fp_cpu(sout, sout[0], fla, fcs, fcl, cpu_acc)
      next_ci = spm[6]
    cms[r] = wsub_now - tc

    gctr[0] = 0
    td = wsub_now
    z = ccall("w_metal_dispatch_n", queue, pipe,
              [wsub_buf(dev, gfcs), wsub_buf(dev, gfcl), wsub_buf(dev, galive),
               wsub_buf(dev, gtaut), wsub_buf(dev, gsiglo), wsub_buf(dev, gsighi),
               wsub_buf(dev, gfla), wsub_buf(dev, gostart), wsub_buf(dev, golist),
               wsub_buf(dev, gocount), wsub_buf(dev, gout), wsub_buf(dev, gctr),
               wsub_buf(dev, gparams)], nth)
    gms[r] = wsub_now - td
    gpu_hits = gctr[0]
    gpu_acc[0] = 0
    gpu_acc[1] = 0
    gpu_acc[2] = 0
    capped = gpu_hits
    capped = outcap if gpu_hits > outcap
    wsub_fp_gpu(gout, capped, gpu_acc)
    << "c round [r]: cpu=[cms[r]]ms gpu=[gms[r]]ms"
    r += 1

  wsub_sort(cms, reps)
  wsub_sort(gms, reps)
  cmed = cms[reps / 2]
  gmed = gms[reps / 2]
  agree = "MATCH"
  agree = "MISMATCH" unless cpu_acc[0] == gpu_acc[0] && cpu_acc[1] == gpu_acc[1] && cpu_acc[2] == gpu_acc[2]
  << "c survivor-set [agree]  n=[cpu_acc[0]]/[gpu_acc[0]] sum=[cpu_acc[1]]/[gpu_acc[1]] xor=[cpu_acc[2]]/[gpu_acc[2]]"
  << "c SUMMARY cpu_scan_median=[cmed]ms | gpu_kernel_median=[gmed]ms | gpu_setup csr=[csr_ms]ms narrow=[nar_ms]ms init=[init_ms]ms | survivors=[cpu_hits]"
  0

wsub_main
