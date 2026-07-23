# GPU-parallel SLS (E3): many independent WalkSAT/SKC walkers on Metal.
#
# Design: docs/gpu-sls-design.md. One thread = one walker with its own
# assignment, clause bookkeeping, and PRNG stream over the shared read-only
# formula. Kernels run bounded chunks (GPU kernels must terminate); the
# unbounded search is the host dispatch loop. A walker reaching zero
# unsatisfied clauses raises the found flag; the host re-checks the winner's
# count and verifies the extracted model against the ORIGINAL formula before
# anything is reported. The CPU engine (lib/sls.w) is the correctness
# oracle; the GPU trades its sophistication for walker breadth.
#
#   params: 0 nvars  1 ncl  2 walkers  3 chunk flips  4 noise (of 256)
#           5 seed   6 (unused)  7 (unused)
#   ctrl:   0 found flag  1 winning walker id

## i32[]: fla, fcs, fcl, asg, satc, crit, ulist, upos, uc, rngbuf, params
@gpu fn wassat_sls_gpu_init(fla, fcs, fcl, asg, satc, crit, ulist, upos, uc, rngbuf, params)
  wid = gpu.thread_position_in_grid.x ## i32
  nv = params[0] ## i32
  ncl = params[1] ## i32
  walkers = params[2] ## i32
  seed = params[5] ## i32
  if wid < walkers
    rng = (seed * 747796405 + wid * 2891336453 + 277803737) ## u32
    vbase = wid * (nv + 1) ## i32
    cbase = wid * ncl ## i32
    v = 1 ## i32
    while v <= nv
      rng = rng * 747796405 + 2891336453
      bit = (rng >> 16) & 1 ## i32
      asg[vbase + v] = bit
      v = v + 1
    rngbuf[wid] = rng
    ucount = 0 ## i32
    ci = 0 ## i32
    while ci < ncl
      stx = fcs[ci] ## i32
      n = fcl[ci] ## i32
      sc = 0 ## i32
      cv = 0 ## i32
      j = 0 ## i32
      while j < n
        l = fla[stx + j] ## i32
        uv = l ## i32
        if l < 0
          uv = 0 - l
        val = asg[vbase + uv] ## i32
        if l < 0
          val = 1 - val
        if val == 1
          sc = sc + 1
          cv = uv
        j = j + 1
      satc[cbase + ci] = sc
      crit[cbase + ci] = cv
      if sc == 0
        ulist[cbase + ucount] = ci
        upos[cbase + ci] = ucount
        ucount = ucount + 1
      else
        upos[cbase + ci] = 0 - 1
      ci = ci + 1
    uc[wid] = ucount

