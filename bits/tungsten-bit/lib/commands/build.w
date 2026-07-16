# bit build — compile a bit from its Bitfile
in Tungsten:Bit:Commands

+ Build < Command
  -> summary
    "Build a bit according to its Bitfile"

  -> usage
    "USAGE\n  bit build (options)\n\nOPTIONS\n  -o, --output DIR    Output directory\n      --release       Build with optimizations\n      --target TARGET Cross-compile target triple\n  -j, --jobs NUM      Parallel compilation jobs\n"

  -> execute
    bitfile = Bitfile.load("Bitfile")

    unless bitfile
      abort "No Bitfile found in current directory"

    config = BuildConfig.new(
      output:  option(:output, "build"),
      release: flag?(:release),
      target:  option(:target, System.target_triple),
      jobs:    option(:jobs, System.cpu_count) |> self.to_i
    )

    say "Building " + bitfile.name + " " + bitfile.version + "..."

    # Verify dependencies are installed
    unless Dependencies.satisfied?(bitfile)
      abort "Dependencies not satisfied. Run `bit install` first."

    compiler = Compiler.new(config)
    unless compiler.available?
      abort "Tungsten compiler not found. Set TUNGSTEN_COMPILER or add tungsten to PATH."

    # Library bits retain the historical compile-every-source behavior. An
    # application bit can instead name one or more entry points; their `use`
    # graph is compiled into independently runnable binaries.
    sources = []
    if bitfile.executables.empty?()
      sources = Dir.glob("lib/**/*.w")
      sources.each -> (source)
        verbose("  compile " + source)
        unless compiler.compile(source)
          abort "Could not compile " + source
    else
      bitfile.executables.each -> (executable)
        name = executable.name
        source = executable.source
        unless safe_package_path?(name)
          abort "Executable name must be a package-relative path: " + name.to_s
        unless safe_package_path?(source)
          abort "Executable source must be a package-relative path: " + source.to_s
        unless File.exists?(source)
          abort "Executable source not found: " + source.to_s

        output = File.join(config.output, "bin/" + name)
        sources.push(source)
        verbose("  compile " + source + " -> " + output)
        unless compiler.compile(source, output)
          abort "Could not compile " + source

    # Link
    verbose("  link    " + config.output_path)
    compiler.link

    # Preserve each package-relative asset path under the build directory. The
    # conventional assets/ directory remains implicit for existing bits.
    packaged_asset_paths(bitfile).each -> (asset)
      unless safe_package_path?(asset)
        abort "Asset must be a package-relative path: " + asset.to_s
      unless File.exists?(asset)
        abort "Declared asset not found: " + asset.to_s
      destination = File.join(config.output, asset)
      # Repeated builds must replace the prior snapshot. Copying a directory
      # onto an existing directory nests it (`build/lib/lib`) and leaves stale
      # worker assets behind.
      FileUtils.rm_rf(destination) if File.exists?(destination)
      FileUtils.mkdir_p(path_parent(destination))
      unless FileUtils.cp_r(asset, destination)
        abort "Could not copy asset " + asset.to_s
      verbose("  copy    " + asset)

    elapsed = compiler.elapsed
    say "Built " + bitfile.name + " (" + sources.size().to_s + " files, " + elapsed.to_s + "ms)"
