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
    root = capture("pwd -P").strip()
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
    home = bit_home() + "/" + name
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
    out = capture("find " + shell_quote(root + "/commands") + " -type f -name '*.w' -print | sort")
    names = []
    prefix = root.size + 10
    out.split("\n").each ->(path)
      if path.ends_with?(".w")
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
    Env.set("BIT_PACKAGE_ROOT", root)
    Env.set("BIT_COMMAND_NAME", name)
    status = Process.exec(run)
    << "bit: cannot execute [source] ([status])"
    exit(126)