## i32[]: fla, fcs, fcl, och, ocn, ocv, asg, satc, crit, ulist, upos, uc, rngbuf, ctrl, params
@gpu fn wassat_sls_gpu_walk(fla, fcs, fcl, och, ocn, ocv, asg, satc, crit, ulist, upos, uc, rngbuf, ctrl, params)
  wid = gpu.thread_position_in_grid.x ## i32
  nv = params[0] ## i32
  ncl = params[1] ## i32
  walkers = params[2] ## i32
  chunk = params[3] ## i32
  noise = params[4] ## i32
  if wid < walkers
    if ctrl[0] == 0
      vbase = wid * (nv + 1) ## i32
      cbase = wid * ncl ## i32
      rng = rngbuf[wid] ## u32
      ucount = uc[wid] ## i32
      f = 0 ## i32
      while f < chunk
        if ucount == 0
          ctrl[0] = 1
          ctrl[1] = wid
          f = chunk
        else
          stop = 0 ## i32
          if (f & 255) == 255
            if ctrl[0] != 0
              stop = 1
              f = chunk
          if stop == 0
            # random unsatisfied clause of THIS walker
            rng = rng * 747796405 + 2891336453
            pick = (rng >> 8) ## u32
            ci = ulist[cbase + (pick % ucount)] ## i32
            stx = fcs[ci] ## i32
            n = fcl[ci] ## i32
            rng = rng * 747796405 + 2891336453
            flip = 0 ## i32
            if ((rng >> 8) % 256) < noise
              rng = rng * 747796405 + 2891336453
              rl = fla[stx + ((rng >> 8) % n)] ## i32
              flip = rl
              if rl < 0
                flip = 0 - rl
            else
              # minimum-break member: break(u) = clauses critically
              # satisfied by u, counted over u's currently-true literal
              bestbreak = 2147483647 ## i32
              j = 0 ## i32
              while j < n
                l = fla[stx + j] ## i32
                uv = l ## i32
                if l < 0
                  uv = 0 - l
                li = uv + uv ## i32
                if asg[vbase + uv] == 0
                  li = li + 1
                bk = 0 ## i32
                w = och[li] ## i32
                while w >= 0
                  c2 = ocv[w] ## i32
                  if satc[cbase + c2] == 1
                    if crit[cbase + c2] == uv
                      bk = bk + 1
                  w = ocn[w]
                if bk < bestbreak
                  bestbreak = bk
                  flip = uv
                j = j + 1
            # flip
            nvv = 1 - asg[vbase + flip] ## i32
            asg[vbase + flip] = nvv
            litrue = flip + flip ## i32
            if nvv == 0
              litrue = litrue + 1
            w = och[litrue] ## i32
            while w >= 0
              c2 = ocv[w] ## i32
              old = satc[cbase + c2] ## i32
              satc[cbase + c2] = old + 1
              if old == 0
                p = upos[cbase + c2] ## i32
                last = ulist[cbase + (ucount - 1)] ## i32
                ulist[cbase + p] = last
                upos[cbase + last] = p
                ucount = ucount - 1
                upos[cbase + c2] = 0 - 1
                crit[cbase + c2] = flip
              w = ocn[w]
            lifalse = flip + flip ## i32
            if nvv == 1
              lifalse = lifalse + 1
            w = och[lifalse]
            while w >= 0
              c2 = ocv[w] ## i32
              old = satc[cbase + c2] ## i32
              satc[cbase + c2] = old - 1
              if old == 1
                ulist[cbase + ucount] = c2
                upos[cbase + c2] = ucount
                ucount = ucount + 1
              else
                if old == 2
                  stx2 = fcs[c2] ## i32
                  n2 = fcl[c2] ## i32
                  x = 0 ## i32
                  j2 = 0 ## i32
                  while j2 < n2
                    l2 = fla[stx2 + j2] ## i32
                    uv2 = l2 ## i32
                    if l2 < 0
                      uv2 = 0 - l2
                    if uv2 != flip
                      val2 = asg[vbase + uv2] ## i32
                      if l2 < 0
                        val2 = 1 - val2
                      if val2 == 1
                        x = uv2
                        j2 = n2
                      else
                        j2 = j2 + 1
                    else
                      j2 = j2 + 1
                  crit[cbase + c2] = x
              w = ocn[w]
            f = f + 1
      rngbuf[wid] = rng
      uc[wid] = ucount

# ---- host driver -----------------------------------------------------------

# Thin wrappers over the Metal runtime bridge (the core/metal.w conveniences
# are not autoloaded into bit builds; the ccall names are the stable ABI).
-> wsls_metal_device
  ccall("w_metal_device_default")

-> wsls_metal_compile(device, source)
  ccall("w_metal_compile_source", device, source)

-> wsls_metal_queue(device)
  ccall("w_metal_queue_new", device)

-> wsls_metal_pipeline(library, name)
  ccall("w_metal_pipeline_for", library, name)

-> wsls_metal_array(ebits, size)
  ccall("w_array_new_aligned", ebits, size)

-> wsls_metal_buffer(device, arr)
  ccall("w_array_as_metal_buffer", device, arr)

-> wsls_metal_dispatch(queue, pipeline, bufs, threads)
  ccall("w_metal_dispatch_n", queue, pipeline, bufs, threads)

# Normalise clauses like the CPU engine (dedupe literals, drop tautologies)
# and report an input empty clause.
-> wassat_sls_gpu_normalize(clauses)
  work = []
  impossible = false
  clauses.each -> (c)
    impossible = true if c.size == 0
    uniq = []
    taut = false
    c.each -> (l)
      dup = false
      uniq.each -> (u)
        dup = true if u == l
        taut = true if u == 0 - l
      uniq.push(l) unless dup
    work.push(uniq) unless taut
  { "work": work, "impossible": impossible }

