use ../lib/cli

in Av:Commands

+ Stage < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Stage verified outputs at a named destination"

  -> usage
    "bit av stage \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "stage")
    context.load
    context.emit(context.publish)

Av:CLI.run(Av:Commands:Stage, argv())
