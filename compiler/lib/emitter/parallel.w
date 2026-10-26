# Deterministic per-function emitter workers. Global analysis, function order,
# metadata numbering, attribute groups, and final concatenation remain serial;
# workers only render immutable WIRE functions into private buffers.

-> emitter_parallel_job_count(mod, cache_bucket)
  # compile-batch already shards work across processes. Do not multiply each
  # child by another worker team and oversubscribe the host.
  if cache_bucket != nil || env("TUNGSTEN_BATCH_WORKER_PROCESS") == "1" || env("TUNGSTEN_PARALLEL_FUNCTION_EMIT") == "0" || runtime_identity() != "compiled-runtime"
    return 1
  if mod[:functions].size() < 64
    return 1
  requested = 0
  configured = env("TUNGSTEN_EMITTER_JOBS")
  if configured != nil && configured != "" && configured != "auto"
    requested = configured.to_i()
  if requested < 1
    requested = ccall("w_cpu_count")
    if requested > 8
      requested = 8
  if requested < 1
    requested = 1
  if requested > mod[:functions].size()
    requested = mod[:functions].size()
  if requested > 32
    requested = 32
  requested

-> emitter_prepare_parallel_metadata(functions, fp_flags, attr_groups = nil, base_attr_text = nil)
  fi = 0
  while fi < functions.size()
    # Complete the last function-record mutation before workers start. Once
    # they are running, the WIRE graph is read-only.
    f = functions[fi]
    f[:fp_flags] = fp_flags
    if attr_groups != nil && base_attr_text != nil && f[:embedded_ll] == nil && f[:embedded_asm] == nil
      function_attr_group_id(attr_groups, base_attr_text)
      attr_text = base_attr_text
      if f[:noinline] == true
        attr_text = attr_text + " noinline"
      elsif f[:is_toplevel] == true && f[:blocks] != nil && f[:blocks].size() > 2000
        attr_text = attr_text + " noinline optnone"
      function_attr_group_id(attr_groups, attr_text)
    if f[:params] != nil
      pi = 0
      while pi < f[:params].size()
        if f[:embedded_ll] != nil
          llvm_safe_name(f[:params][pi])
        else
          llvm_param_reg(f[:params][pi])
        pi += 1
    blocks = f[:blocks]
    bi = 0
    while bi < blocks.size()
      instructions = blocks[bi][:instructions]
      ii = 0
      while ii < instructions.size()
        inst = instructions[ii]
        sid = wire_get(inst, :ewscope)
        if sid != nil
          ewscope_list_id(sid)
        if wire_kind(inst) == :br
          novec = wire_get(inst, :novec) == true
          unroll_count = wire_get(inst, :unroll_count)
          if novec && unroll_count != nil && unroll_count > 0
            novec_md_state[:refs][inst] = latch_loop_md_ref(:both, unroll_count)
          elsif novec
            novec_md_state[:refs][inst] = latch_loop_md_ref(:novec)
          elsif unroll_count != nil && unroll_count > 0
            novec_md_state[:refs][inst] = latch_loop_md_ref(:unroll, unroll_count)
        ii += 1
      bi += 1
    fi += 1
  nil

-> emitter_parallel_worker(state)
  functions = state[:functions]
  texts = state[:texts]
  ptr_ids = state[:ptr_ids]
  # ccall's ordinary integer literal is a raw machine value. These exact
  # literals are boxed Int zero/one, matching the WAtomic ABI without an
  # allocation or a dynamic source-method call in the work loop.
  index = ccall("w_atomic_add", state[:cursor], u0xFFFA000000000001)
  while index < functions.size()
    f = functions[index]
    local_ptr_ids = {}
    texts[index] = emit_function(f, state[:string_wvs], state[:slab_info], local_ptr_ids, state[:frame_pointers], state[:host_fn_attrs], state[:attr_groups], state[:arm64_target], state[:windows_target], state[:preserve_debug_frames])
    ptr_ids[index] = local_ptr_ids.keys()
    index = ccall("w_atomic_add", state[:cursor], u0xFFFA000000000001)
  true

-> emitter_render_functions_parallel(functions, string_wvs, slab_info, frame_pointers, host_fn_attrs, attr_groups, arm64_target, windows_target, preserve_debug_frames, jobs)
  texts = Array.new(functions.size())
  ptr_ids = Array.new(functions.size())
  cursor = ccall("w_atomic_new", u0xFFFA000000000000)
  naming_cache_state[:frozen] = true
  workers = []
  worker = 0
  while worker < jobs
    state = {
      functions: functions,
      texts: texts,
      ptr_ids: ptr_ids,
      cursor: cursor,
      string_wvs: string_wvs,
      slab_info: slab_info,
      frame_pointers: frame_pointers,
      host_fn_attrs: host_fn_attrs,
      attr_groups: attr_groups,
      arm64_target: arm64_target,
      windows_target: windows_target,
      preserve_debug_frames: preserve_debug_frames
    }
    workers.push(Thread.new ->
      emitter_parallel_worker(state))
    worker += 1
  worker = 0
  while worker < workers.size()
    ccall("w_thread_join_release", workers[worker])
    worker += 1
  naming_cache_state[:frozen] = false
  {texts: texts, ptr_ids: ptr_ids}
