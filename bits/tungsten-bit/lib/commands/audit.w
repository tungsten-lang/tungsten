in Tungsten:Bit:Commands

+ Audit < Command
  -> summary
    "Audit installed and locked bits"

  -> usage
    "USAGE\n  bit audit NAME... (options)\n\nOPTIONS\n      --strict      Treat warnings as failures\n      --signatures  Require remote bits to include signatures\n"

  -> execute
    @failures = 0
    @warnings = 0

    lockfile = Lockfile.load("Bitfile.lock")
    bits = audit_targets(lockfile)
    if bits.empty?()
      say "No bits to audit"
      return

    bits.each -> (bit)
      audit_bit(bit)

    if @failures > 0
      abort @failures.to_s + " audit failures"
    if flag?(:strict) && @warnings > 0
      abort @warnings.to_s + " audit warnings"

    if @warnings > 0
      say "Audit passed with " + @warnings.to_s + " warnings"
    else
      say "Audit passed"

  -> audit_targets(lockfile)
    if !.args.empty?()
      targets = []
      .args.each -> (name)
        locked = lockfile.find_dependency(name)
        if locked != nil
          targets.push(locked)
        else
          installed = installed_bit_named(name)
          if installed != nil
            targets.push(BitDependency.new(installed.name, installed.version, {source: "installed"}, installed.dir, installed.summary))
          else
            fail(name, "not found in Bitfile.lock or vendor/bits")
      return targets

    if !lockfile.dependencies.empty?()
      return lockfile.dependencies

    installed = installed_bits()
    targets = []
    installed.each -> (bit)
      targets.push(BitDependency.new(bit.name, bit.version, {source: "installed"}, bit.dir, bit.summary))
    targets

  -> audit_bit(bit)
    failed = false
    warned = false

    if bit.path != nil && remote_url?(bit.path)
      if bit.sha256 == nil || bit.sha256 == ""
        fail(bit.name, "missing sha256 metadata")
        failed = true
      if flag?(:signatures)
        if bit.signature == nil || bit.signature == ""
          fail(bit.name, "missing signature")
          failed = true
        if bit.public_key == nil || bit.public_key == ""
          fail(bit.name, "missing public key")
          failed = true

    if bit.security_status == "fail" || bit.security_risk == "high" || bit.security_risk == "critical"
      fail(bit.name, "security " + status_text(bit))
      failed = true
    elsif bit.security_status == "warn" || bit.security_status == "error" || bit.security_risk == "medium"
      warn(bit.name, "security " + status_text(bit))
      warned = true
    elsif bit.security_status == nil || bit.security_status == ""
      warn(bit.name, "security review missing")
      warned = true
    elsif bit.security_status == "pending" || bit.security_status == "running"
      warn(bit.name, "security " + status_text(bit))
      warned = true

    if !failed && !warned
      say "ok   " + bit.name + " " + bit.version + " security " + status_text(bit)

  -> status_text(bit)
    status = bit.security_status || "unknown"
    risk = bit.security_risk || "unknown"
    status + " " + risk

  -> fail(name, message)
    @failures += 1
    say "fail " + name + " - " + message

  -> warn(name, message)
    @warnings += 1
    say "warn " + name + " - " + message
