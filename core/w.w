# W — the Tungsten runtime
#
# Implicit receiver for bare function calls.
# W.clock() and clock() are equivalent.
#
# Everything here is about *this process*.
# For the outside world (files, commands, network), see OS.

+ W
  # Time
  -> clock        # monotonic seconds (float)
  -> clock_ms     # monotonic milliseconds (int)

  # Process
  -> exit(code = 0)
  -> argv         # command-line arguments as array
  -> pid          # process ID
  -> env(name)    # environment variable lookup

  # I/O
  -> puts(*args)  # print with newline
  -> print(*args) # print without newline

  # Type introspection
  -> type(value)  # returns type name as string

  # Project
  -> .root        # Path to project root
    Path(__project_root)
