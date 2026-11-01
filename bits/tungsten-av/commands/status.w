use ../lib/cli

in Av:Commands

+ Status < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Show the latest project job"

  -> usage
    "bit av status \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "status")
    context.load
    context.emit(context.status)

Av:CLI.run(Av:Commands:Status, argv())
