in Tungsten:Bit:Commands

+ Show < Command
  -> summary
    "Show information about a bit"

  -> usage
    "USAGE\n  bit show NAME (options)\n\nOPTIONS\n      --registry URL   Registry to query\n"

  -> execute
    name = .args.first
    abort "Please provide a bit name: bit show NAME" unless name

    current = Bitfile.load("Bitfile")
    registry = option(:registry) || (current ? current.source : DEFAULT_REGISTRY)
    lockfile = Lockfile.load("Bitfile.lock")
    locked = lockfile.find_dependency(name)
    client = Registry:Client.new(registry)
    available = client.versions(name, true)
    bitfile = installed_bit_named(name)
    location = "installed"

    if bitfile == nil
      found = latest_bit(available)
      if found != nil
        if found.path != nil && !remote_url?(found.path)
          bitfile = Bitfile.load(File.join(found.path, "Bitfile"))
        if bitfile == nil
          bitfile = Bitfile.new(found.name, found.version, found.summary, "", registry, [], found.path)
        location = "available"

    if bitfile == nil
      abort "Could not find bit: " + name

    say "name    " + bitfile.name
    say "version " + bitfile.version
    if bitfile.summary != nil && bitfile.summary != ""
      say "summary " + bitfile.summary
    if bitfile.license != nil && bitfile.license != ""
      say "license " + bitfile.license
    say "status  " + location
    say "path    " + bitfile.dir
    if locked != nil
      say "locked  " + locked.version
      say "source  " + locked.source
      if locked.path != nil
        say "source_path " + locked.path
      if locked.sha256 != nil && locked.sha256 != ""
        say "sha256  " + locked.sha256
      if locked.security_status != nil && locked.security_status != ""
        say "security " + locked.security_status + " (" + (locked.security_risk || "unknown") + ")"

    if !available.empty?()
      say "available"
      available.each -> (bit)
        suffix = if bit.path == nil then "" else " " + bit.path
        if bit.security_status != nil && bit.security_status != ""
          suffix = suffix + " security=" + bit.security_status + " risk=" + (bit.security_risk || "unknown")
        say "  " + bit.version + suffix

    if !bitfile.dependencies.empty?()
      say "dependencies"
      bitfile.dependencies.each -> (dep)
        say "  " + dep.name + " " + dep.version
