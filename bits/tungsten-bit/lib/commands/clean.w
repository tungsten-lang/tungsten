# bit clean — remove build artifacts and caches
in Tungsten:Bit:Commands

+ Clean < Command
  -> summary
    "Remove build artifacts and cached files"

  -> usage
    "USAGE\n  bit clean (options)\n\nOPTIONS\n      --cache    Also clear the download cache\n      --all      Remove vendor/, build/, tmp/, and cache\n  -n, --dry-run  Show what would be removed\n"

  -> execute
    targets = ["build", "tmp"]
    targets.push("vendor/cache") if flag?(:cache)
    targets.push("vendor") if flag?(:all)

    removed = 0

    targets.each -> (dir)
      if Dir.exists?(dir)
        if flag?(:dry_run)
          say "  would remove " + dir + "/"
        else
          FileUtils.rm_rf(dir)
          say "  removed " + dir + "/"
        removed += 1

    if removed == 0
      say "Nothing to clean"
    else
      say "Cleaned " + removed.to_s + " directories" unless flag?(:dry_run)
