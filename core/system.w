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
    ccall("w_cpu_count")

  # Installed physical memory in bytes, or zero when the host cannot report
  # it. Resource-aware algorithms use zero as "unknown", never as no memory.
  -> .physical_memory_bytes
    ccall("w_physical_memory_bytes")
