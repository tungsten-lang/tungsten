in Tungsten:Bit:Commands

+ Outdated < Command
  -> summary
    "Display bits that have newer matching versions"

  -> usage
    "USAGE\n  bit outdated NAME... (options)\n\nOPTIONS\n      --deploy          Exclude development/spec/test groups\n      --with GROUP      Include groups\n      --without GROUP   Exclude groups\n      --pre             Allow prerelease versions\n"

  -> execute
    bitfile = Bitfile.load("Bitfile")
    abort "No Bitfile found" unless bitfile

    with_groups = parse_group_names(option(:with))
    without_groups = parse_group_names(option(:without))
    abort_on_conflicting_groups(with_groups, without_groups)

    bits = selected_dependencies(bitfile, with_groups, without_groups)
    lockfile = Lockfile.load("Bitfile.lock")
    count = 0

    bits.each -> (dep)
      current = current_dependency(dep, lockfile)
      latest = latest_allowed(bitfile, dep)
      if current != nil && latest != nil && semver_compare(latest.version, current.version) > 0
        say dep.name + " " + current.version + " -> " + latest.version
        count += 1

    if count == 0
      say "All bits up to date"

  -> selected_dependencies(bitfile, with_groups, without_groups)
    selected = []
    if .args.empty?()
      bitfile.dependencies.each -> (dep)
        if dependency_selected?(dep, with_groups, without_groups, flag?(:deploy), false)
          selected.push(dep)
    else
      .args.each -> (name)
        dependency = bitfile.find_dependency(name)
        if dependency == nil
          abort "Dependency not found in Bitfile: " + name
        selected.push(dependency)
    selected

  -> current_dependency(dep, lockfile)
    locked = lockfile.find_dependency(dep.name)
    if locked != nil
      return locked

    installed = installed_bit_named(dep.name)
    if installed != nil
      return BitDependency.new(installed.name, installed.version, {source: "installed"}, installed.dir, installed.summary)

    nil

  -> latest_allowed(bitfile, dep)
    client = Registry:Client.new(source_url_for(bitfile, dep))
    policy = source_policy_for(bitfile, dep)
    client.versions(dep.name, flag?(:pre)).each -> (candidate)
      if version_satisfies?(candidate.version, dep.version) && cooldown_elapsed?(candidate, policy)
        return candidate
    nil

  -> abort_on_conflicting_groups(with_groups, without_groups)
    i = 0
    while i < with_groups.size()
      if without_groups.include?(with_groups[i])
        abort "Group appears in both --with and --without: " + with_groups[i]
      i += 1
