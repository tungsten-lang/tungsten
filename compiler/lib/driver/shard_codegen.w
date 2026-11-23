# Parallel native `.ll -> .o` shard compilation and content-addressed `.o` store cache.

-> shard_codegen_job_count
  configured = env("TUNGSTEN_SHARD_JOBS")
  if configured != nil && configured != "" && configured != "auto"
    n = configured.to_i()
    if n < 2
      return 0
    return n > 16 ? 16 : n
  cpus = ccall("w_cpu_count")
  if cpus < 2
    return 0
  cpus > 16 ? 16 : cpus

-> shard_codegen_base_config(cc_identity, compile_flags, path_map_flag)
  cfg = StringBuffer(512)
  cfg << "cc="
  cfg << cc_identity
  cfg << "\nflags="
  cfg << compile_flags
  cfg << path_map_flag
  cfg << "\n"
  dev_runtime_append_env(cfg, "SDKROOT")
  dev_runtime_append_env(cfg, "MACOSX_DEPLOYMENT_TARGET")
  dev_runtime_append_env(cfg, "CPATH")
  dev_runtime_append_env(cfg, "C_INCLUDE_PATH")
  dev_runtime_append_env(cfg, "CPLUS_INCLUDE_PATH")
  cfg.to_s()

-> shard_sort_indices_desc(indices, shard_irs)
  n = indices.size()
  out = []
  i = 0
  while i < n
    out.push(indices[i])
    i += 1
  i = 1
  while i < n
    cur = out[i]
    cur_sz = shard_irs[cur].size()
    j = i
    while j > 0 && shard_irs[out[j - 1]].size() < cur_sz
      out[j] = out[j - 1]
      j -= 1
    out[j] = cur
    i += 1
  out

-> shard_codegen_canonical_shards
  configured = env("TUNGSTEN_SHARD_COUNT")
  if configured != nil && configured != "" && configured != "auto"
    n = configured.to_i()
    if n < 2
      return 0
    return n > 16 ? 16 : n
  16

-> shard_run_commands(work_dir, cmds, max_jobs)
  ncmds = cmds.size()
  if ncmds == 0
    return true
  if max_jobs >= ncmds
    cmd = StringBuffer(ncmds * 256 + 64)
    i = 0
    while i < ncmds
      cmd << "( "
      cmd << cmds[i]
      cmd << " ) & "
      i += 1
    cmd << "wait"
    return system(cmd.to_s()) == true
  # Bounded parallelism: write each shard command to its own script (ordered
  # largest IR first) and let xargs -P schedule at most max_jobs clangs at once.
  list_buf = StringBuffer(ncmds * 64 + 128)
  list_buf << "printf '%s\\n'"
  i = 0
  while i < ncmds
    script = work_dir + "/job_" + i.to_s() + ".sh"
    write_file(script, cmds[i] + "\n")
    list_buf << " "
    list_buf << dev_runtime_shell_quote(script)
    i += 1
  list_buf << " | xargs -P "
  list_buf << max_jobs.to_s()
  list_buf << " -n 1 /bin/sh"
  system(list_buf.to_s()) == true

