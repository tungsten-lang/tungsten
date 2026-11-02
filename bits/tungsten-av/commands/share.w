use ../lib/cli

in Av:Commands

+ Share < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Render the share profile and its dependencies"

  -> usage
    "bit av share \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "share")
    context.load
    names = context.profiles
    names = ["share"] if names.size == 0
    state = Pipeline.new(context.project, context.media).render(names, false)
    context.emit_job(state)

Av:CLI.run(Av:Commands:Share, argv())
