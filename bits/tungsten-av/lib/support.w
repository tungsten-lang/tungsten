# Native AV utilities; no shell or host-language runtime in the command path.
in Av

+ Util
  -> .min(a, b)
    a < b ? a : b

  -> .max(a, b)
    a > b ? a : b

  -> .get(hash, key, default = nil)
    hash.has_key?(key) ? hash[key] : default

  -> .copy(value)
    JSON.parse(JSON.encode(value))

  -> .symbols(hash)
    result = {}
    hash.keys.each ->(k)
      result[k.to_sym] = hash[k]
    result

  -> .all(values)
    result = true
    values.each ->(v)
      result = false if !v
    result

  -> .unique(values)
    found = {}
    values.each ->(v)
      found[v] = true
    found.keys.sort

  -> .now
    ccall("w_av_now")

  -> .id
    Random.uuid.to_s.replace("-", "").slice(0, 20)

  -> .sha(path)
    ccall("w_av_sha256", path)

  -> .json(path, value)
    File.mkdir_p(File.dirname(path))
    File.atomic_write(path, JSON.encode(value) + "\n")

  -> .stamp(path)
    s = File.stat(path)
    [s.dev, s.ino, s.size, s.mtime_ns, s.ctime_ns]

  -> .inside?(path, root)
    path.starts_with?(root + "/")

  -> .absolute(path, base = nil)
    raise "path requires a string without NUL bytes" if type(path) != "String" || path.include?("\0")
    File.expand_path(path, base || Dir.pwd)

  -> .canonical(path)
    return File.realpath(path) if File.exist?(path)
    parent = File.dirname(path)
    return path if parent == path
    File.join(canonical(parent), File.basename(path))

  -> .unlink(path)
    File.delete(path) if File.exist?(path) || File.symlink?(path)

  -> .remove_tree(path)
    if File.directory?(path) && !File.symlink?(path)
      File.children(path).each ->(name)
        remove_tree(File.join(path, name))
      File.rmdir(path)
    else
      unlink(path)

  -> .copy_file(src, dst)
    File.mkdir_p(File.dirname(dst))
    ccall("w_av_copy", src, dst)

  -> .link_atomic(target, path)
    File.mkdir_p(File.dirname(path))
    tmp = path + ".link-" + id()
    begin
      File.symlink(target, tmp)
      File.atomic_replace(tmp, path)
    ensure
      unlink(tmp)

  -> .lock(path)
    File.mkdir_p(File.dirname(path))
    handle = ccall("w_av_lock", path)
    raise "another AV job is using [path]" if handle < 0
    handle

  -> .unlock(handle)
    ccall("w_av_unlock", handle)

  # Explicit fault-injection hook used by crash regressions.
  -> .barrier(name)
    if Env.get("TUNGSTEN_AV_TEST_BARRIER") == name
      marker = Env.get("TUNGSTEN_AV_TEST_MARKER")
      raise "test barrier requires marker path" if marker == nil
      File.atomic_write(marker, JSON.encode({"name": name, "pid": ccall("w_av_pid")}))
      while File.exist?(marker)
        ccall("w_av_pause", 10)

  -> .sync(path)
    ccall("w_av_sync", path)

+ Runner
  ro :peak_rss
  -> new(@timeout = 3600)
    @peak_rss = 0

  -> run(args, cwd = nil, environment = nil, log = nil)
    base = File.join(Env.get("TMPDIR") || "/tmp", "av-process-" + Util.id())
    File.mkdir_p(base)
    out = base + "/stdout"
    err = base + "/stderr"
    pairs = []
    if environment != nil
      environment.keys.each ->(key)
        pairs.push([key.to_s, environment[key].to_s])
    strings = args.map ->(a) a.to_s
    begin
      result = ccall("w_av_run", strings, cwd || Dir.pwd, pairs, out, err, @timeout)
      @peak_rss = Util.max(@peak_rss, result[1])
      stdout = File.read_prefix(out, 16777216)
      stderr = File.read_prefix(err, 16777216)
      if log != nil
        File.mkdir_p(File.dirname(log))
        File.write(log, stdout + stderr)
      raise "stage timed out: [strings[0]]" if result[0] == 124
      raise "stage cancelled: [strings[0]]" if result[0] == 130 || result[0] == 143
      raise "stage failed ([result[0]]): [strings.join(" ")]\n[stderr.slice(Util.max(0, stderr.size - 4000), 4000)]" if result[0] != 0
      {"stdout": stdout, "stderr": stderr}
    ensure
      Util.remove_tree(base)

  -> json(args)
    JSON.parse(run(args)["stdout"])

+ Budget
  -> new(@settings, @available = nil, @cpus = nil)

  -> choose(width, height, source_width = nil, source_height = nil)
    available = @available || ccall("w_av_memory")
    limit = Util.min(available, (Util.get(@settings, "memory_mb", available / ~1048576 * ~0.65) * 1048576).to_i)
    source = (source_width || width) * (source_height || height)
    per_job = 16 * source + 16 * width * height + 134217728
    raise "memory budget too small; need approximately [(per_job + 1048575) / 1048576] MiB per job" if per_job > limit
    cpus = @cpus || System.cpu_count
    jobs = Util.max(1, Util.min(Util.get(@settings, "jobs", Util.min(cpus, 8)), Util.min(limit / per_job, cpus)))
    decode = Util.min(Util.get(@settings, "decode_ahead", 6), Util.max(1, (limit - 134217728) / Util.max(4 * source, 1) / jobs))
    {"jobs": jobs, "animation_jobs": Util.min(Util.get(@settings, "animation_jobs", jobs), jobs), "decode_ahead": decode, "segments_ahead": Util.get(@settings, "segments_ahead", 3), "memory_budget_mb": limit / 1048576, "estimated_memory_per_job_mb": (per_job + 1048575) / 1048576}

  -> disk(path, needed)
    parent = path
    while !File.exist?(parent)
      parent = File.dirname(parent)
    free = ccall("w_av_free", parent)
    reserve = (Util.get(@settings, "disk_reserve_mb", 1024) * 1048576).to_i
    {"free_bytes": free, "estimated_bytes": needed.to_i, "reserve_bytes": reserve, "ok": free >= needed + reserve}
