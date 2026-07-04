# Bit::Command — base class for all bit CLI commands
# Provides argument parsing, help text, and execution lifecycle

in Tungsten:Bit

+ Command
  ro :args
  ro :options
  ro :flags

  -> new(@args)
    @options = {}
    @flags   = {}
    parse_args(@args)

  # Parse raw argument list into positional args, options, and flags
  -> parse_args(argv)
    positional = []
    i = 0

    while i < argv.size()
      arg = argv[i]

      if arg.starts_with?("--no-")
        name = arg.slice(5, arg.size() - 5)
        @flags[option_key(name)] = false
      elsif arg.starts_with?("--")
        name = arg.slice(2, arg.size() - 2)
        eq = name.index("=")
        if eq != nil
          key = name.slice(0, eq)
          value = name.slice(eq + 1, name.size() - eq - 1)
          @options[option_key(key)] = value
        elsif i + 1 < argv.size() && !argv[i + 1].starts_with?("-")
          @options[option_key(name)] = argv[i + 1]
          i += 1
        else
          @flags[option_key(name)] = true
      elsif arg.starts_with?("-") && arg.size() == 2
        name = arg.slice(1, 1)
        if i + 1 < argv.size() && !argv[i + 1].starts_with?("-")
          @options[option_key(name)] = argv[i + 1]
          i += 1
        else
          @flags[option_key(name)] = true
      else
        positional.push(arg)

      i += 1

    @args = positional

  -> option_key(name)
    name.replace("-", "_").to_sym()

  # Override in subclasses — the main command logic
  -> execute
    <! "Command#execute must be implemented by subclass"

  # Override in subclasses — one-line summary for help listing
  -> summary
    ""

  # Override in subclasses — detailed usage text
  -> help
    << .usage

  # Display formatted usage text
  -> usage
    "Run `bit help` for usage information."

  # Convenience: fetch a named option with a default
  -> option(name, default = nil)
    @options[name] || default

  # Convenience: check if a flag is set
  -> flag?(name)
    @flags[name] == true

  # Print an error and exit
  -> abort(message)
    << "Error: " + message.to_s
    exit 1

  # Print a success message
  -> say(message)
    << message

  # Print a message only in verbose mode
  -> verbose(message)
    << message if flag?(:verbose)
