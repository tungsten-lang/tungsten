in Tungsten:Bit:Commands

+ Prune < Command
  -> summary
    "Remove installed bits not referenced by Bitfile.lock"

  -> usage
    "USAGE\n  bit prune (options)\n\nOPTIONS\n  -n, --dry-run         Show changes without removing\n"

  -> execute
    keep = {}

    lockfile = Lockfile.load("Bitfile.lock")
    lockfile.dependencies.each -> (dep)
      keep[dep.name] = true

    bitfile = Bitfile.load("Bitfile")
    if bitfile != nil
      bitfile.dependencies.each -> (dep)
        keep[dep.name] = true

    bits = installed_bits()
    removed = 0
    i = 0
    while i < bits.size()
      bit = bits[i]
      if keep[bit.name] != true
        if flag?(:dry_run)
          say "  would remove " + bit.name + " " + bit.version
        else
          FileUtils.rm_rf(bit.dir)
          say "  removed " + bit.name + " " + bit.version
        removed += 1
      i += 1

    if removed == 0
      say "Nothing to prune"
