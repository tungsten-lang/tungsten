# AV commands retain native media processing and use the shared Python coordinator.
+ AvCommand
  -> .run(command, args)
    root = env("TUNGSTEN_ROOT")
    raise "bit av requires TUNGSTEN_ROOT or the bit launcher" if root == nil
    python = env("TW_PYTHON")
    if python == nil || python == ""
      python = root + "/build/av-python/bin/python"
      python = "python3" if !File.exist?(python)
    package = env("BIT_PACKAGE_ROOT")
    package = root + "/bits/tungsten-av" if package == nil
    run = [python, package + "/lib/av/cli.py", command]
    args.each ->(argument)
      run.push(argument)
    code = Process.exec(run)
    raise "cannot launch bit av ([code])"
