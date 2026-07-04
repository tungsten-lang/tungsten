in Tungsten:Bit:Commands

+ Info < Command
  -> summary
    "Show information about a bit"

  -> usage
    "USAGE\n  bit info NAME (options)\n\nOPTIONS\n      --registry URL   Registry to query\n\nUse `bit env` for local environment information.\n"

  -> execute
    if .args.first == nil
      abort "Please provide a bit name: bit info NAME. Use `bit env` for environment information."

    Show.new(.args).execute
