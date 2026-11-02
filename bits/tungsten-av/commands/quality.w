use ../lib/cli

in Av:Commands

+ Quality < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Probe and select a passing bitrate without activating outputs"

  -> usage
    "bit av quality \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "quality")
    context.load
    names = context.profiles
    state = Pipeline.new(context.project, context.media).render(names, true)
    context.emit_job(state)

Av:CLI.run(Av:Commands:Quality, argv())
