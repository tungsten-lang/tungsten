in Tungsten:Bit:Commands

+ Doctor < Command
  -> summary
    "Check bit environment readiness"

  -> usage
    "USAGE\n  bit doctor (options)\n\nOPTIONS\n      --registry URL   Registry URL or local registry path\n      --key PATH       SSH private key used for signing\n      --local          Skip registry auth and signing checks\n"

  -> execute
    @failures = 0
    @warnings = 0

    say "bit doctor"
    check_tungsten_tool()
    check_command("tar", "tar")
    check_command("ssh-keygen", "ssh-keygen")
    check_sha256_tool()

    bitfile = check_bitfile()
    check_lockfile()
    check_registry(bitfile)

    if @failures > 0
      abort @failures.to_s + " doctor checks failed"

    if @warnings > 0
      say "bit doctor ok with " + @warnings.to_s + " warnings"
    else
      say "bit doctor ok"

  -> check(label, ok, detail = nil)
    if ok
      if detail == nil || detail == ""
        say "ok   " + label
      else
        say "ok   " + label + " - " + detail
    else
      @failures += 1
      if detail == nil || detail == ""
        say "fail " + label
      else
        say "fail " + label + " - " + detail

  -> warn(label, detail)
    @warnings += 1
    say "warn " + label + " - " + detail

  -> tool_path(name)
    out = capture("command -v " + shell_quote(name) + " 2>/dev/null").strip()
    if out == nil
      ""
    else
      out

  -> check_command(label, name)
    path = tool_path(name)
    if path != ""
      check(label, true, path)
    else
      check(label, false, name + " not found on PATH")

  -> check_tungsten_tool
    path = tungsten_compiler_command()
    if path != nil && path != ""
      check("tungsten toolchain", true, path)
    else
      check("tungsten toolchain", false, "set TUNGSTEN_COMPILER or add tungsten to PATH")

  -> check_sha256_tool
    shasum = tool_path("shasum")
    sha256sum = tool_path("sha256sum")
    if shasum != ""
      check("sha256 tool", true, shasum)
    elsif sha256sum != ""
      check("sha256 tool", true, sha256sum)
    else
      check("sha256 tool", false, "install shasum or sha256sum")

  -> check_bitfile
    bitfile = Bitfile.load("Bitfile")
    if bitfile == nil
      check("Bitfile", false, "No Bitfile found")
      return nil

    check("Bitfile", true, bitfile.name + " " + bitfile.version)
    if bitfile.name != nil && bitfile.name != "" && bitfile.name != "unknown"
      check("name", true, bitfile.name)
    else
      check("name", false, "set name in Bitfile")
    if bitfile.version != nil && bitfile.version != "" && bitfile.version != "0.0.0"
      check("version", true, bitfile.version)
    else
      check("version", false, "set version in Bitfile")
    if bitfile.summary != nil && bitfile.summary != ""
      check("summary", true, bitfile.summary)
    else
      check("summary", false, "set summary in Bitfile")
    if bitfile.license != nil && bitfile.license != ""
      check("license", true, bitfile.license)
    else
      check("license", false, "set license in Bitfile")
    if Dir.exists?("lib")
      check("lib directory", true, "lib/")
    else
      check("lib directory", false, "create lib/ with the bit sources")
    if Dir.exists?("spec")
      check("spec directory", true, "spec/")
    else
      warn("spec directory", "not present; push CI will have little to run")
    bitfile

  -> check_lockfile
    if !File.exists?("Bitfile.lock")
      warn("Bitfile.lock", "not present; run `bit install` before publishing")
      return nil

    lockfile = Lockfile.load("Bitfile.lock")
    check("Bitfile.lock", true, lockfile.dependencies.size().to_s + " entries")
    missing = 0
    remote = 0
    lockfile.dependencies.each -> (dep)
      if dep.path != nil && remote_url?(dep.path)
        remote += 1
        if dep.sha256 == nil || dep.sha256 == ""
          missing += 1
    if remote > 0
      check("lock sha256 metadata", missing == 0, missing.to_s + " of " + remote.to_s + " remote entries missing sha256")

  -> check_registry(bitfile)
    auth = Auth.load
    registry = option(:registry)
    if registry == nil
      if bitfile != nil
        registry = bitfile.source
      elsif env("BIT_HOME") != nil
        registry = default_bit_source()
      else
        registry = auth.registry
    if registry == nil
      registry = DEFAULT_REGISTRY

    if remote_url?(registry)
      check_command("curl", "curl")
    else
      check("registry path", Dir.exists?(registry), registry)

    if flag?(:local)
      return nil

    check("registry auth", auth.valid?, "Run `bit login` or set BIT_TOKEN")
    if auth.handle != nil
      check("profile handle", true, auth.handle)
    else
      warn("profile handle", "run `bit create` to save a profile")

    public_key = auth.public_key_path || default_public_key_path()
    if public_key != nil && File.exists?(public_key)
      check("public key", true, public_key)
    else
      check("public key", false, "Run `bit create` with an SSH public key")

    key = option(:key) || default_signing_key_path()
    if key != nil && File.exists?(key)
      check("signing key", true, key)
    else
      check("signing key", false, "Pass --key PATH or run `bit create`")
