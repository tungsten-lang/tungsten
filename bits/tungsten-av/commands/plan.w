use ../lib/cli

in Av:Commands

+ Plan < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Resolve output profiles and show a read-only execution plan"

  -> usage
    "bit av plan \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "plan")
    context.load
    context.emit(Planner.new(context.project, context.media).build(context.profiles, false))

Av:CLI.run(Av:Commands:Plan, argv())
