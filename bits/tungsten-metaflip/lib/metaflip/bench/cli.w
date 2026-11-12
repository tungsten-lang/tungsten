# Command-line parsing shared by metabench and metascore.

+ Cli
  # Splits the arguments into positional words and `--name value` options;
  # the names in `flags` take no value. Raises on an unknown or incomplete option.
  -> .parse(args, valued, flags)
    positional = []
    opts = {}
    i = 0 ## i64
    while i < args.size
      arg = args[i]
      if arg.starts_with?("--")
        if flags.include?(arg)
          opts[arg] = "1"
        elsif valued.include?(arg)
          raise "option " + arg + " needs a value" if i + 1 >= args.size
          opts[arg] = args[i + 1]
          i += 1
        else
          raise "unknown option " + arg
      else
        positional.push(arg)
      i += 1
    [positional, opts]

  # The value of an option, or `fallback`.
  -> .get(opts, name, fallback)
    value = opts[name]
    value == nil ? fallback : value

  -> .integer(opts, name, fallback)
    value = opts[name]
    return fallback if value == nil
    raise "option " + name + " needs a number" if value.to_i.to_s != value
    value.to_i

  -> .number(opts, name, fallback)
    value = opts[name]
    value == nil ? fallback : value.to_f
