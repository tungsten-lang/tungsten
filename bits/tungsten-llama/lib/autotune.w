# Phase 4 autotuner — minimum-viable harness.
#
# Takes a list of named kernel variants (compiled from one or more
# @schedule blocks) and a benchmark setup (input/output buffers, dispatch
# shape, expected output), and:
#   1. Validates each variant's output against the baseline.
#   2. Times each variant via N-iteration warmup + M-iteration measurement.
#   3. Reports a sorted ranking and writes the winner to a cache file
#      keyed by (kernel-identity, shape-tuple).
#
# The "wrong-but-fast never wins" rule from the plan: a variant whose
# output diverges from baseline by more than abs_tol is dropped, even
# if it ran faster.
#
# v1 takes hand-written @schedule variants and picks among them. The
# enumeration step (programmatic schedule generation across a bounded
# grammar) is future work but already enabled by the new vectorize
# primitive plus the existing parallelize/stride/reduce primitives.

in Tungsten:Llama

+ AutotuneCandidate
  rw :name        # variant name, e.g. "q8_matvec_coop_packed"
  rw :pipeline    # MTLComputePipelineState
  rw :dispatch_n  # threads for metal_dispatch_n (or n_groups for groups)
  rw :tg_size     # threads_per_group (0 = use dispatch_n)
  rw :bufs        # array of MTLBuffer args

  -> new(name, pipeline, dispatch_n, tg_size, bufs)
    @name = name
    @pipeline = pipeline
    @dispatch_n = dispatch_n
    @tg_size = tg_size
    @bufs = bufs

+ Autotuner
  rw :queue
  rw :candidates
  rw :baseline_idx     # index of the variant whose output is the truth
  rw :output_buf       # buffer that holds the result (for validation)
  rw :output_n         # number of f32 elements to compare
  rw :abs_tol          # max absolute difference for validation pass
  rw :warmup_iters
  rw :measure_iters

  -> new(queue, candidates, output_buf, output_n)
    @queue = queue
    @candidates = candidates
    @baseline_idx = 0
    @output_buf = output_buf
    @output_n = output_n
    @abs_tol = ~0.001
    @warmup_iters = 3
    @measure_iters = 20

  # Dispatch one candidate once.
  -> dispatch_one(c)
    if c.tg_size == 0
      metal_dispatch_n(@queue, c.pipeline, c.bufs, c.dispatch_n)
    else
      metal_dispatch_groups(@queue, c.pipeline, c.bufs, c.dispatch_n, c.tg_size)

  # Read the output buffer into an array.
  -> read_output
    out = []
    i = 0
    while i < @output_n
      out.push(metal_buffer_read_f32(@output_buf, i))
      i = i + 1
    out

  # Run a candidate, capture its output.
  -> capture_output(c)
    dispatch_one(c)
    read_output()

  # Element-wise compare to baseline. Returns the max abs error.
  -> max_diff(a, b)
    m = ~0.0
    i = 0
    while i < a.size()
      d = a[i] - b[i]
      if d < ~0.0
        d = ~0.0 - d
      if d > m
        m = d
      i = i + 1
    m

  # Time a candidate via warmup + measure passes. Returns ms per dispatch.
  -> time_one(c)
    i = 0
    while i < @warmup_iters
      dispatch_one(c)
      i = i + 1
    metal_batch_begin(@queue)
    i = 0
    while i < @measure_iters
      dispatch_one(c)
      i = i + 1
    t0 = ccall("__w_clock_ms")
    metal_batch_commit(@queue)
    t1 = ccall("__w_clock_ms")
    (t1 - t0) * ~1.0 / @measure_iters

  # Run the full sweep. Reports each candidate as (valid?, max_err, ms/iter).
  # Returns the index of the winner (fastest valid candidate), or -1
  # if no candidate passed validation.
  -> run
    baseline_out = capture_output(@candidates[@baseline_idx])
    << "autotune sweep: " + @candidates.size().to_s + " candidates, baseline=" + @candidates[@baseline_idx].name
    best_idx = -1
    best_ms = ~1000000000.0
    i = 0
    while i < @candidates.size()
      c = @candidates[i]
      cand_out = capture_output(c)
      err = max_diff(cand_out, baseline_out)
      valid = err <= @abs_tol
      ms = time_one(c)
      mark = "  "
      if valid && ms < best_ms
        best_ms = ms
        best_idx = i
        mark = "* "
      tag = "\[ok\]"
      if !valid
        tag = "\[FAIL\]"
      << mark + c.name + " — err=" + err.to_s + " ms/iter=" + ms.to_s + " " + tag
      i = i + 1
    if best_idx >= 0
      << ""
      << "winner: " + @candidates[best_idx].name + " at " + best_ms.to_s + " ms/iter"
    else
      << ""
      << "no valid candidate"
    best_idx

  # Write the winner to a cache file keyed by (kernel-identity,
  # shape-tuple). Future compilation runs can read this back to pick
  # the schedule the autotuner converged on without re-running the
  # whole sweep. JSON-ish format (Tungsten stringification — close
  # enough for a v1 cache).
  -> write_cache(cache_dir, kernel_id, shape_key, winner_idx, winner_ms)
    if winner_idx < 0
      return nil
    w = @candidates[winner_idx]
    sb = StringBuffer(256)
    sb << "{\"kernel\": \""
    sb << kernel_id
    sb << "\", \"shape\": \""
    sb << shape_key
    sb << "\", \"winner\": \""
    sb << w.name
    sb << "\", \"ms_per_iter\": "
    sb << winner_ms.to_s
    sb << "}\n"
    path = cache_dir + "/" + kernel_id + "-" + shape_key + ".json"
    write_file(path, sb.to_s)
    << "cached: " + path
