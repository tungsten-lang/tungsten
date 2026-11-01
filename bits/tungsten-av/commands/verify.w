use ../lib/cli

in Av:Commands

+ Verify < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Verify delivered media and frozen QC inputs"

  -> usage
    "bit av verify \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "verify")
    context.load
    context.emit(context.verify)

Av:CLI.run(Av:Commands:Verify, argv())
