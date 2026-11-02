use ../lib/cli

in Av:Commands

+ Gc < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Preview or remove expired failed jobs and temporary candidates"

  -> usage
    "bit av gc \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "gc")
    context.load
    context.emit(context.collect)

Av:CLI.run(Av:Commands:Gc, argv())