# Run the GPU walker fleet. Deterministic per (seed, walkers, chunk size).
# Returns the CPU engine's result shape; "flips" is the per-walker bound.
-> wassat_sls_gpu_solve(formula, walkers, chunk_flips, chunks, seed, noise, metal_path)
  nv = formula["nvars"]
  norm = wassat_sls_gpu_normalize(formula["clauses"])
  if norm["impossible"]
    return { "sat": false, "model": [], "flips": 0, "restarts": 0,
             "best_unsat": 1, "seed": seed, "walkers": walkers }
  work = norm["work"]
  ncl = work.size
  total = 0
  work.each -> (c)
    total += c.size

  msl = read_file(metal_path)
  raise "cannot read Metal kernel source at '[metal_path]' (build emits it beside the entry point; set WASSAT_METAL to override)" if msl == nil
  device = wsls_metal_device
  raise "no Metal device available" if device == nil
  library = wsls_metal_compile(device, msl)
  raise "Metal kernel compilation failed" if library == nil
  queue = wsls_metal_queue(device)

  fla = wsls_metal_array(32, total + 2)
  fcs = wsls_metal_array(32, ncl + 2)
  fcl = wsls_metal_array(32, ncl + 2)
  och = wsls_metal_array(32, 2 * nv + 4)
  ocn = wsls_metal_array(32, total + 2)
  ocv = wsls_metal_array(32, total + 2)
  i = 0
  while i < 2 * nv + 4
    och[i] = 0 - 1
    i += 1
  pos = 0
  ci = 0
  work.each -> (c)
    fcs[ci] = pos
    fcl[ci] = c.size
    c.each -> (l)
      fla[pos] = l
      li = l > 0 ? 2 * l : 2 * (0 - l) + 1
      ocn[pos] = och[li]
      ocv[pos] = ci
      och[li] = pos
      pos += 1
    ci += 1

  asg = wsls_metal_array(32, walkers * (nv + 1) + 2)
  satc = wsls_metal_array(32, walkers * ncl + 2)
  crit = wsls_metal_array(32, walkers * ncl + 2)
  ulist = wsls_metal_array(32, walkers * ncl + 2)
  upos = wsls_metal_array(32, walkers * ncl + 2)
  uc = wsls_metal_array(32, walkers + 2)
  rngbuf = wsls_metal_array(32, walkers + 2)
  ctrl = wsls_metal_array(32, 4)
  params = wsls_metal_array(32, 8)
  ctrl[0] = 0
  ctrl[1] = 0
  params[0] = nv
  params[1] = ncl
  params[2] = walkers
  params[3] = chunk_flips
  params[4] = noise              # of 256; ~145 for random 3-SAT, ~48 structured
  params[5] = seed

  init_pipe = wsls_metal_pipeline(library, "wassat_sls_gpu_init")
  walk_pipe = wsls_metal_pipeline(library, "wassat_sls_gpu_walk")
  wsls_metal_dispatch(queue, init_pipe, [wsls_metal_buffer(device, fla), wsls_metal_buffer(device, fcs), wsls_metal_buffer(device, fcl), wsls_metal_buffer(device, asg), wsls_metal_buffer(device, satc), wsls_metal_buffer(device, crit), wsls_metal_buffer(device, ulist), wsls_metal_buffer(device, upos), wsls_metal_buffer(device, uc), wsls_metal_buffer(device, rngbuf), wsls_metal_buffer(device, params)], walkers)

  found = false
  c = 0
  while c < chunks && !found
    wsls_metal_dispatch(queue, walk_pipe, [wsls_metal_buffer(device, fla), wsls_metal_buffer(device, fcs), wsls_metal_buffer(device, fcl), wsls_metal_buffer(device, och), wsls_metal_buffer(device, ocn), wsls_metal_buffer(device, ocv), wsls_metal_buffer(device, asg), wsls_metal_buffer(device, satc), wsls_metal_buffer(device, crit), wsls_metal_buffer(device, ulist), wsls_metal_buffer(device, upos), wsls_metal_buffer(device, uc), wsls_metal_buffer(device, rngbuf), wsls_metal_buffer(device, ctrl), wsls_metal_buffer(device, params)], walkers)
    found = ctrl[0] != 0
    c += 1

  best = 2147483647
  wi = 0
  while wi < walkers
    best = uc[wi] if uc[wi] < best
    wi += 1

  if found
    wid = ctrl[1]
    # trust nothing device-side: the winner must really be at zero
    if uc[wid] == 0
      model = []
      vbase = wid * (nv + 1)
      v = 1
      while v <= nv
        model.push(asg[vbase + v] == 1 ? v : 0 - v)
        v += 1
      return { "sat": true, "model": model, "flips": c * chunk_flips,
               "restarts": 0, "best_unsat": 0, "seed": seed,
               "walkers": walkers, "winner": wid }
  { "sat": false, "model": [], "flips": chunks * chunk_flips, "restarts": 0,
    "best_unsat": best, "seed": seed, "walkers": walkers }
