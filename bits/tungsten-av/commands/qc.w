use ../lib/cli

in Av:Commands

+ Qc < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Run final-file quality checks"

  -> usage
    "bit av qc \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "qc")
    context.load
    context.emit(context.verify)

Av:CLI.run(Av:Commands:Qc, argv())
