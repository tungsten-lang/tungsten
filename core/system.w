+ System
  # Canonical absolute path of the running executable. This resolves symlinks
  # and does not depend on argv[0] or the process working directory.
  -> .executable_path
    ccall("w_executable_path")

  # Canonical absolute directory containing the running executable. The path
  # has no trailing slash except when the executable lives in the root.
  -> .executable_dir
    ccall("w_executable_dir")

  # Number of processors currently available to this process. Prefer the
  # active/online count over the machine maximum so campaign schedulers behave
  # sensibly under VM and container CPU limits as well as on Apple Silicon.
  -> .cpu_count
    raw = capture("sysctl -n hw.activecpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1")
    if raw == nil
      return 1
    count = raw.strip().to_i() ## i64
    if count < 1
      return 1
    count
