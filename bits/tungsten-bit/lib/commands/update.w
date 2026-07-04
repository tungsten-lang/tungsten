in Tungsten:Bit:Commands

+ Update < Command
  -> summary
    "Update the local bit cache"

  -> usage
    "USAGE\n  bit update NAME... (options)\n\nOPTIONS\n      --deploy          Exclude development/spec/test groups\n      --with GROUP      Include groups\n      --without GROUP   Exclude groups\n  -n, --dry-run         Show changes without installing\n      --pre             Allow prerelease versions\n"

  -> execute
    bitfile = Bitfile.load("Bitfile")
    abort "No Bitfile found" unless bitfile
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
        selected.push(dependency)
      selected

    resolver = Resolver.new(bitfile, Lockfile.empty, flag?(:pre))
    resolution = resolver.resolve(bits)

    if resolution.empty?()
      say "No dependencies"
      return

    if flag?(:dry_run)
      resolution.each -> (bit)
        suffix = if bit.path == nil then " (unresolved)" else " from " + bit.path
        say "  update: " + bit.name + " " + bit.version + suffix
      return

    resolution.each -> (bit)
      if bit.path == nil
        abort "Could not resolve " + bit.name + " from the local registry"
      if Dir.exists?(bit.install_path)
        FileUtils.rm_rf(bit.install_path)
      installer = BitInstaller.new(bit, options)
      if !installer.install
        abort "Could not install " + bit.name

    File.write("Bitfile.lock", Lockfile.generate(resolution))
    say "Updated " + resolution.size().to_s + " bits"

  -> abort_on_conflicting_groups(with_groups, without_groups)
    i = 0
    while i < with_groups.size()
      if without_groups.include?(with_groups[i])
        abort "Group appears in both --with and --without: " + with_groups[i]
      i += 1
