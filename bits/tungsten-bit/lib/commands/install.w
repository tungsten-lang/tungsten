# bit install — resolve and install dependencies from Bitfile
in Tungsten:Bit:Commands

+ Install < Command
  -> summary
    "Install bits listed in your Bitfile"

  -> usage
    "USAGE\n  bit install NAME... (options)\n\nOPTIONS\n      --deploy          Optimized for production/CI\n      --with GROUP      Include groups\n      --without GROUP   Exclude groups\n  -v, --version VER     Install a specific version\n      --bitfile FILE    Bitfile to use\n  -d, --dir DIR         Install directory\n  -j, --jobs NUM        Parallel jobs\n      --clean           Remove bits not in Bitfile\n  -n, --dry-run         Show changes without installing\n  -f, --force           Skip dependency checks\n      --local           Don't connect to bits.tungsten-lang.org\n      --pre             Allow prerelease versions\n"

  -> execute
    bitfile = load_bitfile
    lockfile = load_lockfile
    with_groups = parse_group_names(option(:with))
    without_groups = parse_group_names(option(:without))
    abort_on_conflicting_groups(with_groups, without_groups)

    bits = if .args.empty?()
      selected = []
      bitfile.dependencies.each -> (dep)
        if dependency_selected?(dep, with_groups, without_groups, flag?(:deploy), false)
          selected.push(dep)
      selected
    else
      selected = []
      .args.each -> (name)
        dependency = bitfile.find_dependency(name)
        if dependency == nil
          abort "Dependency not found in Bitfile: " + name
        if option(:version) != nil
          dependency = BitDependency.new(dependency.name, option(:version), dependency.options, dependency.path, dependency.summary)
        selected.push(dependency)
      selected

    # Resolve dependency graph
    resolver = Resolver.new(bitfile, lockfile, flag?(:pre))
    resolution = resolver.resolve(bits)

    if flag?(:dry_run)
      report_plan(resolution)
      return

    resolution.each -> (bit)
      verbose("Installing " + bit.name + " " + bit.version)
      installer = BitInstaller.new(bit, options)
      if !installer.install
        abort "Could not install " + bit.name + " from the local registry"

    # Update lockfile
    write_lockfile(resolution) unless flag?(:no_lock)

    say "Installed " + resolution.size().to_s + " bits"

  -> load_bitfile
    path = option(:bitfile, "Bitfile")
    unless File.exists?(path)
      abort "Could not find " + path
    Bitfile.load(path)

  -> load_lockfile
    path = "Bitfile.lock"
    if File.exists?(path)
      Lockfile.parse(File.read(path))
    else
      Lockfile.empty

  -> write_lockfile(resolution)
    content = Lockfile.generate(resolution)
    File.write("Bitfile.lock", content)

  -> report_plan(resolution)
    if resolution.empty?()
      say "No dependencies"
      return

    resolution.each -> (bit)
      status = if bit.installed? then "up to date" else "install"
      suffix = if bit.path == nil then " (unresolved)" else " from " + bit.path
      say "  " + status + ": " + bit.name + " " + bit.version + suffix

  -> abort_on_conflicting_groups(with_groups, without_groups)
    i = 0
    while i < with_groups.size()
      if without_groups.include?(with_groups[i])
        abort "Group appears in both --with and --without: " + with_groups[i]
      i += 1
