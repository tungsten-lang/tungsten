# Package command namespaces: bit NAME SUBCOMMAND, from NAME/commands/*.w.
# Built-ins remain reserved; packages are resolved from the nearest project,
# its lockfile, installed current links, then the selected source toolchain.
in Tungsten:Bit

+ PackageCommands
  -> .valid_name?(text)
    return false if text == nil || text == ""
    i = 0
    while i < text.size
      c = text.byte_at(i)
      return false if !((c >= 97 && c <= 122) || (i > 0 && c >= 48 && c <= 57) || (i > 0 && c == 45) || (i > 0 && c == 95))
      i += 1
    !text.ends_with?("-") && !text.ends_with?("_")

  -> .project_root
    root = File.realpath(Dir.pwd)
    while root != "" && root != "/"
      return root if File.exists?(root + "/Bitfile")
      root = path_parent(root)
    return "/" if File.exists?("/Bitfile")
    nil

  -> .matches?(root, name)
    return false if !File.exists?(root + "/Bitfile") || !Dir.exists?(root + "/commands")
    manifest = Bitfile.load(root + "/Bitfile")
    manifest != nil && manifest.name == name

  -> .resolve(name)
    return nil if !valid_name?(name)
    project = project_root()
    if project != nil
      manifest = Bitfile.load(project + "/Bitfile")
      return project if matches?(project, name)
      dependency = manifest.find_dependency(name)
      if dependency != nil && dependency.path != nil
        root = dependency.path
        root = path_parent(root) if root.ends_with?("/Bitfile")
        return root if matches?(root, name) && version_satisfies?(Bitfile.load(root + "/Bitfile").version, dependency.version)
        << "bit: dependency [name] has no matching commands directory at [root]"
        exit(2)
      lock = Lockfile.load(project + "/Bitfile.lock")
      lock.dependencies.each ->(item)
        if item.name == name
          root = item.path
          root = bit_home() + "/" + name + "/" + item.version if root == nil
          root = project + "/" + root if !root.starts_with?("/")
          root = path_parent(root) if root.ends_with?("/Bitfile")
          return root if matches?(root, name) && Bitfile.load(root + "/Bitfile").version == item.version
          << "bit: locked command package [name] [item.version] is not installed; run bit install"
          exit(2)
      if dependency != nil
        << "bit: command dependency [name] requires an installed lockfile entry; run bit install"
        exit(2)
    # Package directories may retain their tungsten- prefix while their
    # declared command namespace is the shorter package name.
    homes = [bit_home() + "/" + name, bit_home() + "/tungsten-" + name]
    homes.each ->(home)
      return home + "/current" if matches?(home + "/current", name)
      return home if matches?(home, name)
    toolchain = env("TUNGSTEN_ROOT")
    if toolchain != nil
      root = toolchain + "/bits/" + name
      return root if matches?(root, name)
      root = toolchain + "/bits/tungsten-" + name
      return root if matches?(root, name)
    nil

  -> .names(root)
    commands_dir = root + "/commands"
    return [] if !Dir.exists?(commands_dir)
    found = []
    File.walk(commands_dir, ->(path)
      found.push(path) if File.file?(path) && path.ends_with?(".w")
    )
    found.sort!
    names = []
    prefix = root.size + 10
    found.each ->(path)
      relative = path.slice(prefix, path.size - prefix - 2)
      valid = true
      relative.split("/").each ->(part)
        valid = false if !valid_name?(part)
      names.push(relative.replace("/", " ")) if valid
    names

  -> .help(name, root = nil)
    root = resolve(name) if root == nil
    return false if root == nil
    manifest = Bitfile.load(root + "/Bitfile")
    << "[name] — [manifest.summary]"
    << "Usage: bit [name] COMMAND \[options]"
    names(root).each ->(command)
      << "  bit [name] [command]"
    true

  -> .binary_current?(bin_path, toolchain)
    return false if !File.file?(bin_path)
    deps_path = bin_path + ".deps"
    return executable_file?(bin_path) if !File.file?(deps_path)
    built_at = File.mtime_ns(bin_path)
    return false if built_at == nil
    if toolchain != nil && toolchain != ""
      compiler_at = File.mtime_ns(toolchain + "/bin/tungsten-compiler")
      return false if compiler_at != nil && compiler_at > built_at
    rows = File.read(deps_path).split("\n")
    return false if rows.size < 2 || !rows[0].starts_with?("tungsten-bit-deps-v1 ")
    i = 1
    while i < rows.size
      row = rows[i]
      i += 1
      if row != ""
        parts = row.split("\t")
        return false if parts.size != 3
        dep = parts[1] == "r" ? (toolchain != nil && toolchain != "" ? toolchain + "/" + parts[2] : parts[2]) : parts[2]
        changed_at = File.mtime_ns(dep)
        return false if changed_at == nil || changed_at > built_at
    true

  -> .package_binary(root, name)
    toolchain = env("TUNGSTEN_ROOT")
    bin_path = root + "/bin/" + name
    return bin_path if binary_current?(bin_path, toolchain)
    if toolchain != nil && toolchain != "" && File.file?(root + "/bin/" + name + ".w")
      real_root = File.realpath(root)
      real_tc = File.realpath(toolchain)
      if real_root.starts_with?(real_tc + "/bits/") && File.file?(real_tc + "/bin/tungsten")
        File.mkdir_p(real_tc + "/build")
        log = real_tc + "/build/bit-" + File.basename(real_root) + "-" + name + ".log"
        cmd = "cd " + shell_quote(real_root) + " && BIT_HOME=" + shell_quote(real_tc + "/bits") + " TUNGSTEN_ROOT=" + shell_quote(real_tc) + " " + shell_quote(real_tc + "/bin/tungsten") + " build >" + shell_quote(log) + " 2>&1"
        return bin_path if system(cmd) && File.file?(bin_path)
    nil

  -> .dispatch(name, args)
    root = resolve(name)
    return false if root == nil
    if args.size == 0 || args[0] == "--help" || args[0] == "-h" || args[0] == "help"
      help(name, root)
      return true
    path = root + "/commands"
    source = nil
    consumed = 0
    i = 0
    while i < args.size && valid_name?(args[i])
      path = path + "/" + args[i]
      if File.exists?(path + ".w")
        source = path + ".w"
        consumed = i + 1
      i += 1
    if source == nil
      << "bit: unknown [name] command: [args[0]]"
      help(name, root)
      exit(2)
    Env.set("BIT_PACKAGE_ROOT", root)
    Env.set("BIT_COMMAND_NAME", name)
    bin_path = package_binary(root, name)
    if bin_path != nil
      exec_args = [bin_path, args.slice(0, consumed).join(" ")]
      while consumed < args.size
        exec_args.push(args[consumed])
        consumed += 1
      status = Process.exec(exec_args)
      << "bit: cannot execute [bin_path] ([status])"
      exit(126)
    compiler = tungsten_compiler_command()
    if compiler == nil
      << "bit: a Tungsten driver is required to execute package commands"
      exit(127)
    run = [compiler]
    run.push("run") if compiler.ends_with?("tungsten-compiler")
    run.push(source)
    run.push("--")
    while consumed < args.size
      run.push(args[consumed])
      consumed += 1
    status = Process.exec(run)
    << "bit: cannot execute [source] ([status])"
    exit(126)
