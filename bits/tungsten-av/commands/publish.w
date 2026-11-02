use ../lib/cli

in Av:Commands

+ Publish < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Publish verified outputs to a named destination"

  -> usage
    "bit av publish \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "publish")
    context.load
    context.emit(context.publish)

Av:CLI.run(Av:Commands:Publish, argv())
