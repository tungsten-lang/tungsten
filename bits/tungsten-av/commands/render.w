use ../lib/cli

in Av:Commands

+ Render < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Render and atomically activate verified outputs"

  -> usage
    "bit av render \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "render")
    context.load
    names = context.profiles
    state = Pipeline.new(context.project, context.media).render(names, false)
    context.emit_job(state)

Av:CLI.run(Av:Commands:Render, argv())
