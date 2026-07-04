in Tungsten:Bit:Commands

+ Env < Command
  -> summary
    "Show bit environment information"

  -> usage
    "USAGE\n  bit env (options)\n\nOPTIONS\n      --registry URL   Registry URL to report\n      --paths          Include config/profile paths\n"

  -> execute
    auth = Auth.load
    current = Bitfile.load("Bitfile")
    registry = option(:registry)
    if registry == nil
      if current != nil
        registry = current.source
      elsif env("BIT_HOME") != nil
        registry = default_bit_source()
      else
        registry = auth.registry
    if registry == nil
      registry = DEFAULT_REGISTRY

    say "bit 0.1.0"
    say "cwd " + Dir.pwd
    say "target " + System.target_triple
    say "registry " + registry
    say "bit_home " + bit_home()

    if current != nil
      say "project " + current.name + " " + current.version
      if current.tungsten_requirement != nil
        say "tungsten " + current.tungsten_requirement
      say "source " + current.source
    else
      say "project none"

    if auth.handle != nil
      say "handle " + auth.handle
    if auth.email != nil
      say "email " + auth.email

    public_key = auth.public_key_path || default_public_key_path()
    if public_key != nil
      say "public_key " + public_key

    signing_key = default_signing_key_path()
    if signing_key != nil
      say "signing_key " + signing_key
    else
      say "signing_key missing"

    if auth.valid?
      say "auth logged-in"
    else
      say "auth logged-out"

    if flag?(:paths)
      say "config_home " + bit_config_home()
      say "profile " + bit_profile_path()
      say "credentials " + bit_credentials_path()
      if File.exists?("Bitfile")
        say "bitfile " + File.join(Dir.pwd, "Bitfile")
      if File.exists?("Bitfile.lock")
        say "lockfile " + File.join(Dir.pwd, "Bitfile.lock")
