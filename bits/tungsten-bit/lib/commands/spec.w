# bit spec — run the project's spec suite
in Tungsten:Bit:Commands

+ Spec < Command
  -> summary
    "Run specs for the current project"

  -> usage
    "USAGE\n  bit spec FILES... (options)\n\nOPTIONS\n  -f, --format FORMAT   Output format: dots, doc, json\n      --fail-fast       Stop on first failure\n      --seed SEED       Random seed for ordering\n  -t, --tag TAG         Only run specs with this tag\n      --no-color        Disable colored output\n  -j, --jobs NUM        Parallel spec workers\n"

  -> execute
    use spec

    paths = case .args
      [] => ["spec"]
      =>   .args

    config = Spec:Config.new(
      paths:     paths,
      format:    option(:format, "dots"),
      fail_fast: flag?(:fail_fast),
      seed:      option(:seed, Random.int(99999)),
      tag:       option(:tag),
      color:     !flag?(:no_color),
      jobs:      option(:jobs, 1) |> self.to_i
    )

    runner = Spec:Runner.new(config)
    result = runner.run

    exit result.exit_code
