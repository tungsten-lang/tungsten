# bit yank — yank a published version
in Tungsten:Bit:Commands

+ Yank < Command
  -> summary
    "Yank a published bit version"

  -> usage
    "USAGE\n  bit yank NAME VERSION (options)\n\nOPTIONS\n      --registry URL   Registry URL\n"

  -> execute
    bitfile = Bitfile.load("Bitfile")
    name = .args[0] || (bitfile ? bitfile.name : nil)
    version = .args[1] || (bitfile ? bitfile.version : nil)
    abort "Bit name is required" unless name
    abort "Version is required" unless version

    auth = Auth.load
    abort "Not logged in. Run `bit login`." unless auth.valid?
    registry = option(:registry, auth.registry || DEFAULT_REGISTRY)
    response = Tungsten:Bit:Registry:Client.new(registry, auth).yank(name, version)
    if response.status == :ok
      say "Yanked " + name + " " + version
    else
      abort response.message