-> native_sharded_codegen_objects(ll_path, clang_opt, store_entries, verbose = false, lto_flag = "")
  rt_id = runtime_identity()
  if rt_id != "compiled-runtime" && rt_id != "tungsten-c"
    return nil
  if env("TUNGSTEN_SHARD_CODEGEN") == "0" || env("TUNGSTEN_BATCH_WORKER_PROCESS") == "1"
    return nil
  if cross_target != ""
    return nil
  if clang_opt != nil && clang_opt.index("-fprofile") != nil
    return nil
  if g_incremental[:last_emitted_ll_path] != ll_path
    return nil
  plan = emitter_last_artifact_state[:shard_plan]
  if plan == nil
    return nil
  max_jobs = shard_codegen_job_count()
  if max_jobs < 2
    return nil
  canonical_shards = shard_codegen_canonical_shards()
  if canonical_shards < 2
    return nil
  shard_irs = emit_sharded_ir_modules(plan, canonical_shards)
  if shard_irs == nil || shard_irs.size() < 2
    return nil

  cc_command = host_c_compiler()
  compile_flags = clang_opt + " " + debug_compile_flag()
  if march_flags() != ""
    compile_flags = compile_flags + " " + march_flags()
  compile_flags = compile_flags + " -fmerge-all-constants"
  if lto_flag != nil && lto_flag != ""
    compile_flags = compile_flags + " " + lto_flag
  if frame_pointers
    compile_flags = compile_flags + " -fno-omit-frame-pointer"
  if detect_target()[:os] == "macos"
    compile_flags = compile_flags + " -fveclib=Darwin_libsystem_m"
  path_map_flag = !resolve_runtime_dir().starts_with?("/") ? " -ffile-prefix-map=\"$PWD\"=." : ""

  cache_dir = compiler_cache_dir()
  cc_identity = dev_runtime_cc_identity(cc_command, rt_id)
  use_cache = env("TUNGSTEN_SHARD_CACHE") != "0" && cache_dir != nil && cc_identity != nil && ensure_driver_dir(cache_dir)

  nshards = shard_irs.size()
  obj_paths = []
  miss_indices = []

  if use_cache
    base_cfg = shard_codegen_base_config(cc_identity, compile_flags, path_map_flag)
    s = 0
    while s < nshards
      ir_txt = shard_irs[s]
      key_src = "irshard-v1\n" + ir_txt.size().to_s() + "\n" + wyhash64_hex_string(ir_txt) + "\n" + base_cfg
      obj_path = cache_dir + "/irshard-v1-" + wyhash64_hex_string(key_src) + ".o"
      obj_paths.push(obj_path)
      if file?(obj_path)
        store_entries.push(obj_path)
      else
        miss_indices.push(s)
      s += 1
    if miss_indices.size() == 0
      objs_out = StringBuffer(nshards * 96)
      s = 0
      while s < nshards
        objs_out << dev_runtime_shell_quote(obj_paths[s])
        objs_out << " "
        s += 1
      return objs_out.to_s()

    work_dir = capture("mktemp -d \"${TMPDIR:-/tmp}/tungsten-shards.XXXXXX\" 2>/dev/null").strip()
    if work_dir == ""
      return nil
    ordered_misses = shard_sort_indices_desc(miss_indices, shard_irs)
    cmds = []
    mi = 0
    while mi < ordered_misses.size()
      s = ordered_misses[mi]
      ll_file = work_dir + "/shard" + s.to_s() + ".ll"
      tmp_obj = work_dir + "/shard" + s.to_s() + ".o"
      ok_file = work_dir + "/shard" + s.to_s() + ".ok"
      write_file(ll_file, shard_irs[s])
      c = StringBuffer(256)
      c << cc_command
      c << " "
      c << compile_flags
      c << path_map_flag
      c << " -c -x ir "
      c << dev_runtime_shell_quote(ll_file)
      c << " -o "
      c << dev_runtime_shell_quote(tmp_obj)
      c << " && mv -f "
      c << dev_runtime_shell_quote(tmp_obj)
      c << " "
      c << dev_runtime_shell_quote(obj_paths[s])
      c << " && touch "
      c << dev_runtime_shell_quote(ok_file)
      cmds.push(c.to_s())
      mi += 1
    ok = shard_run_commands(work_dir, cmds, max_jobs)
    if ok
      mi = 0
      while mi < miss_indices.size()
        s = miss_indices[mi]
        if !file?(work_dir + "/shard" + s.to_s() + ".ok") || !file?(obj_paths[s])
          ok = false
        else
          store_entries.push(obj_paths[s])
        mi += 1
    system("rm -rf " + dev_runtime_shell_quote(work_dir))
    if !ok
      return nil
    objs_out = StringBuffer(nshards * 96)
    s = 0
    while s < nshards
      objs_out << dev_runtime_shell_quote(obj_paths[s])
      objs_out << " "
      s += 1
    return objs_out.to_s()

  work_dir = capture("mktemp -d \"${TMPDIR:-/tmp}/tungsten-shards.XXXXXX\" 2>/dev/null").strip()
  if work_dir == ""
    return nil
  all_indices = []
  s = 0
  while s < nshards
    obj_paths.push(work_dir + "/shard" + s.to_s() + ".o")
    all_indices.push(s)
    s += 1
  ordered_all = shard_sort_indices_desc(all_indices, shard_irs)
  cmds = []
  oi = 0
  while oi < ordered_all.size()
    s = ordered_all[oi]
    ll_file = work_dir + "/shard" + s.to_s() + ".ll"
    obj_file = obj_paths[s]
    ok_file = work_dir + "/shard" + s.to_s() + ".ok"
    write_file(ll_file, shard_irs[s])
    c = StringBuffer(256)
    c << cc_command
    c << " "
    c << compile_flags
    c << path_map_flag
    c << " -c -x ir "
    c << dev_runtime_shell_quote(ll_file)
    c << " -o "
    c << dev_runtime_shell_quote(obj_file)
    c << " && touch "
    c << dev_runtime_shell_quote(ok_file)
    cmds.push(c.to_s())
    oi += 1
  ok = shard_run_commands(work_dir, cmds, max_jobs)
  if ok
    s = 0
    while s < nshards
      if !file?(work_dir + "/shard" + s.to_s() + ".ok") || !file?(obj_paths[s])
        ok = false
      s += 1
  if !ok
    system("rm -rf " + dev_runtime_shell_quote(work_dir))
    return nil
  g_incremental[:temp_shard_dir] = work_dir
  objs_out = StringBuffer(nshards * 96)
  s = 0
  while s < nshards
    objs_out << dev_runtime_shell_quote(obj_paths[s])
    objs_out << " "
    s += 1
  objs_out.to_s()
