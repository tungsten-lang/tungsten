use ../lib/cli

in Av:Commands

+ Init < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Add declarative AV settings to a project Bitfile"

  -> usage
    "bit av init \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "init")
    context.emit(context.init)

Av:CLI.run(Av:Commands:Init, argv())
