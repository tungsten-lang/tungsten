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

    # Compile source files
    sources = Dir.glob("lib/**/*.w")
    compiler = Compiler.new(config)

    sources.each -> (source)
      verbose("  compile " + source)
      compiler.compile(source)

    # Link
    verbose("  link    " + config.output_path)
    compiler.link

    # Copy assets if present
    if Dir.exists?("assets")
      FileUtils.cp_r("assets", config.output)
      verbose("  copy    assets/")

    elapsed = compiler.elapsed
    say "Built " + bitfile.name + " (" + sources.size().to_s + " files, " + elapsed.to_s + "ms)"
