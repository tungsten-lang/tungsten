# bit install — resolve and install dependencies from Bitfile
in Tungsten:Bit:Commands

+ Install < Command
  -> summary
    "Install bits listed in your Bitfile"

  -> usage
    "USAGE\n  bit install NAME... (options)\n\nOPTIONS\n      --deploy          Require an existing compatible lockfile\n      --with GROUP      Include groups\n      --without GROUP   Exclude groups\n  -v, --version VER     Install a specific version\n      --bitfile FILE    Bitfile to use\n  -d, --dir DIR         Versioned install root\n      --system          Install under a system prefix\n      --prefix DIR      System install root (default: /usr/local/lib/tungsten/bits)\n  -j, --jobs NUM        Parallel jobs\n      --clean           Remove bits not in Bitfile\n  -n, --dry-run         Show changes without installing\n  -f, --force           Reinstall an existing version\n      --local           Don't connect to bits.tungsten-lang.org\n      --pre             Allow prerelease versions\n"

  -> execute
    bitfile = load_bitfile
    lock_path = lockfile_path(bitfile)
    if flag?(:deploy) && !File.exists?(lock_path)
      abort "--deploy requires " + lock_path
    lockfile = load_lockfile(lock_path)
    root = install_root
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
          dependency = BitDependency.new(name)
        requested_version = option(:version) || option(:v)
        if requested_version != nil
          dependency = BitDependency.new(dependency.name, requested_version, dependency.options, dependency.path, dependency.summary)
        selected.push(dependency)
      selected

    if flag?(:deploy)
      selected.each -> (dependency)
        locked = lockfile.find_dependency(dependency.name)
        if locked == nil || !version_satisfies?(locked.version, dependency.version)
          abort "Bitfile.lock is missing a compatible " + dependency.name + " entry"

    # Resolve dependency graph
    resolver = Resolver.new(bitfile, lockfile, flag?(:pre))
    resolution = resolver.resolve(bits)

    if flag?(:dry_run)
      report_plan(resolution, root)
      return

    resolution.each -> (bit)
      verbose("Installing " + bit.name + " " + bit.version)
      if remote_url?(bit.path) && (bit.sha256 == nil || bit.sha256 == "")
        abort "Locked remote bit is missing sha256: " + bit.name + " " + bit.version
      installer = BitInstaller.new(bit, {install_root: root, force: flag?(:force)})
      if !installer.install
        abort "Could not install " + bit.name + " " + bit.version + " into " + root

    # Update lockfile
    if @flags[:lock] != false
      write_lockfile(lock_path, resolution)

    say "Installed " + resolution.size().to_s + " bits into " + root

  -> load_bitfile
    path = option(:bitfile, "Bitfile")
    unless File.exists?(path)
      abort "Could not find " + path
    Bitfile.load(path)

  -> lockfile_path(bitfile)
    explicit = option(:lockfile)
    if explicit != nil
      return explicit
    File.join(bitfile.dir(), "Bitfile.lock")

  -> load_lockfile(path)
    if File.exists?(path)
      Lockfile.parse(File.read(path))
    else
      Lockfile.empty

  -> write_lockfile(path, resolution)
    content = Lockfile.generate(resolution)
    File.write(path, content + "\n")

  -> report_plan(resolution, root)
    if resolution.empty?()
      say "No dependencies"
      return

    resolution.each -> (bit)
      status = if bit.installed_at?(root) then "up to date" else "install"
      suffix = if bit.path == nil then " (unresolved)" else " from " + bit.path
      say "  " + status + ": " + bit.name + " " + bit.version + " -> " + bit.install_path(root) + suffix

  -> install_root
    directory = option(:dir) || option(:d)
    prefix = option(:prefix)
    system_install = flag?(:system)
    if system_install && directory != nil
      abort "--system and --dir cannot be combined"
    if prefix != nil && !system_install
      abort "--prefix requires --system"
    if system_install
      return prefix || "/usr/local/lib/tungsten/bits"
    directory || bit_home()

  -> abort_on_conflicting_groups(with_groups, without_groups)
    i = 0
    while i < with_groups.size()
      if without_groups.include?(with_groups[i])
        abort "Group appears in both --with and --without: " + with_groups[i]
      i += 1
