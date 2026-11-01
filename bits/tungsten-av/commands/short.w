use ../lib/cli

in Av:Commands

+ Short < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Render the short profile and its dependencies"

  -> usage
    "bit av short \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "short")
    context.load
    names = context.profiles
    names = ["short"] if names.size == 0
    state = Pipeline.new(context.project, context.media).render(names, false)
    context.emit_job(state)

Av:CLI.run(Av:Commands:Short, argv())
