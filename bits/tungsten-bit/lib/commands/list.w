in Tungsten:Bit:Commands

+ List < Command
  -> summary
    "List installed bits"

  -> usage
    "USAGE\n  bit list (options)\n\nOPTIONS\n      --paths    Include install paths\n"

  -> execute
    bits = installed_bits()
    if bits.empty?()
      say "No installed bits"
      return

    lockfile = Lockfile.load("Bitfile.lock")
    bits.each -> (bit)
      line = bit.name + " " + bit.version
      locked = lockfile.find_dependency(bit.name)
      if locked != nil
        line = line + " (locked " + locked.version + ", " + locked.source + ")"
      if flag?(:paths)
        line = line + " " + bit.dir
        if locked != nil && locked.path != nil
          line = line + " source " + locked.path
      say line
